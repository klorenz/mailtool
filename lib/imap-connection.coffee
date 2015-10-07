{BrowserBox} = require './imap-client.coffee'
Mailbox = require './mailbox.coffee'
MailMessage = require './message.coffee'
Q = require 'q'
{EventEmitter} = require 'events'
{clone} = require 'underscore'
path = require 'path'
fs = require 'fs'
mkdirp = require 'mkdirp'

class Cache
  constructor: (@directory) ->
    @objectsInFiles = false

  getCacheFileName: (name) ->
    path.resolve @directory, "#{name}.json"

  getObject: (name, value=null) ->
    fileName = @getCacheFileName name
    return value unless fs.existsSync fileName
    JSON.parse fs.readFileSync fileName

  getObjects: (dir, factory=null) ->
    unless factory
      factory = (x) -> x

    debugger

    if @objectsInFiles
      cacheDir = path.resolve @directory, dir
      objects = {}
      for fileName in fs.readDirSync cacheDir
        fileName = path.resolve cacheDir, fileName
        key = path.basename fileName, '.json'
        objects[key] = factory JSON.parse fs.readFileSync fileName

    else
      objects = {}
      _object = @getObject dir
      for k,v of _object
        objects[k] = factory v

    objects

  putObjects: (dir, objects) ->
    if @objectsInFiles
      throw "pubObjects for objects in files is not implemented"

      cacheDir = path.resolve @directory, dir
      curObjects = {}
      for fileName in fs.readDirSync cacheDir
        key = path.basename fileName, '.json'
        objects[key] = true

      objects
    else
      @putObject dir, objects

  putObject: (name, object) ->
    fileName = @getCacheFileName name
    dir = path.dirname fileName
    mkdirp.sync dir, 0o0700
    fs.writeFileSync fileName, JSON.stringify object, 2

# TODO: rename ImapConnection to something like ImapManager

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
    @cache = null
    @client = null

    if @options.cache?.directory
      @cache = new Cache @options.cache.directory
      @mailboxes  = @cache.getObject 'mailboxes'
      @namespaces = @cache.getObject 'namespaces'

      @onDidUpdateMailboxes (mailboxes) =>
        @cache.putObject 'mailboxes', mailboxes

      @onDidUpdateNamespaces (namespaces) =>
        @cache.putObject 'namespace', namespaces

      # @onDidUpdateMessage (path, message) =>
      #   @cache.putObject 'messages/#{path}/#{message.uid}', message

      @onDidOpenMailbox (mailbox) =>
        mailbox.messages = @cache.getObjects "mailboxes/#{mailbox.path}/messages",
          (x) -> new MailMessage x
        mailbox.info = @cache.getObject "mailboxes/#{mailbox.path}/info"

      @onDidCloseMailbox (mailbox) =>
        @cache.putObjects "mailboxes/#{mailbox.path}/messages", mailbox.messages
        @cache.putObject "mailboxes/#{mailbox.path}/info", mailbox.info


    #   @messages   = @cache.getObject 'messages', {}
    #   @mailboxes  = @cache.getObject 'mailboxes'
    #   @namespaces = @cache.getObject 'namespaces'

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

  imapSession: ({reuse}={})->
    session = Q.Promise (resolve, reject) =>
      if reuse
        if @client
          return resolve(@client)
        else
          @imapSession().then (client) =>
            @client = client
            resolve(client)
          .catch (error) =>
            resolve(error)
      else
        @canStartNextSession().then =>
          @openingSession = session

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

  onDidUpdateMailboxes: (callback) ->
    @emitter.on 'did-update-mailboxes', callback

  onDidUpdateNamespaces: (callback) ->
    @emitter.on 'did-update-namespaces', callback

  onDidOpenMailbox: (callback) ->
    @emitter.on 'did-open-mailbox', callback

  onDidCloseMailbox: (callback) ->
    @emitter.on 'did-close-mailbox', callback

  didOpenMailbox: (mailbox) ->
    @emitter.emit 'did-open-mailbox', mailbox

  updateMailboxFromCache: (mailbox) ->
    @didOpenMailbox mailbox

  didCloseMailbox: (mailbox) ->
    @emitter.emit 'did-close-mailbox', mailbox
