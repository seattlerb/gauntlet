# -*- ruby -*-

require 'rubygems'
require 'hoe'

Hoe.plugin :seattlerb
Hoe.plugin :isolate

Hoe.spec 'gauntlet' do
  developer 'Ryan Davis', 'ryand-ruby@zenspider.com'

  dependency "net-http-persistent", "~> 1.4.1"

  license "MIT"
end

desc "update your gauntlet gems"
task :update => :isolate do
  ruby "-I lib ./bin/gauntlet update"
end

# vim: syntax=ruby
