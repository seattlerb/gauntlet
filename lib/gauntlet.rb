require 'rubygems/remote_fetcher'
require 'thread'

$u ||= false
$f ||= false
$F ||= false

Thread.abort_on_exception = true

class Gauntlet
  VERSION = '1.0.0'

  GEMURL = URI.parse 'http://gems.rubyforge.org'
  GEMDIR = File.expand_path "~/.gauntlet"

  # stupid dups usually because of "dash" renames
  # TODO: probably stale by now - try to generate dynamically
  STUPID_GEMS = %w(ruby-aes-table1-1.0.gem
                   ruby-aes-unroll1-1.0.gem
                   hpricot-scrub-0.2.0.gem
                   extract_curves-0.0.1.gem
                   extract_curves-0.0.1-i586-linux.gem
                   extract_curves-0.0.1-mswin32.gem
                   rfeedparser-ictv-0.9.931.gem
                   spec_unit-0.0.1.gem)

  def initialize_dir
    Dir.mkdir GEMDIR unless File.directory? GEMDIR
    in_gem_dir do
      File.symlink ".", "cache" unless File.exist? "cache"
    end
  end

  def get_source_index
    @index ||= in_gem_dir do
      dump = if ($u and not $F) or not File.exist? '.source_index' then
               url = GEMURL + "Marshal.#{Gem.marshal_version}.Z"
               dump = Gem::RemoteFetcher.fetcher.fetch_path url
               require 'zlib'
               dump = Gem.inflate dump
               open '.source_index', 'wb' do |io| io.write dump end
               dump
             else
               open '.source_index', 'rb' do |io| io.read end
             end

      Marshal.load dump
    end
  end

  def get_latest_gems
    @cache ||= get_source_index.latest_specs
  end

  def get_gems_by_name
    @by_name ||= Hash[*get_latest_gems.map { |gem|
                        [gem.name, gem, gem.full_name, gem]
                      }.flatten]
  end

  def dependencies_of name
    index = get_source_index
    get_gems_by_name[name].dependencies.map { |dep| index.search(dep).last }
  end

  def dependent_upon name
    get_latest_gems.find_all { |gem|
      gem.dependencies.any? { |dep| dep.name == name }
    }
  end

  def update_gem_tarballs
    initialize_dir

    latest = get_latest_gems

    puts "updating mirror"

    in_gem_dir do
      gems = Dir["*.gem"]
      tgzs = Dir["*.tgz"]

      old = tgzs - latest.map { |spec| "#{spec.full_name}.tgz" }
      unless old.empty? then
        puts "deleting #{old.size} tgzs"
        old.each do |tgz|
          File.unlink tgz
        end
      end

      tasks = Queue.new
      latest.sort!
      latest.reject! { |spec| tgzs.include? "#{spec.full_name}.tgz" }
      tasks.push(latest.shift) until latest.empty? # LAME

      puts "fetching #{tasks.size} gems"

      threads = []
      1.times do
        threads << Thread.new do
          until tasks.empty? do
            spec = tasks.shift
            full_name = spec.full_name
            tgz_name = "#{full_name}.tgz"
            gem_name = "#{full_name}.gem"

            unless gems.include? gem_name then
              begin
                warn "downloading #{full_name}"
                Gem::RemoteFetcher.fetcher.download(spec, GEMURL, Dir.pwd)
              rescue Gem::RemoteFetcher::FetchError
                warn "  failed"
                next
              end
            end

            warn "  converting #{gem_name} to tarball"

            unless File.directory? full_name then
              system "gem unpack cache/#{gem_name} &> /dev/null"
              system "gem spec -l cache/#{gem_name} > #{full_name}/gemspec.rb"
            end

            system "chmod -R u+w #{full_name}"
            system "tar zmcf #{tgz_name} #{full_name}"
            system "rm -rf   #{full_name} #{gem_name}"
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
      begin
        system "tar zxmf #{name}.tgz 2> /dev/null"
        Dir.chdir name do
          yield name
        end
      ensure
        system "rm -r #{name}"
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

  def run name
    raise "subclass responsibility"
  end

  def run_the_gauntlet filter = nil
    initialize_dir
    update_gem_tarballs if $u

    each_gem filter do |name|
      with_gem name do
        if block_given? then
          yield name
        else
          run name
        end
      end
    end
  end
end
