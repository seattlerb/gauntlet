= gauntlet

home :: https://github.com/seattlerb/gauntlet

== DESCRIPTION:

Gauntlet is a pluggable means of running code against all the latest
gems and storing off the data.

== FEATURES/PROBLEMS:

* Downloads all the latest gems and converts them to tarballs for easy access.
* Iterates through all downloaded gems, unpacks them, and then runs your code.
* Automates storage of results to YAML files.
* Easily skips over projects that already have results (overridable).
* gauntlet commandline locates your gauntlet library via rubygems:
  * eg. `gauntlet flog` finds gauntlet_flog.rb in the flog gem.

== SYNOPSIS:

  require 'gauntlet'

  class MyGauntlet < Gauntlet
    def run name
      data[name] = Dir["**/*.rb"]
      self.dirty = true
    end
  end

  filter = ARGV.shift
  filter = Regexp.new filter if filter

  gauntlet = MyGauntlet.new
  gauntlet.source_index
  gauntlet.update_gem_tarballs
  gauntlet.run_the_gauntlet filter

== REQUIREMENTS:

* rubygems

== INSTALL:

* sudo gem install gauntlet

== LICENSE:

(The MIT License)

Copyright (c) Ryan Davis, Seattle.rb

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
