{BrowserBox} = require './imap-client.coffee'
Mailbox = require './mailbox.coffee'
Q = require 'q'

module.exports =
class ImapConnection
  constructor: (@name, @options) ->
    @client = new BrowserBox @options.host, @options.port, @options
    @onClose = options.onClose
    @namespaces = null
    @mailboxes = null
    @messages = {}

  login: ->
    Q.Promise (resolve, reject) =>
      client = new BrowserBox @options.host, @options.port, @options

      client.onauth = ->
        promises = []

        unless @namespaces
          promises.push client.listNamespaces().then (namespaces) =>
            @namespaces = namespaces

        unless @mailboxes
          promises.push client.listMailboxes().then (mailboxes) =>
            @mailboxes = mailboxes

        getMailbox = =>
          mb = new Mailbox @, client
          if @onClose
            mb.onDidClose =>
              @onClose

        if promises.length
          Q.all(promises).then -> resolve getMailbox()
        else
          resolve getMailbox()

      client.onerror = (error) ->
        reject(error)

      if @onClose
        client.onclose = @onClose

      client.connect()

  openMailbox: (path) ->
    Q.Promise (resolve, reject) =>
      @login()
      .then (mailbox) ->
        mailbox.selectMailbox(path)
        .then ->
          resolve(mailbox)
        .reject (err) ->
          reject(err)
      .reject (err) ->
        reject(err)

  # Public: return list of mailboxes.  This is only available after first
  # login.
  #
  getMailboxes: ->
    @mailboxes

  buildMailboxesList: (mailboxtree) ->
    result = []

  eachMailbox: (callback, mailbox=null) ->
    mailbox = @mailboxes if mailbox?

    callback mailbox

    if mailbox.children?.length
      for childbox in mailbox.children
        @eachMailbox callback, childbox

  # Public: update mailboxes list
  #
  # Mailboxes (and namespaces) list is cached on first connect.  If you
  # want it to be updated, call updateMailboxes.
  #
  updateMailboxes: ->
    Q.Promise (resolve, reject) =>
      promises = []

      client = new BrowserBox @options.host, @options.port, @options

      client.onauth = ->
        resolve
        # promises.push client.listNamespaces().then (namespaces) =>
        #   @namespaces = namespaces
        #   @emitter.emit 'did-update-namespaces', namespaces
        #
        # promises.push client.listMailboxes()
        #   .then (mailboxes) =>
        #     @mailboxes = mailboxes
        #     @emitter.emit 'did-update-mailboxes', mailboxes
        #     updatedMailboxInfo = []
        #
        #     # trigger an event that mailbox has been updated
        #
        #
        #     Q.all(updatedMailboxInfo)
        #
        # Q.all(promises)
        # .then ->
        #   client.close()
        #   resolve()
        # .reject (err) ->
        #   client.close()
        #   reject(err)

      client.onerror = (err) ->
        reject(err)

      client.connect()

  onDidGetMailboxes: (callback) ->
    @emitter.on 'did-update-mailboxes', callback

  onDidGetNamespaces: (callback) ->
    @emitter.on 'did-update-namespaces', callback
