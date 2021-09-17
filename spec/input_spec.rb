require_relative "spec_helper"
require "fileutils"

RSpec.describe Metanorma::Input::Asciidoc do
  it "aborts if include error" do
    begin
      require "metanorma-iso"
      input = <<~INPUT
        = Document title
        Author
        :docfile: test.adoc
        :nodoc:

        include::common/common-sections/00-abstract.adoc[]

      INPUT
      expect do
        Metanorma::Input::Asciidoc.new
          .process(input, "test.adoc", :iso)
      end.to raise_error(SystemExit)
    rescue SystemExit
    end
  end

  it "extracts Asciidoctor document attributes" do
    expect(Hash[Metanorma::Input::Asciidoc.new
      .extract_options(<<~"INPUT").sort].to_s + "\n").to eq <<~"OUTPUT"
        = Document title
        Author
        :sectionsplit: a
        :body-font: b
        :header-font: c
        :title-font: d
        :i18nyaml: e
        :htmlstylesheet: f
        :htmlcoverpage: g
        :htmlintropage: h
        :scripts: i
        :scripts-pdf: j
        :wordstylesheet: k
        :standardstylesheet: l
        :header: m
        :wordcoverpage: n
        :wordintropage: o
        :ulstyle: p
        :olstyle: q
        :data-uri-image: false
        :htmltoclevels: r
        :doctoclevels: s
        :hierarchical-assets: t
        :use-xinclude: u
        :break-up-urls-in-tables: v
        :bare: w
        :htmlstylesheet-override: x
        :wordstylesheet-override: y
        :scripts-override: z
        :suppress-asciimath-dup: true
        :base-asset-path: aa
      INPUT
        {:bare=>"w", :baseassetpath=>"aa", :bodyfont=>"b", :break_up_urls_in_tables=>"v", :datauriimage=>false, :doctoclevels=>"s", :header=>"m", :headerfont=>"c", :hierarchical_assets=>"t", :htmlcoverpage=>"g", :htmlintropage=>"h", :htmlstylesheet=>"f", :htmlstylesheet_override=>"x", :htmltoclevels=>"r", :i18nyaml=>"e", :olstyle=>"q", :scripts=>"i", :scripts_override=>"z", :scripts_pdf=>"j", :sectionsplit=>"a", :standardstylesheet=>"l", :suppressasciimathdup=>true, :titlefont=>"d", :ulstyle=>"p", :use_xinclude=>"u", :wordcoverpage=>"n", :wordintropage=>"o", :wordstylesheet=>"k", :wordstylesheet_override=>"y"}
      OUTPUT
  end

  it "extracts Asciidoctor document attributes with default values" do
    expect(Hash[Metanorma::Input::Asciidoc.new
      .extract_options(<<~"INPUT").sort].to_s + "\n").to eq <<~"OUTPUT"
        = Document title
        Author
        :hierarchical-assets:
        :use-xinclude:
        :break-up-urls-in-tables:
        :suppress-asciimath-dup:
      INPUT
        {:break_up_urls_in_tables=>"true", :datauriimage=>true, :hierarchical_assets=>"true", :suppressasciimathdup=>true, :use_xinclude=>"true"}
      OUTPUT
  end

  it "extracts Asciidoctor document attributes for Metanorma" do
    expect(Hash[Metanorma::Input::Asciidoc.new
      .extract_metanorma_options(<<~"INPUT").sort].to_s + "\n").to eq <<~"OUTPUT"
        = Document title
        Author
        :mn-document-class: a
        :mn-output-extensions: b
        :mn-keep-asciimath:
      INPUT
        {:asciimath=>true, :extensions=>"b", :type=>"a"}
      OUTPUT
  end

  it "extracts Asciidoctor document attributes for Metanorma" do
    expect(Hash[Metanorma::Input::Asciidoc.new
      .extract_metanorma_options(<<~"INPUT").sort].to_s + "\n").to eq <<~"OUTPUT"
        = Document title
        Author
      INPUT
        {}
      OUTPUT
  end
end
