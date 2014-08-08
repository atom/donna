fs = require 'fs'
util = require 'util'
path = require 'path'
walkdir = require 'walkdir'
Async = require 'async'
_ = require 'underscore'
CoffeeScript = require 'coffee-script'

Parser = require './parser'
Metadata = require './metadata'
{exec} = require 'child_process'

SRC_DIRS = ['src', 'lib', 'app']
BLACKLIST_FILES = ['Gruntfile.coffee']

module.exports = class MetaDoc
  @Parser: Parser
  @Metadata: Metadata

  @version: ->
    'v' + JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'package.json'), 'utf-8'))['version']

  @run: ->

    optimist = require('optimist')
      .usage("""
      Usage: $0 [options] [source_files]
      """)
      .options('o',
        alias: 'output-dir'
        describe: 'The output directory'
        default: './doc'
      )
      .options('d',
        alias: 'debug'
        describe: 'Show stacktraces and converted CoffeeScript source'
        boolean: true
        default: false
      )
      .options('h',
        alias: 'help'
        describe: 'Show the help'
      )

    argv = optimist.argv

    if argv.h
      console.log optimist.help()
      return

    options =
      inputs: argv._
      output: argv.o

    parser = new Parser(options)
    metadataSlugs = []

    for input in options.inputs
      continue unless (fs.existsSync || path.existsSync)(input)

      # collect probable package.json path
      package_json_path = path.join(input, 'package.json')
      stats = fs.lstatSync input
      absoluteInput = path.resolve(process.cwd(), input)

      if stats.isDirectory()
        for filename in walkdir.sync input
          if @isAcceptableFile(filename) and @isInAcceptableDir(absoluteInput, filename)
            console.log absoluteInput, filename

            try
              relativePath = filename
              relativePath = path.normalize(filename.replace(process.cwd(), ".#{path.sep}")) if filename.indexOf(process.cwd()) == 0
              parser.parseFile relativePath
            catch error
              throw error if options.debug
              console.log "Cannot parse file #{ filename }@#{error.location.first_line}: #{ error.message }"
      else
        if @isAcceptableFile(input)
          try
            parser.parseFile input
          catch error
            throw error if options.debug
            console.log "Cannot parse file #{ filename }@#{error.location.first_line}: #{ error.message }"

      metadataSlugs.push @generateMetadataSlug(package_json_path, parser, options)

    @writeMetadata(metadataSlugs, options)

  @isAcceptableFile = (filePath) ->
    for file in BLACKLIST_FILES
      return false if new RegExp(file+'$').test(filePath)

    filePath.match(/\._?coffee$/)

  @isInAcceptableDir = (inputPath, filePath) ->
    # is in the root of the input?
    return true if path.join(inputPath, path.basename(filePath)) is filePath

    # is under src, lib, or app?
    acceptableDirs = (path.join(inputPath, dir) for dir in SRC_DIRS)
    for dir in acceptableDirs
      return true if filePath.indexOf(dir) == 0

    false

  @writeMetadata: (metadataSlugs, options) ->
    fs.writeFileSync path.join(options.output, 'metadata.json'), JSON.stringify(metadataSlugs, null, "    ")

  # Public: Builds and writes to metadata.json
  @generateMetadataSlug: (packageJsonPath, parser, options) ->
    if fs.existsSync(packageJsonPath)
      packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf-8'))

    metadata = new Metadata(packageJson?.dependencies ? {}, parser)
    slug =
      main: @mainFileFinder(packageJsonPath, packageJson?.main)
      repository: packageJson?.repository?.url ? packageJson?.repository
      version: packageJson?.version
      files: {}

    for filename, content of parser.iteratedFiles
      relativeFilename = path.relative(packageJsonPath, filename)
      # TODO: @lineMapping is all messed up; try to avoid a *second* call to .nodes
      metadata.generate(CoffeeScript.nodes(content))
      @populateSlug(slug, relativeFilename, metadata)

    slug

  # Public: Parse and collect metadata slugs
  @populateSlug: (slug, filename, {defs:unindexedObjects, exports:exports}) ->
    objects = {}
    for key, value of unindexedObjects
      startLineNumber = value.range[0][0]
      startColNumber = value.range[0][1]
      objects[startLineNumber] = {} unless objects[startLineNumber]?
      objects[startLineNumber][startColNumber] = value
      # Update the classProperties/prototypeProperties to be line numbers
      if value.type is 'class'
        value.classProperties = ( [prop.range[0][0], prop.range[0][1]] for prop in _.clone(value.classProperties))
        value.prototypeProperties = ([prop.range[0][0], prop.range[0][1]] for prop in _.clone(value.prototypeProperties))

    if exports._default
      exports = exports._default.range[0][0]
    else
      for key, value of exports
        exports[key] = value.startLineNumber

    # TODO: ugh, I don't understand relative resolving ;_;
    filename = filename.substring(1, filename.length) if filename.match /^\.\./
    slug["files"][filename] = {objects, exports}
    slug

  @mainFileFinder: (package_json_path, main_file) ->
    return unless main_file?

    if main_file.match(/\.js$/)
      main_file = main_file.replace(/\.js$/, ".coffee")
    else
      main_file += ".coffee"

    filename = path.basename(main_file)
    filepath = path.dirname(package_json_path)

    for dir in SRC_DIRS
      composite_main = path.normalize path.join(filepath, dir, filename)

      if fs.existsSync composite_main
        file = path.relative(package_json_path, composite_main)
        file = file.substring(1, file.length) if file.match /^\.\./
        return file
