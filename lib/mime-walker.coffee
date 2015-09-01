# Functions here are translated to coffeescript from
#
# https://github.com/whiteout-io/imap-client
#
# The MIT License (MIT)
#
# Copyright (c) 2014 Whiteout Networks GmbH
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
# FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
# IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#


# Matches encrypted PGP/MIME nodes
#
# multipart/encrypted
# |
# |-- application/pgp-encrypted
# |-- application/octet-stream <-- ciphertext

matchEncrypted = (node, message) ->
  isEncrypted = /^multipart\/encrypted/i.test(node.type) && node.childNodes && node.childNodes[1]
  return false unless isEncrypted

  message.bodyParts.push
    type: 'encrypted',
    partNumber: node.part || '',

  return true


# Matches signed PGP/MIME nodes
#
# multipart/signed
# |
# |-- *** (signed mime sub-tree)
# |-- application/pgp-signature
#
matchSigned = (node, message) ->
  c = node.childNodes

  isSigned = /^multipart\/signed/i.test(node.type) && c && c[0] && c[1] && /^application\/pgp-signature/i.test(c[1].type)
  return false unless isSigned

  message.bodyParts.push
    type: 'signed'
    partNumber: node.part || ''

  return true


# Matches non-attachment text/plain nodes
#
# node - {Object} Mime Node to match
# message - {Object} Message
#
matchText = (node, message) ->
  isText = /^text\/plain/i.test(node.type) && node.disposition isnt 'attachment'
  return false unless isText

  message.bodyParts.push
    type: 'text'
    partNumber: node.part || ''

  return true

# Matches non-attachment text/html nodes
#
matchHtml = (node, message) ->
  isHtml = (/^text\/html/i.test(node.type) && node.disposition isnt 'attachment')
  return false unless isHtml

  message.bodyParts.push
    type: 'html',
    partNumber: node.part || ''

  return true

# Matches attachment
#
matchAttachment = (node, message) ->
  isAttachment = (/^text\//i.test(node.type) && node.disposition) || (!/^text\//i.test(node.type) && !/^multipart\//i.test(node.type))
  return false unless isAttachment

  bodyPart =
    type: 'attachment'
    partNumber: node.part || ''
    mimeType: node.type || 'application/octet-stream'
    id: if node.id then node.id.replace(/[<>]/g, '') else undefined

  if (node.dispositionParameters && node.dispositionParameters.filename)
    bodyPart.filename = node.dispositionParameters.filename
  else if (node.parameters && node.parameters.name)
    bodyPart.filename = node.parameters.name
  else
    bodyPart.filename = 'attachment'

  message.bodyParts.push bodyPart
  return true

mimeTreeMatchers = [ matchAttachment, matchText, matchAttachment, matchSigned, matchEncrypted, matchHtml ]

# Helper function that walks the MIME tree in a dfs and calls the handlers
# mimeNode - {Object} The initial MIME node whose subtree should be traversed
# message  - {Object} message The initial root MIME node whose subtree should
#            be traversed
walkMimeTree = (mimeNode, message) ->
  for mimeTreeMatcher in mimeTreeMatchers
    return if mimeTreeMatcher mimeNode, message

  if mimeNode.childNodes
    mimeNode.childNodes.forEach (childNode) ->
      walkMimeTree childNode, message

module.exports = walkMimeTree
