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

      refid = compound.xpath('@refid').text
      compounddef = Nokogiri::XML(open(File.join(@doxyout, refid+'.xml')))
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
    @doxyfile.write ERB.new(open('../Doxyfile.erb').read).result(binding)
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
    comment = comment.split("\n")[1..-1].join("\n") # omit-xml-declaration doesn't work
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

end

if __FILE__ == $0
  r = RDoc::RDoc.new
  wpdir = 'wordpress'
  output = 'doc'
  Dir.chdir wpdir
  r.document ['wp-includes', '-o', "../#{output}"]
end
