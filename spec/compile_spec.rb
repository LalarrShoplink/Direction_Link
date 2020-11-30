require_relative "spec_helper"
require "fileutils"

RSpec.describe Metanorma::Compile do
  it "processes metanorma options inside Asciidoc" do
    FileUtils.rm_f %w(spec/assets/test1.xml spec/assets/test1.presentation.xml spec/assets/test1.html spec/assets/test1.alt.html spec/assets/test1.doc spec/assets/test1.relaton.xml)
    Metanorma::Compile.new().compile("spec/assets/test1.adoc")
    expect(File.exist?("spec/assets/test1.xml")).to be true
    expect(File.exist?("spec/assets/test1.doc")).to be false
    expect(File.exist?("spec/assets/test1.html")).to be true
    expect(File.exist?("spec/assets/test1.alt.html")).to be false
    expect(File.exist?("spec/assets/test1.relaton.xml")).to be true
    xml = File.read("spec/assets/test1.xml", encoding: "utf-8")
    expect(xml).to include "</iso-standard>"
  end

  it "processes an asciidoc ISO document" do
    FileUtils.rm_f %w(spec/assets/test.xml spec/assets/test.html spec/assets/test.alt.html spec/assets/test.doc)
    Metanorma::Compile.new().compile("spec/assets/test.adoc", { type: "iso" } )
    expect(File.exist?("spec/assets/test.xml")).to be true
    expect(File.exist?("spec/assets/test.doc")).to be true
    expect(File.exist?("spec/assets/test.html")).to be true
    expect(File.exist?("spec/assets/test.alt.html")).to be true
  end

  it "processes all extensions of an asciidoc ISO document" do
    FileUtils.rm_f %w(spec/assets/test.xml spec/assets/test.html spec/assets/test.alt.html spec/assets/test.doc)
    Metanorma::Compile.new().compile("spec/assets/test.adoc", { type: "iso", extension_keys: [:all] } )
    expect(File.exist?("spec/assets/test.xml")).to be true
    expect(File.exist?("spec/assets/test.doc")).to be true
    expect(File.exist?("spec/assets/test.html")).to be true
    expect(File.exist?("spec/assets/test.alt.html")).to be true
  end

  it "processes specific extensions of an asciidoc ISO document" do
    FileUtils.rm_f %w(spec/assets/test.xml spec/assets/test.html spec/assets/test.alt.html spec/assets/test.doc)
    Metanorma::Compile.new().compile("spec/assets/test.adoc", { type: "iso", extension_keys: [:xml, :doc] } )
    expect(File.exist?("spec/assets/test.xml")).to be true
    expect(File.exist?("spec/assets/test.doc")).to be true
    expect(File.exist?("spec/assets/test.html")).to be false
    expect(File.exist?("spec/assets/test.alt.html")).to be false
    xml = File.read("spec/assets/test.xml", encoding: "utf-8")
    expect(xml).to include "</iso-standard>"
  end

  it "write documents to specified output dir" do
    Metanorma::Compile.new.compile "spec/examples/metanorma-collection/dummy.adoc", "output-dir": "spec/assets"
    expect(File.exist?("spec/assets/dummy.doc"))
    expect(File.exist?("spec/assets/dummy.html"))
    expect(File.exist?("spec/assets/dummy.pdf"))
    expect(File.exist?("spec/assets/dummy.rxl"))
    expect(File.exist?("spec/assets/dummy.xml"))
    expect(File.exist?("spec/assets/dummy.alt.xml"))
    expect(File.exist?("spec/assets/dummy.presentation.xml"))
    expect(File.exist?("spec/assets/dummy.err"))
    Dir["spec/assets/dummy.*"].each { |f| File.delete f }
  end

  it "processes a Metanorma XML ISO document" do
    FileUtils.rm_f %w(spec/assets/test.xml spec/assets/test.html spec/assets/test.alt.html spec/assets/test.doc)
    Metanorma::Compile.new().compile("spec/assets/test.adoc", { type: "iso" } )
    expect(File.exist?("spec/assets/test.xml")).to be true
    FileUtils.rm_f %w(spec/assets/test.html spec/assets/test.alt.html spec/assets/test.doc)
    expect { Metanorma::Compile.new().compile("spec/assets/test.xml") }.not_to output(/Error: Please specify a standard type/).to_stdout
    expect(File.exist?("spec/assets/test.html")).to be true
    html = File.read("spec/assets/test.html", encoding: "utf-8")
    expect(html).to include "ISO copyright office"
  end

  it "extracts isodoc options from asciidoc file" do
    FileUtils.rm_f %w(spec/assets/test.xml spec/assets/test.html spec/assets/test.alt.html spec/assets/test.doc)
    Metanorma::Compile.new().compile("spec/assets/test.adoc", { type: "iso", extension_keys: [:html] } )
    html = File.read("spec/assets/test.html", encoding: "utf-8")
    expect(html).to include "font-family: body-font;"
    expect(html).to include "font-family: header-font;"
    expect(html).to include "font-family: monospace-font;"
  end

  it "wraps HTML output" do
    FileUtils.rm_f %w(spec/assets/test.xml spec/assets/test.html spec/assets/test.alt.html spec/assets/test.doc)
    FileUtils.rm_rf %w(spec/assets/test spec/assets/test.alt)
    Metanorma::Compile.new().compile("spec/assets/test.adoc", { type: "iso", wrapper: true, extension_keys: [:html] } )
    expect(File.exist?("spec/assets/test/test.html")).to be true
  end

  it "data64 encodes images" do
    FileUtils.rm_f %w(spec/assets/test.xml spec/assets/test.html spec/assets/test.alt.html spec/assets/test.doc)
    FileUtils.rm_rf %w(spec/assets/test spec/assets/test.alt)
    Metanorma::Compile.new().compile("spec/assets/test.adoc", { type: "iso", datauriimage: true, extension_keys: [:html] } )
    expect(File.exist?("spec/assets/test.html")).to be true
    html = File.read("spec/assets/test.html", encoding: "utf-8")
    expect(html).to include "data:image"
  end

  it "exports bibdata" do
    FileUtils.rm_f %w(spec/assets/test.xml spec/assets/test.html spec/assets/test.alt.html spec/assets/test.doc)
    FileUtils.rm_f "spec/assets/testrelaton.xml"
    Metanorma::Compile.new().compile("spec/assets/test.adoc", { type: "iso", relaton: "spec/assets/testrelaton.xml", extension_keys: [:xml] } )
    expect(File.exist?("spec/assets/testrelaton.xml")).to be true
    xml = File.read("spec/assets/testrelaton.xml", encoding: "utf-8")
    expect(xml).to include %(<bibdata type="standard">)
  end

  it "exports bibdata, rxl" do
    FileUtils.rm_f %w(spec/assets/test.xml spec/assets/test.html spec/assets/test.alt.html spec/assets/test.doc)
    FileUtils.rm_f "spec/assets/test.rxl"
    Metanorma::Compile.new().compile("spec/assets/test.adoc", { type: "iso", extension_keys: [:rxl] } )
    expect(File.exist?("spec/assets/test.rxl")).to be true
    xml = File.read("spec/assets/test.rxl", encoding: "utf-8")
    expect(xml).to include %(<bibdata type="standard">)
  end

  it "keeps asciimath" do
    FileUtils.rm_f %w(spec/assets/test1.xml spec/assets/test1.html spec/assets/test1.alt.html spec/assets/test1.doc)
    FileUtils.rm_f "spec/assets/test1.rxl"
    Metanorma::Compile.new().compile("spec/assets/test1.adoc", { type: "iso", extension_keys: [:xml] } )
    expect(File.exist?("spec/assets/test1.xml")).to be true
    xml = File.read("spec/assets/test1.xml", encoding: "utf-8")
    expect(xml).not_to include %(<stem type="MathML">)
    expect(xml).to include %(<stem type="AsciiMath">)
  end

  it "exports assets" do
    FileUtils.rm_f %w(spec/assets/test.xml spec/assets/test.html spec/assets/test.alt.html spec/assets/test.doc)
    FileUtils.rm_f "spec/assets/testrelaton.xml"
    FileUtils.rm_rf "spec/assets/extract"
    Metanorma::Compile.new().compile("spec/assets/test.adoc", { type: "iso", extract: "spec/assets/extract", extract_type: [:sourcecode, :image, :requirement], extension_keys: [:xml, :html] } )
    expect(File.exist?("spec/assets/test.xml")).to be true
    expect(File.exist?("spec/assets/extract/sourcecode/sourcecode-0000.txt")).to be true
    expect(File.exist?("spec/assets/extract/sourcecode/sourcecode-0001.txt")).to be false
    expect(File.exist?("spec/assets/extract/sourcecode/a.html")).to be true
    expect(File.read("spec/assets/extract/sourcecode/sourcecode-0000.txt", encoding: "utf-8") + "\n").to eq <<~OUTPUT
