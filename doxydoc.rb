require 'rubygems'
require 'rdoc' # ensure we're using the gem, not the stdlib
require 'rdoc/rdoc'
require 'rdoc/parser'
require 'tempfile'
require 'hpricot'

class RDoc::Parser::Doxygen < RDoc::Parser

  parse_files_matching(/\.php$/)

  attr_reader :content

  def initialize(top_level, file_name, content, options, stats)
    super

    @path = file_name
    generate_doxyfile
  end

  def scan
    unless system 'doxygen', @doxyfile.path
      puts "`doxygen #{@doxyfile.path}` exited with errors"
      exit
    end
    index = Hpricot(open(File.join(@doxyout,'index.xml')).read)
    (index/'/doxygenindex/compound').each do |compound|
      refid = compound[:refid].to_s
      compounddef = Hpricot(open(File.join(@doxyout, refid+'.xml')).read)
      (compounddef/'/doxygen/compounddef/sectiondef[@kind="func"]/memberdef[@kind="function"]').each do |function|
        name = (function/'name/text()').to_s
        method = RDoc::AnyMethod.new(nil, name)
        @top_level.add_method method
      end
    end

    @top_level
  end

  def generate_doxyfile
    @doxyfile = Tempfile.open('Doxyfile')
    @doxyout = nil
    Tempfile.open('doxygen') do |f|
      @doxyout=f.path
      f.unlink
    end
    Dir.mkdir @doxyout

    input_files = %Q%"#{@path}"%
    xml_output = %Q%"#{@doxyout}"%
    @doxyfile.write ERB.new(open(File.join(File.dirname(__FILE__),'Doxyfile.erb')).read).result(binding)
    @doxyfile.flush
  end

end

if __FILE__ == $0
  r = RDoc::RDoc.new
  r.document %w[wp-includes -o output]
end
