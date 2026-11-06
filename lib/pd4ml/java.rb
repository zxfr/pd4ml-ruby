# frozen_string_literal: true

module Pd4ml
  # Converts a Ruby-style method name to the Java one: set_page_size -> setPageSize,
  # demo_mode? -> isDemoMode. Names without underscores (Java names) pass through.
  module Naming
    @methods = {}
    @lock = Mutex.new

    module_function

    # The Java method `name` (Ruby-style or Java) means on the class: use_ttf -> useTTF,
    # demo_mode? -> isDemoMode, read_html -> readHTML. Ruby-style names are matched against the
    # class's real method names ignoring case and underscores, so acronyms resolve too.
    def resolve(bridge, java_class, name, static)
      n = name.to_s
      return n unless n.include?('_') || n.end_with?('?')

      key = (n.end_with?('?') ? "is#{n[0..-2]}" : n).delete('_').downcase
      table = @lock.synchronize do
        @methods[[bridge.object_id, java_class, static]] ||= begin
          info = bridge.describe(java_class)
          names = static ? info['methods'] : Array(info['instanceMethods']) + Array(info['methods'])
          names.to_h { |m| [m.downcase, m] }
        end
      end
      table[key] || java_name(n)
    end

    def java_name(name)
      n = name.to_s
      if n.end_with?('?')
        base = java_name(n[0..-2])
        return "is#{base[0].upcase}#{base[1..]}"
      end
      return n unless n.include?('_') && n == n.downcase

      parts = n.split('_').reject(&:empty?)
      parts.first + parts.drop(1).map(&:capitalize).join
    end
  end

  # A Java object living in the bridge. Call its Java methods by their Java names or in Ruby
  # style (`size.rotate`, `pd.set_page_size(...)`, `pd.demo_mode?`). Public fields: `obj[:width]`
  # / `obj[:width] = v`. Released in Java when garbage collected. The DOM API's objects
  # (com.pd4ml.dom) return their Java lists and sets as Ruby Arrays, maps as Hashes
  # (`doc.query_selector_all('p').each { ... }`); `call_java` returns them as they are.
  class JavaObject < BasicObject
    def initialize(bridge, handle, java_class, enum_name)
      @bridge = bridge
      @handle = handle
      @java_class = java_class
      @enum_name = enum_name
      ::ObjectSpace.define_finalizer(self, JavaObject.releaser(bridge, handle))
    end

    def self.releaser(bridge, handle)
      proc { bridge.release(handle) }
    end

    # internal: the bridge handle
    def __handle = @handle

    # The Java class name ('com.pd4ml.PageSize').
    def java_class = @java_class

    # For an enum constant, its name ('v42', 'MM'); else nil.
    def enum_name = @enum_name

    # Reads a public field.
    def [](field) = @bridge.get_field(self, field.to_s)

    # Writes a public field.
    def []=(field, value)
      @bridge.set_field(self, field.to_s, value)
    end

    # Calls a Java method by its exact Java name.
    def call_java(method, *args) = @bridge.call(self, method.to_s, args)

    # Whether the object is an instance of the Java class or interface.
    def instance_of_java?(name) = @bridge.instance_of?(self, name)

    # Java toString().
    def to_s = @bridge.call(self, 'toString', []).to_s
    alias to_str to_s

    def inspect = "#<Java #{@java_class} #{@enum_name || to_s}>"

    # Java equals() (and the same object).
    def ==(other)
      equal?(other) || (JavaObject === other && @bridge.call(self, 'equals', [other]) == true)
    end

    def hash = @bridge.call(self, 'hashCode', [])

    def eql?(other) = equal?(other)

    def is_a?(klass) = klass == JavaObject || klass == ::BasicObject
    alias kind_of? is_a?

    def class = JavaObject

    def nil? = false

    def respond_to?(name, _include_all = false)
      %i[java_class enum_name to_s inspect [] []= call_java instance_of_java?].include?(name.to_sym) ||
        !name.to_s.end_with?('=')
    end

    def method_missing(name, *args, &block)
      ::Kernel.raise ::NoMethodError, "set Java fields with obj[:#{name.to_s.chomp('=')}] = value" if name.to_s.end_with?('=')
      ::Kernel.raise ::ArgumentError, 'Java methods take no block' if block

      result = @bridge.call(self, Naming.resolve(@bridge, @java_class, name, false), args)
      # the DOM API's lists, sets and maps are snapshots: Ruby Arrays and Hashes
      @java_class.start_with?('com.pd4ml.dom.') ? Java.to_ruby(result) : result
    end

    def respond_to_missing?(_name, _include_private = false) = true
  end

  # A Java class as a Ruby class: constants and static fields (`PageSize::A4`, `PageSize.A4`,
  # `LayoutEngine.v42`), static methods (`PdfSpec.get_instance('pdf/a-2b')`), constructors
  # (`PageMargins.new(10, 10, 10, 10, Units::MM)`).
  class JavaClass
    class << self
      attr_reader :java_name

      def new(*args) = Bridge.get.new_object(@java_name, args)

      def to_s = @java_name
      alias inspect to_s

      # Reads a static field.
      def [](field) = Bridge.get.get_field(@java_name, field.to_s)

      # Writes a static field.
      def []=(field, value)
        Bridge.get.set_field(@java_name, field.to_s, value)
      end

      # Calls a static method by its exact Java name.
      def call_java(method, *args) = Bridge.get.call_static(@java_name, method.to_s, args)

      def const_missing(name)
        value_of(name.to_s) { super }
      end

      def method_missing(name, *args, &block)
        n = name.to_s
        return super if block || n.end_with?('=', '!')

        d = description
        if d[:fields].include?(n) && args.empty?
          value_of(n)
        else
          java = Naming.resolve(Bridge.get, @java_name, n, true)
          return super unless d[:methods].include?(java)

          Bridge.get.call_static(@java_name, java, args)
        end
      end

      def respond_to_missing?(name, include_private = false)
        d = description
        d[:fields].include?(name.to_s) || d[:methods].include?(Naming.resolve(Bridge.get, @java_name, name, true)) || super
      end

      private

      # A static field: constants are read once per bridge.
      def value_of(field)
        d = description
        return yield unless d[:fields].include?(field)
        return Bridge.get.get_field(@java_name, field) unless d[:constants].include?(field)

        d[:values].fetch(field) { d[:values][field] = Bridge.get.get_field(@java_name, field) }
      end

      def description
        bridge = Bridge.get
        if @description.nil? || !@description[:bridge].equal?(bridge)
          info = bridge.describe(@java_name)
          @description = { bridge: bridge, fields: info['fields'], constants: info['constants'],
                           methods: info['methods'], values: {} }
        end
        @description
      end
    end
  end

  # Java classes by name, Java interfaces implemented by Ruby blocks.
  module Java
    @classes = {}
    @lock = Mutex.new

    # A Java class (`Pd4ml::Java.type('java.util.Locale').get_default`); nested classes by '.' or '$'.
    def self.type(name)
      @lock.synchronize do
        @classes[name] ||= Class.new(JavaClass) { @java_name = name }
      end
    end

    # A Java object implementing the interface, its methods calling the block with
    # (method, args) on this thread while PD4ML runs.
    def self.proxy(iface, &block)
      raise ArgumentError, 'a block is required' unless block

      Bridge.get.proxy(iface, &block)
    end

    # A Java collection (List, Set...) as a Ruby Array and a Java Map as a Hash, in one or two
    # bridge calls; any other value as it is.
    def self.to_ruby(value)
      return value unless value.is_a?(JavaObject) && value.java_class.start_with?('java.util.')

      if value.instance_of_java?('java.util.Collection')
        value.call_java('toArray')
      elsif value.instance_of_java?('java.util.Map')
        keys = value.call_java('keySet').call_java('toArray')
        values = value.call_java('values').call_java('toArray')
        keys.zip(values).to_h
      else
        value
      end
    end
  end
end
