require "fileutils"
require "nokogiri"
require "htmlentities"
require "yaml"
require "fontist"
require "fontist/manifest/install"
require_relative "compile_validate"
require_relative "compile_options"
require_relative "fontist_utils"
require_relative "util"
require_relative "sectionsplit"
require_relative "extract"
require_relative "worker_pool"

module Metanorma
  class Compile
    # @return [Array<String>]
    attr_reader :errors, :processor

    def initialize
      @registry = Metanorma::Registry.instance
      @errors = []
      @isodoc = IsoDoc::Convert.new({})
      @fontist_installed = false
    end

    def compile(filename, options = {})
      require_libraries(options)
      options = options_extract(filename, options)
      validate_options(options)
      @processor = @registry.find_processor(options[:type].to_sym)
      extensions = get_extensions(options) or return nil
      (file, isodoc = process_input(filename, options)) or return nil
      relaton_export(isodoc, options)
      extract(isodoc, options[:extract], options[:extract_type])
      font_install(options)
      process_exts(filename, extensions, file, isodoc, options)
    end

    def process_input(filename, options)
      case extname = File.extname(filename)
      when ".adoc" then process_input_adoc(filename, options)
      when ".xml" then process_input_xml(filename, options)
      else
        Util.log("[metanorma] Error: file extension #{extname} " \
                 "is not supported.", :error)
        nil
      end
    end

    def process_input_adoc(filename, options)
      Util.log("[metanorma] Processing: AsciiDoc input.", :info)
      file = read_file(filename)
      options[:asciimath] and
        file.sub!(/^(=[^\n]+\n)/, "\\1:mn-keep-asciimath:\n")
      dir = File.dirname(filename)
      dir != "." and
        file = file.gsub(/^include::/, "include::#{dir}/")
          .gsub(/^embed::/, "embed::#{dir}/")
      [file, @processor.input_to_isodoc(file, filename, options)]
    end

    def process_input_xml(filename, _options)
      Util.log("[metanorma] Processing: Metanorma XML input.", :info)
      # TODO NN: this is a hack -- we should provide/bridge the
      # document attributes in Metanorma XML
      ["", read_file(filename)]
    end

    def read_file(filename)
      File.read(filename, encoding: "utf-8").gsub("\r\n", "\n")
    end

    def relaton_export(isodoc, options)
      return unless options[:relaton]

      xml = Nokogiri::XML(isodoc) { |config| config.huge }
      bibdata = xml.at("//bibdata") || xml.at("//xmlns:bibdata")
      # docid = bibdata&.at("./xmlns:docidentifier")&.text || options[:filename]
      # outname = docid.sub(/^\s+/, "").sub(/\s+$/, "").gsub(/\s+/, "-") + ".xml"
      File.open(options[:relaton], "w:UTF-8") { |f| f.write bibdata.to_xml }
    end

    def export_output(fname, content, **options)
      mode = options[:binary] ? "wb" : "w:UTF-8"
      File.open(fname, mode) { |f| f.write content }
    end

    def wrap_html(options, file_extension, outfilename)
      if options[:wrapper] && /html$/.match(file_extension)
        outfilename = outfilename.sub(/\.html$/, "")
        FileUtils.mkdir_p outfilename
        FileUtils.mv "#{outfilename}.html", outfilename
        FileUtils.mv "#{outfilename}_images", outfilename, force: true
      end
    end

    # isodoc is Raw Metanorma XML
    def process_exts(filename, extensions, file, isodoc, options)
      f = File.expand_path(change_output_dir(options))
      fnames = { xml: f.sub(/\.[^.]+$/, ".xml"), f: f,
                 orig_filename: File.expand_path(filename),
                 presentationxml: f.sub(/\.[^.]+$/, ".presentation.xml") }
      @queue = ::Metanorma::WorkersPool
        .new(ENV["METANORMA_PARALLEL"]&.to_i || 3)
      Util.sort_extensions_execution(extensions).each do |ext|
        process_ext(ext, file, isodoc, fnames, options)
      end
      @queue.shutdown
    end

    def process_ext(ext, file, isodoc, fnames, options)
      fnames[:ext] = @processor.output_formats[ext]
      fnames[:out] = fnames[:f].sub(/\.[^.]+$/, ".#{fnames[:ext]}")
      isodoc_options = get_isodoc_options(file, options, ext)
      thread = nil
      unless process_ext_simple(ext, isodoc, fnames, options,
                                isodoc_options)
        thread = process_exts1(ext, fnames, isodoc, options, isodoc_options)
      end
      thread
    end

    def process_ext_simple(ext, isodoc, fnames, options, isodoc_options)
      if ext == :rxl
        relaton_export(isodoc, options.merge(relaton: fnames[:out]))
      elsif options[:passthrough_presentation_xml] && ext == :presentation
        f = File.exist?(fnames[:f]) ? fnames[:f] : fnames[:orig_filename]
        FileUtils.cp f, fnames[:presentationxml]
      elsif ext == :html && options[:sectionsplit]
        sectionsplit_convert(fnames[:xml], isodoc, fnames[:out],
                             isodoc_options)
      else return false
      end
      true
    end

    def process_exts1(ext, fnames, isodoc, options, isodoc_options)
      if @processor.use_presentation_xml(ext)
        @queue.schedule(ext, fnames.dup, options.dup,
                        isodoc_options.dup) do |a, b, c, d|
          process_output_threaded(a, b, c, d)
        end
      else
        process_output_unthreaded(ext, fnames, isodoc, isodoc_options)
      end
    end

    def process_output_threaded(ext, fnames1, options1, isodoc_options1)
      @processor.output(nil, fnames1[:presentationxml], fnames1[:out], ext,
                        isodoc_options1)
      wrap_html(options1, fnames1[:ext], fnames1[:out])
    rescue StandardError => e
      strict = ext == :presentation || isodoc_options1[:strict] == "true"
      isodoc_error_process(e, strict)
    end

    def process_output_unthreaded(ext, fnames, isodoc, isodoc_options)
      @processor.output(isodoc, fnames[:xml], fnames[:out], ext,
                        isodoc_options)
      nil # return as Thread
    rescue StandardError => e
      strict = ext == :presentation || isodoc_options[:strict] == "true"
      isodoc_error_process(e, strict)
    end

    private

    def isodoc_error_process(err, strict)
      if strict || err.message.include?("Fatal:")
        @errors << err.message
      else
        puts err.message
      end
      puts err.backtrace.join("\n")
    end

    # @param options [Hash]
    # @return [String]
    def change_output_dir(options)
      if options[:output_dir]
        File.join options[:output_dir], File.basename(options[:filename])
      else options[:filename]
      end
    end
  end
end
