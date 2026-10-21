# frozen_string_literal: true

module Pd4ml
  # The bridge to Java cannot start or broke down (no Java, no PD4ML build, process gone).
  class BridgeError < StandardError; end

  # A PD4ML build could not be found, downloaded or verified.
  class InstallError < StandardError; end

  # A Ruby block (a progress listener...) raised while PD4ML ran; the error is #cause.
  class CallbackError < StandardError; end

  # A Java exception thrown by PD4ML (or any Java code called): its Java class and superclasses,
  # message, causes and stack trace.
  #
  #   begin
  #     pd.read_html('missing.html')
  #   rescue Pd4ml::JavaError => e
  #     raise unless e.instance_of_java?('java.io.IOException')
  #   end
  class JavaError < StandardError
    attr_reader :java_class, :hierarchy, :java_message, :causes, :java_trace

    def initialize(java_message, java_class, hierarchy = [], causes = [], java_trace = '')
      super("#{java_class}: #{java_message}")
      @java_message = java_message
      @java_class = java_class
      @hierarchy = hierarchy
      @causes = causes
      @java_trace = java_trace
    end

    # Whether the Java exception is of the class or a subclass ('java.io.IOException').
    def instance_of_java?(name)
      @java_class == name || @hierarchy.include?(name)
    end

    def self.from(e)
      new(e['message'].to_s, e['class'] || 'java.lang.Throwable', e['hierarchy'] || [], e['causes'] || [], e['trace'].to_s)
    end
  end
end
