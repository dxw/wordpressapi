require 'rubygems'
require 'rdoc' # ensure we're using the gem, not the stdlib
require 'rdoc/rdoc'
require 'rdoc/parser'
require 'tempfile'
require 'nokogiri'

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

    index = Nokogiri::XML(open(File.join(@doxyout,'index.xml')))
    index.xpath('/doxygenindex/compound').each do |compound|

      refid = compound[:refid].to_s
      compounddef = Nokogiri::XML(open(File.join(@doxyout, refid+'.xml')))
      compounddef.xpath('/doxygen/compounddef').each do |cdef|

        attributes = []
        cdef.xpath('sectiondef/memberdef[@kind="variable"]').each do |attribute|
          name = attribute.xpath('name/text()').to_s
          attr = RDoc::Attr.new(nil, name, nil, nil)
          attributes << attr
        end

        methods = []
        cdef.xpath('sectiondef/memberdef[@kind="function"]').each do |function|
          name = function.xpath('name/text()').to_s
          method = RDoc::AnyMethod.new(nil, name)
          method.params = function.xpath('argsstring/text()').to_s.gsub('&amp;','&')
          xslt = Nokogiri::XSLT(<<XSLT)
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="text"/>

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
          comment = xslt.transform(function.xpath('detaileddescription').first).to_s
          method.comment = comment
          methods << method
        end

        case cdef.xpath('@kind').to_s
        when 'file'
          obj = @top_level
        when 'class'
          name = cdef.xpath('compoundname/text()').to_s
          obj = @top_level.class.find_class_named(name)
          obj = @top_level.add_class(RDoc::NormalClass, name) unless obj
        when 'namespace'
          puts 'NAMSPOOCE'
          raise Exception, 'arrrN' if methods.size > 0
        when 'dir'
          puts 'DIR'
          raise Exception, 'arrrD' if methods.size > 0
        when 'page'
          puts 'PAIGE'
          raise Exception, 'arrrP' if methods.size > 0
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
