# TODO: Caching
#
#
CSON           = require 'season'
{markdown}     = require 'nodemailer-markdown'
{doT}          = require 'nodemailer-dot-templates'
{signature}    = require 'nodemailer-signature'
nodemailer     = require 'nodemailer'
{keys, extend, union} = require 'underscore'
{EventEmitter} = require 'events'
Mailbox = require './mailbox.coffee'
MailMessage = require './message.coffee'
mkdirp  = require 'mkdirp'
Q       = require 'q'

fs   = require 'fs'
path = require 'path'

###
work around a bug in tcp-socket.  It does not detect atom-shell
in right way and uses wrong tcp,tls factory and fails :(
###

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
      config = "~/.mailtool/config.cson"
      dir = @resolveFileName("~/.mailtool")
      if not fs.existsSync dir
        fs.mkdir dir, 0o0700

    @version = JSON.parse(fs.readFileSync path.resolve path.dirname(__filename), '..', 'package.json').version

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

    # if typeof @config.default is "string"
    #   @config.default = @config[@config.default]

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

  hasMailbox: (name) ->
    cfg = @getConfig name
    "mailbox" of cfg

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
        try
          ImapConnection = require './imap-connection.coffee'
        catch e
          console.log e
        @imapConnections[name] = new ImapConnection name, options

      @imapConnections[name]

    cfg = @getConfig(name)

    if "mailbox" not of cfg and not host
      throw new Error "No mailbox configured for #{name}"

    if name
      options = extend {}, cfg.mailbox, options
      options.auth = extend {}, cfg.mailbox.auth, options.auth or {}

      if typeof options.auth.pass is "function"
        passwdFunction = options.auth.pass
        options.auth.pass (passwd, callback) =>
          options.auth.pass = passwd
          callback connectImap name, options

      configFileDir = @getConfigDirName()
      passwdFile = path.resolve configFileDir, options.auth.pass

      if fs.existsSync passwdFile
        options.auth.pass = fs.readFileSync(passwdFile).toString().trim()

      if options.cache and not options.cache.directory
        cacheDir  = path.resolve configFileDir, name, 'cache'
        mkdirp.sync cacheDir, mode: 0o0700
        options.cache.directory = cacheDir

    else
      name = "#{options.auth.user}@#{host}:#{port}"

    sslIndicator = if options.useSecureTransport then "s" else ""
    options.uri = "imap#{sslIndicator}://#{options.auth.user}@#{host}:#{port}"
    options.configName = name or options.uri

    connectImap name, options


  closeImapConnections: (callback) ->
    imapConnections = @imapConnections
    for name, imap of @imapConnections
      delete imapConnections[name]

      # imap.logout().then =>
      #   delete imapConnections[name]

    @imapConnections = {}

  getConfigFileName: -> @config.configFileName
  getConfigDirName: ->
    path.dirname @config.configFileName

  # save current configuration to fileName.  if None given, then
  # configFileName will be used
  saveConfig: (fileName) ->
    if not fileName
      fileName = @getConfigFileName()

    @writeConfig fileName, @config

  resolveFileName: (fileName) ->
    fileName.replace /^~/, getUserHome()

  # load current configuration from fileName
  loadConfig: (fileName=null) ->
    if @watcher
      @watcher.close()

    fileName = @getConfigFileName() unless fileName?

    @closeImapConnections()

    @config = @readConfig fileName

    @watcher = fs.watch @getConfigFileName(), persistent: false, =>
      @loadConfig @getConfigFileName()

  # reads configuraiton from filename and returns a config object
  readConfig: (fileName) ->
    fileName = @resolveFileName fileName
    config = CSON.readFileSync fileName
    config.configFileName = fileName
    console.log "mailtool config", config
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

  # append a message to a storage
  #
  # storage - a storage string like mailbox://<configname>/<path> or
  #           file://<relative pathname to mailconfig or absolute path>
  # rfc2822  - raw rfc2822 content
  appendMessage: (storage, rfc2822) ->
    Q.Promise (resolve, reject) =>
      [match, scheme, name, folder] = storage.match /(mailbox|file):\/\/([^/]+)\/(.*)/
      console.log "appendMessage", storage, rfc2822

      if scheme is 'file'
        try
          mkdirp = require 'mkdirp'
          dir = path.resolve(@getConfigDirName(), name, folder)

          mkdirp.sync dir, mode: 0o0700

          fileName = path.resolve(dir, (new Date).toISOString()+".eml")

          fs.writeFileSync fileName, rfc2822

          resolve {storage, name, folder, scheme, absolutePath: fileName, relativePath: fileName}
        catch e
          e.message = "Error storing mail to #{scheme} #{name}/#{folder}: " + e.message
          e.rfc2822 = rfc2822
          reject(e)

      else if scheme is 'mailbox'
        (@getImapConnection {name}).imapSession(reuse: yes).then (client) ->
          console.log "got connection"
          client.upload(folder, rfc2822).then (info) ->
            console.log "uploaded", info
            resolve { storage, name, folder, scheme }
          .catch (error) ->
            console.log "upload error", error, error.stack
            reject error
        .catch (error) ->
          reject error

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

  compile: (options) ->
    Q.Promise (resolve, reject) =>

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
          return options.optionDialog {missing, options}, (error) =>
            if error
              reject error
            else
              resolve options

        else
          return reject new MailToolMissingFieldError missing

      resolve options

  getTransporter: (config) ->
    Q.Promise (resolve, reject) =>
      # have transoporter
      # -------------------

      if config.transport
        storeSentMessages = union(
          (config.storeSentMessages ? []),
          (config.transport.storeSentMessages ? [])
          )
        if @transport.sendmail
          return resolve @transport
        else
          transport = @transport config.transport
          return resolve nodemailer.createTransport transport

      # create transoporter
      # -------------------

      cfgName = config.config or config.name or 'default'
      if m = cfgName.match /(.*)\.(.*)/
        cfgName = m[1]

      unless transport = @getConfig(cfgName).transport
        return reject new Error "No mail transport defined for config #{cfgName}"

      config.transport = extend {}, transport
      config.transport.auth = auth = extend {}, config.transport.auth

      configFileDir = path.dirname @getConfigFileName()
      console.log "configFileDir", configFileDir, "auth.pass", auth.pass

      passwdFile = path.resolve configFileDir, auth.pass

      if fs.existsSync passwdFile
        auth.pass = fs.readFileSync(passwdFile).toString().trim()

    # setup transport

      if config.transport.rejectUnauthorized is false
        process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0'

      transport = (require "nodemailer-smtp-transport") config.transport

      resolve nodemailer.createTransport transport

  sendMail: (config) ->
    Q.Promise (resolve, reject, notify) =>
      config = extend {}, config
      storeSentMessages = []

      @compile(config).then =>
        @getTransporter(config).then (transporter) =>
          storeSentMessages = union(
            (config.storeSentMessages ? []),
            (config.transport.storeSentMessages ? [])
            )

          transporter.use 'compile', doT()
          transporter.use 'compile', signature()
          transporter.use 'compile', markdown config

          rfc2822 = ''
          plugin = new (require('stream').Transform)();
          plugin._transform = (chunk, encoding, done) ->
            # replace all spaces with tabs in the stream chunk
            rfc2822 += chunk.toString()
            console.log encoding
            plugin.push chunk
            done()

          transporter.use 'stream', (mail, done) ->
            mail.message.transform plugin
            done()

          transporter.sendMail config, (error, info) =>
            info ?= {}
            info.rfc2822 = rfc2822.replace /(\r\n|\r|\n)/g, "\r\n"
            return reject(error) if error

            notify info

            promises = []
            errors = []

            for storage in storeSentMessages
              promise = @appendMessage(storage, info.rfc2822)
              .then (info) ->
                notify info
              .catch (error) ->
                errors.push error
                notify error

              promises.push promise

            if promises.length
              Q.allSettled(promises).then ->
                if errors.length
                  resolve info, errors
                else
                  resolve info
            else
              resolve info


nodeMailerConfig = (args...) ->
  mailtool = new MailTool args...

  (options, done) ->
    mailtool.compile(options, done)

main = ->
  mt = new MailTool "~/.mailtool/config.cson"

  mt.connectImap('default').then () =>
    mt.imap.listWellKnownFolders().then (folderInfo) =>
      console.log folderInfo

module.exports = {MailTool, nodeMailerConfig, main, MailToolMissingFieldError, MailMessage}
