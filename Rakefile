# -*- ruby -*-

require 'rubygems'
require 'hoe'

Hoe.plugin :seattlerb
Hoe.plugin :isolate

Hoe.spec 'gauntlet' do
  developer 'Ryan Davis', 'ryand-ruby@zenspider.com'

  self.rubyforge_name = 'seattlerb'

  extra_deps << ["net-http-persistent", "~> 1.4.1"]
end

desc "update your gauntlet gems"
task :update do
  sh "ruby -I lib ./bin/gauntlet update"
end

# vim: syntax=ruby
