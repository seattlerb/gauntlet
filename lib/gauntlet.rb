require 'rubygems'
require 'thread'
require 'yaml'
require 'net/http/persistent'

$u ||= false
$f ||= false
$F ||= false

Thread.abort_on_exception = true

class Gauntlet
  VERSION = '2.0.2'
  GEMURL  = URI.parse 'http://gems.rubyforge.org'
  GEMDIR  = File.expand_path "~/.gauntlet"
  DATADIR = File.expand_path "~/.gauntlet/data"

  attr_accessor :dirty, :data_file, :data

  def initialize
    name = self.class.name.downcase.sub(/gauntlet/, '')
    self.data_file = "#{DATADIR}/#{name}-data.yml"
    self.dirty = false
    @cache = nil
  end

  def initialize_dir
    Dir.mkdir GEMDIR unless File.directory? GEMDIR
    Dir.mkdir DATADIR unless File.directory? DATADIR
    in_gem_dir do
      File.symlink ".", "cache" unless File.exist? "cache"
    end
  end

  def source_index
    @index ||= in_gem_dir do
      dump = if ($u and not $F) or not File.exist? '.source_index' then
               warn "fetching and caching gem index"
               url = GEMURL + "Marshal.#{Gem.marshal_version}.Z"
               dump = Gem::RemoteFetcher.fetcher.fetch_path url
               require 'zlib' # HACK for rubygems :(
               dump = Gem.inflate dump
               open '.source_index', 'wb' do |io| io.write dump end
               dump
             else
               warn "using cached gem index"
               open '.source_index', 'rb' do |io| io.read end
             end

      Marshal.load dump
    end
  end

  def latest_gems
    Gem::SpecFetcher.new.list.map { |source_uri, gems|
      base_url = source_uri.to_s
      gems.map { |(name, version, platform)|
        gem_name = case platform
                   when Gem::Platform::RUBY then
                     [name, version].join '-'
                   else
                     [name, version, platform].join '-'
                   end

        [gem_name, File.join(base_url, "/gems/#{gem_name}.gem")]
      }
    }.flatten(1)
  end

  def update_gem_tarballs
    initialize_dir

    latest = self.latest_gems

    warn "updating mirror"

    in_gem_dir do
      gems = Dir["*.gem"]
      tgzs = Dir["*.tgz"]

      old = tgzs - latest.map { |(full_name, url)| "#{full_name}.tgz" }
      unless old.empty? then
        warn "deleting #{old.size} tgzs"
        old.each do |tgz|
          File.unlink tgz
        end
      end

      conversions = Queue.new
      gem_names = gems.map { |gem| File.basename gem, '.gem' }
      tgz_names = tgzs.map { |tgz| File.basename tgz, '.tgz' }
      to_convert = gem_names - tgz_names

      seen_tgzs = Hash[*tgzs.map { |name| [name, true] }.flatten]

      warn "adding #{to_convert.size} unconverted gems" unless to_convert.empty?

      conversions.push to_convert.shift until to_convert.empty? # LAME

      downloads = Queue.new
      latest = latest.sort_by { |(full_name, url)| full_name.downcase }
      latest.reject! { |(full_name, url)| seen_tgzs["#{full_name}.tgz"] }

      downloads.push(latest.shift) until latest.empty? # LAME

      converter = Thread.start do
        while payload = conversions.shift do
          full_name, _ = payload
          tgz_name  = "#{full_name}.tgz"
          gem_name  = "#{full_name}.gem"

          warn " converting #{gem_name} to tarball"

          unless File.directory? full_name then
            system "gem unpack cache/#{gem_name} > /dev/null 2>&1"
            system "gem spec -l cache/#{gem_name} > #{full_name}/gemspec"
          end

          system ["chmod -R u+rwX #{full_name}",
                  "tar zmcf #{tgz_name} -- #{full_name}",
                  "rm -rf -- #{full_name} #{gem_name}"].join(" && ")
        end
      end

      warn "fetching #{downloads.size} gems"

      http = Net::HTTP::Persistent.new

      workers downloads do |full_name, url|
        gem_name  = "#{full_name}.gem"

        unless gems.include? gem_name then
          limit = 3
          begin
            warn "downloading #{full_name}"
            while limit > 0 do
              http.request URI.parse(url) do |response|
                case response
                when Net::HTTPSuccess
                  File.open gem_name, "wb" do |f|
                    response.read_body do |chunk|
                      f.write chunk
                    end
                  end
                  limit = 0 # kinda lame.
                when Net::HTTPRedirection
                  url = response['location']
                  limit -= 1
                else
                  warn "  #{full_name} got #{response.code}. skipping."
                  limit = 0
                end
              end
            end
          rescue SocketError, Net::HTTP::Persistent::Error => e
            warn "  #{full_name} raised #{e.message}. skipping."
          end
        end

        conversions.push full_name
      end

      conversions.push nil

      converter.join
    end

  rescue Interrupt
    warn "user cancelled... quitting"
    exit 1
  end

  def workers tasks, count = 10
    threads = []
    count.times do
      threads << Thread.new do
        until tasks.empty? do
          task = tasks.shift
          yield task
        end
      end
    end

    threads.each do |thread|
      thread.join
    end
  end

  def each_gem filter = nil
    filter ||= /^[\w-]+-\d+(\.\d+)*\.tgz$/
    in_gem_dir do
      Dir["*.tgz"].each do |tgz|
        next unless tgz =~ filter

        yield File.basename(tgz, ".tgz")
      end
    end
  end

  def with_gem name
    in_gem_dir do
      process_dir = "#{$$}"
      begin
        Dir.mkdir process_dir
        Dir.chdir process_dir do
          system "tar zxmf ../#{name}.tgz 2> /dev/null"
          Dir.chdir name do
            yield name
          end
        end
      ensure
        system "rm -rf -- #{process_dir}"
      end
    end
  end

  def load_yaml path, default = {}
    YAML.load(File.read(path)) rescue default
  end

  def save_yaml path, data
    File.open("#{path}.new", 'w') do |f|
      warn "*** saving #{path}"
      YAML.dump data, f
    end
    File.rename "#{path}.new", path
  end

  def in_gem_dir
    Dir.chdir GEMDIR do
      yield
    end
  end

  ##
  # Override this to customize gauntlet. See run_the_gauntlet for
  # other ways of adding behavior.

  def run name
    raise "subclass responsibility"
  end

  ##
  # Override this to return true if the gem should be skipped.

  def should_skip? name
    self.data[name]
  end

  ##
  # This is the main driver for gauntlet. filter allows you to pass in
  # a regexp to only run against a subset of the gems available. You
  # can pass a block to run_the_gauntlet or it will call run. Both are
  # passed the name of the gem and are executed within the gem
  # directory.

  def run_the_gauntlet filter = nil
    initialize_dir
    update_gem_tarballs if $u

    self.data ||= load_yaml data_file

    outdateds = self.data.keys - in_gem_dir do
      Dir["*.tgz"].map { |tgz| File.basename(tgz, ".tgz") }
    end

    outdateds.each do |outdated|
      self.data.delete outdated
    end

    %w[TERM KILL].each do |signal|
      trap signal do
        shutdown
        exit
      end
    end

    each_gem filter do |name|
      next if should_skip? name
      with_gem name do
        if block_given? then
          yield name
        else
          run name
        end
      end
    end
  rescue Interrupt
    warn "user cancelled. quitting"
  ensure
    shutdown
  end

  def shutdown
    save_yaml data_file, data if dirty
  end
end

############################################################
# Extensions and Overrides

class Gem::SpecFetcher
  attr_writer :fetcher

  alias :old_initialize :initialize

  def initialize fetcher = Gem::RemoteFetcher.fetcher
    old_initialize

    self.fetcher = fetcher
  end
end

class Array
  def sum
    sum = 0
    self.each { |i| sum += i }
    sum
  end

  def average
    return self.sum / self.length.to_f
  end

  def sample_variance
    avg = self.average
    sum = 0
    self.each { |i| sum += (i - avg) ** 2 }
    return (1 / self.length.to_f * sum)
  end

  def stddev
    return Math.sqrt(self.sample_variance)
  end
end

