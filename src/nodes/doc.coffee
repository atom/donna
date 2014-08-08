_ = require 'underscore'
Node = require './node'

# Public: A documentation node is responsible for parsing
# the comments for known tags.
#
module.exports = class Doc extends Node

  # Public: Construct a documentation node.
  #
  # node - The comment node (a {Object})
  # options - The parser options (a {Object})
  constructor: (@node, @options) ->
    try
      if @node
        trimmedComment = @leftTrimBlock(@node.comment.replace(/\u0091/gm, '').split('\n'))
        @comment = trimmedComment.join("\n")

    catch error
      console.warn('Create doc error:', @node, error) if @options.verbose

  leftTrimBlock: (lines) ->
    # Detect minimal left trim amount
    trimMap = _.map lines, (line) ->
      if line.length is 0
        undefined
      else
        line.length - _.str.ltrim(line).length

    minimalTrim = _.min _.without(trimMap, undefined)

    # If we have a common amount of left trim
    if minimalTrim > 0 and minimalTrim < Infinity

      # Trim same amount of left space on each line
      lines = for line in lines
        line = line.substring(minimalTrim, line.length)
        line

    lines
