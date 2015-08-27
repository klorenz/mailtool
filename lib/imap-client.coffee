axe = require('axe-logger')
axe.logLevel = axe.ERROR

tcp_socket = require('tcp-socket')

orig_require = module.constructor.prototype.require
module.constructor.prototype.require = (name) ->
  if name is 'tcp-socket'
    return tcp_socket
  else if name is 'axe-logger'
    return axe
  else
    return orig_require.call this, name
BrowserBox = require 'browserbox'
module.constructor.prototype.require = orig_require

module.exports = {axe, BrowserBox}
