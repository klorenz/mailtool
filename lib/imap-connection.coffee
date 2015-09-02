{BrowserBox} = require './imap-client.coffee'
Mailbox = require './mailbox.coffee'
Q = require 'q'
{EventEmitter} = require 'events'
{clone} = require 'underscore'

module.exports =
class ImapConnection
  constructor: (@name, @options) ->
    #@client = new BrowserBox @options.host, @options.port, @options
    @onClose = options.onClose
    @namespaces = null
    @mailboxes = null
    @messages = {}
    @emitter = new EventEmitter

    @openingSession = false

  # get options without login data
  getOptions: ->
    opts = clone @options
    delete opts.auth
    return opts

  getMailbox: (path) ->
    @imapSession()
    .then (client) =>
      mb = new Mailbox @, client
      if @onClose
        mb.onDidClose =>
          @onClose
      mb

  # checks if not another session is opened right now, because only
  # one session may be in non-authenticated state.

  canStartNextSession: ->
    Q.Promise (resolve, reject) =>
      if @openingSession is false
        resolve()
      else
        @openingSession
        .then =>
          @openingSession = false
          resolve()
        .catch (err) =>
          @openingSession = false
          resolve()

  imapSession: ->
    @canStartNextSession().then =>
      @openingSession = Q.Promise (resolve, reject) =>
        client = new BrowserBox @options.host, @options.port, @options

        client.onauth = ->
          resolve client

        client.onerror = (error) ->
          reject error

        if @onClose
          client.onclose = @onClose

        client.connect()

  # Public: return list of mailboxes.  This is only available after first
  # login.
  #
  getMailboxes: ->
    Q(@mailboxes).then (mailboxes) =>
      return mailboxes if mailboxes?
      @updateMailboxes()

  getRootMailbox: ->
    @getMailboxes().then (mailboxes) =>
      @root

  getNamespaces: (client=null) ->
    Q(@namespaces).then (namespaces) =>
      return namespaces if namespaces?
      @updateNamespaces()

  # Public: update mailboxes list
  #
  # Mailboxes (and namespaces) list is cached on first connect.  If you
  # want it to be updated, call updateMailboxes.
  #
  updateMailboxes: ->
    @imapSession().then (client) =>
      client.listMailboxes().then (mailboxes) =>
        result = []
        flatten = (mailbox) ->
          result.push mailbox
          return unless mailbox.children
          for childbox in mailbox.children
            flatten childbox

        flatten mailboxes

        @root      = result[0]
        @mailboxes = result[1..]

        @emitter.emit 'did-update-mailboxes', @mailboxes

  updateNamespaces: ->
    @imapSession().then (client) =>
      client.listNamespaces().then (namespaces) =>
        @emitter.emit 'did-update-namespaces', namespaces
        @namespaces = namespaces

  onDidGetMailboxes: (callback) ->
    @emitter.on 'did-update-mailboxes', callback

  onDidGetNamespaces: (callback) ->
    @emitter.on 'did-update-namespaces', callback
