require 'rubygems'
require 'rdoc' # ensure we're using the gem, not the stdlib
require 'rdoc/rdoc'
require 'rdoc/parser'

class RDoc::Parser::Doxygen < RDoc::Parser

  parse_files_matching(/\.php$/)

  attr_reader :content

  def initialize(top_level, file_name, content, options, stats)
    super

    preprocess = RDoc::Markup::PreProcess.new @file_name, @options.rdoc_include

    preprocess.handle @content do |directive, param|
      top_level.metadata[directive] = param
      false
    end
  end

  def scan
    p 'scanning'
    p @top_level
    @top_level
  end

end

if __FILE__ == $0
  r = RDoc::RDoc.new
  r.document(%w[category.php -o output])
end
