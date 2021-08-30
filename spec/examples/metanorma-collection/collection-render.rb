require "nokogiri"
require "metanorma-cli"
require "metanorma"
require "isodoc"
require "fileutils"

# This is only going to render the HTML collection
# ARGV[0]: input file
# ARGV[1]: cover page HTML (Liquid template)
# ARGV[2]: output directory
#
# We presuppose that the bibdata of the document is equivalent to that of the collection,
# and that the flavour gem can sensibly process it. We may need to enhance metadata
# in the flavour gems isodoc/metadata.rb with collection metadata

def init
  # @xml is the collection manifest
  @xml = Nokogiri::XML(File.read(ARGV[0], encoding: "utf-8"))
  @lang = @xml&.at(ns("//bibdata/language"))&.text || "en"
  @script = @xml&.at(ns("//bibdata/script"))&.text || "Latn"
  @doctype = doctype
  require "metanorma-#{@doctype}"

  # output processor for flavour
  @isodoc = isodoc

  # list of files in the collection
  @files = read_files
  FileUtils.rm_rf ARGV[2]
  FileUtils.mkdir_p ARGV[2]
end

class Dummy
  def attr(_x); end
end

# The isodoc class for the metanorma flavour we are using
def isodoc
  x = Asciidoctor.load nil, { backend: @doctype.to_sym }
  isodoc = x.converter.html_converter(Dummy.new)
  # read in internationalisation
  isodoc.i18n_init(@lang, @script)
  # create the @meta class of isodoc, with "navigation" set to the index bar extracted from the manifest
  isodoc.metadata_init(@lang, @script,
                       isodoc.labels.merge(navigation: indexfile(@xml.at(ns("//manifest")))))
  # populate the @meta class of isodoc with the various metadata fields native to the flavour;
  # used to populate Liquid
  isodoc.info(@xml, nil)
  isodoc
end

# infer the flavour from the first document identifier; relaton does that
def doctype
  if docid = @xml&.at(ns("//bibdata/docidentifier/@type"))&.text
    doctype = docid.downcase
  elsif docid = @xml&.at(ns("//bibdata/docidentifier"))&.text
    doctype = docid.sub(/\s.*$/, "").lowercase
  else
    return "standoc"
  end
  @registry = Metanorma::Registry.instance
  t = @registry.alias(doctype.to_sym) and return t.to_s
  doctype
end

def ns(xpath)
  IsoDoc::Convert.new({}).ns(xpath)
end

# hash for each document in collection of document identifier to:
# document reference (fileref or id), type of document reference, and bibdata entry for that file
def read_files
  files = {}
  @xml.xpath(ns("//docref")).each do |d|
    identifier = d.at(ns("./identifier")).text
    files[identifier] = (if d["fileref"]
                           { type: "fileref", ref: d["fileref"] }
                         else
                           { type: "id", ref: d["id"] }
                         end)
    file, filename = targetfile(files[identifier], true)
    xml = Nokogiri::XML(file)
    files[identifier][:anchors] = read_anchors(xml)
    files[identifier][:bibdata] = xml.at(ns("//bibdata"))
  end
  files
end

# map locality type and label (e.g. "clause" "1") to id = anchor for a document
def read_anchors(xml)
  ret = {}
  xrefs = @isodoc.xref_init(@lang, @script, @isodoc, @isodoc.labels, {})
  xrefs.parse xml
  xrefs.get.each do |k, v|
    v[:label] && v[:type] or next
    ret[v[:type]] ||= {}
    ret[v[:type]][v[:label]] = k
  end
  ret
end

# populate liquid template of ARGV[1] with metadata extracted from collection manifest
def coverpage
  File.open(File.join(ARGV[2], "index.html"), "w:UTF-8") do |f|
    f.write @isodoc.populate_template(File.read(ARGV[1]))
  end
end

def indexfile_title(m)
  lvl = m&.at(ns("./level"))&.text&.capitalize
  lbl = m&.at(ns("./title"))&.text
  "#{lvl}#{lvl && lbl ? ': ' : ''}#{lbl}"
end

