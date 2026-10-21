# frozen_string_literal: true

require 'json'
require 'monitor'
require 'open3'
require 'socket'
require 'uri'
require 'pathname'

module Pd4ml
  # An OutputStream argument whose content comes back to Ruby (see Bridge#request).
  Output = Struct.new(:index)

  # The connection to the Java side: a bridge process (pd4ml-bridge.jar, started on first use) or
  # a bridge server (`pd4ml serve`, PD4ML_BRIDGE=tcp://host:port). One shared bridge serves the
  # whole process; it is thread-safe, and a callback may call PD4ML itself.
  class Bridge
    BRIDGE_JAR = File.expand_path('pd4ml-bridge.jar', __dir__)

    @options = {}
    @default = nil
    @lock = Monitor.new

    class << self
      # Sets up the shared bridge; call before the first use of PD4ML.
      # Options: classpath (Array), java, jvm_options (Array), server ('tcp://127.0.0.1:8723'), log_file.
      def configure(**options)
        @lock.synchronize do
          raise BridgeError, 'the PD4ML bridge runs already: configure before the first use' if @default
          @options = @options.merge(options)
        end
      end

      # The shared bridge, started on first use.
      def get
        @lock.synchronize do
          unless @at_exit
            @at_exit = true
            at_exit { shutdown } # Java ends with the Ruby process, before it exits
          end
          @default ||= new(**@options)
        end
      end

      def started?
        @lock.synchronize { !@default.nil? }
      end

      # Stops the shared bridge (it starts again on the next use).
      def shutdown
        @lock.synchronize do
          @default&.close
          @default = nil
        end
      end

      def forget(bridge)
        @lock.synchronize { @default = nil if @default.equal?(bridge) }
      end

      # The classpath the bridge starts with: configured, from the environment, or the installed build.
      def classpath(options = @options)
        entries = options[:classpath]
        entries ||= ENV['PD4ML_CLASSPATH'].split(File::PATH_SEPARATOR) if ENV['PD4ML_CLASSPATH'].to_s != ''
        entries ||= File.read(ENV['PD4ML_CLASSPATH_FILE']).split(/\r?\n/) if ENV['PD4ML_CLASSPATH_FILE'].to_s != ''
        unless entries
          entries = Installer.installed_classpath
          if entries.empty? && Installer.auto_install?
            warn 'pd4ml: no PD4ML build installed yet: downloading the most recent release ' \
                 "(once; 'pd4ml install' updates it, PD4ML_AUTO_INSTALL=0 turns this off)"
            Installer.install
            entries = Installer.installed_classpath
          end
        end
        entries.map(&:strip).reject(&:empty?).flat_map do |e|
          if e.end_with?('/*', '\\*')
            Dir.glob(File.join(e[0..-3].tr('\\', '/'), '*.jar')).sort
          else
            [e]
          end
        end
      end

      # The java executable: PD4ML_JAVA, JAVA_HOME/bin/java, else `java`.
      def java(options = @options)
        return options[:java] if options[:java]
        return ENV['PD4ML_JAVA'] if ENV['PD4ML_JAVA'].to_s != ''

        home = ENV['JAVA_HOME'].to_s
        unless home.empty?
          exe = File.join(home, 'bin', Gem.win_platform? ? 'java.exe' : 'java')
          return exe if File.exist?(exe)
        end
        'java'
      end

      # The command line that runs the bridge (with a port: a bridge server).
      def command(options = @options, port: nil)
        cp = classpath(options)
        if cp.empty?
          raise BridgeError, "PD4ML not found: install a build with 'pd4ml install' (or Pd4ml.install), or point at " \
                             'one with Pd4ml.configure(classpath: [...]), PD4ML_CLASSPATH or PD4ML_CLASSPATH_FILE'
        end
        args = [java(options), '-Djava.awt.headless=true', *Array(options[:jvm_options])]
        args.concat(ENV['PD4ML_JVM_OPTIONS'].split) if ENV['PD4ML_JVM_OPTIONS'].to_s != ''
        args.push('-cp', [BRIDGE_JAR, *cp].join(File::PATH_SEPARATOR), 'com.pd4ml.bridge.Bridge')
        args.push('--port', port.to_s) if port
        args
      end
    end

    def initialize(**options)
      @lock = Monitor.new
      @next_id = 1
      @next_callback = 1
      @callbacks = {}
      @pending = {}
      @released = Queue.new
      @callback_error = nil
      @closed = false
      server = options[:server] || ENV['PD4ML_BRIDGE']
      if server.to_s != ''
        uri = URI(server)
        begin
          @socket = TCPSocket.new(uri.host, uri.port)
        rescue SystemCallError => e
          raise BridgeError, "cannot connect to the PD4ML bridge at #{server}: #{e.message}"
        end
        @in = @out = @socket
      else
        cmd = self.class.command(options)
        begin
          @in, @out, err, @thread = Open3.popen3(*cmd)
        rescue SystemCallError => e
          raise BridgeError, "cannot start java (#{cmd.first}): #{e.message}"
        end
        log = options[:log_file] || ENV['PD4ML_BRIDGE_LOG']
        @stderr_tail = +''
        # drained either way, so Java never blocks on a full pipe
        @stderr_reader = Thread.new do
          File.open(log, 'a') do |f|
            err.each_line { |l| f.write(l); keep_tail(l) }
          end if log
          err.each_line { |l| keep_tail(l) } unless log
        rescue IOError
          nil
        end
      end
      @in.binmode
      @out.binmode
      @in.sync = true
      hello = request({ 'op' => 'hello' })
      raise BridgeError, 'incompatible PD4ML bridge protocol' unless hello.is_a?(Hash) && hello['protocol'] == 1
    end

    def close
      @lock.synchronize do
        return if @closed

        @closed = true
        begin
          @in.write("{\"id\":0,\"op\":\"close\"}\n")
          @in.close unless @socket
        rescue IOError, SystemCallError
          nil
        end
        @socket&.close
        # let Java finish (it exits on 'close' or end of input), so it never outlives Ruby
        if @thread && !@thread.join(5)
          begin
            Process.kill(:KILL, @thread.pid)
          rescue SystemCallError
            nil
          end
          @thread.join(5)
        end
        @stderr_reader&.join(1)
      end
    end

    # ------------------------------------------------------------------------------- protocol

    # Sends one request and returns its decoded result; callbacks run while it waits. With `outs`
    # (an Array), the content of Output arguments is stored there (binary Strings).
    def request(req, outs = nil)
      response = @lock.synchronize do
        raise BridgeError, 'the PD4ML bridge is closed' if @closed

        refs = []
        refs << @released.pop until @released.empty?
        exchange({ 'op' => 'release', 'refs' => refs }) unless refs.empty?
        exchange(req)
      end
      raise JavaError.from(response['error']) if response['error']

      if outs && response['out'].is_a?(Array)
        response['out'].each_with_index { |data, i| outs[i] = data&.unpack1('m0') }
      end
      if (e = @callback_error)
        @callback_error = nil
        begin
          raise e
        rescue StandardError
          raise CallbackError, "a callback failed: #{e.message}"
        end
      end
      decode(response['result'])
    end

    # ----------------------------------------------------------------------------- operations

    def new_object(cls, args) = request({ 'op' => 'new', 'class' => cls, 'args' => args })

    def call(target, method, args, outs = nil)
      request({ 'op' => 'call', 'ref' => handle_of(target), 'method' => method, 'args' => args }, outs)
    end

    def call_static(cls, method, args, outs = nil)
      request({ 'op' => 'static', 'class' => cls, 'method' => method, 'args' => args }, outs)
    end

    def get_field(target, field)
      if target.is_a?(String)
        request({ 'op' => 'get', 'class' => target, 'field' => field })
      else
        request({ 'op' => 'get', 'ref' => handle_of(target), 'field' => field })
      end
    end

    def set_field(target, field, value)
      if target.is_a?(String)
        request({ 'op' => 'set', 'class' => target, 'field' => field, 'value' => value })
      else
        request({ 'op' => 'set', 'ref' => handle_of(target), 'field' => field, 'value' => value })
      end
    end

    def describe(cls) = request({ 'op' => 'describe', 'class' => cls })

    def instance_of?(target, cls)
      request({ 'op' => 'instanceof', 'ref' => handle_of(target), 'class' => cls }) == true
    end

    # A Java object implementing `iface`; its methods call the block with (method, args).
    def proxy(iface, &block)
      id = @lock.synchronize { (@next_callback += 1) - 1 }
      @callbacks[id] = block
      request({ 'op' => 'proxy', 'interface' => iface, 'callback' => id })
    end

    # Called by JavaObject finalizers; released with the next request.
    def release(handle)
      @released << handle unless @closed
    end

    # ------------------------------------------------------------------------------- values

    def encode(v)
      case v
      when JavaObject then { '$ref' => v.__handle }
      when Output then { '$out' => v.index }
      when PD4ML then { '$ref' => v.java.__handle }
      when String
        v.encoding == Encoding::BINARY || !v.valid_encoding? ? { '$bytes' => [v].pack('m0') } : v
      when Symbol then v.to_s
      when Pathname, URI::Generic then v.to_s
      when Hash then v.to_h { |k, x| [k.to_s, encode(x)] }
      when Array then v.map { |x| encode(x) }
      when nil, true, false, Integer then v
      when Float
        raise ArgumentError, "not a finite number: #{v}" unless v.finite?

        v
      else
        if v.respond_to?(:read)
          data = v.read
          { '$bytes' => [data.to_s].pack('m0') }
        elsif v.respond_to?(:to_str)
          v.to_str
        else
          raise ArgumentError, "cannot pass #{v.class} to Java"
        end
      end
    end

    def decode(v)
      case v
      when Array then v.map { |x| decode(x) }
      when Hash
        if v.key?('$ref')
          JavaObject.new(self, v['$ref'], v['class'], v['enum'])
        elsif v.key?('$bytes')
          v['$bytes'].unpack1('m0')
        else
          v.transform_values { |x| decode(x) }
        end
      else
        v
      end
    end

    private

    def keep_tail(line)
      @stderr_tail = (@stderr_tail + line)[-4000..] || (@stderr_tail + line)
    end

    def handle_of(target)
      case target
      when JavaObject then target.__handle
      when PD4ML then target.java.__handle
      else raise ArgumentError, "not a Java object: #{target.inspect}"
      end
    end

    def exchange(req)
      id = @next_id
      @next_id += 1
      line = JSON.generate(encode(req.merge('id' => id)))
      begin
        @in.write(line, "\n")
      rescue IOError, SystemCallError => e
        gone("the PD4ML bridge is gone (#{e.message})")
      end
      loop do
        return @pending.delete(id) if @pending.key?(id)

        raw = @out.gets
        gone('the PD4ML bridge closed the connection') if raw.nil?
        next if raw.strip.empty?

        msg = JSON.parse(raw.force_encoding(Encoding::UTF_8))
        if msg.key?('callback')
          dispatch(msg)
        elsif msg['id'] == id
          return msg
        else
          @pending[msg['id']] = msg # an outer request's response, during a callback
        end
      end
    end

    def dispatch(msg)
      callback = @callbacks[msg['callback']]
      return if callback.nil? || @callback_error

      begin
        callback.call(msg['method'], Array(msg['args']).map { |a| decode(a) })
      rescue StandardError => e
        @callback_error = e # raised by the request that caused the callback
      end
    end

    def gone(why)
      @closed = true
      self.class.forget(self)
      detail = @stderr_tail.to_s.strip
      raise BridgeError, why + (detail.empty? ? '' : "\n#{detail}") +
                         (ENV['PD4ML_BRIDGE_LOG'] ? '' : ' (PD4ML_BRIDGE_LOG=file keeps its output)')
    end
  end
end
