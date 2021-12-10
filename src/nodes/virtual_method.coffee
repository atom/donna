Node      = require './node'
Parameter = require './parameter'
Doc       = require './doc'

_         = require 'underscore'
_.str     = require 'underscore.string'

# Public: The Node representation of a CoffeeScript  virtual method that has
# been declared by the `@method` tag.
module.exports = class VirtualMethod extends Node

  # Public: Construct a virtual method node.
  #
  # entity - The method's {Class}
  # doc - The property node (a {Object})
  # options - The parser options (a {Object})
  constructor: (@entity, @doc, @options) ->
    super()

  # Public: Get the method type, either `class`, `instance` or `mixin`.
  #
  # Returns the method type (a {String}).
  getType: ->
    unless @type
      if @doc.signature.substring(0, 1) is '.'
        @type = 'instance'
      else if @doc.signature.substring(0, 1) is '@'
        @type = 'class'
      else
        @type = 'mixin'

    @type

  # Public: Get the class doc
  #
  # Returns the class doc (a {Doc}).
  getDoc: -> @doc

  # Public: Get the full method signature.
  #
  # Returns the signature (a {String}).
  getSignature: ->
    try
      unless @signature
        @signature = switch @getType()
                     when 'class'
                       '+ '
                     when 'instance'
                       '- '
                     else
                       '? '

        if @getDoc()
          @signature += if @getDoc().returnValue then "(#{ _.str.escapeHTML @getDoc().returnValue.type }) " else "(void) "

        @signature += "<strong>#{ @getName() }</strong>"
        @signature += '('

        params = []

        for param in @getParameters()
          params.push param.name

        @signature += params.join(', ')
        @signature += ')'

      @signature

    catch error
      console.warn('Get method signature error:', @node, error) if @options.verbose

  # Public: Get the short method signature.
  #
  # Returns the short signature (a {String}).
  getShortSignature: ->
    try
      unless @shortSignature
        @shortSignature = switch @getType()
                          when 'class'
                            '@'
                          when 'instance'
                            '.'
                          else
                            ''
        @shortSignature += @getName()

      @shortSignature

    catch error
      console.warn('Get method short signature error:', @node, error) if @options.verbose

  # Public: Get the method name
  #
  # Returns the method name (a {String}).
  getName: ->
    try
      unless @name
        if name = /[.#]?([$A-Za-z_\x7f-\uffff][$\w\x7f-\uffff]*)/i.exec @doc.signature
          @name = name[1]
        else
          @name = 'unknown'

      @name

    catch error
      console.warn('Get method name error:', @node, error) if @options.verbose

  # Public: Get the method parameters
  #
  # params - The method parameters
  getParameters: -> @doc.params or []

  # Public: Get the method source in CoffeeScript
  #
  # Returns the CoffeeScript source (a {String}).
  getCoffeeScriptSource: ->

  # Public: Get the method source in JavaScript
  #
  # Returns the JavaScript source (a {String}).
  getJavaScriptSource: ->
