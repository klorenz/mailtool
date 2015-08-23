CSON           = require 'season'
{markdown}     = require 'nodemailer-markdown'
{doT}          = require 'nodemailer-dot-templates'
{signature}    = require 'nodemailer-signature'
nodemailer     = require 'nodemailer'
{keys, extend} = require 'underscore'
fs   = require 'fs'
path = require 'path'

###
work around a bug in tcp-socket.  It does not detect atom-shell
in right way and uses wrong tcp,tls factory and fails :(
###

getImapClient = (logLevel=null)->
  if getImapClient.ImapClient
    return getImapClient.ImapClient

  axe = require('axe-logger')
  axe.logLevel = logLevel ? axe.ERROR
  tcp_socket = require('tcp-socket')
  orig_require = module.constructor.prototype.require
  module.constructor.prototype.require = (name) ->
    if name is 'tcp-socket'
      return tcp_socket
    else if name is 'axe-logger'
      return axe
    else
      return orig_require.call this, name
  ImapClient = require 'imap-client'
  module.constructor.prototype.require = orig_require

  getImapClient.ImapClient = ImapClient
  return ImapClient

getUserHome = () ->
  process.env[(process.platform is 'win32') and 'USERPROFILE' or 'HOME']

isUpperCase = (s) ->
  s.toUpperCase() == s

class MailToolMissingFieldError extends Error
  constructor: (@field) ->
    super
    @message = "Missing field '#{@field}' in envelope"

  __toString: ->
    @message

class MailTool
  constructor: (config, transport) ->
    if not config
      config = "~/.mailtool.cson"

    # read config from file if it is a string
    if typeof config is "string"
      @loadConfig config

    else
      @config = config

    # setup default configuration
    if 'default' not of @config
      for k,v of @config
        @config.default = k
        break

    if typeof @config.default is "string"
      @config.default = @config[@config.default]

    @transport = transport
    @required = ['subject', 'to']

  # Public: Return configuration data.
  #
  # name - Optional, the name of account configuration to be retrieved.
  #
  #        It can be either "AccountName" to retrieve complete account
  #        data or "AccountName.configuration" to retrieve specific
  #        configuration.
  #
  #        If you do not supply a name at all, there is returned a list
  #        of objects {name: "AccountName", alias: "OtherAccountName"}.
  #        Alias is not present, if account is not an alias for another
  #        account.
  #
  # Examples
  #
  #    mailtool->getConfig()
  #    # => [{name: 'FirstAccount'}, {name: 'default', alias: 'FirstAccount'}]
  #
  #    mailtool->getConfig('FirstAccount.default')
  #    # return default send mail configuration from FirstAccount
  #
  # Returns configuration data.

  getConfig: (name) ->
    unless name
      result = []
      for name of @config
        continue if name is "configFileName"
        if typeof @config[name] is "string"
          result.push name: name, alias: @config[name]
        else
          result.push name: name
      return result

    cfg = name
    subcfg = null

    if m = name.match /(.*)\.(.*)/
      cfg = m[1]
      subcfg = m[2]

    while typeof cfg is "string"
      cfg = @config[cfg]

    if subcfg
      return cfg[subcfg]

    return cfg

  getMailerConfig: (name, mailer=null) ->
    cfg = @getConfig name
    unless mailer
      opts = {}
      for k,v of cfg
        continue if k is "mailbox"
        continue if k is "transport"
        opts[k] = v
      return opts

    return cfg[mailer]

  # returns promise
  #
  # pass may be a function getting a callback with first parameter
  # the password and second a callback, which gets the imap object
  #
  getImapConnection: (options={}) ->
    {name, config, host, port, logLevel} = options

    name = config or name
    name = 'default' unless name or host

    connectImap = (name, options) =>
      if name not of @imapConnections
        ImapClient = getImapClient(logLevel)
        @imapConnections[name] = new ImapClient options

      @imapConnections[name]

    if name
      options = extend {}, @config[name].mailbox, options
      options.auth = extend {}, @config[name].mailbox.auth, options.auth or {}

      if typeof config.auth.pass is "function"
        passwdFunction = options.auth.pass
        options.auth.pass (passwd, callback) =>
          options.auth.pass = passwd
          callback connectImap name, options

      configFileDir = path.dirname @config[name].configFileName
      passwdFile = path.resolve configFileDir, config.auth.pass

      if fs.existsSync passwdFile
        options.auth.pass = fs.readFileSync(passwdFile).toString().trim()

    else
      name = "#{config.auth.user}@#{host}:#{port}"

    connectImap name, options

  closeImapConnections: (callback) ->
    imapConnections = @imapConnections
    for name, imap of @imapConnections
      imap.logout().then =>
        delete imapConnections[name]

    @imapConnections = {}

  getConfigFileName: -> @config.configFileName

  # save current configuration to fileName.  if None given, then
  # configFileName will be used
  saveConfig: (fileName) ->
    if not fileName
      fileName = @getConfigFileName()

    @writeConfig fileName, @config

  resolveFileName: (fileName) ->
    fileName.replace /^~/, getUserHome()

  # load current configuration from fileName
  loadConfig: (fileName) ->
    if @watcher
      @watcher.close()

    @closeImapConnections()

    @config = @readConfig fileName

    @watcher = fs.watch @getConfigFileName(), persistent: false, =>
      @loadConfig()

  # reads configuraiton from filename and returns a config object
  readConfig: (fileName) ->
    fileName = @resolveFileName fileName
    config = CSON.readFileSync fileName
    config.configFileName = fileName
    return config

  # writes a configuration object to fileName
  writeConfig: (fileName, config) ->
    configFileName = null

    try
      if 'configFileName' of config
        configFileName = config.configFileName
        delete config.configFileName

      CSON.writeFileSync @resolveFileName(fileName), config

    finally
      if configFileName?
        config.configFileName = configFileName

  parseMessageText: (text) ->
    return {text} unless m = text.match /^([\w\-]+[ \t]*:\s[\s\S]*?)\r?\n\r?\n([\s\S]*)/

    header = m[1]+"\n"
    body   = m[2]
    #header = header.replace /\r?\n[ \t]+/, " "
    opts = {}
    for line in header.match /^\S.*\n(?:[ \t].*\n)*/gm
      line = line.replace /\s*$/, ''
      try
        d = CSON.parse(line)
        extend opts, d
      catch
        try
          if not line.match /\n/
            [ key, value ] = line.match(/^([\w\-]+)\s*:\s+(.*)/)[1..]
            opts[key] = value

          else
            opts = null
            break

        catch
          opts = null
          break

    if opts?
      opts.text = body
      return opts

    else
      throw new Error "Cannot parse header"

  compile: (options, callback) ->
    extend options, @parseMessageText options.text

    cfgName = options.config or options.name or 'default.default'

    if not cfgName.match /\./
      throw new Error "invalid configuration name (must contain a .)"

    for key, value of @getConfig(cfgName)
      if key not of options
        options[key] = value
      else if typeof options[key] is "object" and typeof value is "object"
        options[key] = extend {}, value, options[key]

    if options.markdown is true
      options.markdown = options.text
      delete options.text

    missing = []
    for field in @required
      if field not of options
        missing.push field

    if missing.length
      if options.optionDialog
        return options.optionDialog {missing, options}, ->
          callback?(options)

      err = new MailToolMissingFieldError missing

      if callback
        return process.nextTick -> callback err
      else
        throw err

    callback?(options)


  sendMail: (config, callback) ->
    config = extend {}, config

    setupTransporter = (done) =>
      unless config.transport

        cfgName = config.config or config.name or 'default'
        if m = cfgName.match /(.*)\.(.*)/
          cfgName = m[1]

        config.transport = extend {}, @getConfig(cfgName).transport
        config.transport.auth = auth = extend {}, config.transport.auth

        configFileDir = path.dirname @getConfigFileName()
        passwdFile = path.resolve configFileDir, auth.pass

        if fs.existsSync passwdFile
          auth.pass = fs.readFileSync(passwdFile).toString().trim()

      # setup transport

        if config.transport.rejectUnauthorized is false
          process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0'

        transport = (require "nodemailer-smtp-transport") config.transport

        # transport.on 'log', (args...) =>
        #   console.log args...
        # transport.on 'error', (args...) =>
        #   console.log 'error', args...

        transporter = nodemailer.createTransport transport
      else if @transport.sendMail
        transporter = @transport
      else
        transport = @transport config.transport
        transporter = nodemailer.createTransport transport

      done transporter

    @compile config, =>
      setupTransporter (transporter) =>
        theMail = null
        transporter.use 'compile', doT()
        transporter.use 'compile', signature()
        transporter.use 'compile', markdown config

        transporter.use 'compile', (mail, callback) =>
          theMail = mail
          console.log "message compiled", theMail
          callback()

        transporter.sendMail config, callback
          # #store mailMessage to imap
          # if err?
          #   callback(err)
          # else
          #   callback(theMail)

nodeMailerConfig = (args...) ->
  mailtool = new MailTool args...

  (options, done) ->
    mailtool.compile(options, done)

main = ->
  mt = new MailTool "~/.mailtool.cson"

  mt.connectImap('default').then () =>
    mt.imap.listWellKnownFolders().then (folderInfo) =>
      console.log folderInfo

module.exports = {MailTool, nodeMailerConfig, main, MailToolMissingFieldError}
