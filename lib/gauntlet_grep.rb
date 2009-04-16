#!/usr/bin/ruby -ws

$v ||= false # HACK

require 'rubygems'
require 'gauntlet'

class GrepGauntlet < Gauntlet
  attr_accessor :pattern

  def initialize pattern
    self.pattern = pattern
  end

  def run name
    system "find . -type f -print0 | xargs -0 grep #{pattern}"
  end
end

pattern = ARGV.shift
flogger = GrepGauntlet.new pattern
flogger.run_the_gauntlet

