walkMimeTree = require './mime-walker.coffee'
Q = require 'q'
{extend} = require 'underscore'

formatAddress = (o) ->
  return o.trim() if typeof o is 'string'
  return o unless o

  address = ''
  if o.name
    address += o.name
  if o.address
    address += " <#{o.address}>"

  address.trim()

formatAddressList = (o) ->
  if o instanceof Array
    (formatAddress x for x in o).join(', ')
  else
    formatAddress o


module.exports =
class MailMessage
  constructor: (msg, @options={}) ->
    unless msg.sentTimestamp
      @initialize msg
    else
      # deserialize
      extend this, msg

  initialize: (msg) ->
    @sentTimestamp = Date.parse msg.envelope.date

    if @options.dateFormat is 'local'
      @sent = new Date(msg.envelope.date).toLocaleString()
    else if @options.dateFormat is 'iso'
      @sent = new Date(msg.envelope.date).toISOString()
    else if @options.dateFormat is 'utc' or @options.dateFormat is 'gmt'
      @sent = new Date(msg.envelope.date).toUTCString()
    else
      @sent = msg.envelope.date

    {@uid, @modseq} = msg
    {@from, @to, @cc, @bcc, @sender, @subject} = msg.envelope
    @envelope = msg.envelope

    if 'in-reply-to' of msg.envelope
      @inReplyTo = formatAddressList msg.envelope['in-reply-to']

    if 'reply-to' of msg.envelope
      @replyTo = formatAddressList msg.envelope['reply-to']

    if 'message-id' of msg.envelope
      @messageId = msg.envelope['message-id']

    @from = formatAddressList @from
    @to   = formatAddressList @to
    @cc   = formatAddressList @cc
    @bcc  = formatAddressList @bcc

    @flag = @makeFlags msg

    @bodyStructure = msg.bodystructure

    @bodyParts = []

    walkMimeTree msg.bodystructure, @

    for part in @bodyParts
      if part.type is 'attachment'
        @flag['attachment'] = true

  makeFlags: (msg) ->
    flags =
      answered: false
      seen: false
      flagged: false
      draft: false
      deleted: false

    for flag in msg.flags
      key = flag.replace(/^\\+/, '').toLowerCase()
      flags[key] = true

    flags

  update: (msg) ->
    updated = false

    flags = @makeFlags(msg)

    # unset flags, which are not in mail
    for flag of @flag
      continue if flag is 'attachment'

      if flag not of flags
        @flag[flag] = false
        updated = true

    # set flags, which are in mail
    for flag of flags
      if flag not of @flag
        @flags[flag] = flags[flag]
        updated = true
      else if @flag[flag] != flags[flag]
        updated = true
        @flag[flag] = flags[flag]

    return updated

  updateBodyParts: (parts) ->
    partTable = {}
    for part in parts
      partTable[part.partNumber] = part

    for part, i in @bodyParts
      if partTable[part.partNumber]
        @bodyParts[i] = partTable[part.partNumber]

  getBodyPartsForType: (type) ->
    result = []
    for part in @bodyParts
      if part.type == type
        result.push part

    return result

  getAddrString: (field) ->
    return '' unless field of this

    value = @[field]
    return value if typeof value is "string"

    makeAddr = (o) ->
      if o.name
        return "#{o.name} <#{o.address}>"
      else
        return o.address

    if value instanceof Array
      (makeAddr(o) for o in value).join(", ")
    else
      makeAddr o

  getReplyOptions: (options={}) =>
    options.composed ?= {}
    composed = options.composed

    if @replyTo
      composed.to = @replyTo
    else if @sender
      composed.to = @sender
    else
      composed.to = @from

    subject = @subject ? ""

    if subject.match /^re:/i
      composed.subject = subject
    else
      composed.subject = "Re: " + subject

    if options.replyAll
      if @cc
        composed.cc = @cc

    return options

  quoteMessage: (options, callback) ->
    if options instanceof Function
      callback = opts
      options = {}
    options ?= {}

    if 'quoted' not of options
      options.quoted = true

    @prefer = ['text', 'html']
    content = null
    for preferred in @prefer
      for part in @bodyParts
        if part.type is preferred
          if part.content
            content = part.content
            break

      neededParts = @getBodyPartsForType preferred
      break if neededParts.length

    options.composed ?= {}
    options.composed.content ?= ''

    if options.forwardHeader
      options.composed.content += """
        -------- Forwarded Message --------
        Subject: #{@subject}
        Date: #{@sent}
        From: #{@from}
        To: #{@to}
        \n\n
      """

    quote = (content) ->
      if options.quoted
        ("> #{line}\n" for line in content.trim().split /\n/g).join("")
      else
        content

    if content
      options.composed.content += quote content
      callback null, options
    else
      gotParts = (parts) =>
        content = ''

        for part in parts
          if part.type == 'html'
             # do html
             htmlToText = require 'html-to-text'
             content += htmlToText.fromString part.content, wordWrap: 75
          else
             content += part.content

        options.composed.content += quote content
        callback null, options

      if options.mailbox
        options.mailbox.getMessageBodyParts(this, neededParts).then(gotParts).catch (error) -> callback error
      else
        error = new Error "Need message parts"
        error.parts = neededParts
        error.callback = (parts) =>

        throw error

  replyAll: (options, callback) ->
    @quoteMessage @getReplyOptions(extend options, replyAll: true), callback

  reply: (options, callback) ->
    @quoteMessage @getReplyOptions(options), callback

  forward: (options, callback) ->
    options.composed ?= {}
    if 'forwardHeader' not of options
      options.forwardHeader = true
    if 'forwardPrefex' not of options
      options.forwardPrefix = "Fwd: "
    if 'subject' not of options
      options.composed.subject = (options.forwardPrefix or '') + @subject

    @quoteMessage options, callback
