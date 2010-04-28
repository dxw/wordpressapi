#!/usr/bin/env ruby

require 'rubygems'
require 'nokogiri'
require 'open-uri'

class ExtractCodex
  def initialize
    @index = []
  end

  def run
    uri = 'http://codex.wordpress.org/Special:PrefixIndex'
    while uri
      # Read page
      h = Nokogiri::HTML(open(uri))
      # Extract list of pages
      h.xpath('//*[@id="mw-prefixindex-list-table"]//a/@href').each do |e|
        @index << URI.join(uri,e.text)
      end
      # uri = URI.join(uri,next)
      next_page = h.xpath('//*[@id="mw-prefixindex-nav-form"]//a[starts-with(text(),"Next page")]/@href').first
      if next_page
        uri = URI.join(uri,next_page.text).to_s
      else
        uri = nil
      end
      # Start over
    end

    @index
  end
end

if __FILE__ == $0
  open('codex_index.txt','w+') do |f|
    ExtractCodex.new.run.each do |l|
      f.puts l
    end
  end
end
