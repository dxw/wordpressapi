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
  links.map! { |name, link| %Q%<a href="#{link}">#{name}</a>% }.join(' | ')
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

          # Source (just File xxx, line n)
          method.collect_tokens
          line_no = function.xpath('location/@bodystart').text.to_i
          token = TkCOMMENT.new nil, line_no, 1
          token.set_text "# File #{@top_level.absolute_name}, line #{line_no}"
          method.add_token token

          methods << method
        end

        case cdef.xpath('@kind').text
        when 'file'
          obj = @top_level
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
          obj.add_method m
        end
        attributes.each do |a|
          obj.add_attribute a
        end

      end
    end

    @top_level
  end

  def generate_doxyfile global = false
    @doxyfile = Tempfile.open('Doxyfile')
    @doxyout = nil
    Tempfile.open('doxygen') do |f|
      @doxyout=f.path
      f.unlink
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
    obj = @top_level.add_class(RDoc::NormalClass, name) unless obj
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

end

if __FILE__ == $0
  r = RDoc::RDoc.new
  output = 'doc'
  r.document ['README.rdoc', 'wp-includes', '-o', output, '-t', 'WordPress API']
end
