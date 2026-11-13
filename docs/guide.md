# PD4ML for Ruby — User Guide

`pd4ml` brings [PD4ML](https://pd4ml.com) to Ruby: it converts HTML and CSS into **PDF**,
**PDF/A**, **PDF/UA**, **ZUGFeRD/Factur-X** invoices, **DOCX**, **RTF**, **Markdown** and **page images**, and
gives Ruby applications the complete public PD4ML API.

PD4ML is a Java library. The gem runs it in a small Java *bridge* process that Ruby talks to.
Every PD4ML class and method can be called from Ruby, by its Java name or Ruby-style
(`set_page_size`), and the gem adds Ruby I/O on top: paths, binary strings and IO objects
instead of Java streams.

The PD4ML manual, which this guide refers to throughout, is at <https://pd4ml.com/docs/>.
The generated reference of every class and method is [api.md](api.md).

**Contents**

1. [Prerequisites](#1-prerequisites)
2. [Installation](#2-installation)
3. [Quick start](#3-quick-start)
4. [How it works](#4-how-it-works)
5. [Use cases](#5-use-cases)
6. [Tips and hints](#6-tips-and-hints)
7. [Troubleshooting](#7-troubleshooting)
8. [API reference](#8-api-reference)
9. [Further reading](#9-further-reading)

---

## 1. Prerequisites

| Requirement | Notes |
|---|---|
| **Ruby 3.1 or later** | MRI on any platform Ruby and Java run on. |
| **Java 8 or later** | A JDK or JRE; an LTS release (17, 21) is recommended. The gem finds it through `PD4ML_JAVA`, then `JAVA_HOME`, then `java` on the `PATH`. |
| **PD4ML** | Downloaded automatically on first use, or ahead of time with `pd4ml install` (see below); or any PD4ML build you point the gem at. |
| **Network access** | Only for downloading PD4ML. Conversions need none, unless the HTML references remote resources. |
| **A PD4ML license** | Optional for evaluation. Without one, PD4ML runs in evaluation mode and watermarks its output. See [Licensing](https://pd4ml.com/docs/#3.-licensing) and [5.21](#521-licensing). |

Check Java with `java -version`. On a server without Java, install a JRE package (for example
`apt install openjdk-21-jre-headless`) and, if it is not on the `PATH`, set `JAVA_HOME`. In
containers, use an image with both Ruby and Java, or add a JRE to the Ruby image.

## 2. Installation

### 2.1 Install the gem

```
gem install pd4ml
```

or, with Bundler, `gem 'pd4ml'` in the `Gemfile` and `bundle install`. The gem has no gem
dependencies and installs the `pd4ml` command.

The gem is published on RubyGems as [`pd4ml`](https://rubygems.org/gems/pd4ml). The same files
are on GitHub, <https://github.com/zxfr/pd4ml-ruby>, with each version's `.gem` attached to its
[release](https://github.com/zxfr/pd4ml-ruby/releases); Bundler can also take it from there
(`gem 'pd4ml', git: 'https://github.com/zxfr/pd4ml-ruby.git'`).

### 2.2 Install PD4ML

The gem contains the Ruby library and the bridge only. The PD4ML library itself comes from the
PD4ML Maven repository (<https://pd4ml.com/maven2>), in one of two ways.

**Automatically, on first use.** If no PD4ML build is installed or configured
([2.3](#23-other-ways-to-provide-pd4ml)), the first use of PD4ML in a process downloads PD4ML 4.2
([which build](#which-build)) before starting Java. A warning on standard error reports it. So
once the gem is installed, this is all it takes:

<!-- no-test -->
```ruby
require 'pd4ml'

pdf = Pd4ml.html_to_pdf('<h1>Hello</h1>'.b)     # the first call downloads PD4ML (once)
```

**Ahead of time, with the `pd4ml` command.** This is better for servers, CI and container
images, where a download in the middle of a request is unwelcome:

```
pd4ml install                 # with Bundler: bundle exec pd4ml install
```

Either way, the gem:

- downloads PD4ML 4.2 ([which build](#which-build));
- downloads the Bouncy Castle jars PD4ML needs for encryption and signing, from Maven Central;
- checks every file against its published SHA-1 checksum;
- stores them in a per-user cache directory: `%LOCALAPPDATA%\pd4ml-ruby` on Windows,
  `~/.cache/pd4ml-ruby` elsewhere, or `PD4ML_HOME`.

The gem then uses that build. Later runs do not check for newer PD4ML releases: run
`pd4ml install` again to update. Updating the gem does not change the PD4ML build.

<a id="which-build"></a>**Which build.** The gem needs PD4ML 4.2 for its 4.2 API: `read_eml` and
`read_mht`, `add_allowed_resource_location`, `add_metadata` (XMP), and the DOM API
(`get_document`, `layout`), as well as for the v42 layout engine ([4.3](#43-layout-engines)). So a
plain `pd4ml install` (and the first use) takes:

- the most recent PD4ML release from 4.2.0 on;
- while 4.2.0 is not released yet, the most recent 4.2.x **development snapshot** (today
  4.2.0-SNAPSHOT), because no release has the 4.2 API yet.

Once 4.2.0 is released, new installs take it by themselves, and `pd4ml install` updates an
existing snapshot install to it. Snapshots of later versions (4.3, 5.0) are never taken by
default; `--snapshots` asks for them.

The rest of the API works with older builds too: to stay on the current 4.1 release, install it
explicitly (`pd4ml install 4.1.2`); the 4.2 methods then raise `Pd4ml::JavaError`
(`NoSuchMethodException`).

| Option | |
|---|---|
| *(none)* | the most recent release from 4.2.0 on, else the most recent 4.2.x snapshot ([which build](#which-build)), or an update to it |
| `--snapshots` | the most recent 4.x build, including development snapshots |
| `pd4ml install 4.1.2` | an exact version (any release or snapshot the repository lists) |
| `--jakarta` | for Jakarta EE / Servlet 6 environments: a `-jakarta` variant if one fits; PD4ML 4.2 has none (its builds contain the Jakarta tag library), so the same 4.2 build (an older `-jakarta` build by version, e.g. `pd4ml install 4.0.20fx3-jakarta`) |
| `--home DIR` | install into `DIR` (default: `PD4ML_HOME`, else the cache directory) |
| `--force` | download again |
| `--no-bouncycastle` | skip the Bouncy Castle jars (encryption and signing will not work) |
| `pd4ml list` | list the available versions |

The same is available from Ruby, which suits an application's boot (a Rails initializer):

<!-- no-test -->
```ruby
require 'pd4ml'

Pd4ml.install                      # downloads only when that build is not there yet
puts Pd4ml.installed_version, Pd4ml.installed_classpath
```

To check the installation, run `pd4ml version`.

**Turning the automatic download off.** Set `PD4ML_AUTO_INSTALL=0`, for example on servers that
must not reach the internet, or where the build is provisioned separately. The gem then raises
`Pd4ml::BridgeError` until a build is installed or configured. The automatic download never runs
when a build is configured through [2.3](#23-other-ways-to-provide-pd4ml).

> **Services and containers**: the account the application runs as must see the installed
> build. Install it as that account, or install into a shared directory and set `PD4ML_HOME`
> for the application too. In a Dockerfile:
>
> ```
> RUN bundle install && PD4ML_HOME=/opt/pd4ml bundle exec pd4ml install
> ENV PD4ML_HOME=/opt/pd4ml PD4ML_AUTO_INSTALL=0
> ```

### 2.3 Other ways to provide PD4ML

The gem looks for PD4ML in this order:

1. `Pd4ml.configure(classpath: [...])`, called before the first conversion;
2. the `PD4ML_CLASSPATH` environment variable: jars and class directories separated by `;`
   (Windows) or `:` (elsewhere), with `dir/*` for all jars of a directory;
3. the `PD4ML_CLASSPATH_FILE` environment variable: a file with one entry per line;
4. the build `pd4ml install` (or the first use) downloaded.

Typical reasons to use them:

- **Offline or air-gapped servers**: run `pd4ml install --home ./pd4ml-libs` on a machine with
  network access, copy the directory, and set `PD4ML_HOME` and `PD4ML_AUTO_INSTALL=0` on the
  target.
- **A licensed or specific jar**: `PD4ML_CLASSPATH=/opt/pd4ml/pd4ml.jar:/opt/pd4ml/lib/*`.
- **A PD4ML development build** (for the v42 layout engine, see [4.3](#43-layout-engines)): a
  classpath file listing the build's classes and its Maven dependencies, in
  `PD4ML_CLASSPATH_FILE`.

## 3. Quick start

```ruby
require 'pd4ml'

pd = Pd4ml::PD4ML.new
pd.set_page_size(Pd4ml::PageSize::A4)
pd.read_html_string('<h1>Hello, PDF</h1><p>Generated with <b>PD4ML</b>.</p>')
pd.write_pdf('hello.pdf')
```

Or in one call:

```ruby
require 'pd4ml'

pdf = Pd4ml.html_to_pdf('<h1>Invoice 42</h1>'.b)
puts pdf[0, 5]                              # %PDF-
```

## 4. How it works

### 4.1 The two-phase model

A document is **read once and written any number of times**:

- `read_html` parses the document and lays it out;
- each `write_pdf`, `write_docx`, `write_rtf`, `write_markdown` or `render_as_images` call then produces one output
  from that same layout.

Settings (page size, headers, fonts...) go before `read_html`. See
[the two-phase model](https://pd4ml.com/docs/#6.1-the-two-phase-model).

```ruby
require 'pd4ml'

pd = Pd4ml::PD4ML.new
pd.read_html_string('<h1>Quarterly report</h1>')
pd.write_pdf('report.pdf')
pd.write_docx('report.docx')
thumbnails = pd.render_png               # PNG images, one binary String per page
```

### 4.2 The bridge and threads

- **One bridge per process.** The first use of PD4ML starts a Java bridge process. It serves
  every conversion of the Ruby process, from any thread, and ends with it. Starting Java takes a
  fraction of a second; after that, converting an ordinary document takes milliseconds.
- **Threads.** The bridge is thread-safe: use one `Pd4ml::PD4ML` per document (each thread its
  own) and convert from as many threads as you like (Puma, Sidekiq). The conversions themselves
  run one at a time, so for parallel throughput use several processes, or point them all at one
  bridge server (next item). Each Puma or Unicorn worker process starts its own bridge on first
  use; there is nothing to set up before forking.
- **Shared bridge server.** Several processes, or short-lived ones (rake tasks, CLI tools), can
  use one long-running bridge instead of each starting Java:

  ```
  pd4ml serve --port 8723          # keep it running (systemd, a sidecar container, foreman)
  ```

  Then set `PD4ML_BRIDGE=tcp://127.0.0.1:8723`, or call
  `Pd4ml.configure(server: 'tcp://127.0.0.1:8723')`. The server listens on the loopback
  interface only, and each connection has its own objects.
- **JVM options** (memory, system properties): set `PD4ML_JVM_OPTIONS="-Xmx2g"`, or call
  `Pd4ml.configure(jvm_options: ['-Xmx2g'])` before the first use. Java runs headless.
- **The bridge's console output** is discarded unless `PD4ML_BRIDGE_LOG=path` (or
  `Pd4ml.configure(log_file: ...)`) keeps it. `Pd4ml.shutdown` stops the bridge; the next use
  starts it again.

### 4.3 Layout engines

PD4ML 4.2 introduces a second HTML layout engine, **v42**, written to match current browsers
closely (flexbox, grid, modern CSS). `Pd4ml::PD4ML.new` uses it by default:

```ruby
require 'pd4ml'

if Pd4ml.layout_engines?
  pd = Pd4ml::PD4ML.new                          # v42
  legacy = Pd4ml::PD4ML.new(engine: 'v40')       # the previous engine
  puts pd.engine, legacy.engine
end
```

Builds before 4.2 have one engine only; this includes the current public release, 4.1.x. With
such a build:

- the gem uses that build's engine and warns once;
- `Pd4ml.layout_engines?` returns false;
- asking for an engine explicitly raises.

### 4.4 Ruby and Java values

- **Method names**: Java methods can be called by their Java names (`setPageSize`, `readHTML`)
  or Ruby-style: `set_page_size`, `use_ttf` (for `useTTF`), `demo_mode?` (for `isDemoMode`).
  Ruby-style names are matched to the real Java names, acronyms included.
- **Classes**: the PD4ML classes are Ruby classes in the `Pd4ml` module. Constants are Ruby
  constants (`Pd4ml::PageSize::A4`, `Pd4ml::Constants::AllowPrint`); lower-case static fields and
  static methods are class methods (`Pd4ml::LayoutEngine.v42`,
  `Pd4ml::PdfSpec.get_instance('pdf/a-2b')`); constructors use `new`. Any other Java class:
  `Pd4ml::Java.type('java.util.Locale')`.
- **Objects**: a Java object comes back as a `Pd4ml::JavaObject` with all its Java methods.
  Public fields: `obj[:width]` and `obj[:width] = value`. `to_s` is Java's `toString()`,
  `enum_name` an enum constant's name, `java_class` the class name.
- **Collections**: a Java `List` or `Map` generally comes back as a `JavaObject` (`size`,
  `get(i)`). The DOM API ([5.18](#518-modifying-the-document-before-conversion-dom-api)) is the
  exception: its lists and sets come back as Ruby Arrays and its maps as Hashes. `call_java` returns
  them as Java objects.
- **Values**: Strings, Integers, Floats (`100.0` goes to Java as a float), `true`/`false`, `nil`,
  Symbols (as strings: `engine: :v40`), Arrays, Hashes (as Java `Map`s).
- **Binary data**: a binary String (`File.binread`, `"...".b`, encoding ASCII-8BIT) goes to Java
  as `byte[]`; an IO is read. Java's `byte[]` comes back as a binary String. Text Strings (UTF-8)
  go to Java as text.
- Java objects are released when Ruby garbage-collects them.

### 4.5 Exceptions

Java exceptions are raised as `Pd4ml::JavaError`, which knows the Java class and its superclasses:

```ruby
require 'pd4ml'

begin
  pd = Pd4ml::PD4ML.new
  pd.read_html('file:///no/such/document.html')
  pd.write_pdf
rescue Pd4ml::JavaError => e
  raise unless e.instance_of_java?('java.io.IOException')

  puts "cannot read the document: #{e.java_message}"
end
```

`e.java_class`, `e.causes` and `e.java_trace` hold the details. Other errors:

| Error | Raised when |
|---|---|
| `Pd4ml::BridgeError` | the bridge itself fails: no Java, no PD4ML build, or the process ended |
| `Pd4ml::CallbackError` | a Ruby block raised, such as a progress listener; the original error is `cause` |
| `Pd4ml::InstallError` | downloading PD4ML fails |

---

## 5. Use cases

The snippets below are complete and runnable. Files they read (`report.html`...) are assumed to
exist in the working directory.

### 5.1 HTML string to PDF

This is the common case for web applications: render HTML with your template engine (ERB, Haml,
Slim, a Rails view) and convert it in memory.

```ruby
require 'pd4ml'

html = '<html><body><h1>Order 1001</h1><p>Thank you for your order.</p></body></html>'

pd = Pd4ml::PD4ML.new
pd.read_html_string(html)
pdf = pd.write_pdf                       # the PDF as a binary String
```

`write_pdf`, `write_docx`, `write_rtf` and `write_markdown` return the document as a binary String when given no
target. Given a path (a String or Pathname) they write the file, given an IO (a `File`, a
`StringIO`, a Rack body) they write into it.

### 5.2 Files and URLs

```ruby
require 'pd4ml'

pd = Pd4ml::PD4ML.new
pd.read_html('report.html')              # also: 'https://example.com/report', a Pathname, a URI
pd.write_pdf('report.pdf')
```

**Relative links** (`<img src="logo.png">`, `<link href="style.css">`) resolve against the
document's own location when it is read from a path or URL. When the HTML comes from a string,
binary String or IO, pass the base location. Otherwise images and stylesheets go missing without
an error (see [reading the source](https://pd4ml.com/docs/#6.2-reading-the-source)):

```ruby
require 'pd4ml'

html = '<link rel="stylesheet" href="style.css"><p class="note">Styled</p>'
pd = Pd4ml::PD4ML.new
pd.read_html_string(html, '.')           # a directory, file path or URL
pd.write_pdf('styled.pdf')
```

A text String that does not start with `<` is taken as a path or URL; content always goes in as a
binary String (`File.binread`), an IO, or through `read_html_string`. For a document in a known
encoding other than UTF-8, call `pd.read_html(File.binread(path), base, 'windows-1251')`.

### 5.3 Page size, orientation, margins and scaling

```ruby
require 'pd4ml'

pd = Pd4ml::PD4ML.new
pd.set_page_size(Pd4ml::PageSize::LETTER.rotate)                               # landscape
pd.set_page_margins(Pd4ml::PageMargins.new(15, 20, 15, 20, Pd4ml::Units::MM)) # left, top, right, bottom
pd.set_html_width(1000)           # the virtual browser width the page is laid out in
pd.read_html_string("<table width='100%'><tr><td>wide content</td></tr></table>")
pd.write_pdf('landscape.pdf')
```

The layout is scaled to the page: `scale = printable width / html width`, so a smaller HTML width
makes everything larger. Related controls:

- `adjust_html_width(true)` lays the page out at the document's own natural width.
- `fit_page_vertically(Pd4ml::Constants::CENTER_ALIGN)` shrinks the whole document onto a
  single page.
- `set_page_size` and `set_page_margins` accept a page *scope* (`'1'`, `'2+'`, `'odd'`...) as a
  second argument.

More in [page layout](https://pd4ml.com/docs/#7.-page-layout-size-margins-and-scaling).

For a custom size, use `Pd4ml::PageSize.new(100.0, 150.0, Pd4ml::Units::MM)`. For a named size,
use `Pd4ml::PageSize.get_instance('a5')` (the name in lower case).

### 5.4 Headers, footers and page numbers

Headers and footers are HTML fragments. PD4ML fills in `$[page]`, `$[total]` and `$[title]` on
each page, and `set_dynamic_data` adds placeholders of your own. `$[...]` is safe in both single-
and double-quoted Ruby strings (only `#{...}` is interpolated).

```ruby
require 'pd4ml'

pd = Pd4ml::PD4ML.new
pd.set_dynamic_data({ 'customer' => 'Acme Corp.', 'invoice' => 'INV-2026-0031' })
pd.set_page_header("<div style='font-size:9pt'><b>$[title]</b></div>", 30, '1+')
pd.set_page_footer(
  "<div style='font-size:8pt; text-align:right'>" \
  'Invoice $[invoice] &mdash; $[customer] &mdash; page $[page] of $[total]</div>',
  24, '1+'
)
pd.read_html_string("<title>Invoice</title><h1>Invoice</h1>#{'<p>Line item</p>' * 80}")
pd.write_pdf('invoice.pdf')
```

The second argument is the area height in pixels. The third is the page scope: `'1'` (first
page), `'2+'` (all but the first), `'odd'`, `'even'`, `'3-7'`... You can also write headers and
footers inline in the HTML with PD4ML's extension tags. See
[headers, footers, watermarks and backgrounds](https://pd4ml.com/docs/#8.-headers-footers-watermarks-and-backgrounds)
and the [usage examples](https://pd4ml.com/docs/usage-examples.html#set-page-header-and-footer).

### 5.5 Watermarks and page backgrounds

```ruby
require 'pd4ml'

pd = Pd4ml::PD4ML.new
pd.set_watermark("<span style='font-size:72pt; color:#c00'>DRAFT</span>",
                 120.0, 350.0,   # left, top (px)
                 0.15,           # opacity
                 45.0,           # rotation, degrees
                 1.0,            # scale
                 true, true,     # visible on screen, in print
                 '1+')           # pages
pd.set_page_background("<div style='background:#f7f7f2; height:100%'></div>", '1+')
pd.read_html_string('<h1>Proposal</h1>')
pd.write_pdf('draft.pdf')
```

### 5.6 Fonts

PD4ML's built-in fonts cover Unicode broadly. For a specific typeface (a corporate font, CJK
coverage), give it a font directory:

<!-- no-test -->
```ruby
require 'pd4ml'

pd = Pd4ml::PD4ML.new
pd.use_ttf('/opt/fonts', true)     # a directory of TTF/OTF fonts (indexed: see below)
pd.embed_ttfs(true, false)         # embed only the glyphs used
pd.apply_kerning(true)
pd.enable_ligatures(true)
```

Index a font directory once, ahead of time. PD4ML then reads the index (`pd4fonts.properties`)
instead of scanning all the fonts on every conversion
([font indexing](https://pd4ml.com/docs/#4.3-font-indexing)):

```
java -jar <pd4ml jar> -configure.fonts /opt/fonts
```

`ruby -rpd4ml -e 'puts Pd4ml.installed_jar'` prints the jar's path. CSS `@font-face` web fonts in
the document work as well.

### 5.7 Bookmarks, links and tables of contents

```ruby
require 'pd4ml'

pd = Pd4ml::PD4ML.new
pd.generate_bookmarks_from_headings(true)    # one PDF bookmark per <h1>..<h6>
pd.enable_hyperlinks(true)                   # <a href> become clickable links (the default)
pd.read_html_string("<h1>Introduction</h1><p>...</p><h1 style='page-break-before:always'>Details</h1>")
pd.write_pdf('bookmarked.pdf')
```

PD4ML's `<pd4ml:toc>` tag generates a table of contents with page numbers from the headings; see
the [usage examples](https://pd4ml.com/docs/usage-examples.html#add-toc). For explicit page
breaks, use CSS `page-break-before` / `break-before`, or `<pd4ml:page.break>`.

### 5.8 PDF/A and PDF/UA

```ruby
require 'pd4ml'

pd = Pd4ml::PD4ML.new
pd.read_html_string("<html lang='en'><title>Annual report</title><h1>Annual report</h1>")
pd.write_pdf('archive.pdf', spec: Pd4ml::PdfSpec::PDFA_3B)                  # archival
pd.write_pdf('accessible.pdf', spec: Pd4ml::PdfSpec::PDFUA_1)               # accessible
pd.write_pdf('both.pdf', spec: Pd4ml::PdfSpec::PDF_1_7.combine(Pd4ml::PdfSpec::PDFA_2A))
pd.write_pdf('keyword.pdf', spec: 'pdf/a-2b')                               # by keyword

status = pd.get_last_render_info(Pd4ml::Constants::PD4ML_PDFA_STATUS)      # after writing
```

`Pd4ml::PdfSpec.list_keywords` lists the keywords; an unknown one raises `ArgumentError`
(`PdfSpec.get_instance` alone would fall back to PDF 1.7 without an error).

- PDF/A embeds all fonts.
- PDF/UA needs well-structured HTML: real headings, `alt` texts, `lang`, table headers.
  Combine it with `pd.set_error_policy(Pd4ml::ErrorPolicy::PEDANTIC)` to be told when the source
  does not satisfy the standard.

Details: [PDF/A, PDF/UA and e-invoicing](https://pd4ml.com/docs/#11.2-pdfa-pdfua-and-e-invoicing-formats).

### 5.9 ZUGFeRD / Factur-X e-invoices

`PdfSpec::ZUGFeRD` and `PdfSpec::FacturX` select the PDF/A-3 container the standards require.
The HTML attaches the invoice XML with PD4ML's attachment tag. The
[ZUGFeRD and Factur-X page](https://pd4ml.com/docs/features/zugferd-and-factur-x-pdf-invoices.html)
has the complete recipe, including the required attachment names.

<!-- no-test -->
```ruby
require 'pd4ml'

pd = Pd4ml::PD4ML.new
pd.read_html('invoice.html')          # contains the <pd4ml:attachment> of factur-x.xml
pd.write_pdf('invoice.pdf', spec: Pd4ml::PdfSpec::FacturX)
```

### 5.10 Passwords and permissions

```ruby
require 'pd4ml'

c = Pd4ml::Constants
pd = Pd4ml::PD4ML.new
pd.set_permissions('owner-secret', c::AllowPrint | c::AllowCopy, c::AES_256BIT)
pd.read_html_string('<p>Confidential</p>')
pd.write_pdf('protected.pdf')
```

Combine the `Allow*` flags with `|`, or start from `Constants::DefaultPermissions` and remove
flags with `& ~`. Encryption needs the Bouncy Castle jars, which the installation downloads. See
[permissions and encryption](https://pd4ml.com/docs/#11.1-permissions-and-encryption).

### 5.11 Word (DOCX, RTF) and images

```ruby
require 'pd4ml'

pd = Pd4ml::PD4ML.new
pd.read_html_string('<h1>Letter</h1><p>Dear customer, ...</p>')
pd.write_docx('letter.docx')
pd.write_rtf('letter.rtf')
pages = pd.render_png                                          # a PNG per page
tiffs = pd.render_as_images(Pd4ml::Constants::TIFF)            # one TIFF per page
pd.render_as_images('pages', 'page', Pd4ml::Constants::PNG24)  # page files in a directory
```

The image formats are `PNG8`, `PNG24`, `TIFF` and `TIFF_COMPRESSED` (constants in `Constants`).
The TIFF formats need Java 9 or later.
The v42 engine does not support the multi-page TIFF formats yet; use the v40 engine for them.

With the v42 engine, DOCX/RTF output is *editable*: positioned content becomes text boxes
and form fields, not pictures.

**Markdown** for LLM, RAG and search pipelines (PD4ML 4.2.0 or newer, v42 engine): only the
text a reader sees, in reading order, with headings, lists, tables, links, footnotes and image
references. With `page_markers: true` each page starts with `<!-- page N -->`, the page of the
PDF the same conversion writes, so a chunk of text can be cited by page:

```ruby
require 'pd4ml'

pd = Pd4ml::PD4ML.new
pd.read_html_string('<h1>Report</h1><p>Revenue grew by <b>12%</b>.</p>')
pd.write_pdf('report.pdf')
md = pd.to_markdown(page_markers: true)   # a String: "<!-- page 1 -->\n\n# Report\n\n..."
pd.write_markdown('report.md')            # or to an IO, or a binary String
```

Markdown output is a feature of the DMS and UA editions: with another license, or none, the
Markdown carries evaluation notes. See
[HTML to Markdown for LLM and RAG Pipelines](https://pd4ml.com/docs/features/html-to-markdown-for-llm-and-rag-pipelines.html).

### 5.12 Interactive forms and multi-column layout

```ruby
require 'pd4ml'

pd = Pd4ml::PD4ML.new
pd.generate_forms(true, nil)           # <input>/<select>/<textarea> become PDF form fields
pd.read_html_string("<form>Name: <input name='name' size='30'></form>")
pd.write_pdf('form.pdf')

news = Pd4ml::PD4ML.new
news.generate_multicolumn(2, 20, true) # two columns, 20 mm apart
news.read_html_string("<h1>Newsletter</h1>#{'<p>Lorem ipsum dolor sit amet.</p>' * 200}")
news.write_pdf('newsletter.pdf')
```

See [forms](https://pd4ml.com/docs/#10.1-interactive-pdf-forms) and
[multi-column pages](https://pd4ml.com/docs/#10.2-multi-column-pages). Multi-column pages need
PD4ML 4.0.24 / 4.1.2 or later.

### 5.13 Adding CSS and HTML programmatically

```ruby
require 'pd4ml'

pd = Pd4ml::PD4ML.new
pd.add_style('body { font-family: sans-serif } h1 { color: #036 }', true)   # true: after the document's styles
pd.inject_html("<div style='font-size:8pt'>Generated by the reporting service</div>", false)  # before </body>
pd.read_html_string('<h1>Report</h1>')
pd.write_pdf('report-styled.pdf')
```

`add_style` also takes the URL of a stylesheet: `pd.add_style(Pd4ml.to_url('print.css'), true)`.
See [injecting HTML](https://pd4ml.com/docs/#10.3-injecting-html-and-custom-resource-providers)
and [adding styles](https://pd4ml.com/docs/usage-examples.html#add-style-programmatically).

### 5.14 Progress, diagnostics and metadata

```ruby
require 'pd4ml'

pd = Pd4ml::PD4ML.new
pd.monitor_progress_with do |message_id, percent, note, msec|
  puts format('%3d%% %s (%d ms)', percent, note, msec)
end
pd.set_error_policy(Pd4ml::ErrorPolicy::NORMAL)   # NONE, RELAXED, NORMAL, PEDANTIC, STRICT
pd.set_log_level(1)                               # 0 (silent) .. 5
pd.set_author_name('Reporting service')
pd.set_document_title('Monthly statement')
pd.add_metadata('StatementId', '2026-10', false)
pd.add_metadata('http://www.w3.org/ns/tdmrep/', 'tdm', 'reservation', '1')   # XMP, a namespace of your own
pd.read_html_string('<h1>Statement</h1>')
pd.write_pdf('statement.pdf')
pages = pd.get_last_render_info(Pd4ml::Constants::PD4ML_TOTAL_PAGES).to_i
```

The block runs on the calling thread while the conversion runs in Java, and it may call PD4ML
itself. An error it raises comes out of the call that caused it, as a `Pd4ml::CallbackError`.
The v42 engine currently reports fewer progress stages than v40. More in
[extensibility and diagnostics](https://pd4ml.com/docs/#12.-extensibility-and-diagnostics).

`add_metadata(key, value, hide)` adds a custom property to the PDF's XMP metadata, which viewers
show among the custom document properties (`hide`: true keeps it out of their view).
`add_metadata(namespace_uri, prefix, key, value)` (PD4ML 4.2) adds an XMP property in a
namespace of your own; the example writes `<tdm:reservation>1</tdm:reservation>`, which tells
text and data mining crawlers the rights are reserved (the W3C TDM Reservation Protocol). In PDF/A
output, PD4ML declares the namespace in a PDF/A extension schema. A reserved prefix (`rdf`, `xmp`,
`dc`, `pdf`, `pd4ml`...) raises `Pd4ml::JavaError` (`IllegalArgumentException`).

### 5.15 Working with existing PDFs

```ruby
require 'pd4ml'

cover = Pd4ml.html_to_pdf("<h1 style='margin-top:300px; text-align:center'>Annual Report</h1>".b)
body = Pd4ml.html_to_pdf('<h2>Chapter 1</h2><p>...</p>'.b)

doc = Pd4ml.open_pdf(cover)               # a binary String, IO, path or URL (+ password)
doc.append(Pd4ml.open_pdf(body))          # pages of another document after these
doc.set_title('Annual Report')
Pd4ml.write_pdf(doc, 'annual-report.pdf')

stamp = Pd4ml.html_to_pdf("<p style='color:#c00; font-size:40pt'>COPY</p>".b)
original = Pd4ml.open_pdf('annual-report.pdf')
original.overlay(Pd4ml.open_pdf(stamp), 128)   # draw over every page, half opaque (0..255)
Pd4ml.write_pdf(original, 'annual-report-copy.pdf', password: 'secret')

puts Pd4ml.open_pdf('annual-report.pdf').get_number_of_pages
both = Pd4ml.merge_pdfs(cover, body)      # two documents appended in one call
```

`underlay` draws another document *under* the pages (a letterhead, for example);
`delete_page`, `get_page_size`, `get_metadata` and `dump_outlines` inspect and edit a document.
PD4ML's PDF toolkit (signing, optimisation, XFDF) is described in
[the PDF post-processing toolkit](https://pd4ml.com/docs/#15.-the-pdf-post-processing-toolkit)
and is reachable through `Pd4ml::Java.type(...)`.

### 5.16 E-mail messages and saved web pages

> **Editions.** E-mail and saved web page input — `read_eml`/`read_mht`, and `read_html` for input it
> recognizes as one of them — is part of the PD4ML **DMS and UA editions**. With an STD or PRO license it
> works, but the output carries the "PD4ML EVALUATION MODE" banners.

PD4ML 4.2 reads e-mail messages (`.eml`) and web pages saved as a single file (`.mht`, `.mhtml`)
and writes them to any output format:

```ruby
require 'pd4ml'

pd = Pd4ml::PD4ML.new
pd.read_eml('message.eml')                 # a path or URL, or the message itself: File.binread, an IO
pd.write_pdf('message.pdf')                # the attachments are embedded in the PDF

page = Pd4ml::PD4ML.new
page.read_mht('page.mht')                  # a saved web page, with its images, styles and fonts
page.write_pdf('page.pdf')
```

- A message becomes a block with From, Date, To, Cc, Subject and the attachments, followed by its
  body: the HTML version if there is one, otherwise the plain text, with the images it embeds. The
  attached files are embedded in the PDF next to their names (PDF/A-1 and PDF/A-2 and the other
  outputs keep only the names).
- A saved page shows as it was saved, with the resources saved in the file; its links lead where
  they led on the original page.
- `read_html` recognizes these files too, by the `.eml`, `.mht` or `.mhtml` ending or by how the
  content starts. For mail from outside your control, use `read_eml` and `read_mht`.
- Of the resources a file refers to but does not contain, only `https://` ones are loaded.
  `add_allowed_resource_location` ([5.17](#517-untrusted-html-restricting-resource-loading))
  replaces that list. A file read from a path or URL must then be within the allowed locations
  itself; one passed as content (a binary String or IO) need not be.
- Scripts do not run, the content of frames is not shown, and encrypted (S/MIME, PGP) messages
  are not decrypted.

See [converting e-mail and saved web pages](https://pd4ml.com/docs/features/converting-e-mail-and-saved-web-pages.html).

### 5.17 Untrusted HTML: restricting resource loading

HTML from users, customers or other systems decides what PD4ML loads: `<img src="file:/etc/...">`
reads local files, `http://169.254.169.254/...` calls services inside your network.
`add_allowed_resource_location` (PD4ML 4.2) limits loading to the locations you list:

```ruby
require 'pd4ml'

user_html = '<p>Comment <img src="file:/etc/hosts"> <img src="http://169.254.169.254/latest/meta-data/"></p>'
pd = Pd4ml::PD4ML.new
pd.add_allowed_resource_location('https://cdn.example.com/assets/')
pd.add_allowed_resource_location('https://*.example.org/, file:/opt/app/templates/')
pd.read_html_string(user_html, 'https://cdn.example.com/assets/')
pd.write_pdf('comment.pdf')                # without the two images
```

- `locations` is a comma-separated list of URL prefixes; each call adds to the list. `*` matches
  any characters except `/` (one host name or path segment). The comparison ignores case, and a
  path containing `..` is always rejected.
- It covers style sheets, images, web fonts and attachments, and the document itself when it is
  read from a path or URL. `data:` URIs, `java:` resources and the font directories of `use_ttf`
  are not affected.
- A rejected resource is left out and the conversion goes on;
  `set_error_policy(Pd4ml::ErrorPolicy::PEDANTIC)` makes it fail with a `Pd4ml::JavaError`
  instead, and `set_log_level(Pd4ml::Constants::LOG_CACHE)` logs what was rejected.
- With no location added, resources load from anywhere. Call it before `read_html`.

See [restricting resource loading for untrusted HTML](https://pd4ml.com/docs/features/restricting-resource-loading-for-untrusted-html.html).

### 5.18 Modifying the document before conversion (DOM API)

With the v42 layout engine, the document `read_html` parsed can be read, queried with CSS
selectors and changed before it is written; `layout` lays it out into pages without writing it
and tells where each element ended up.

> The DOM API (`get_document`, `layout` and the `Pd4ml::Dom` classes) is part of the **DMS and UA
> editions** of PD4ML 4.2. Without a license it can be evaluated (the output carries the
> evaluation watermark); with an STD or PRO license it works, but the output of a document it was
> used on carries "PD4ML EVALUATION MODE" banners. See [editions](https://pd4ml.com/products/).

```ruby
require 'pd4ml'

pd = Pd4ml::PD4ML.new                      # the v42 engine
pd.read_html_string(<<~HTML)
  <h1 id="title">Invoice</h1>
  <table class="items"><tr><td>Consulting</td><td class="price">1 200,00</td></tr></table>
  <img src="logo.png">
  <div id="totals">Total: <span id="total"></span></div>
HTML

doc = pd.get_document
doc.get_element_by_id('total').set_text_content('1 250,00 EUR')
doc.query_selector_all('img:not([alt])').each { |img| img.set_attribute('alt', '') }   # a Ruby Array
doc.query_selector('table.items').add_class('striped')
note = doc.create_element('p')
note.set_inner_html('Payable within <b>30 days</b>.')
doc.get_body.append_child(note)

layout = pd.layout                         # the pages as write_pdf would make them
totals = doc.get_element_by_id('totals')
totals.set_attribute('style', 'page-break-before: always') if layout.get_pages(totals).size > 1
layout.get_boxes(totals).each do |box|
  puts format('page %d: %.1f, %.1f, %.1f x %.1f pt', box.get_page, box.get_x, box.get_y, box.get_width, box.get_height)
end
puts "#{layout.get_page_count} page(s), total in #{layout.get_computed_style(totals, 'color')}"
pd.write_pdf('invoice.pdf')
```

| | Methods (Ruby-style; the Java names work too) |
|---|---|
| `Dom::Document` (`pd.get_document`) | `get_element_by_id`, `query_selector`, `query_selector_all`, `get_elements_by_tag_name`, `get_elements_by_class_name`, `get_head`, `get_body`, `get_title`, `create_element`, `create_text_node`, `create_comment` |
| `Dom::Node` (every node) | `get_parent_node`, `get_child_nodes`, `get_first_child`, `get_next_sibling`..., `append_child`, `insert_before`, `replace_child`, `remove_child`, `remove`, `clone_node`, `contains`, `get_text_content`, `set_text_content`, `to_html` |
| `Dom::Element` | `get_attribute`, `set_attribute`, `remove_attribute`, `get_attributes` (a Hash), `get_id`, `get_class_list`, `add_class`, `remove_class`, `toggle_class`, `get_inner_html`, `set_inner_html`, `get_outer_html`, `set_outer_html`, `matches`, `closest`, `get_children`... and the queries of `Document` within the element |
| `Dom::Layout` (`pd.layout`) | `get_page_count`, `get_page_width(page)`, `get_page_height(page)`, `get_page_number(page)`, `get_boxes(element)`, `get_pages(element)`, `get_computed_style(element, property)`, `element_at(page, x, y)` |
| `Dom::LayoutBox` | `get_page`, `get_x`, `get_y`, `get_width`, `get_height` (PDF points from the top left corner of the page) |

- Lists (`query_selector_all`, `get_child_nodes`, `get_boxes`, `get_pages`...) come back as Ruby
  Arrays, `get_attributes` as a Hash. They are snapshots: removing or moving nodes while going
  through one is safe.
- Two objects for the same node are `==` (Java `equals`), but not necessarily the same object.
- A layout is a snapshot too: after changing the document, call `layout` again. Pages are
  numbered from 1.
- Change the document before the first output; every later write lays out the changed document.
- `get_document` and `layout` raise `Pd4ml::JavaError` (`IllegalStateException`) before
  `read_html` or with the v40 engine.

The full method list is in [api.md](api.md#pd4mldomnode); the PD4ML guide is
[modifying the HTML document before conversion](https://pd4ml.com/docs/features/modifying-the-html-document-before-conversion.html).

### 5.19 Web applications

Rails controller, with the HTML from a view:

<!-- no-test -->
```ruby
class InvoicesController < ApplicationController
  def show
    invoice = Invoice.find(params[:id])
    html = render_to_string(:show, layout: 'pdf', locals: { invoice: invoice })
    pd = Pd4ml::PD4ML.new
    pd.read_html_string(html, Rails.public_path.to_s)    # base: where images/CSS live
    send_data pd.write_pdf, type: 'application/pdf', disposition: 'inline',
                            filename: "invoice-#{invoice.number}.pdf"
  end
end
```

Sinatra:

<!-- no-test -->
```ruby
require 'sinatra'
require 'pd4ml'

get '/report.pdf' do
  pd = Pd4ml::PD4ML.new
  pd.read_html_string(erb(:report), settings.public_folder)
  content_type 'application/pdf'
  pd.write_pdf
end
```

To pay the cost of starting Java at boot instead of on the first request, touch PD4ML in an
initializer (`Pd4ml.version`). Each Puma worker process starts its own bridge; set
`PD4ML_BRIDGE` to share one bridge server between them.

### 5.20 Batch conversion

```ruby
require 'pd4ml'

Dir.glob('*.html').each do |source|
  pd = Pd4ml::PD4ML.new                  # one converter per document
  pd.read_html(source)
  pd.write_pdf(source.sub(/\.html\z/, '.pdf'))
  puts "written #{source}"
end
```

One bridge serves the whole loop. To convert in parallel, run several processes (each with its
own bridge), or point them all at one bridge server.

### 5.21 Licensing

<!-- no-test -->
```ruby
require 'pd4ml'

pd = Pd4ml::PD4ML.new(license: 'YOUR-SERIAL-NUMBER')   # or a license file URL; or pd4ml.lic in the working dir / classpath
puts 'unlicensed: output is watermarked' if pd.demo_mode?
puts "PD4ML #{Pd4ml.version}#{pd.pro? ? ' pro' : ''}"
```

Without a license, PD4ML is fully functional but marks its output. See
[licensing](https://pd4ml.com/docs/#3.-licensing).

---

## 6. Tips and hints

- **Start the bridge early.** The first use starts Java. Touch PD4ML when the application
  boots, or use a bridge server for short-lived processes.
- **One converter per document.** `Pd4ml::PD4ML.new` is cheap; reuse the bridge, not the object.
- **Set the base location for HTML from strings.** Missing images and unstyled output are almost
  always caused by unresolved relative links ([details](https://pd4ml.com/docs/#6.2-reading-the-source)).
- **Settings go before `read_html`.** Page size, headers, fonts and styles apply to the layout
  `read_html` makes; writes afterwards only choose the output format.
- **Write several formats from one read.** PDF, DOCX, Markdown and page images from a single `read_html`
  cost one layout.
- **Binary in, binary out.** Pass content as a binary String (`File.binread`, `.b`) or an IO;
  results are binary Strings, ready for `File.binwrite` or `send_data`.
- **Print CSS works.** `@page { size: A4 landscape; margin: 15mm }`, `@media print` and
  `page-break-*` / `break-*` are honoured. They are often simpler than API calls.
- **Control the scale with the HTML width.** If text is too small, or a layout wraps
  differently than in the browser, set `set_html_width` to the width the page was designed for.
- **Index fonts once** with `-configure.fonts`, instead of pointing `use_ttf` at a large
  unindexed directory on every conversion.
- **Restrict what documents can load** when converting untrusted HTML, with
  `add_allowed_resource_location` ([5.17](#517-untrusted-html-restricting-resource-loading)); also
  consider `set_param(Pd4ml::Constants::PD4ML_DISABLE_EXTERNAL_ATTACHMENTS, 'true')`.
- **Pin the build in production.** Use `pd4ml install <version>` or a `PD4ML_CLASSPATH` to a
  jar you keep, rather than following the latest release.

## 7. Troubleshooting

| Symptom | Cause and remedy |
|---|---|
| `Pd4ml::BridgeError: PD4ML not found` | No build is configured and the automatic download is off (`PD4ML_AUTO_INSTALL=0`) or failed: run `pd4ml install`, or set `PD4ML_CLASSPATH`. |
| `Pd4ml::BridgeError: cannot start java` / "closed the connection" | Java is missing or failed. Check `java -version`, set `JAVA_HOME` or `PD4ML_JAVA`; `PD4ML_BRIDGE_LOG=file` keeps Java's output. |
| `Pd4ml::BridgeError: cannot connect to the PD4ML bridge` | The bridge server is not running, or `PD4ML_BRIDGE` names another port. |
| A pause and a "downloading" warning on the first conversion | The automatic first-use download ([2.2](#22-install-pd4ml)). Run `pd4ml install` at deployment instead. |
| `Errno::ENOENT` reading the document | A text String is taken as a path: pass HTML content with `read_html_string`, or as a binary String (`.b`). |
| Images or styles missing | Relative links have no base location, or the server cannot reach the resources (proxies, authentication). See `set_cookie` and `set_http_options`. |
| Output is watermarked | No license is installed ([licensing](https://pd4ml.com/docs/#3.-licensing)). |
| Squares instead of characters | The fonts lack those glyphs. Provide fonts with `use_ttf` ([fonts](https://pd4ml.com/docs/#9.-fonts-bookmarks-and-hyperlinks)). |
| `NoClassDefFoundError: org/bouncycastle/...` with `set_permissions` | The Bouncy Castle jars are missing. Install without `--no-bouncycastle`, or add them to the classpath. |
| `NoClassDefFoundError: com/sun/media/jai/...` with `render_as_images` / `render_png` | PD4ML 4.1.1 and earlier need the Java Advanced Imaging jars for page images. Use a newer PD4ML build, or add `jai-core` and `jai-codec` 1.1.3 (from the JBoss Maven repository) to the classpath. |
| Warning "has no v42 layout engine" | The PD4ML build predates 4.2, so the conversion uses its own engine. Use a 4.2 build for v42. |
| `Pd4ml::JavaError: ... NoSuchMethodException` | No Java method of that name takes those argument types. Check [api.md](api.md); pass floats as `10.0`, binary data as a binary String. |

## 8. API reference

### Module `Pd4ml`

| | |
|---|---|
| `Pd4ml::PD4ML` | the converter: `Pd4ml::PD4ML.new(license:, html_width:, engine:)`; every Java method of `com.pd4ml.PD4ML` |
| `PageSize`, `PageMargins`, `Units`, `Dimensions`, `Constants`, `LayoutEngine`, `ErrorPolicy`, `PdfSpec`, `PdfDocument`, `ProgressListener`, `StatusMessage`, `ResourceProvider`, `CustomTag` | the PD4ML Java classes ([api.md](api.md)) |
| `Dom::Document`, `Dom::Node`, `Dom::Element`, `Dom::Text`, `Dom::Comment`, `Dom::DocumentType`, `Dom::Layout`, `Dom::LayoutBox` | the DOM API classes, from `pd.get_document` and `pd.layout` ([5.18](#518-modifying-the-document-before-conversion-dom-api)); their lists come back as Arrays |
| `html_to_pdf(source, target, base_url:, page_size:, page_margins:, spec:, engine:, html_width:)`, `open_pdf(source, password)`, `write_pdf(doc, target, password:, permissions:)`, `merge_pdfs(a, b, target)` | one-call conversion and PDF documents |
| `version`, `layout_engines?`, `to_url(location)`, `pdf_spec(keyword)` | runtime helpers |
| `configure(**options)`, `shutdown` | the bridge: `classpath:`, `java:`, `jvm_options:`, `server:`, `log_file:` |
| `install(version, **options)`, `installed_jar`, `installed_classpath`, `installed_version`, `available_versions` | PD4ML builds |
| `Java.type(name)`, `Java.proxy(iface) { \|method, args\| ... }` | any Java class, Java interfaces implemented by Ruby blocks |
| `JavaError`, `BridgeError`, `CallbackError`, `InstallError` | errors |

### `Pd4ml::PD4ML` methods with Ruby additions

| Method | |
|---|---|
| `read_html(source, base_url = nil, encoding = nil)` | `source`: a path or URL (String, Pathname, URI), a binary String or IO, or a Java `URL`/`InputStream` |
| `read_html_string(html, base_url = nil)` | the document as a String |
| `read_eml(source)`, `read_mht(source)` | an e-mail message, a saved web page ([5.16](#516-e-mail-messages-and-saved-web-pages)), DMS and UA editions; `source` as for `read_html` |
| `write_pdf(target = nil, spec: nil)` | `target`: a path or IO; none: returns a binary String. `spec`: a `PdfSpec`, a keyword (`'pdf/a-2b'`) or `'PDF'`/`'PDFA'`/`'PDFUA'` |
| `write_docx(target = nil)`, `write_rtf(target = nil, rtf_wmf: false)` | as `write_pdf` |
| `write_markdown(target = nil, page_markers: false)`, `to_markdown(page_markers: false)` | Markdown, as `write_pdf` / as a String |
| `render_as_images(format)`, `render_png` | pages as encoded images (binary Strings); `render_as_images(dir, name, format)` writes files |
| `monitor_progress_with { \|message_id, progress, note, msec\| ... }` | a block, or a Java `ProgressListener` |
| `use_html_renderer(engine, html_width: nil, params: nil)` | the layout engine by name; `pd.engine` tells which one is in use |

The Java names of these methods (`readHTML`, `writePDF`...) work too. All other methods are those
of the Java class `com.pd4ml.PD4ML` ([api.md](api.md#pd4mlpd4ml),
[Java API](https://pd4ml.com/docs/#6.-the-java-api)); static ones are called on the class
(`Pd4ml::PD4ML.get_version`). The Java object itself is `pd.java`.

`ResourceProvider` and `CustomTag` are extended in **Java**: register yours with
`add_custom_resource_provider` / `add_custom_tag_handler`, and put its classes on the classpath.
Java *interfaces* (such as `ProgressListener`) can be implemented in Ruby with
`Pd4ml::Java.proxy`. Examples: [resource loaders](https://github.com/zxfr/pd4ml-examples/blob/master/src/main/java/advanced/A005AddCustomResourceLoader.java),
[custom tags](https://github.com/zxfr/pd4ml-examples/blob/master/src/main/java/advanced/A008AddingCustomTagRenderer.java).

## 9. Further reading

- [PD4ML documentation](https://pd4ml.com/docs/) and the full [programmer's manual](https://pd4ml.com/docs/pd4ml-manual.html)
- [Usage examples](https://pd4ml.com/docs/usage-examples.html)
- [HTML5 element support matrix](https://pd4ml.com/docs/html5-element-support-matrix.html)
- [Command-line tool reference](https://pd4ml.com/docs/pd4cmd-command-line-reference.html)
- [ZUGFeRD and Factur-X invoices](https://pd4ml.com/docs/features/zugferd-and-factur-x-pdf-invoices.html)
- [PDF post-processing toolkit](https://pd4ml.com/docs/#15.-the-pdf-post-processing-toolkit)
- [Java examples on GitHub](https://github.com/zxfr/pd4ml-examples)
