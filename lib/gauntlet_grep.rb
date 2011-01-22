#!/usr/bin/ruby -ws

$v ||= false # HACK

require 'rubygems'
require 'gauntlet'

class GrepGauntlet < Gauntlet
  attr_accessor :args

  def initialize args
    self.args = args
  end

  def run name
    system "grep", *args
  end
end

flogger = GrepGauntlet.new ARGV
flogger.run_the_gauntlet

