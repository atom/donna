fs           = require 'fs'
path         = require 'path'

_            = require 'underscore'
builtins     = require 'builtins'

module.exports = class Metadata
  constructor: (@dependencies, @parser) ->

  generate: (@root) ->
    @defs = {} # Local variable definitions
    @exports = {}
    @bindingTypes = {}
    @modules = {}
    @classes = @parser.classes
    @files = @parser.files

    @root.traverseChildren no, (exp) => @visit(exp) # `no` means Stop at scope boundaries

  visit: (exp) ->
    @["visit#{exp.constructor.name}"]?(exp)
  eval:  (exp) ->
    @["eval#{exp.constructor.name}"](exp)

  visitComment: (exp) ->
    # Skip the 1st comment which is added by donna
    return if exp.comment is '~Private~'

  visitClass: (exp) ->
    return unless exp.variable?
    @defs[exp.variable.base.value] = @evalClass(exp)
    no # Do not traverse into the class methods

  visitAssign: (exp) ->
    variable = @eval(exp.variable)
    value = @eval(exp.value)

    baseName = exp.variable.base.value
    switch baseName
      when 'module'
        return if exp.variable.properties.length is 0 # Ignore `module = ...` (atom/src/browser/main.coffee)
        unless exp.variable.properties?[0]?.name?.value is 'exports'
          throw new Error 'BUG: Does not support module.somthingOtherThanExports'
        baseName = 'exports'
        firstProp = exp.variable.properties[1]
      when 'exports'
        firstProp = exp.variable.properties[0]

    switch baseName
      when 'exports'
        # Handle 3 cases:
        #
        # - `exports.foo = SomeClass`
        # - `exports.foo = 42`
        # - `exports = bar`
        if firstProp
          if value.base? && @defs[value.base.value]
            # case `exports.foo = SomeClass`
            @exports[firstProp.name.value] = @defs[value.base.value]
          else
            # case `exports.foo = 42`
            unless firstProp.name.value == value.name
              @defs[firstProp.name.value] =
                name: firstProp.name.value
                bindingType: 'exportsProperty'
                type: value.type
                range: [ [exp.variable.base.locationData.first_line, exp.variable.base.locationData.first_column], [exp.variable.base.locationData.last_line, exp.variable.base.locationData.last_column ] ]
            @exports[firstProp.name.value] =
              startLineNumber:  exp.variable.base.locationData.first_line
        else
          # case `exports = bar`
          @exports = {_default: value}
          switch value.type
            when 'class'
              @bindingTypes[value.name] = "exports"

      # case left-hand-side is anything other than `exports...`
      else
        # Handle 5 common cases:
        #
        # X     = ...
        # {X}   = ...
        # {X:Y} = ...
        # X.y   = ...
        # [X]   = ...
        switch exp.variable.base.constructor.name
          when 'Literal'
            # Something we dont care about is on the right side of the `=`.
            # This could be some garbage like an if statement.
            return unless value?.range

            # case _.str = ...
            if exp.variable.properties.length > 0
              keyPath = exp.variable.base.value
              for prop in exp.variable.properties
                if prop.name?
                  keyPath += ".#{prop.name.value}"
                else
                  keyPath += "[#{prop.index.base.value}]"
              @defs[keyPath] = _.extend name: keyPath, value
            else # case X = ...
              @defs[exp.variable.base.value] = _.extend name: exp.variable.base.value, value

              # satisfies the case of npm module requires (like Grim in our tests)
              if @defs[exp.variable.base.value].type == "import"
                key = @defs[exp.variable.base.value].path || @defs[exp.variable.base.value].module
                if _.isUndefined @modules[key]
                  @modules[key] = []

                @modules[key].push { name: @defs[exp.variable.base.value].name, range: @defs[exp.variable.base.value].range }

              switch @defs[exp.variable.base.value].type
                when 'function'
                  # FIXME: Ugh. This is so fucked. We shouldnt match on name in all the files in the entire project.
                  for file in @files
                    for method in file.methods
                      if @defs[exp.variable.base.value].name == method.name
                        @defs[exp.variable.base.value].doc = method.doc.comment
                        break

          when 'Obj', 'Arr'
            for key in exp.variable.base.objects
              switch key.constructor.name
                when 'Value'
                  # case {X} = ...
                  @defs[key.base.value] = _.extend {}, value,
                    name: key.base.value
                    exportsProperty: key.base.value
                    range: [ [key.base.locationData.first_line, key.base.locationData.first_column], [key.base.locationData.last_line, key.base.locationData.last_column ] ]

                  # Store the name of the exported property to the module name
                  if @defs[key.base.value].type == "import" # I *think* this will always be true
                    if _.isUndefined @modules[@defs[key.base.value].path]
                      @modules[@defs[key.base.value].path] = []
                    @modules[@defs[key.base.value].path].push {name: @defs[key.base.value].name, range: @defs[key.base.value].range}
                when 'Assign'
                  # case {X:Y} = ...
                  @defs[key.value.base.value] = _.extend {}, value,
                    name: key.value.base.value
                    exportsProperty: key.variable.base.value
                  return no # Do not continue visiting X

                else throw new Error "BUG: Unsupported require Obj structure: #{key.constructor.name}"
          else throw new Error "BUG: Unsupported require structure: #{exp.variable.base.constructor.name}"

  visitCode: (exp) ->

  visitValue: (exp) ->

  visitCall: (exp) ->

  visitLiteral: (exp) ->

  visitObj: (exp) ->

  visitAccess: (exp) ->

  visitBlock: (exp) ->

  visitTry: (exp) ->

  visitIn: (exp) ->

  visitExistence: (exp) ->

  evalComment: (exp) ->
    type: 'comment'
    doc: exp.comment
    range: [ [exp.locationData.first_line, exp.locationData.first_column], [exp.locationData.last_line, exp.locationData.last_column ] ]

  evalClass: (exp) ->
    className = exp.variable.base.value
    superClassName = exp.parent?.base.value
    classProperties = []
    prototypeProperties = []

    classNode = _.find(@classes, (clazz) -> clazz.getFullName() == className)

    for subExp in exp.body.expressions
      switch subExp.constructor.name
        # case Prototype-level methods (this.foo = (foo) -> ...)
        when 'Assign'
          value = @eval(subExp.value)
          @defs["#{className}.#{value.name}"] = value
          classProperties.push(value)
        when 'Value'
          # case Prototype-level properties (@foo: "foo")
          for prototypeExp in subExp.base.properties
            switch prototypeExp.constructor.name
              when 'Comment'
                value = @eval(prototypeExp)
                @defs["#{value.range[0][0]}_line_comment"] = value
              else
                isClassLevel = prototypeExp.variable.this

                if isClassLevel
                  name = prototypeExp.variable.properties[0].name.value
                else
                  name = prototypeExp.variable.base.value

                # The reserved words are a string with a property: {reserved: true}
                # We dont care about the reserved-ness in the name. It is
                # detrimental as comparisons fail.
                name = name.slice(0) if name.reserved

                value = @eval(prototypeExp.value)

                if value.constructor?.name is 'Value'
                  lookedUpVar = @defs[value.base.value]
                  if lookedUpVar
                    if lookedUpVar.type is 'import'
                      value =
                        name: name
                        range: [ [value.locationData.first_line, value.locationData.first_column], [value.locationData.last_line, value.locationData.last_column ] ]
                        reference: lookedUpVar
                    else
                      value = _.extend name: name, lookedUpVar

                  else
                    # Assigning a simple var
                    value =
                      type: 'primitive'
                      name: name
                      range: [ [value.locationData.first_line, value.locationData.first_column], [value.locationData.last_line, value.locationData.last_column ] ]

                else
                  value = _.extend name: name, value

                # TODO: `value = @eval(prototypeExp.value)` is messing this up
                # interferes also with evalValue
                if isClassLevel
                  value.name = name
                  value.bindingType = "classProperty"
                  @defs["#{className}.#{name}"] = value
                  classProperties.push(value)

                  if reference = @applyReference(prototypeExp)
                    @defs["#{className}.#{name}"].reference =
                      position: reference.range[0]
                else
                  value.name = name
                  value.bindingType = "prototypeProperty"
                  @defs["#{className}::#{name}"] = value
                  prototypeProperties.push(value)

                  if reference = @applyReference(prototypeExp)
                    @defs["#{className}::#{name}"].reference =
                      position: reference.range[0]

                # apply the reference (if one exists)
                if value.type is "primitive"
                  variable = _.find classNode?.getVariables(), (variable) -> variable.name == value.name
                  value.doc = variable?.doc.comment
                else if value.type is "function"
                  # find the matching method from the parsed files
                  func = _.find classNode?.getMethods(), (method) -> method.name == value.name
                  value.doc = func?.doc.comment
          true

    type: 'class'
    name: className
    superClass: superClassName
    bindingType: @bindingTypes[className] unless _.isUndefined @bindingTypes[className]
    classProperties: classProperties
    prototypeProperties: prototypeProperties
    doc: classNode?.doc.comment
    range: [ [exp.locationData.first_line, exp.locationData.first_column], [exp.locationData.last_line, exp.locationData.last_column ] ]

  evalCode: (exp) ->
    bindingType: 'variable'
    type: 'function'
    paramNames: _.map(exp.params, ((param) -> param.name.value))
    range: [ [exp.locationData.first_line, exp.locationData.first_column], [exp.locationData.last_line, exp.locationData.last_column ] ]
    doc: null

  evalValue: (exp) ->
    if exp.base
      type: 'primitive'
      name: exp.base?.value
      range: [ [exp.locationData.first_line, exp.locationData.first_column], [exp.locationData.last_line, exp.locationData.last_column ] ]
    else
      throw new Error 'BUG? Not sure how to evaluate this value if it does not have .base'

  evalCall: (exp) ->
    # The only interesting call is `require('foo')`
    if exp.variable.base?.value is 'require'
      return unless exp.args[0].base?

      return unless moduleName = exp.args[0].base?.value
      moduleName = moduleName.substring(1, moduleName.length - 1)

      # For npm modules include the version number
      ver = @dependencies[moduleName]
      moduleName = "#{moduleName}@#{ver}" if ver

      ret =
        type: 'import'
        range: [ [exp.locationData.first_line, exp.locationData.first_column], [exp.locationData.last_line, exp.locationData.last_column ] ]
        bindingType: 'variable'

      if /^\./.test(moduleName)
        # Local module
        ret.path = moduleName
      else
        ret.module = moduleName
      # Tag builtin NodeJS modules
      ret.builtin = true if builtins.indexOf(moduleName) >= 0

      ret

    else
      type: 'function'
      range: [ [exp.locationData.first_line, exp.locationData.first_column], [exp.locationData.last_line, exp.locationData.last_column ] ]

  evalError: (str, exp) ->
    throw new Error "BUG: Not implemented yet: #{str}. Line #{exp.locationData.first_line}"

  evalAssign: (exp) -> @eval(exp.value) # Support x = y = z

  evalLiteral: (exp) -> @evalError 'evalLiteral', exp

  evalObj: (exp) -> @evalError 'evalObj', exp

  evalAccess: (exp) -> @evalError 'evalAccess', exp

  evalUnknown: (exp) -> exp
  evalIf: -> @evalUnknown(arguments)
  visitIf: ->
  visitFor: ->
  visitParam: ->
  visitOp: ->
  visitArr: ->
  visitNull: ->
  visitBool: ->
  visitIndex: ->
  visitParens: ->
  visitReturn: ->
  visitUndefined: ->

  evalOp: (exp) -> exp

  applyReference: (prototypeExp) ->
    for module, references of @modules
      for reference in references
        # non-npm module case (local file ref)
        if prototypeExp.value.base?.value
          ref = prototypeExp.value.base.value
        else
          ref = prototypeExp.value.base

        if reference.name == ref
          return reference
