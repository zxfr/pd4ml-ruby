# pd4ml — PD4ML for Ruby

HTML and CSS to **PDF**, **PDF/A**, **PDF/UA**, **ZUGFeRD/Factur-X**, **DOCX**, **RTF** and
**images** from Ruby, with the complete public [PD4ML](https://pd4ml.com) API. The v42 layout
engine is the default.

```ruby
require 'pd4ml'

pd = Pd4ml::PD4ML.new
pd.set_page_size(Pd4ml::PageSize::A4)
pd.set_page_footer('<div style="text-align:right">page $[page] of $[total]</div>', 24, '1+')
pd.read_html_string('<h1>Hello, PDF</h1><p>Generated with <b>PD4ML</b>.</p>')
pd.write_pdf('hello.pdf')          # or pdf = pd.write_pdf (a binary String), or an IO
```

## Installation

With Bundler, in the `Gemfile`:

```ruby
gem 'pd4ml', git: 'https://github.com/zxfr/pd4ml-ruby.git'
```

or download the gem from <https://github.com/zxfr/pd4ml-ruby/releases>:

```
gem install pd4ml-1.0.0.gem
pd4ml install            # optional: otherwise the first use downloads PD4ML
```

Requirements:

- Ruby 3.1 or later.
- Java 8 or later, found through `PD4ML_JAVA`, `JAVA_HOME` or the `PATH`.

PD4ML itself is downloaded from <https://pd4ml.com/maven2>: the most recent 4.x release, plus the
Bouncy Castle jars it needs for encryption and signing. Every file is checked against its SHA-1
checksum. The download happens with `pd4ml install`, or on first use (`PD4ML_AUTO_INSTALL=0`
turns that off). Builds are stored per user (`%LOCALAPPDATA%\pd4ml-ruby`, `~/.cache/pd4ml-ruby`,
or `PD4ML_HOME`).

To use a PD4ML jar of your own, set `PD4ML_CLASSPATH`, set `PD4ML_CLASSPATH_FILE`, or call
`Pd4ml.configure(classpath: [...])`.

## How it works

PD4ML is a Java library. The gem starts it once per process in a small bridge process and calls
it over a pipe. Every class and method is available:

- by its Java name (`setPageSize`) or Ruby-style (`set_page_size`, `use_ttf`, `demo_mode?`);
- constants as Ruby constants (`Pd4ml::PageSize::A4`, `Pd4ml::Constants::AllowPrint`);
- any other Java class through `Pd4ml::Java.type`.

The gem adds Ruby I/O on top: paths, URLs, binary Strings and IO objects in and out, and blocks
for progress listeners. Several processes can share one bridge server: run `pd4ml serve` and set
`PD4ML_BRIDGE=tcp://127.0.0.1:8723`.

## Command line

```
pd4ml install [VERSION] [--snapshots]   download PD4ML (or update it)
pd4ml list                              versions in the repository
pd4ml version                           the PD4ML version in use
pd4ml convert in.html out.pdf [--page-size A4 --landscape --spec pdf/a-2b ...]
pd4ml serve [--port 8723]               a shared bridge server
```

## Documentation

- [User guide](docs/guide.md): installation, the bridge, use cases, tips, troubleshooting
- [API reference](docs/api.md): every PD4ML class and method with its Ruby name
- [PD4ML documentation](https://pd4ml.com/docs/)

## License

The gem is provided by PD4ML. PD4ML is commercial software: without a license it runs in
evaluation mode and watermarks its output. See [licensing](https://pd4ml.com/docs/#3.-licensing).