def ruby(x)
  if x < 0 && x > 1
    return
  end
end
    OUTPUT
    expect(File.read("spec/assets/extract/sourcecode/a.html", encoding: "utf-8") + "\n").to eq <<~OUTPUT
<html>
  <head>&amp;</head>
</html>
    OUTPUT
    expect(File.exist?("spec/assets/extract/image/image-0000.png")).to be true
    expect(File.exist?("spec/assets/extract/image/image-0001.png")).to be false
    expect(File.exist?("spec/assets/extract/image/img1.png")).to be true
    expect(File.exist?("spec/assets/extract/requirement/requirement-0000.xml")).to be true
    expect(File.exist?("spec/assets/extract/requirement/requirement-0001.xml")).to be false
    expect(File.exist?("spec/assets/extract/requirement/permission-0001.xml")).to be false
    expect(File.exist?("spec/assets/extract/requirement/reqt1.xml")).to be true
  end

  it "warns when no standard type provided" do
    expect { Metanorma::Compile.new().compile("spec/assets/test.adoc", { relaton: "testrelaton.xml" } ) }.to output(/Please specify a standard type/).to_stdout
  end

  it "throw an error when bogus standard type requested" do
    expect do
      Metanorma::Compile.new().
        compile(
          "spec/assets/test.adoc",
          type: "bogus_format",
      )
    end.to output(/loading gem `metanorma-bogus_format` failed/).to_stdout
  end

  it "warns when bogus format requested" do
    expect { Metanorma::Compile.new().compile("spec/assets/test.adoc", { type: "iso", format: "bogus_format" } ) }.to output(/Only source file format currently supported is 'asciidoc'/).to_stdout
  end

  it "warns when bogus extension requested" do
    expect { Metanorma::Compile.new().compile("spec/assets/test.adoc", { type: "iso", extension_keys: [:bogus_format] } ) }.to output(/bogus_format format is not supported for this standard/).to_stdout
  end

  it "rewrites remote include paths" do
    FileUtils.rm_f %w(spec/assets/test2.xml)
    Metanorma::Compile.new().compile("spec/assets/test2.adoc", { type: "iso", extension_keys: [:xml] } )
    expect(File.exist?("spec/assets/test2.xml")).to be true
    xml = File.read("spec/assets/test2.xml", encoding: "utf-8")
    expect(xml).to include "ABC"
  end

  it "processes a Metanorma XML ISO document with CRLF line endings" do
    doc_name = 'test_crlf'
    FileUtils.rm_f Dir["spec/assets/#{doc_name}.*"]

    # convert LF -> CRLF
    doc = "spec/assets/#{doc_name}.adoc"
    line_no = 0
    eol = Gem.win_platform? ? "\n" : "\r\n"
    File.open(doc, "w:UTF-8") do |output|
      File.readlines("spec/assets/test.adoc", chomp: true).each do |line|
        if line_no == 3
          output.write(":mn-document-class: iso#{eol}")
          output.write(":mn-output-extensions: xml,html,doc,rxl#{eol}")
        end
        output.write("#{line}#{eol}")
        line_no += 1
      end
    end

    Metanorma::Compile.new.compile(doc)
    expect(File.exist?("spec/assets/#{doc_name}.xml")).to be true
  end
end
