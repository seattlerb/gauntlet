require 'rubygems/remote_fetcher'
require 'thread'
require 'yaml'

$u ||= false
$f ||= false
$F ||= false

Thread.abort_on_exception = true

class Gauntlet
  VERSION = '1.0.0'

  GEMURL = URI.parse 'http://gems.rubyforge.org'
  GEMDIR = File.expand_path "~/.gauntlet"
  DATADIR = File.expand_path "~/.gauntlet/data"

  # stupid dups usually because of "dash" renames
  STUPID_GEMS = %w(ajax-scaffold-generator
                   extract_curves
                   flickr-fu
                   hpricot-scrub
                   html_me
                   merb-builder
                   merb-jquery
                   merb-parts
                   merb_exceptions
                   merb_helpers
                   merb_param_protection
                   model_graph
                   not_naughty
                   rfeedparser-ictv
                   spec-converter
                   spec_unit)

  attr_accessor :dirty, :data_file, :data

  def initialize
    name = self.class.name.downcase.sub(/gauntlet/, '')
    self.data_file = "#{DATADIR}/#{name}-data.yml"
    self.dirty = false
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
    @cache ||= source_index.latest_specs
  end

  def gems_by_name
    @by_name ||= Hash[*latest_gems.map { |gem|
                        [gem.name, gem, gem.full_name, gem]
                      }.flatten]
  end

  def dependencies_of name
    index = source_index
    gems_by_name[name].dependencies.map { |dep| index.search(dep).last }
  end

  def dependent_upon name
    latest_gems.find_all { |gem|
      gem.dependencies.any? { |dep| dep.name == name }
    }
  end

  def find_stupid_gems
    gems   = Hash.new { |h,k| h[k] = [] }
    stupid = []
    latest = {}

    latest_gems.each do |spec|
      name = spec.name.gsub(/-/, '_')
      next unless name =~ /_/
      gems[name] << spec
    end

    gems.reject! { |k,v| v.size == 1 || v.map { |s| s.name }.uniq.size == 1 }

    gems.each do |k,v|
      sorted = v.sort_by { |spec| spec.version }
      latest[sorted.last.name] = true
      sorted.each do |spec|
        stupid << spec.name unless latest[spec.name]
      end
    end

    stupid.uniq
  end

  def update_gem_tarballs
    initialize_dir

    latest = self.latest_gems

    warn "updating mirror"

    in_gem_dir do
      gems = Dir["*.gem"]
      tgzs = Dir["*.tgz"]

      old = tgzs - latest.map { |spec| "#{spec.full_name}.tgz" }
      unless old.empty? then
        warn "deleting #{old.size} tgzs"
        old.each do |tgz|
          File.unlink tgz
        end
      end

      tasks = Queue.new
      latest.sort!
      latest.reject! { |spec| tgzs.include? "#{spec.full_name}.tgz" }
      tasks.push(latest.shift) until latest.empty? # LAME

      warn "fetching #{tasks.size} gems"

      threads = []
      10.times do
        threads << Thread.new do
          fetcher = Gem::RemoteFetcher.new nil # fuck proxies
          until tasks.empty? do
            spec      = tasks.shift
            full_name = spec.full_name
            tgz_name  = "#{full_name}.tgz"
            gem_name  = "#{full_name}.gem"

            unless gems.include? gem_name then
              begin
                warn "downloading  #{full_name}"
                fetcher.download(spec, GEMURL, Dir.pwd)
              rescue Gem::RemoteFetcher::FetchError => e
                warn "  failed #{full_name}: #{e.message}"
                next
              end
            end

            warn "  converting #{gem_name} to tarball"

            unless File.directory? full_name then
              system "gem unpack cache/#{gem_name} &> /dev/null"
              system "gem spec -l cache/#{gem_name} > #{full_name}/gemspec"
            end

            system "chmod -R u+rwX #{full_name} && tar zmcf #{tgz_name} #{full_name} && rm -rf   #{full_name} #{gem_name}"
          end
        end
      end

      threads.each do |thread|
        thread.join
      end
    end
  rescue Interrupt
    warn "user cancelled... quitting"
    exit 1
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
        system "rm -rf #{process_dir}"
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
    save_yaml data_file, data if dirty
  end
end

############################################################
# Extensions and Overrides

# bug in RemoteFetcher#download prevents multithreading. Remove after 1.3.2
class Gem::RemoteFetcher
  alias :old_download :download
  def download(spec, source_uri, install_dir = Gem.dir)
    if File.writable?(install_dir)
      cache_dir = File.join install_dir, 'cache'
    else
      cache_dir = File.join(Gem.user_dir, 'cache')
    end

    gem_file_name = "#{spec.full_name}.gem"
    local_gem_path = File.join cache_dir, gem_file_name

    FileUtils.mkdir_p cache_dir rescue nil unless File.exist? cache_dir

    source_uri = URI.parse source_uri unless URI::Generic === source_uri
    scheme = source_uri.scheme

    # URI.parse gets confused by MS Windows paths with forward slashes.
    scheme = nil if scheme =~ /^[a-z]$/i

    case scheme
    when 'http', 'https' then
      unless File.exist? local_gem_path then
        begin
          say "Downloading gem #{gem_file_name}" if
            Gem.configuration.really_verbose

          remote_gem_path = source_uri + "gems/#{gem_file_name}"

          gem = self.fetch_path remote_gem_path
        rescue Gem::RemoteFetcher::FetchError
          raise if spec.original_platform == spec.platform

          alternate_name = "#{spec.original_name}.gem"

          say "Failed, downloading gem #{alternate_name}" if
            Gem.configuration.really_verbose

          remote_gem_path = source_uri + "gems/#{alternate_name}"

          gem = self.fetch_path remote_gem_path
        end

        File.open local_gem_path, 'wb' do |fp|
          fp.write gem
        end
      end
    when nil, 'file' then # TODO test for local overriding cache
      begin
        FileUtils.cp source_uri.to_s, local_gem_path
      rescue Errno::EACCES
        local_gem_path = source_uri.to_s
      end

      say "Using local gem #{local_gem_path}" if
        Gem.configuration.really_verbose
    else
      raise Gem::InstallError, "unsupported URI scheme #{source_uri.scheme}"
    end

    local_gem_path
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
