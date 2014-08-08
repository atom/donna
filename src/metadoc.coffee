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

module.exports = class MetaDoc
  @Parser: Parser
  @Metadata: Metadata

  @version: ->
    'v' + JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'package.json'), 'utf-8'))['version']

  @run: (done, file_generator_cb, analytics = false, homepage = false) ->

    metadocopts =
      _ : []

    try
      if fs.existsSync('.metadocopts')
        configs = fs.readFileSync '.metadocopts', 'utf8'

        for config in configs.split('\n')
          # Key value configs
          if option = /^-{1,2}([\w-]+)\s+(['"])?(.*?)\2?$/.exec config
            metadocopts[option[1]] = option[3]
          # Boolean configs
          else if bool = /^-{1,2}([\w-]+)\s*$/.exec config
            metadocopts[bool[1]] = true
          # Argv configs
          else if config isnt ''
            metadocopts._.push config


      Async.parallel {
        inputs:  @detectSources
        readme:  @detectReadme
        extras:  @detectExtras
        name:    @detectName
        tag:     @detectTag
        origin:  @detectOrigin
      },
      (err, defaults) =>

        extraUsage = if defaults.extras.length is 0 then '' else  "- #{ defaults.extras.join ' ' }"

        optimist = require('optimist')
          .usage("""
          Usage:   $0 [options] [source_files [- extra_files]]
          Default: $0 [options] #{ defaults.inputs.join ' ' } #{ extraUsage }
          """)
          .options('o',
            alias     : 'output-dir'
            describe  : 'The output directory'
            default   : metadocopts['output-dir'] || metadocopts.o || './doc'
          )
          .options('d',
            alias     : 'debug'
            describe  : 'Show stacktraces and converted CoffeeScript source'
            boolean   : true
            default   : metadocopts.debug || metadocopts.d  || false
          )
          .options('h',
            alias     : 'help'
            describe  : 'Show the help'
          )

        argv = optimist.argv

        if argv.h
          console.log optimist.help()

        else
          options =
            inputs: []
            output: argv.o
            json: argv.j || ""
            extras: []
            name: argv.n
            readme: argv.r
            title: argv.title
            quiet: argv.q
            private: argv.private
            internal: argv.internal
            noOutput: argv.noOutput
            missing: argv.missing
            verbose: argv.v
            debug: argv.d
            cautious: argv.cautious
            homepage: homepage
            analytics: analytics || argv.a
            tag: defaults.tag
            origin: defaults.origin
            metadata: argv.metadata
            stability: argv.stability

          extra = false

          # ignore params if metadoc has not been started directly
          args = if argv._.length isnt 0 and /.+metadoc$/.test(process.argv[1]) then argv._ else metadocopts._

          for arg in args
            if arg is '-'
              extra = true
            else
              if extra then options.extras.push(arg) else options.inputs.push(arg)

          options.inputs = defaults.inputs if options.inputs.length is 0
          options.extras = defaults.extras if options.extras.length is 0

          parser = new Parser(options)
          metadataSlugs = []

          for input in options.inputs
            continue unless (fs.existsSync || path.existsSync)(input)

            # collect probable package.json path
            package_json_path = path.join(input, 'package.json')
            stats = fs.lstatSync input

            if stats.isDirectory()
              for filename in walkdir.sync input
                if filename.match /\._?coffee$/
                  console.log filename
                  # try
                  relativePath = filename
                  relativePath = path.normalize(filename.replace(process.cwd(), ".#{path.sep}")) if filename.indexOf(process.cwd()) == 0
                  shortPath = relativePath.replace(path.resolve(process.cwd(), input) + path.sep, '')
                  # don't parse Gruntfile.coffee, specs, or anything not in a src dir
                  parser.parseFile relativePath if _.some(SRC_DIRS, (dir) -> ///^#{dir}///.test(shortPath))
                  # catch error
                  #   throw error if options.debug
                  #   console.log "Cannot parse file #{ filename }@#{error.location.first_line}: #{ error.message }"
            else
              if input.match /\._?coffee$/
                try
                  parser.parseFile input
                catch error
                  throw error if options.debug
                  console.log "Cannot parse file #{ filename }@#{error.location.first_line}: #{ error.message }"

            metadataSlugs.push @generateMetadataSlug(package_json_path, parser, options)

          @writeMetadata(metadataSlugs, options)
          done() if done

    catch error
      done(error) if done
      console.log "Cannot generate documentation: #{ error.message }"
      throw error

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

  # Public: Get the MetaDoc script content that is used in the webinterface
  #
  # Returns the script contents as a {String}.
  @script: ->
    @metadocScript or= fs.readFileSync path.join(__dirname, '..', 'theme', 'default', 'assets', 'metadoc.js'), 'utf-8'

  # Public: Get the MetaDoc style content that is used in the webinterface
  #
  # Returns the style content as a {String}.
  @style: ->
    @metadocStyle or= fs.readFileSync path.join(__dirname, '..', 'theme', 'default', 'assets', 'metadoc.css'), 'utf-8'

  # Public: Find the source directories.
  @detectSources: (done) ->
    Async.filter SRC_DIRS, fs.exists, (results) ->
      results.push '.' if results.length is 0
      done null, results

  # Public: Find the project's README.
  @detectReadme: (done) ->
    Async.filter [
      'README.markdown'
      'README.md'
      'README'
      'readme.markdown'
      'readme.md'
      'readme'
    ], fs.exists, (results) -> done null, _.first(results) || ''

  # Public: Find extra project files in the repository.
  @detectExtras: (done) ->
    Async.filter [
      'CHANGELOG.markdown'
      'CHANGELOG.md'
      'AUTHORS'
      'AUTHORS.md'
      'AUTHORS.markdown'
      'LICENSE'
      'LICENSE.md'
      'LICENSE.markdown'
      'LICENSE.MIT'
      'LICENSE.GPL'
    ], fs.exists, (results) -> done null, results

  # Public: Find the project name by either parsing `package.json`,
  # or getting the current working directory name.
  #
  # done - The {Function} callback to call once this is done
  @detectName: (done) ->
    if fs.existsSync('package.json')
      name = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'package.json'), 'utf-8'))['name']
    else
      name = path.basename(process.cwd())

    done null, name.charAt(0).toUpperCase() + name.slice(1)

  # Public: Find the project's latest Git tag.
  #
  # done - The {Function} callback to call once this is done
  @detectTag: (done) ->
    exec 'git describe --abbrev=0 --tags', (error, stdout, stderr) ->
      currentTag = stdout || "master"

      done null, currentTag

  # Public: Find the project's Git remote.origin URL.
  #
  # done - The {Function} callback to call once this is done
  @detectOrigin: (done) ->
    exec 'git config --get remote.origin.url', (error, stdout, stderr) ->
      url = stdout
      if url
        if url.match /https:\/\/github.com\// # e.g., https://github.com/foo/bar.git
          url = url.replace(/\.git/, '')
        else if url.match /git@github.com/    # e.g., git@github.com:foo/bar.git
          url = url.replace(/^git@github.com:/, 'https://github.com/').replace(/\.git/, '')

      done null, url
