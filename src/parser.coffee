fs = require 'fs'
path = require 'path'
_ = require 'underscore'
_.str = require 'underscore.string'
CoffeeScript = require 'coffee-script'

File = require './nodes/file'
Class = require './nodes/class'
Mixin = require './nodes/mixin'
VirtualMethod = require './nodes/virtual_method'

{SourceMapConsumer} = require 'source-map'

# FIXME: The only reason we use the parser right now is for comment conversion.
# We need to convert the comments to block comments so they show up in the AST.
# This could be done by the {Metadata} class, but just isnt at this point.

# Public: This parser is responsible for converting each file into the intermediate /
# AST representation as a JSON node.
module.exports = class Parser

  # Public: Construct the parser
  #
  # options - An {Object} of options
  constructor: (@options={}) ->
    @files   = []
    @classes = []
    @mixins  = []
    @iteratedFiles = {}
    @fileCount = 0
    @globalStatus = "Private"

  # Public: Parse the given CoffeeScript file.
  #
  # filePath - {String} absolute path name
  parseFile: (filePath, relativeTo) ->
    content = fs.readFileSync(filePath, 'utf8')
    relativePath = path.normalize(filePath.replace(relativeTo, ".#{path.sep}"))
    @parseContent(content, relativePath)
    @iteratedFiles[relativePath] = content
    @fileCount += 1

  # Public: Parse the given CoffeeScript content.
  #
  # content - A {String} representing the CoffeeScript file content
  # file - A {String} representing the CoffeeScript file name
  #
  parseContent: (@content, file='') ->
    @previousNodes = []
    @globalStatus = "Private"

    # Defines typical conditions for entities we are looking through nodes
    entities =
      clazz: (node) -> node.constructor.name is 'Class' && node.variable?.base?.value?
      mixin: (node) -> node.constructor.name == 'Assign' && node.value?.base?.properties?

    [convertedContent, lineMapping] = @convertComments(@content)

    sourceMap = CoffeeScript.compile(convertedContent, {sourceMap: true}).v3SourceMap
    @smc = new SourceMapConsumer(sourceMap)

    try
      root = CoffeeScript.nodes(convertedContent)
    catch error
      console.log('Parsed CoffeeScript source:\n%s', convertedContent) if @options.debug
      throw error

    # Find top-level methods and constants that aren't within a class
    fileClass = new File(root, file, lineMapping, @options)
    @files.push(fileClass)

    @linkAncestors root

    root.traverseChildren true, (child) =>
      entity = false

      for type, condition of entities
        if entities.hasOwnProperty(type)
          entity = type if condition(child)

      if entity

        # Check the previous tokens for comment nodes
        previous = @previousNodes[@previousNodes.length-1]
        switch previous?.constructor.name
          # A comment is preceding the class declaration
          when 'Comment'
            doc = previous
          when 'Literal'
            # The class is exported `module.exports = class Class`, take the comment before `module`
            if previous.value is 'exports'
              node = @previousNodes[@previousNodes.length-6]
              doc = node if node?.constructor.name is 'Comment'

        if entity == 'mixin'
          name = [child.variable.base.value]

          # If p.name is empty value is going to be assigned to index...
          name.push p.name?.value for p in child.variable.properties

          # ... and therefore should be just skipped.
          if name.indexOf(undefined) == -1
            mixin = new Mixin(child, file, @options, doc)

            if mixin.doc.mixin? && (@options.private || !mixin.doc.private)
              @mixins.push mixin

        if entity == 'clazz'
          clazz = new Class(child, file, lineMapping, @options, doc)
          @classes.push clazz

      @previousNodes.push child
      true

    root

  # Public: Converts the comments to block comments, so they appear in the node structure.
  # Only block comments are considered by Donna.
  #
  # content - A {String} representing the CoffeeScript file content
  convertComments: (content) ->
    result         = []
    comment        = []
    inComment      = false
    inBlockComment = false
    indentComment  = 0
    globalCount = 0
    lineMapping = {}

    for line, l in content.split('\n')
      globalStatusBlock = false

      # key: the translated line number; value: the original number
      lineMapping[(l + 1) + globalCount] = l + 1

      if globalStatusBlock = /^\s*#{3} (\w+).+?#{3}/.exec(line)
        result.push ''
        @globalStatus = globalStatusBlock[1]

      blockComment = /^\s*#{3,}/.exec(line) && !/^\s*#{3,}.+#{3,}/.exec(line)

      if blockComment || inBlockComment
        inBlockComment = !inBlockComment if blockComment
        result.push line
      else
        commentLine = /^(\s*#)\s?(\s*.*)/.exec(line)
        if commentLine
          commentText = commentLine[2]?.replace(/#/g, "\u0091#")
          unless inComment
            # append current global status flag if needed
            if !/^\s*\w+:/.test(commentText)
              commentText = @globalStatus + ": " + commentText
            inComment = true
            indentComment = commentLine[1].length - 1
            commentText = "### #{commentText}"

          comment.push whitespace(indentComment) + commentText

        else
          if inComment
            inComment = false
            lastComment = _.last(comment)

            # slight fix for an empty line as the last item
            if _.str.isBlank(lastComment)
              globalCount++
              comment[comment.length] = lastComment + ' ###'
            else
              comment[comment.length - 1] = lastComment + ' ###'

            # Push here comments only before certain lines
            if ///
                 ( # Class
                   class\s*[$A-Za-z_\x7f-\uffff][$\w\x7f-\uffff]*
                 | # Mixin or assignment
                   ^\s*[$A-Za-z_\x7f-\uffff][$\w\x7f-\uffff.]*\s+\=
                 | # Function
                   [$A-Za-z_\x7f-\uffff][$\w\x7f-\uffff]*\s*:\s*(\(.*\)\s*)?[-=]>
                 | # Function
                   @[A-Za-z_\x7f-\uffff][$\w\x7f-\uffff]*\s*=\s*(\(.*\)\s*)?[-=]>
                 | # Function
                   [$A-Za-z_\x7f-\uffff][\.$\w\x7f-\uffff]*\s*=\s*(\(.*\)\s*)?[-=]>
                 | # Constant
                   ^\s*@[$A-Z_][A-Z_]*)
                 | # Properties
                   ^\s*[$A-Za-z_\x7f-\uffff][$\w\x7f-\uffff]*:\s*\S+
               ///.exec line

              result.push c for c in comment
            comment = []
          # A member with no preceding description; apply the global status
          member = ///
                 ( # Class
                   class\s*[$A-Za-z_\x7f-\uffff][$\w\x7f-\uffff]*
                 | # Mixin or assignment
                   ^\s*[$A-Za-z_\x7f-\uffff][$\w\x7f-\uffff.]*\s+\=
                 | # Function
                   [$A-Za-z_\x7f-\uffff][$\w\x7f-\uffff]*\s*:\s*(\(.*\)\s*)?[-=]>
                 | # Function
                   @[A-Za-z_\x7f-\uffff][$\w\x7f-\uffff]*\s*=\s*(\(.*\)\s*)?[-=]>
                 | # Function
                   [$A-Za-z_\x7f-\uffff][\.$\w\x7f-\uffff]*\s*=\s*(\(.*\)\s*)?[-=]>
                 | # Constant
                   ^\s*@[$A-Z_][A-Z_]*)
                 | # Properties
                   ^\s*[$A-Za-z_\x7f-\uffff][$\w\x7f-\uffff]*:\s*\S+
               ///.exec line

          if member and _.str.isBlank(_.last(result))
            indentComment = /^(\s*)/.exec(line)
            if indentComment
              indentComment = indentComment[1]
            else
              indentComment = ""

            globalCount++

          result.push line

    [result.join('\n'), lineMapping]

  # Public: Attach each parent to its children, so we are able
  # to traverse the ancestor parse tree. Since the
  # parent attribute is already used in the class node,
  # the parent is stored as `ancestor`.
  #
  # nodes - A {Base} representing the CoffeeScript nodes
  #
  linkAncestors: (node) ->
    node.eachChild (child) =>
      child.ancestor = node
      @linkAncestors child

whitespace = (n) ->
  a = []
  while a.length < n
    a.push ' '
  a.join ''