# uses the identifier to label documents; other attributes (title) can be looked up
# in @files[id][:bibdata]
def indexfile_docref(m)
  return "" unless m.at(ns("./docref"))

  ret = "<ul>\n"
  m.xpath(ns("./docref")).each do |d|
    identifier = d.at(ns("./identifier")).text
    link = if d["fileref"]
             d["fileref"].sub(/\.xml$/,
                              ".html")
           else
             d["id"] + ".html"
           end
    ret += "<li><a href='./#{link}'>#{identifier}</a></li>\n"
  end
  ret += "</ul>\n"
  ret
end

# single level navigation list, with hierarchical nesting
# if multiple lists are needed as separate HTML fragments, multiple instances of this function will be needed,
# and associated to different variables in the call to @isodoc.metadata_init (including possibly an array of HTML fragments)
def indexfile(m)
  ret = "<ul>\n"
  ret += "<li>#{indexfile_title(m)}</li>\n"
  ret += indexfile_docref(m)
  m.xpath(ns("./manifest")).each do |d|
    ret += "#{indexfile(d)}\n"
  end
  ret += "</ul>\n"
  ret
end

# return file contents + output filename for each file in the collection, given a docref entry
def targetfile(x, read = false)
  if x[:type] == "fileref"
    [read ? File.read(x[:ref], encoding: "utf-8") : nil,
     x[:ref].sub(/\.xml$/, ".html")]
  else
    [read ? @xml.at(ns("//doc-container[@id = '#{x[:id]}']")).to_xml : nil,
     x["id"] + ".html"]
  end
end

def update_bibitem(b, docid, identifier)
  docid = b&.at(ns("./docidentifier"))&.text
  unless @files[docid]
    warn "Cannot find crossreference to document #{docid} in document #{identifier}!"
    abort
  end
  id = b["id"]
  newbib = b.replace(@files[docid][:bibdata])
  newbib.name = "bibitem"
  newbib["id"] = id
  newbib&.at(ns("./ext"))&.remove
  file, url = targetfile(@files[docid], false)
  newbib.at(ns("./docidentifier")).previous = %{<uri type="citation">#{url}</uri>}
end

def repo_docid(docid)
  docid.sub(%r{^current-metanorma-collection/}, "")
end

# TODO: update crossreferences to other files in the selection
# repo(current-metanorma-collection/ISO 17301-1:2016)
# replaced by
# bibdata of "ISO 17301-1:2016" in situ as bibitem
# Any erefs to that bibitem id are replaced with relative URL
# Preferably with anchor, and is a job to realise dynamic lookup of localities
def update_xrefs(file, identifier)
  docxml = Nokogiri::XML(file)
  docxml.xpath(ns("//bibitem[not(ancestor::bibitem)]")).each do |b|
    next unless docid = b&.at(ns("./docidentifier[@type = 'repository']"))&.text
    next unless %r{^current-metanorma-collection/}.match?(docid)

    update_bibitem(b, docid, identifier)
    update_anchors(b, docxml, docid)
  end
  docxml.to_xml
end

# if there is a crossref to another document, with no anchor, retrieve the
# anchor given the locality, and insert it into the crossref
def update_anchors(b, docxml, _id)
  docid = b&.at(ns("./docidentifier"))&.text
  docxml.xpath("//xmlns:eref[@citeas = '#{docid}']").each do |e|
    e.at(ns(".//locality[@type = 'anchor']")).nil? or next
    ins = e.at(ns("./localityStack")) or next
    type = ins&.at(ns("./locality/@type"))&.text
    ref = ins&.at(ns("./locality/referenceFrom"))&.text
    anchor = @files[docid][:anchors][type][ref] and
      ins << %(<locality type="anchor"><referenceFrom>#{anchor.sub(/^_/,
                                                                   '')}</referenceFrom></locality>)
  end
end

# process each file in the collection
# files are held in memory, and altered as postprocessing
def files
  @files.each do |identifier, x|
    file, filename = targetfile(x, true)
    file = update_xrefs(file, identifier)
    Tempfile.open(["collection", ".xml"], encoding: "utf-8") do |f|
      f.write(file)
      f.close
      warn "metanorma compile -x html #{f.path}"
      system "metanorma compile -x html #{f.path}"
      FileUtils.mv f.path.sub(/\.xml$/, ".html"), File.join(ARGV[2], filename)
    end
  end
end

init
files
coverpage
