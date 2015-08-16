CSON           = require 'season'
{markdown}     = require 'nodemailer-markdown'
{doT}          = require 'nodemailer-dot-templates'
{signature}    = require 'nodemailer-signature'
nodemailer     = require 'nodemailer'
{keys, extend} = require 'underscore'

getUserHome = () ->
  process.env[(process.platform == 'win32') ? 'USERPROFILE' : 'HOME']

isUpperCase = (s) ->
  s.toUpperCase() == s

class MailToolMissingFieldError extends Error
  constructor: (@field) ->
    super "Missing field '#{@field}' in envelope"

class MailTool
  constructor: (config, transport) ->
    if not config
      config = getUserHome() + "/.nodemailer.conf"

    # read config from file if it is a string
    if typeof config is "string"
      try
        @config = CSON.readFileSync config
      catch e
        @config = {}
    else
      @config = config

    # setup default configuration
    if 'default' not of @config
      for k,v of @config
        @config.default = v
        break

    if typeof @config.default is "string"
      @config.default = @config[@config.default]

    @transport = transport
    @required = ['subject', 'to']


  # save current configuration to fileName.  if None given, then
  # configFileName will be used
  saveConfig: (fileName) ->
    if not fileName
      fileName = @config.configFileName

    @writeConfig fileName, @config

  # load current configuration from fileName
  loadConfig: (fileName) ->
    @config = @readConfig fileName

  # reads configuraiton from filename and returns a config object
  readConfig: (fileName) ->
    config = CSON.readFileSync fileName
    config.configFileName = fileName
    return config

  # writes a configuration object to fileName
  writeConfig: (fileName, config) ->
    configFileName = null

    if 'configFileName' of config
      configFileName = config.configFileName
      delete config.configFileName

    CSON.writeFileSync fileName, config

    if configFileName?
      config.configFileName = configFileName

  compile: (options, callback) ->
    cfgName = options.config or options.name or 'default'

    for key, value of @config[cfgName]
      if key not of options
        options[key] = value
      else if typeof options[key] is "object" and typeof value is "object"
        options[key] = extend {}, value, options[key]

    for field in @required
      if field not of options
        return process.nextTick -> callback new MailToolMissingFieldError(field)

    callback?()

  sendMail: (config, callback) ->
    @compile(config)

    # setup transport
    if not @transport
      transport = require "nodemailer-smtp-transport"
    else if @transport.sendMail
      transport = @transport
    else
      transport = nodemailer.createTransport @transport data.transport

    transport.use('compile', doT())
    transport.use('compile', signature())
    transport.use('compile', markdown config)

    transport.sendMail config, callback

nodeMailerConfig = (args...) ->
  mailtool = new MailTool args...

  (options, done) ->
    mailtool.compile(options, done)


module.exports = {MailTool}
