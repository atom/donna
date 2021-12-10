Node      = require './node'

_         = require 'underscore'
_.str     = require 'underscore.string'

# Public: The Node representation of a CoffeeScript method parameter.
module.exports = class Parameter extends Node

  # Public: Construct a parameter node.
  #
  # node - The node (a {Object})
  # options - The parser options (a {Object})
  # optionized - A {Boolean} indicating if the parameter is a set of options
  constructor: (@node, @options, @optionized) ->
    super()

  # Public: Get the full parameter signature.
  #
  # Returns the signature (a {String}).
  getSignature: ->
    try
      unless @signature
        @signature = @getName()

        if @isSplat()
          @signature += '...'

        value = @getDefault()
        @signature += " = #{ value.replace(/\n\s*/g, ' ') }" if value

      @signature

    catch error
      console.warn('Get parameter signature error:', @node, error) if @options.verbose

  # Public: Get the parameter name
  #
  # Returns the name (a {String}).
  getName: (i = -1) ->
    try
      # params like `method: ({option1, option2}) ->`
      if @optionized && i >= 0
        @name = @node.name.properties[i].base.value

      unless @name

        # Normal attribute `do: (it) ->`
        @name = @node.name.value

        unless @name
          if @node.name.properties
            # Assigned attributes `do: (@it) ->`
            @name = @node.name.properties[0]?.name?.value

      @name

    catch error
      console.warn('Get parameter name error:', @node, error) if @options.verbose

  # Public: Get the parameter default value
  #
  # Returns the default (a {String}).
  getDefault: (i = -1) ->
    try
      # for optionized arguments
      if @optionized && i >= 0
        _.str.strip(@node.value?.compile({ indent: '' })[1..-2].split(",")[i]).split(": ")[1]
      else
        @node.value?.compile({ indent: '' })

    catch error
      if @node?.value?.base?.value is 'this'
        "@#{ @node.value.properties[0]?.name.compile({ indent: '' }) }"
      else
        console.warn('Get parameter default error:', @node, error) if @options.verbose

  # Public: Gets the defaults of the optionized parameters.
  #
  # Returns the defaults as a {String}.
  getOptionizedDefaults: ->
    return '' unless @node.value?

    defaults = []
    for k in @node.value.compile({ indent: '' }).split("\n")[1..-2]
      defaults.push _.str.strip(k.split(":")[0])

    return "{" + defaults.join(",") + "}"

  # Public: Checks if the parameters is a splat
  #
  # Returns `true` if a splat (a {Boolean}).
  isSplat: ->
    try
      @node.splat is true

    catch error
      console.warn('Get parameter splat type error:', @node, error) if @options.verbose
