# Donna [![Build Status](https://travis-ci.org/atom/donna.svg?branch=master)](https://travis-ci.org/atom/donna)

Donna is a tool for generating [CoffeeScript](http://coffeescript.org/) metadata
for the purpose of generating API documentation. It reads your CoffeeScript
module, and outputs an object indicating the locations and other data about
your classes, properties, methods, etc.

It pulled out of [biscotto](https://github.com/atom/biscotto).

## Metadata??

The Donna [metadata][meta] format is a very raw format indicating the locations
of objects like classes, functions, and imports within files of a CoffeeScript
module. Included in the metadata are unmolested doc strings for these objects.

An Example:

```coffee
# Public: A mutable text container with undo/redo support and the ability to
# annotate logical regions in the text.
#
class TextBuffer
  @prop2: "bar"

  # Public: Takes an argument and does some stuff.
  #
  # a - A {String}
  #
  # Returns {Boolean}.
  @method2: (a) ->
```

Generates metadata:

```json
{
  "files": {
    "spec/metadata_templates/classes/class_with_prototype_properties.coffee": {
      "objects": {
        "3": {
          "0": {
            "type": "class",
            "name": "TextBuffer",
            "bindingType": null,
            "classProperties": [],
            "prototypeProperties": [
              [
                4,
                9
              ],
              [
                11,
                11
              ]
            ],
            "doc": " Public: A mutable text container with undo/redo support and the ability to\nannotate logical regions in the text.\n\n ",
            "range": [
              [
                3,
                0
              ],
              [
                11,
                17
              ]
            ]
          }
        },
        "4": {
          "9": {
            "name": "prop2",
            "type": "primitive",
            "range": [
              [
                4,
                9
              ],
              [
                4,
                13
              ]
            ],
            "bindingType": "prototypeProperty"
          }
        },
        "11": {
          "11": {
            "name": "method2",
            "bindingType": "prototypeProperty",
            "type": "function",
            "paramNames": [
              "a"
            ],
            "range": [
              [
                11,
                11
              ],
              [
                11,
                16
              ]
            ],
            "doc": " Public: Takes an argument and does some stuff.\n\na - A {String}\n\nReturns {Boolean}. "
          }
        }
      },
      "exports": {}
    }
  }
}

```

The Donna metadata format is doc-string-format agnostic. Use tomdoc? Javadoc?
Markdown? With this format, you should be able to generate your own API docs
with any doc format parser you like.

Donna currently has a counterpart named [tello](https://github.com/atom/tello)
that generates an easily digestible json format using the [atomdoc][atomdoc]
format on the docs strings from Donna output.

## Usage

``` bash
npm install donna
```

### From your code

```coffee
donna = require 'donna'
metadata = donna.generateMetadata(['/path/to/my-module', '/path/to/another-module'])
```

### From the command line

Pass it the _top level directory_ of your module. It will read the
`package.json` file and index any `.coffee` files from within the `src`, `app`,
or `lib` directories:

``` bash
donna -o donna.json /path/to/my-module
```

It handles multiple modules. Each should have a `package.json` file. It will
place the results from both modules in the `donna.json` file.

``` bash
donna -o donna.json /path/to/my-module /path/to/another-module
```

## License

(The MIT License)

Copyright (c) 2014 GitHub

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

[meta]:https://github.com/atom/donna/blob/master/spec/metadata_templates/test_package/test_metadata.json
[atomdoc]:https://github.com/atom/atomdoc
