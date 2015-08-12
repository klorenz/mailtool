CSON = require 'season'
{markdown} = require 'nodemailer-markdown'
nodemailer = require 'nodemailer'
doT = require 'dot'
{keys, extend} = require 'underscore'

isUpperCase = (s) ->
  s.toUpperCase() == s

class MailToolMissingFieldError extends Error
  constructor: (@field) ->
    super "Missing field '#{@field}' in envelope"

class MailTool
  constructor: (config, transport) ->

    # read config from file if it is a string
    if typeof config is "string"
      @config = CSON.readFileSync config
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

  applyTemplates: (options) ->
    templates = {}
    templateData = extend {}, options.data

    for key, value of options
      if not value.match /\{\{/
        if key not of templateData
          templateData[key] = value
      else
        templates[key] = {
          source: value,
          template: doT.template(value.replace(/\{\{\w+\}\}/, (m) -> "{{=it."+m.substring(2)))
          hasUndefined: /undefined/.test value
          }

    currentTemplateCount = templates.length
    while keys(templates).length
      for key in keys(templates)
        value = templates[key].template(templateData)
        hasUndefined = /undefined/.test value

        if (not hasUndefined or (hasUndefined and templates[key].hasUndefined))
          delete templates[key]
          templateData[key] = value
          options[key] = value

      if currentTemplateCount == templates.length
        # not all templates could be applied
        # this is may be an error or the text
        break

  sendMail: (config, callback) ->
    cfgName = config.config or config.name or 'default'

    mailOpts = {}
    toolOpts = {}

    data = {}

    # merge Template Data
    templateData = extend @config[cfgName].data or {}, config.data or {}

    for opts in [@config[cfgName], config]
      for key, value of opts
        data[key] = value

    data.data = templateData

    for field in @required
      if field not of data
        return process.nextTick -> callback new MailToolMissingFieldError(field)

    # maybe create an own nodemailer-signature-transport plugin
    if 'signature' of data
      if typeof data.signature is "string"
         # append signature to text and html and markdown

         if data.text
           data.text += "\n--\n" + data.signature

         else if data.markdown
           data.markdown += "\n--\n" + data.signature

      else if data.signature
        for name in ['html', 'text', 'markdown']
          if name of data.signature
            data[name] += data.signature[name]

    # setup transport
    if not @transport
      transport = require "nodemailer-smtp-transport"
    else if @transport.sendMail
      transport = @transport
    else
      transport = nodemailer.createTransport @transport data.transport

    transport.use('compile', markdown data)

    transport.sendMail data, callback

module.exports = {MailTool}
