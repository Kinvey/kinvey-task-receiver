# Copyright (c) 2014, Kinvey, Inc. All rights reserved.
#
# This software is licensed to you under the Kinvey terms of service located at
# http://www.kinvey.com/terms-of-use. By downloading, accessing and/or using this
# software, you hereby accept such terms of service  (and any agreement referenced
# therein) and agree that you have read, understand and agree to be bound by such
# terms of service and are of legal age to agree to such terms with Kinvey.
#
# This software contains valuable confidential and proprietary information of
# KINVEY, INC and is subject to applicable licensing agreements.
# Unauthorized reproduction, transmission or distribution of this file and its
# contents is a violation of applicable laws.

net = require 'net'
config = require 'config'
server = {}

composeErrorReply = (errorMessage, debugMessage, err, metadata) ->
  # build an error response as generated by blApi
  # FIXME: error response format should be handled by the outermost layer,
  # and not be duplicated in various places
  return ret =
    isError: true
    statusCode: 550
    error: err.toString()
    message: errorMessage
    debugMessage: debugMessage
    # note: stack is not a stack array, its a formatted text string that contains a printed stack trace
    stackTrace: err.stack
    metadata: metadata ? {}

parseTask = (task, callback) ->
  console.log "parseTask Invoked"
  console.log task
  unless task?
    return composeErrorReply 'Internal Error', 'Bad Request', new Error('Bad Request'), {}
  if typeof task is 'object'
    return callback null, task

  try
    parsedTask = JSON.parse task
    callback null, parsedTask
  catch e
    callback new Error 'invalid task: unable to parse task json'

exports.startServer = (taskReceivedCallback, startedCallback) ->

  data = ''
  line = ''
  processingTasks = false

  server = net.createServer (socket) ->
    console.log "Connection established..."
    data = ""
    line = ""

    socket.on 'data', (chunk) ->
      console.log "chunk received"
      # always append the new data, then process task below
      data += chunk.toString()

      # process one task at a time in arrival order, sending back responses in the same order
      # an already running processing loop will handle the newly arrived task as well

      while true
        lineEnd = data.indexOf('\n')
        if (lineEnd < 0)
           # stop processing when no (no more) complete lines await
          return
        task = data.slice(0, lineEnd+1)
        data = data.slice(lineEnd + 1)
        # TODO: do not ^^^ re-copy all the data for each task line, index into data instead
        # skip blank lines, processBL non-blank ones
        if (task) then break
      if (task.indexOf '{"healthCheck":1}') > -1
        console.log "healthcheck!"
        healthStatus = JSON.stringify {"status":"ready"}
        socket.write "#{healthStatus}\n"
        return
      else
        console.log "About to parse task"
        console.log task
        parseTask task, (parseError, parsedTask) ->
          console.log "Task parsing complete"
          if parseError?
            console.log "Parse error! #{parseError}"
            parseError.isError = true
            socket.write JSON.stringify composeErrorReply 'Internal Error', parseError.toString(), parseError
            socket.write '\n'
            return
          console.log "About to invoke taskReceivedCallback"
          console.log parsedTask
          taskReceivedCallback parsedTask, (err, result) ->
            console.log "About to respond"
            # processBL returns a pre-assembled response object
            if err?
              console.log "Responding with error"
              console.log err
              socket.write JSON.stringify composeErrorReply('Internal Error', 'Unable to run dlc script', err)
              socket.write '\n'
              return
            else
              console.log "Responding with success"
              console.log result
              # make sure result is present, undefined is not stringified into the json
              if result is undefined then result = null

              # TODO: check size of ret and use a non-blocking serializer if too large
              socket.write JSON.stringify result
              socket.write '\n'


    socket.on 'connect', () ->
    #console.log { containerId: dockerHost, message: "Socket connected"}

    socket.on 'end', () ->
    #console.log { containerId: dockerHost, message: "Socket ended"}

    socket.on 'error', (err) ->
    #console.log { containerId: dockerHost, message: "Socket Error", error: err.toString(), stack: err.stack}


    socket.on 'close', (hasError) ->
      status = if hasError is true then 'error' else 'success'
    #console.log { containerId: dockerHost, message: "Socket closed with #{status}"}


  server.on 'close', () ->
  #console.log { containerId: dockerHost, message: "Server connection closed"}

  server.on 'error', (err) ->
  #console.log { containerId: dockerHost, message: "Server Error", error: err.toString(), stack: err.stack}

  process.nextTick () ->
    server.listen config.server?.port or 7000, () ->
      startedCallback()

exports.stop = () ->
  server.close()