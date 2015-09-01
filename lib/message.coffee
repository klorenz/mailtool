walkMimeTree = require './mime-walker.coffee'
Q = require 'q'

module.exports =
class Message
  constructor: (msg, options={}) ->
    @sentTimestamp = Date.parse msg.envelope.date

    if options.dateFormat is 'local'
      @sentDate = new Date(msg.envelope.date).toLocaleString()
    else if options.dateFormat is 'iso'
      @sentDate = new Date(msg.envelope.date).toISOString()
    else if options.dateFormat is 'utc' or options.dateFormat is 'gmt'
      @sentDate = new Date(msg.envelope.date).toUTCString()
    else
      @sentDate = msg.envelope.date

    {@uid, @modseq} = msg
    {@from, @to, @cc, @bcc, @sender, @subject} = msg.envelope

    if 'in-reply-to' of msg.envelope
      @inReplyTo = msg.envelope['in-reply-to']

    if 'reply-to' of msg.envelope
      @replyTo = msg.envelope['reply-to']

    if 'message-id' of msg.envelope
      @messageId = msg.envelope['message-id']

    @flag =
      answered: false
      seen: false
      flagged: false

    for flag in msg.flags
      key = flag.replace(/^\\+/, '').toLowerCase()
      @flag[key] = true

    @bodyStructure = msg.bodystructure

    @bodyParts = []

    walkMimeTree msg.bodystructure, @

  getBodyPartsForType: (type) ->
    result = []
    for part in @bodyParts
      if part.type == type
        result.push part

    return result
