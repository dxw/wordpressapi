require 'rubygems'
require 'rdoc' # ensure we're using the gem, not the stdlib
require 'rdoc/rdoc'
require 'rdoc/parser'
require 'tempfile'

class RDoc::Parser::Doxygen < RDoc::Parser

  parse_files_matching(/\.php$/)

  attr_reader :content

  def initialize(top_level, file_name, content, options, stats)
    super

    @path = file_name
    generate_doxyfile
  end

  def scan
    # method = RDoc::AnyMethod.new(nil, 'the_method')
    # @top_level.add_method method
    @top_level
  end

  def generate_doxyfile
    @doxyfile = Tempfile.open('Doxyfile')
    @doxyout = nil
    Tempfile.open('doxygen') do |f|
      @doxyout=f.path
      f.close
    end

    input_files = %Q%"#{@path}"%
    xml_output = %Q%"#{@doxyout}"%
    @doxyfile.write ERB.new(open(File.join(File.dirname(__FILE__),'Doxyfile.erb')).read).result(binding)
    @doxyfile.flush
  end

end

if __FILE__ == $0
  r = RDoc::RDoc.new
  r.document %w[wp-includes -o output -f darkfish]
end
