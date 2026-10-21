# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'net/http'
require 'time'

module Pd4ml
  # Downloads a PD4ML build from the PD4ML Maven repository and makes it the gem's default:
  #
  #   pd4ml install                    the most recent 4.* release
  #   pd4ml install --snapshots        the most recent 4.* build, snapshots included
  #   pd4ml install 4.0.23fx2          an exact version
  #
  # or Pd4ml.install from code. The jar is stored in the user's cache directory (PD4ML_HOME to
  # choose another) with the Bouncy Castle jars PD4ML needs for encryption and signing, every
  # file verified against its published SHA-1 checksum. With no build installed or configured,
  # the first use of PD4ML downloads one (PD4ML_AUTO_INSTALL=0 turns that off).
  module Installer
    REPOSITORY = 'https://pd4ml.com/maven2'
    CENTRAL = 'https://repo1.maven.org/maven2'
    GROUP_PATH = 'com/pd4ml/pd4ml'
    # The Bouncy Castle version PD4ML is built against (https://pd4ml.com/docs/#2.-obtaining-pd4ml).
    BOUNCYCASTLE_VERSION = '1.84'
    BOUNCYCASTLE = %w[bcprov-jdk18on bcpkix-jdk18on bcutil-jdk18on].freeze
    MANIFEST = 'installed.json'
    VERSION_PATTERN = /\A(\d+)\.(\d+)\.(\d+)(?:fx(\d+)(?:a(\d+))?)?(-jakarta)?(-SNAPSHOT)?\z/

    module_function

    # ----------------------------------------------------------------------------- versions

    # An ordering key for a PD4ML version (4.1.1, 4.0.23fx2, 4.0.23fx1a1, 4.1.2-SNAPSHOT), or nil
    # for an unknown form. A snapshot sorts below its release, an fxNaM pre-release below fxN.
    def version_key(version)
      m = VERSION_PATTERN.match(version)
      return nil unless m

      [m[1].to_i, m[2].to_i, m[3].to_i, m[4].to_i, m[5] ? 0 : 1, m[5].to_i, m[7] ? 0 : 1]
    end

    # Versions sorted oldest first (unknown forms dropped).
    def sort_versions(versions) = versions.select { |v| version_key(v) }.sort_by { |v| version_key(v) }

    # The most recent `major`.* version: releases only unless `snapshots`, -jakarta only with `jakarta`.
    def select_version(versions, major: 4, snapshots: false, jakarta: false)
      candidates = versions.select do |v|
        k = version_key(v)
        k && k[0] == major && (snapshots || !v.end_with?('-SNAPSHOT')) && v.include?('-jakarta') == jakarta
      end
      raise InstallError, "no #{major}.* version in the repository" if candidates.empty?

      sort_versions(candidates).last
    end

    # The versions the repository lists.
    def available_versions(repository = REPOSITORY)
      fetch("#{repository}/#{GROUP_PATH}/maven-metadata.xml").scan(%r{<version>([^<]+)</version>}).flatten.map(&:strip)
    end

    # ------------------------------------------------------------------------------ install

    # Downloads a PD4ML build (unless already there) and makes it the default one; returns the
    # jar's path. version: 'latest' (the most recent 4.* release; with snapshots: true, the most
    # recent 4.* build) or an exact one such as '4.0.23fx2'.
    def install(version = 'latest', snapshots: false, jakarta: false, repository: REPOSITORY, home: nil,
                force: false, quiet: false, bouncycastle: true)
      home ||= default_home
      version = select_version(available_versions(repository), snapshots: snapshots, jakarta: jakarta) if version == 'latest'
      name = jar_name(version, repository)
      jar = File.join(home, name)
      download("#{repository}/#{GROUP_PATH}/#{version}/#{name}", jar, force, quiet)
      libs = []
      if bouncycastle
        BOUNCYCASTLE.each do |artifact|
          lib = "#{artifact}-#{BOUNCYCASTLE_VERSION}.jar"
          download("#{CENTRAL}/org/bouncycastle/#{artifact}/#{BOUNCYCASTLE_VERSION}/#{lib}", File.join(home, 'lib', lib),
                   force, quiet)
          libs << "lib/#{lib}"
        end
      end
      manifest = read_manifest(home).merge('version' => version, 'jar' => name, 'libs' => libs,
                                           'repository' => repository, 'installed' => Time.now.utc.iso8601)
      tmp = File.join(home, "#{MANIFEST}.#{Process.pid}.part") # several processes may install at once
      File.write(tmp, JSON.pretty_generate(manifest))
      File.rename(tmp, File.join(home, MANIFEST))
      warn "PD4ML #{version}: #{jar}" unless quiet
      jar
    end

    # Where downloaded builds go: PD4ML_HOME, else the user's cache directory.
    def default_home
      return ENV['PD4ML_HOME'] if ENV['PD4ML_HOME'].to_s != ''

      if Gem.win_platform?
        File.join(ENV['LOCALAPPDATA'] || File.join(Dir.home, 'AppData', 'Local'), 'pd4ml-ruby')
      else
        File.join(ENV['XDG_CACHE_HOME'].to_s.empty? ? File.join(Dir.home, '.cache') : ENV['XDG_CACHE_HOME'], 'pd4ml-ruby')
      end
    end

    # The jar install made the default, or nil.
    def installed_jar(home = default_home)
      jar = read_manifest(home)['jar']
      path = jar && File.join(home, jar)
      path && File.exist?(path) ? path : nil
    end

    # The installed build's classpath: the PD4ML jar and its companion jars; empty if none.
    def installed_classpath(home = default_home)
      jar = installed_jar(home)
      return [] unless jar

      [jar, *Array(read_manifest(home)['libs']).map { |l| File.join(home, l) }.select { |p| File.exist?(p) }]
    end

    # The version install made the default, or nil.
    def installed_version(home = default_home)
      installed_jar(home) ? read_manifest(home)['version'] : nil
    end

    # Whether the first use of PD4ML may download a build (PD4ML_AUTO_INSTALL, default on).
    def auto_install?
      !%w[0 false no off].include?(ENV.fetch('PD4ML_AUTO_INSTALL', '1').strip.downcase)
    end

    # ---------------------------------------------------------------------------- internals

    def jar_name(version, repository)
      return "pd4ml-#{version}.jar" unless version.end_with?('-SNAPSHOT')

      xml = fetch("#{repository}/#{GROUP_PATH}/#{version}/maven-metadata.xml")
      xml.scan(%r{<snapshotVersion>(.*?)</snapshotVersion>}m).flatten.each do |sv|
        tag = ->(t) { sv[%r{<#{t}>([^<]*)</#{t}>}, 1] }
        return "pd4ml-#{tag.call('value')}.jar" if tag.call('extension') == 'jar' && tag.call('classifier').to_s.empty? && tag.call('value')
      end
      ts = xml[%r{<timestamp>([^<]+)</timestamp>}, 1]
      build = xml[%r{<buildNumber>([^<]+)</buildNumber>}, 1]
      return "pd4ml-#{version.delete_suffix('-SNAPSHOT')}-#{ts}-#{build}.jar" if ts && build

      raise InstallError, "no jar listed for #{version}"
    end

    def download(url, path, force, quiet)
      return if !force && File.exist?(path)

      warn "downloading #{url}" unless quiet
      data = fetch(url)
      expected = fetch("#{url}.sha1").strip.split.first.to_s.downcase
      actual = Digest::SHA1.hexdigest(data)
      raise InstallError, "checksum mismatch for #{url}: #{actual} != #{expected}" if !expected.empty? && actual != expected

      FileUtils.mkdir_p(File.dirname(path))
      tmp = "#{path}.#{Process.pid}.part"
      File.binwrite(tmp, data)
      File.rename(tmp, path)
    end

    def fetch(url, redirects = 5)
      uri = URI(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 30, read_timeout: 300) do |http|
        http.get(uri.request_uri, 'User-Agent' => 'pd4ml-ruby')
      end
      case response
      when Net::HTTPSuccess then response.body.b
      when Net::HTTPRedirection
        raise InstallError, "too many redirects: #{url}" if redirects.zero?

        fetch(URI.join(url, response['location']).to_s, redirects - 1)
      else raise InstallError, "cannot download #{url} (HTTP #{response.code})"
      end
    rescue SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError => e
      raise InstallError, "cannot download #{url}: #{e.message}"
    end

    def read_manifest(home)
      JSON.parse(File.read(File.join(home, MANIFEST)))
    rescue Errno::ENOENT, JSON::ParserError
      {}
    end
  end
end
