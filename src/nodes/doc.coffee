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
        @parseBlock trimmedComment

    catch error
      console.warn('Create doc error:', @node, error) if @options.verbose
