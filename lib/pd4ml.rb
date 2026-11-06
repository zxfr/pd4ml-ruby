# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'uri'
require_relative 'pd4ml/version'
require_relative 'pd4ml/errors'
require_relative 'pd4ml/bridge'
require_relative 'pd4ml/java'
require_relative 'pd4ml/installer'
require_relative 'pd4ml/pd4ml'

# PD4ML for Ruby: HTML and CSS to PDF, PDF/A, PDF/UA, DOCX, RTF and images, with the full public
# PD4ML API (Java package com.pd4ml). PD4ML runs in a Java bridge process started on first use.
#
#   require 'pd4ml'
#
#   pd = Pd4ml::PD4ML.new                    # the v42 layout engine
#   pd.set_page_size(Pd4ml::PageSize::A4)
#   pd.read_html_string('<h1>Hello</h1>')
#   pd.write_pdf('hello.pdf')
module Pd4ml
  # the public PD4ML classes: constants, static methods, constructors
  Constants = Java.type('com.pd4ml.Constants')
  LayoutEngine = Java.type('com.pd4ml.Constants$LayoutEngine')
  ErrorPolicy = Java.type('com.pd4ml.Constants$ErrorPolicy')
  PageSize = Java.type('com.pd4ml.PageSize')
  PageMargins = Java.type('com.pd4ml.PageMargins')
  Dimensions = Java.type('com.pd4ml.Dimensions')
  Units = Java.type('com.pd4ml.Dimensions$Units')
  PdfSpec = Java.type('com.pd4ml.PdfSpec')
  PdfDocument = Java.type('com.pd4ml.PdfDocument')
  ProgressListener = Java.type('com.pd4ml.ProgressListener')
  StatusMessage = Java.type('com.pd4ml.StatusMessage')
  ResourceProvider = Java.type('com.pd4ml.ResourceProvider')
  CustomTag = Java.type('com.pd4ml.CustomTag')

  # The DOM API (com.pd4ml.dom, PD4ML 4.2, v42 engine; DMS and UA editions): PD4ML#get_document and
  # PD4ML#layout return its objects. Their Java lists and sets come back as Ruby Arrays, maps as Hashes.
  module Dom
    Node = Java.type('com.pd4ml.dom.Node')
    Document = Java.type('com.pd4ml.dom.Document')
    Element = Java.type('com.pd4ml.dom.Element')
    Text = Java.type('com.pd4ml.dom.Text')
    Comment = Java.type('com.pd4ml.dom.Comment')
    DocumentType = Java.type('com.pd4ml.dom.DocumentType')
    Layout = Java.type('com.pd4ml.dom.Layout')
    LayoutBox = Java.type('com.pd4ml.dom.LayoutBox')
  end

  FORMATS = %w[PDF PDFA PDFUA].freeze

  class << self
    # The PD4ML (Java) version.
    def version = Java.type('com.pd4ml.PD4ML').getVersion.to_s

    # Whether the PD4ML build chooses between layout engines (Constants.LayoutEngine, from 4.2):
    # earlier builds, the published 4.1.x among them, have one engine only.
    def layout_engines?
      bridge = Bridge.get
      unless @engines_bridge.equal?(bridge)
        @engines = begin
          bridge.get_field('com.pd4ml.Constants$LayoutEngine', 'v42')
          true
        rescue JavaError
          false
        end
        @engines_bridge = bridge
      end
      @engines
    end

    # Sets up the bridge before first use (Bridge.configure).
    def configure(**options) = Bridge.configure(**options)

    # Stops the bridge (it starts again on the next use).
    def shutdown = Bridge.shutdown

    # Downloads a PD4ML build (Installer.install).
    def install(...) = Installer.install(...)

    def installed_jar(...) = Installer.installed_jar(...)
    def installed_classpath(...) = Installer.installed_classpath(...)
    def installed_version(...) = Installer.installed_version(...)
    def available_versions(...) = Installer.available_versions(...)

    # A Java URL for a URL string, a URI, or a local path (relative: to the working directory).
    def to_url(location)
      return location if location.is_a?(JavaObject)

      s = location.to_s
      if s.match?(%r{\A[A-Za-z][A-Za-z0-9+.-]*://|\A(file|jar|data):}i) && !s.match?(%r{\A[A-Za-z]:[\\/]})
        Java.type('java.net.URL').new(s)
      else
        Java.type('java.io.File').new(File.expand_path(s)).toURI.toURL
      end
    end

    # The PdfSpec for one of its keywords ('pdf/a-3b', case-insensitive); a PdfSpec, nil and the
    # format names 'PDF', 'PDFA', 'PDFUA' as they are. Raises ArgumentError for an unknown
    # keyword (PdfSpec.getInstance alone falls back to PDF 1.7 for it).
    def pdf_spec(spec)
      return spec unless spec.is_a?(String) || spec.is_a?(Symbol)

      s = spec.to_s
      return s if FORMATS.include?(s.upcase)

      keywords = PdfSpec.list_keywords.to_s.scan(/'([^']+)'/).flatten
      raise ArgumentError, "unknown PDF spec '#{s}'; one of: #{keywords.join(', ')}" unless keywords.any? { |k| k.casecmp?(s) }

      PdfSpec.get_instance(s)
    end

    # Converts one document to PDF: `source` as for PD4ML#read_html, `target` as for
    # PD4ML#write_pdf. Options: base_url, page_size, page_margins, spec, engine, html_width.
    def html_to_pdf(source, target = nil, base_url: nil, page_size: nil, page_margins: nil, spec: nil, engine: nil,
                    html_width: nil)
      pd = PD4ML.new(engine: engine, html_width: html_width)
      pd.setPageSize(page_size) if page_size
      pd.setPageMargins(page_margins) if page_margins
      pd.read_html(source, base_url)
      pd.write_pdf(target, spec: spec)
    end

    # A com.pd4ml.PdfDocument from a path, URL, binary String/IO (+ password).
    def open_pdf(source, password = nil)
      if (source.is_a?(String) && source.match?(%r{\A[A-Za-z][A-Za-z0-9+.-]*://})) || source.is_a?(URI::Generic)
        return PdfDocument.new(to_url(source), password)
      end

      PdfDocument.new(pdf_bytes(source), password)
    end

    # Writes a PdfDocument (after append, overlay...): returned as a binary String, or written to
    # a path or IO. password: encrypts, with `permissions` (Constants flags; default
    # Constants::DefaultPermissions).
    def write_pdf(document, target = nil, password: nil, permissions: nil)
      outs = []
      if password
        permissions ||= Constants::DefaultPermissions
        Bridge.get.call(document, 'write', [Output.new(0), password, permissions], outs)
      else
        Bridge.get.call(document, 'write', [Output.new(0)], outs)
      end
      deliver(outs[0] || ''.b, target)
    end

    # PdfDocument.mergePDFs: two PDF documents appended into one.
    def merge_pdfs(first, second, target = nil)
      outs = []
      Bridge.get.call_static('com.pd4ml.PdfDocument', 'mergePDFs', [pdf_bytes(first), pdf_bytes(second), Output.new(0)], outs)
      deliver(outs[0] || ''.b, target)
    end

    # internal: writes data to a path or IO, or returns it for a nil target
    def deliver(data, target)
      return data if target.nil?

      if target.respond_to?(:write) && !target.is_a?(String) && !target.is_a?(Pathname)
        target.write(data)
      else
        File.binwrite(target.to_s, data)
      end
      nil
    end

    # internal: the content of a String/IO as a binary String (sent to Java as byte[])
    def binary(source)
      data = source.respond_to?(:read) ? source.read : source.to_s
      data.b
    end

    private

    def pdf_bytes(source)
      return binary(source) if source.respond_to?(:read)

      s = source.to_s
      s.start_with?('%PDF') ? s.b : File.binread(s)
    end
  end
end
