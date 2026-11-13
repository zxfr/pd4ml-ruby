# frozen_string_literal: true

module Pd4ml
  # An HTML to PDF/DOCX/RTF/Markdown/image converter: com.pd4ml.PD4ML with Ruby I/O and the v42 layout
  # engine by default. Every Java method is available by its Java name or in Ruby style
  # (`set_page_size`, `add_style`, `use_ttf`); these take Ruby I/O: read_html (a path, URL or
  # binary String/IO), read_html_string, write_pdf/write_docx/write_rtf (the document returned as
  # a binary String, or written to a path or IO), render_as_images and monitor_progress_with (a block);
  # read_eml/read_mht (e-mail messages, saved web pages) as read_html. get_document and layout (the
  # DOM API, v42 engine) return com.pd4ml.dom objects, whose lists come back as Ruby Arrays.
  #
  #   pd = Pd4ml::PD4ML.new
  #   pd.set_page_size(Pd4ml::PageSize::A4)
  #   pd.read_html_string('<h1>Hello</h1>')
  #   pdf = pd.write_pdf
  class PD4ML
    DEFAULT_ENGINE = 'v42'

    @warned_no_engines = false
    class << self
      attr_accessor :warned_no_engines

      # Static Java members: PD4ML.get_version / PD4ML.getVersion.
      def method_missing(name, *args, &block)
        java_class.respond_to?(name) ? java_class.public_send(name, *args, &block) : super
      end

      def respond_to_missing?(name, include_private = false)
        java_class.respond_to?(name) || super
      end

      def java_class = Java.type('com.pd4ml.PD4ML')
    end

    # The Java object (com.pd4ml.PD4ML).
    attr_reader :java
    # The layout engine chosen ('v42', 'v40'), or nil for the build's own.
    attr_reader :engine

    # license: a license serial number or license file URL (default: pd4ml.lic on the classpath
    # or in the working directory, else evaluation mode); html_width: the width in pixels the
    # HTML is laid out in; engine: 'v42', 'v40' (or :v42, a LayoutEngine), default v42 where the
    # build has layout engines, else the build's own; false: the Java default.
    def initialize(license: nil, html_width: nil, engine: nil)
      args = [license, html_width].compact
      @java = Bridge.get.new_object('com.pd4ml.PD4ML', args)
      @engine = nil
      if engine.nil?
        if Pd4ml.layout_engines?
          engine = DEFAULT_ENGINE
        else
          engine = false
          unless self.class.warned_no_engines
            self.class.warned_no_engines = true
            warn "PD4ML #{Pd4ml.version} has no #{DEFAULT_ENGINE} layout engine (from 4.2): its own engine is used"
          end
        end
      end
      use_html_renderer(engine) unless engine == false
    end

    # Java methods not defined here.
    def method_missing(name, *args, &block)
      return super if block

      @java.__send__(name, *args)
    end

    def respond_to_missing?(_name, _include_private = false) = true

    # ------------------------------------------------------------------------- layout engine

    # Chooses the layout engine ('v42', 'v40', a LayoutEngine), optionally with the HTML width
    # and engine parameters (a Hash).
    def use_html_renderer(engine = DEFAULT_ENGINE, html_width: nil, params: nil)
      unless Pd4ml.layout_engines?
        raise "PD4ML #{Pd4ml.version} has no layout engines to choose from (Constants.LayoutEngine is new in 4.2)"
      end

      e = engine.is_a?(JavaObject) ? engine : Java.type('com.pd4ml.Constants$LayoutEngine').value_of(engine.to_s)
      if params
        @java.useHtmlRenderer(e, html_width || -1, params.to_h { |k, v| [k.to_s, v.to_s] })
      elsif html_width
        @java.useHtmlRenderer(e, html_width)
      else
        @java.useHtmlRenderer(e)
      end
      @engine = e.enum_name
    end
    alias useHtmlRenderer use_html_renderer

    # --------------------------------------------------------------------------------- input

    # Reads the document to convert: a URL ('https://...', 'file:...') or a local path (a String,
    # Pathname or URI), its content (a binary String - File.binread - or an IO), or a Java
    # URL/InputStream. base_url: where relative links resolve, for content (a URL or a local
    # directory/file); encoding: the document's encoding when it does not declare one.
    def read_html(source, base_url = nil, encoding = nil)
      if location?(source)
        url = Pd4ml.to_url(source)
        encoding ? @java.readHTML(url, encoding) : @java.readHTML(url)
        return
      end
      content = source.is_a?(JavaObject) ? source : Pd4ml.binary(source)
      base = base_url && Pd4ml.to_url(base_url)
      if base_url.nil? && encoding.nil?
        @java.readHTML(content)
      elsif encoding.nil?
        @java.readHTML(content, base)
      else
        @java.readHTML(content, base, encoding)
      end
    end
    alias readHTML read_html

    # Reads the document from a String of HTML.
    def read_html_string(html, base_url = nil)
      read_html(html.to_s.encode(Encoding::UTF_8).b, base_url, 'UTF-8')
    end
    alias readHtmlString read_html_string

    # Reads an e-mail message (.eml) to convert: its body, HTML if it has one, with the images it
    # embeds, after a block with From, Date, To, Cc, Subject and the attachments, which are
    # embedded in the PDF. `source` as for read_html: a path or URL, or the message itself (a
    # binary String or IO). Of resources outside the message only https:// ones are loaded;
    # add_allowed_resource_location replaces that. read_html recognizes messages too; this is the
    # way for mail from outside your control. PD4ML 4.2 and later.
    def read_eml(source)
      read_mime('readEML', source)
    end
    alias readEML read_eml

    # Reads a web page saved as a single file (.mht, .mhtml), with the images, style sheets and
    # fonts saved in it; `source` as for read_eml. PD4ML 4.2 and later.
    def read_mht(source)
      read_mime('readMHT', source)
    end
    alias readMHT read_mht

    # -------------------------------------------------------------------------------- output

    # Writes the PDF: to `target` (a path or an IO), or returned as a binary String. spec: a
    # PdfSpec (PdfSpec::PDFA_2B), one of its keywords ('pdf/a-2b', see PdfSpec.list_keywords),
    # or 'PDF'/'PDFA'/'PDFUA'.
    def write_pdf(target = nil, spec: nil)
      s = Pd4ml.pdf_spec(spec)
      outs = []
      Bridge.get.call(@java, 'writePDF', s.nil? ? [Output.new(0)] : [Output.new(0), s], outs)
      Pd4ml.deliver(outs[0] || ''.b, target)
    end
    alias writePDF write_pdf

    # Writes a DOCX document (see write_pdf for `target`).
    def write_docx(target = nil)
      outs = []
      Bridge.get.call(@java, 'writeDOCX', [Output.new(0)], outs)
      Pd4ml.deliver(outs[0] || ''.b, target)
    end
    alias writeDOCX write_docx

    # Writes an RTF document; rtf_wmf: images as WMF (see write_pdf for `target`).
    def write_rtf(target = nil, rtf_wmf: false)
      outs = []
      Bridge.get.call(@java, 'writeRTF', [Output.new(0), rtf_wmf], outs)
      Pd4ml.deliver(outs[0] || ''.b, target)
    end
    alias writeRTF write_rtf

    # Writes the document as Markdown (GitHub-flavored, UTF-8) for LLM, RAG and search pipelines:
    # the text a reader sees, in reading order, with headings, lists, tables, links, footnotes and
    # image references (v42 engine, PD4ML 4.2.0 or newer). page_markers: each page starts with
    # `<!-- page N -->`, N being the page of the PDF the same conversion writes. A feature of the
    # DMS and UA editions: with another license, or none, the Markdown carries evaluation notes.
    # See write_pdf for `target`; to_markdown returns it as a String.
    def write_markdown(target = nil, page_markers: false)
      outs = []
      begin
        Bridge.get.call(@java, 'writeMarkdown', [Output.new(0), page_markers ? true : false], outs)
      rescue StandardError => e
        raise unless e.message.to_s.include?('NoSuchMethodException')

        raise "write_markdown needs PD4ML 4.2.0 or newer (this is #{@java.getVersion}): " \
                     "run 'pd4ml install' to update"
      end
      Pd4ml.deliver(outs[0] || ''.b, target)
    end
    alias writeMarkdown write_markdown

    # The document as a Markdown String, UTF-8 (see write_markdown).
    def to_markdown(page_markers: false)
      write_markdown(nil, page_markers: page_markers).force_encoding(Encoding::UTF_8)
    end

    # render_as_images(format): the pages as encoded images (Constants::PNG24...), binary Strings;
    # render_as_images(dir, name, format): image files written to a directory;
    # render_as_images: Java BufferedImage objects.
    def render_as_images(*args)
      if args.size == 3 && (args[0].is_a?(String) || args[0].is_a?(Pathname))
        FileUtils.mkdir_p(args[0].to_s)
        return @java.renderAsImages(Java.type('java.io.File').new(File.expand_path(args[0].to_s)), args[1], args[2])
      end
      @java.renderAsImages(*args)
    end
    alias renderAsImages render_as_images

    # The pages as 24-bit PNG images (binary Strings).
    def render_png = @java.renderAsImages(Java.type('com.pd4ml.Constants')::PNG24)

    # ------------------------------------------------------------------------------ progress

    # Reports conversion progress to a block |message_id, progress, note, msec| - it runs on this
    # thread while PD4ML works - or to a Java ProgressListener.
    def monitor_progress_with(listener = nil, &block)
      listener ||= Java.proxy('com.pd4ml.ProgressListener') do |_method, a|
        block.call(a[0].to_i, a[1].to_i, a[2], a[3].to_i)
      end
      @java.monitorProgressWith(listener)
    end
    alias monitorProgressWith monitor_progress_with

    private

    def read_mime(method, source)
      arg = if location?(source)
              Pd4ml.to_url(source)
            else
              source.is_a?(JavaObject) ? source : Pd4ml.binary(source)
            end
      Bridge.get.call(@java, method, [arg])
      nil
    end

    def location?(source)
      source.is_a?(Pathname) || source.is_a?(URI::Generic) ||
        (source.is_a?(String) && source.encoding != Encoding::BINARY && !source.lstrip.start_with?('<')) ||
        (source.is_a?(JavaObject) && source.java_class == 'java.net.URL')
    end
  end
end
