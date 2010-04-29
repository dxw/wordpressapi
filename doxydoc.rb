#!/usr/bin/env ruby

require 'rubygems'
require 'rdoc' # ensure we're using the gem, not the stdlib
require 'rdoc/rdoc'
require 'rdoc/parser'
require 'wpdoc'
require 'tempfile'
require 'nokogiri'

def get_codex_links function
  fnref = []
  tmtag = []
  $codex_index.each do |link|
    fnref << link if link =~ %r[^http://codex.wordpress.org/Function_Reference/#{function}$]
    tmtag << link if link =~ %r[^http://codex.wordpress.org/Template_Tags/#{function}$]
  end

  if fnref.size > 1 or tmtag.size > 1
    p function
    p fnref
    p tmtag
    raise Exception, 'wtf?'
  end

  links = fnref.map {|l| ['Function Reference', l]} + tmtag.map {|l| ['Template Tags', l]}
  links = links.map { |name, link| %Q%<a target="_blank" href="#{link}">#{name}</a>% }.join(' | ')
  links.empty? ? nil : links
end

$codex_index = open('codex_index.txt').read.split("\n")

class RDoc::Parser::Doxygen < RDoc::Parser

  parse_files_matching(/\.php$/)

  attr_reader :content

  include RDoc::RubyToken

  def initialize(top_level, file_name, content, options, stats)
    super

    generate_superdoxy

    @path = file_name
    generate_doxyfile
  end

  def scan
    run_doxygen

    index = Nokogiri::XML(open(File.join(@doxyout,'index.xml')))
    index.xpath('/doxygenindex/compound[@kind!="dir"]').each do |compound|

      refid = compound.xpath('@refid').text
      file = File.join(@@superdoxy, refid+'.xml')
      unless File.exist? file
        file = File.join(@@superdoxy, 'wp-includes_2'+refid+'.xml')
      end

      compounddef = Nokogiri::XML(open(file))
      compounddef.xpath('/doxygen/compounddef').each do |cdef|

        attributes = []
        cdef.xpath('sectiondef/memberdef[@kind="variable"]').each do |attribute|
          name = attribute.xpath('name').text
          next if %w[ else endif endwhile false if return this ].include? name
          attr = RDoc::Attr.new(nil, name, nil, nil)
          attr.comment = attribute.xpath('initializer').text.gsub(/\s+/,' ')
          attributes << attr
        end

        methods = []
        cdef.xpath('sectiondef/memberdef[@kind="function"]').each do |function|
          name = function.xpath('name').text
          method = RDoc::AnyMethod.new(nil, name)
          method.params = function.xpath('argsstring').text.gsub('&amp;','&')
          method.comment = xml_to_rdoc function

          # Source
          method.collect_tokens
          line_no = function.xpath('location/@bodystart').text.to_i
          finish_line = function.xpath('location/@bodyend').text.to_i
          method.add_tokens get_source(@path, line_no, finish_line)

          methods << method
        end

        case cdef.xpath('@kind').text
        when 'file'
          obj = nil
        when 'class'
          name = cdef.xpath('compoundname').text
          obj = find_or_create_class(name)

          # Superclasses
          parent = cdef.xpath('basecompoundref').text
          obj.superclass = parent unless parent.empty?
        when 'namespace'
          puts 'NAMSPOOCE'
          raise Exception, 'arrrN' unless methods.empty?
        when 'dir'
          puts 'DIR'
          raise Exception, 'arrrD' unless methods.empty?
        when 'page'
          puts 'PAIGE'
          raise Exception, 'arrrP' unless methods.empty?
        else
          p cdef
          raise Exception, 'zomg wtf'
        end

        methods.each do |m|
          if obj.nil?
            chr = m.name[0..0].upcase
            chr = '_' unless chr.match /^[A-Z]$/
            obj = find_or_create_global(chr)
            obj.add_method m
            obj = nil
          else
            obj.add_method m
          end
        end
        unless obj.nil?
          attributes.each do |a|
            obj.add_attribute a
          end
        end

      end
    end

    @top_level
  end

  def generate_doxyfile global = false
    @doxyfile = Tempfile.open('Doxyfile')
    @doxyout = nil
    begin
      Tempfile.open('doxygen') do |f|
        @doxyout=f.path
        f.unlink
      end
    rescue NoMethodError
      # Fix for 1.8.6 -> unlink sets @data to nil, which causes problems on exit
    end
    Dir.mkdir @doxyout

    if global
      input_files = 'wp-includes'
    else
      input_files = %Q%"#{@path}"%
    end
    xml_output = %Q%"#{@doxyout}"%
    @doxyfile.write ERB.new(open(File.join(File.dirname(__FILE__),'Doxyfile.erb')).read).result(binding)
    @doxyfile.flush
  end

  def xml_to_rdoc element
    xslt = Nokogiri::XSLT(<<XSLT)
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="text" omit-xml-declaration="yes"/>

  <xsl:template match="/">
<xsl:apply-templates/>
  </xsl:template>

  <xsl:template match="para">
<xsl:text>
</xsl:text>
<xsl:apply-templates/>
<xsl:text>
</xsl:text>
  </xsl:template>

  <xsl:template match="simplesect">
==== <xsl:value-of select="@kind"/>
<xsl:text>
</xsl:text>
<xsl:apply-templates/>
  </xsl:template>

  <xsl:template match="parameterlist">
==== <xsl:value-of select="@kind"/>
<xsl:text>
</xsl:text>
<xsl:apply-templates/>
  </xsl:template>

  <xsl:template match="parameteritem">
[<xsl:value-of select="parameternamelist/parametername"/>] <xsl:apply-templates select="parameterdescription"/>
  </xsl:template>

</xsl:stylesheet>
XSLT
    comment = xslt.transform(element.xpath('detaileddescription').first).text
    comment = comment.split("\n")[1..-1].join("\n").strip # omit-xml-declaration doesn't work
    puts '------------------------------------------------------------------------------'
    puts comment
    puts '------------------------------------------------------------------------------'
    comment
  end

  def find_or_create_class name
    obj = @top_level.class.find_class_named(name)
    unless obj
      obj = @top_level.add_class(RDoc::NormalClass, name)
      obj.superclass = nil
    end
    obj
  end

  def find_or_create_global letter
    global = @top_level.find_module_named('Global')
    unless global
      global = @top_level.add_module(RDoc::NormalModule, 'Global')
      global.comment = 'Global functions have been split up to improve performance.'
    end
    obj = global.find_class_named(letter)
    unless obj
      obj = global.add_class(RDoc::NormalClass, letter)
      obj.superclass = nil
      obj.comment = 'Global functions beginning with '+letter+'.'
    end
    obj
  end

  def generate_superdoxy
    @@superdoxy ||= nil
    if @@superdoxy.nil?
      generate_doxyfile true
      run_doxygen
      @@superdoxy = @doxyout
    end
  end

  def run_doxygen
    unless system 'doxygen', @doxyfile.path
      raise Exception, "`doxygen #{@doxyfile.path}` exited with errors"
    end
  end

  def get_source path, start_line, end_line
    tokens = []

    token = TkCOMMENT.new nil, start_line, 1, "# File #{@top_level.absolute_name}, line #{start_line}"
    tokens << token

    open(path) do |f|
      src = f.read.split("\n")[(start_line-1)...end_line].join("\n")
      token = TkIDENTIFIER.new nil, start_line, 1, "\n"+src
      tokens << token
    end

    tokens
  end

end

class RDoc::AnyMethod
  def geshi code
    php = <<PHP
include("../geshi/geshi.php");
$code = file_get_contents("php://stdin");
$geshi = new GeSHi($code, "php");
echo $geshi->parse_code();
PHP
    IO.popen("php -r '#{php}'", 'r+') do |f|
      f.write(code)
      f.close_write
      out = f.readlines
      out.first.sub!(%r&^<pre[^>]*>&,'')
      out.last.sub!(%r&</pre>$&,'')
      out.join
    end
  end
  def markup_code
    return '' unless @token_stream
    src = ""
    @token_stream.each do |t|
      next unless t
      style = case t
              when RDoc::RubyToken::TkCOMMENT      then "ruby-comment cmt"
              else
                nil
              end

      if t.is_a? RDoc::RubyToken::TkIDENTIFIER
        text = geshi(t.text)
      else
        text = CGI.escapeHTML t.text
      end

      if style
        src << "<span class=\"#{style}\">#{text}</span>"
      else
        src << text
      end
    end

    add_line_numbers src

    src
  end
end

if __FILE__ == $0
  r = RDoc::RDoc.new
  output = 'doc'
  r.document ['README.rdoc', 'wp-includes', '-o', output, '-t', 'WordPress API']
end
