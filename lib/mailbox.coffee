module.exports =
class Mailbox
  constructor: (@imap, @client) ->
    @info     = {}
    @emitter  = new EventEmitter
    @sorted   = {}
    @byUid    = {}
    @fetching = false
    @lastUid  = @mess
    @path     = null
    @msgChunk = 100
    @updater  = null

    @client.onclose = =>
      @emitter.emit 'did-close'
    @client.onerror = =>
      @emitter.emit 'on-error'

  selectMailbox: (path=null, @options={}) ->
    Q.Promise (resolve, reject) =>
      @client.selectMailbox(path, options).then (info) =>
        @path = path
        @info = info
        @emitter.emit 'did-select-mailbox', path, info
        resolve(path, info)

      .reject (err) =>
        reject(err)

  # Public: starts automatic updating of message box info and messages
  #
  # interval - The time in seconds to wait between updates.
  #
  startUpdater: (interval) ->
    @stopUpdater()

    @updater = setInterval (=>
      @selectMailbox(@path, @options).then =>
        @getMessages()
    ), seconds*1000

  stopUpdater: ->
    if @updater
      clearTimeout @updater
      @updater = null

  ###
  Section: Event Handlers
  ###

  # Public:

  onDidSelectMailbox: (callback) ->
    @emitter.on 'did-select-mailbox', callback

  onDidStartGetMessages: (callback) ->
    @emitter.on 'did-start-get-messages', callback

  onDidProgressGetMessages: (callback) ->
    @emitter.on 'did-progress-get-messages', callback

  onDidEndGetMessages: (callback) ->
    @emitter.on 'did-end-get-messages', callback

  onDidClose: (callback) ->
    @emitter.on 'did-close', callback

  onError: (callback) ->
    @emitter.on 'on-error', callback

  # TODO: fetch messages from end to start (uid descending)
  getMessages: () ->
    if @fetching is false
      @fetching = max(values(@byUid), (o) -> o.uid).uid + 1
      return @byUid if @fetching >= @lastUid

      @emitter.emit 'did-start-get-messages', @byUid

      while end isnt '*'
        break if @fetching >= @info.nextUid

        end = @fetching + @msgChunk
        if end > @lastUid
          end = '*'

      #  fetch = (start, end)

        promises.push @client.listMessages("#{@fetching}:#{end}", ['all']).then (messages) =>
          messages.forEach (msg) =>
            @byUid[msg.uid] = msg

          @emitter.emit 'did-progress-get-messages', @byUid

        @fetching = end

      Q.all(promises)
      .then =>
        @emitter.emit 'did-end-get-messages', @byUid
        @fetching = false
      .reject (err) =>
        @emitter.emit 'on-error-get-messages', err
        @emitter.emit 'on-error', err
        @emitter.emit 'did-end-get-messages', @byUid
        @fetching = false

    @byUid
