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

main = ->
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

  writeMetadata(generateMetadata(options.inputs), options.output)

generateMetadata = (inputs) ->
  metadataSlugs = []

  for input in inputs
    continue unless (fs.existsSync || path.existsSync)(input)
    parser = new Parser()

    # collect probable package.json path
    packageJsonPath = path.join(input, 'package.json')
    stats = fs.lstatSync input
    absoluteInput = path.resolve(process.cwd(), input)

    if stats.isDirectory()
      for filename in walkdir.sync input
        if isAcceptableFile(filename) and isInAcceptableDir(absoluteInput, filename)
          try
            parser.parseFile(filename, absoluteInput)
          catch error
            logError(filename, error)
    else
      if isAcceptableFile(input)
        try
          parser.parseFile(input, path.dirname(input))
        catch error
          logError(filename, error)

    metadataSlugs.push generateMetadataSlug(packageJsonPath, parser)

  metadataSlugs

logError = (filename, error) ->
  if error.location?
    console.warn "Cannot parse file #{ filename }@#{error.location.first_line}: #{ error.message }"
  else
    console.warn "Cannot parse file #{ filename }: #{ error.message }"

isAcceptableFile = (filePath) ->
  try
    return false if fs.statSync(filePath).isDirectory()

  for file in BLACKLIST_FILES
    return false if new RegExp(file+'$').test(filePath)

  filePath.match(/\._?coffee$/)

isInAcceptableDir = (inputPath, filePath) ->
  # is in the root of the input?
  return true if path.join(inputPath, path.basename(filePath)) is filePath

  # is under src, lib, or app?
  acceptableDirs = (path.join(inputPath, dir) for dir in SRC_DIRS)
  for dir in acceptableDirs
    return true if filePath.indexOf(dir) == 0

  false

writeMetadata = (metadataSlugs, output) ->
  fs.writeFileSync path.join(output, 'metadata.json'), JSON.stringify(metadataSlugs, null, "    ")

# Public: Builds and writes to metadata.json
generateMetadataSlug = (packageJsonPath, parser) ->
  if fs.existsSync(packageJsonPath)
    packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf-8'))

  metadata = new Metadata(packageJson?.dependencies ? {}, parser)
  slug =
    main: findMainFile(packageJsonPath, packageJson?.main)
    repository: packageJson?.repository?.url ? packageJson?.repository
    version: packageJson?.version
    files: {}

  for filename, content of parser.iteratedFiles
    metadata.generate(CoffeeScript.nodes(content))
    populateSlug(slug, filename, metadata)

  slug

# Public: Parse and collect metadata slugs
populateSlug = (slug, filename, {defs:unindexedObjects, exports:exports}) ->
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

  if exports._default?
    exports = exports._default.range[0][0] if exports._default.range?
  else
    for key, value of exports
      exports[key] = value.startLineNumber

  slug["files"][filename] = {objects, exports}
  slug

findMainFile = (packageJsonPath, main_file) ->
  return unless main_file?

  if main_file.match(/\.js$/)
    main_file = main_file.replace(/\.js$/, ".coffee")
  else
    main_file += ".coffee"

  filename = path.basename(main_file)
  filepath = path.dirname(packageJsonPath)

  for dir in SRC_DIRS
    composite_main = path.normalize path.join(filepath, dir, filename)

    if fs.existsSync composite_main
      file = path.relative(packageJsonPath, composite_main)
      file = file.substring(1, file.length) if file.match /^\.\./
      return file

# TODO: lessen the suck enough to remove generateMetadataSlug and populateSlug. They really shouldnt be necessary.
module.exports = {Parser, Metadata, main, generateMetadata, generateMetadataSlug, populateSlug}
