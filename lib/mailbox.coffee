{EventEmitter} = require 'events'
Q = require 'q'
{max, values} = require 'underscore'

MailMessage = require "./message.coffee"

{makeSequence} = require "./utils.coffee"

module.exports =
class Mailbox
  constructor: (@imap, @client) ->
    @info     = {}
    @emitter  = new EventEmitter
    @sorted   = {}
    @messages = null
    @fetching = false
    @lastUid  = @mess
    @path     = null
    @msgChunk = 100
    @updater  = null

    @client.onclose = =>
      if @path?
        @imap.didCloseMailbox this
      @emitter.emit 'did-close'

    @client.onerror = =>
      if @path?
        @imap.didCloseMailbox this
      @emitter.emit 'on-error'

  close: ->
    @client.close()
    if @path?
      @imap.didCloseMailbox this

  selectMailbox: (path=null, @options={}) ->
    Q.Promise (resolve, reject) =>
      selectMailbox = (path, options) =>
        @client.selectMailbox path, options, (error, info) =>
          if error?
            reject error
          else
            # if there was opened a mailbox before, dump the current data to
            # disk
            if @path?
              @imap.didCloseMailbox this

            @messages = null
            @info = null
            @path = path

            @imap.didOpenMailbox this
            if @info?
              console.log "current info", @info
              console.log "new info    ", info

              if @info.nextUid != info.nextUid
                @needUpdateSince = @info.nextUid
                # check if we have to update messages using

            @info = info

            @emitter.emit 'did-select-mailbox', path, info
            resolve path, info

      unless path?
        @imap.getNamespaces(@client).then (namespaces) =>
          selectMailbox 'INBOX', @options
        .fail (error) =>
          reject error
      else
        selectMailbox path, @options

  # Public: starts automatic updating of message box info and messages
  #
  # interval - The time in seconds to wait between updates.
  #
  startUpdater: (interval) ->
    @stopUpdater()

    @updater = setInterval (=>
      @selectMailbox(@path, @options).then =>
        @getAllMessages()
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

  setFlags: (uids, flags) ->
    add = []
    remove = []

    for k,v of flags
      flag = k.toLowerCase()
      flag = "\\" + flag[0].toUpperCase()+flag[1..]

      if v is false
        remove.push flag
      else
        add.push flag

    sequence = makeSequence uids

    console.log "sequence", sequence

    Q.Promise (resolve, reject) =>
      if add.length and remove.length
        @client.setFlags(sequence, {add}, byUid: true).then (add) =>
          @client.setFlags(sequence, {remove}, byUid: true).then (remove) =>
            resolve {add, remove}
          .catch (error) =>
            error.add = add
            reject error
        .catch (error) =>
          reject error
      else if add.length
        @client.setFlags(sequence, {add}, byUid: true).then (add) =>
          resolve error
        .catch (error) =>
          reject error
      else if remove.length
        @client.setFlags(sequence, {remove}, byUid: true).then (remove) =>
          resolve {remove}
        .catch (error) =>
          reject error

  getMessageBodyParts: (message, parts=null) ->
    Q.Promise (resolve, reject) =>
      parts = message.bodyParts unless parts?

      inlineAttachments = []

      # html may have inlined content.  So look for content having an ID
      for part in parts
        if part.type is 'html'
          for p in message.bodyParts
            if p.id
              inlineAttachments.push p

      for attachment in inlineAttachments
        continue if attachment in parts
        parts.push attachment

      buildQuery = (parts) ->
        query = []
        for part in parts
          continue unless part.partNumber?

          if part.partNumber is ""
            query.push "body.peek[]"
          else
            query.push "body.peek[#{part.partNumber}.mime]"
            query.push "body.peek[#{part.partNumber}]"
        query

      console.log "get parts for uid", message.uid, parts

      @client.listMessages "#{message.uid}", buildQuery(parts), byUid: true
      .then (msgs) =>
        msg = msgs[0]

        unless msg
          # message has been deleted ...
          resolve(parts)

        for part in parts
          continue unless part.partNumber?
          if part.partNumber is ""
            part.raw = msg['body[]']
          else
            part.raw = msg["body[#{part.partNumber}.mime]"] + msg["body[#{part.partNumber}]"]

        parser = require './mime-parser'
        parser.parse parts, (bodyParts) =>

          byId = {}
          for part in parts
            if part.id
              byId[part.id] = part

          for part in parts
            if part.type is "html"
              part.content = part.content.replace /(<img[^>]+src=["'])cid:([^'"]+)(['"])/ig, (match, prefix, src, suffix) =>
                localSource = ''
                payload = ''
                byteArray = byId[src].content

                if byteArray
                   # create octets
                   for b in byteArray
                     payload += String.fromCharCode b

                try
                  localSource = 'data:application/octet-stream;base64,'+btoa(payload)
                catch e
                  #console.log e

                return prefix + localSource + suffix

          resolve bodyParts

      .catch (error) =>
        reject error

  updateMessages: () ->
    if @fetching is false
      console.log "updateMessages"

      messages = {}
      count = @info.exists

      console.log "updateMessages: start get message info"
      @emitter.emit 'did-start-get-messages', @messages, {count}
      fetched = 0

      getSomeMessageInfo = (start, end) => =>
        console.log "updateMessages: get message info for seq number #{start} to #{end}"

        @client.listMessages "#{start}:#{end}", ['uid', 'flags'], byUid: false
        .then (msgs) =>
          updated = []

          for msg in msgs
            if msg.uid of @messages
              if @messages[msg.uid].update(msg)
                updated.push @messages[msg.uid]

            else
              messages[msg.uid] = msg

          fetched += msgs.length

          console.log "updateMessages (info):", "fetched", fetched, "# updated", updated.length, "# new messages", messages.length

          if updated.length
            @emitter.emit 'did-progress-get-messages', @messages, {updated, fetched, count}

        .catch (error) =>
          console.log "updateMessages (info):", "error", error

          @emitter.emit 'on-error-get-messages', error
          @emitter.emit 'on-error', error
          @emitter.emit 'did-end-get-messages', messages {fetched, error}
          @fetching = false

      getSomeMessages = (sequence) => =>
        console.log "updateMessages: uid sequence", sequence

        @client.listMessages sequence, ['uid', 'flags', 'rfc822.size', 'envelope', 'bodystructure'], byUid: true
        .then (msgs) =>
          fetchedMessages = []

          for msg in msgs
            msg = new MailMessage msg, @imap.getOptions()
            @messages[msg.uid] = msg
            fetchedMessages.push msg

          fetched += msgs.length
          console.log "updateMessages (info):", "fetched", fetched, "fetchedMessages", fetchedMessages

          @emitter.emit 'did-progress-get-messages', @messages, {fetchedMessages, fetched, count}

        .catch (error) =>
          @emitter.emit 'on-error-get-messages', error
          @emitter.emit 'on-error', error
          @emitter.emit 'did-end-get-messages', @messages {fetched, error}
          @fetching = false

      getters = []
      prev_i = 0
      for i in [1..@info.exists] by (@msgChunk*4)
        unless prev_i
          prev_i = i
          continue

        getters.push getSomeMessageInfo(prev_i, i)
        prev_i = i

      getters.push getSomeMessageInfo(prev_i, @info.exists)

      getters.reverse()

      getters.push =>
        @emitter.emit 'did-end-get-messages', @messages
        console.log "updateMessages (info): done"

        new_getters = []
        sequences = []
        sequence = []
        sequences.push sequence
        uids = (parseInt(uid) for uid of messages)
        uids.sort()
        count = uids.length

        console.log "updateMessages: start get #{count} msgs"

        @emitter.emit 'did-start-get-messages', @messages, {count}
        for uid in uids
          sequence.push uid
          if sequence.length >= @msgChunk
            sequence = []
            sequences.push sequence

        sequences.reverse()

        for sequence in sequences
          new_getters.push getSomeMessages(makeSequence sequence)

        new_getters.push =>
          console.log "updateMessages: done"
          @emitter.emit 'did-end-get-messages', @messages
          @fetching = false

        new_getters.reduce Q.when, Q()

      getters.reduce Q.when, Q()

    @messages

  # TODO: fetch messages from end to start (uid descending)
  getAllMessages: () ->
    # Q(@messages).then (messages) =>
    #   if @messages?
    #     @messages
    #   else
    if @fetching is false
      console.log "getAllMessages"
      messages = {}
      count = @info.exists
      @emitter.emit 'did-start-get-messages', messages, {count}
      fetched = 0

      getSomeMessages = (start, end) => =>
        @client.listMessages "#{start}:#{end}", ['uid', 'flags', 'rfc822.size', 'envelope', 'bodystructure'], byUid: false
        .then (msgs) =>
          fetchedMessages = []

          msgs.forEach (msg) =>
            msg = new MailMessage msg, @imap.getOptions()
            messages[msg.uid] = msg
            fetchedMessages.push msg

          fetched += msgs.length

          @emitter.emit 'did-progress-get-messages', messages, {fetchedMessages, fetched, count}

        .catch (error) =>
          @emitter.emit 'on-error-get-messages', error
          @emitter.emit 'on-error', error
          @emitter.emit 'did-end-get-messages', messages {fetched, error}
          @fetching = false

      getters = []
      prev_i = 0
      for i in [1..@info.exists] by @msgChunk
        unless prev_i
          prev_i = i
          continue

        getters.push getSomeMessages(prev_i, i)
        console.log "getSomeMessages #{prev_i}, #{i}"
        prev_i = i

      getters.push getSomeMessages(prev_i, @info.exists)

      getters.reverse()

      getters.push =>
        @emitter.emit 'did-end-get-messages', messages
        @messages = messages
        @fetching = false

      getters.reduce Q.when, Q()

    @messages
