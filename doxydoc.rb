require 'rubygems'
require 'rdoc' # ensure we're using the gem, not the stdlib
require 'rdoc/rdoc'
require 'rdoc/parser'

class RDoc::Parser::Doxygen < RDoc::Parser

  parse_files_matching(/\.php$/)

  attr_reader :content

  def initialize(top_level, file_name, content, options, stats)
    super

    @path = file_name
  end

  def scan
    # method = RDoc::AnyMethod.new(nil, 'the_method')
    # @top_level.add_method method
    @top_level
  end

end

if __FILE__ == $0
  r = RDoc::RDoc.new
  r.document %w[wp-includes -o output -f darkfish]
end
