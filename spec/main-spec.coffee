main = require "../lib/mailtool.coffee"
{extend} = require "underscore"

describe "MailTool", ->
  mock = null
  mailopts = null
  mailoptsConfig = null
  mt = null

  beforeEach ->

    mockObject = {
      callback: (err) ->
        debugger

      sendMail: (data, callback) ->

        callback(null)

      use: (mode, func) ->

    }

    mockFunction = ->

    mock = extend mockFunction, mockObject

    spyOn(mock, 'callback').andCallThrough()
    spyOn(mock, 'sendMail').andCallThrough()
    spyOn(mock, 'use').andCallThrough()

    mailoptsConfig =
      default: {
        transport: {
        }
      }
      someconfig: {
        from: "harry@hogwarts.edu"
      }

    mailopts = {subject: "foo", to: "bar@glork.com"}

    mt = new main.MailTool mailoptsConfig, mock

  it "uses markdown mails", ->
    mt.sendMail mailopts, mock.callback
    waitsFor ->
      mock.callback.wasCalled
    runs ->
      expect(mock.callback).toHaveBeenCalledWith(null)
      expect(mock.use.mostRecentCall.args[0]).toBe "compile"

  it "can handle configuration data", ->
    mt.sendMail extend({config: 'someconfig'}, mailopts), mock.callback

    waitsFor ->
      mock.callback.wasCalled
    runs ->
      expect(mock.sendMail).toHaveBeenCalledWith(extend({config: 'someconfig'}, mailoptsConfig.someconfig, mailopts), mock.callback)

  # fit "can run mail", ->
  #   debugger
  #   main.main()

  fit "can create a uid sequence", ->
    {makeSequence} = require '../lib/utils.coffee'
    expect(makeSequence([1, 2, 3])).toEqual "1:3"
    expect(makeSequence([1, 2, 8, 5, 3, 9])).toEqual "1:3,5,8:9"
