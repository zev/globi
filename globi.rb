#!/usr/env ruby

require 'rubygems'
require 'geoip'
require 'date'
require 'optparse'

class Globi
  attr_writer :formatter

  def formatter
    @formatter ||= Globi::PrintFormater.new
  end
  
  def geo_ip
    @geo_ip ||= default_geo_ip
  end
  
  def scan(io)
    formatter.open do |fmt|
      io.each_line do |line|
        if geo_info = scan_line(line)
          fmt.process_entry(geo_info)
        end
      end
    end
  end

  protected

  COMMON_FORMAT = /
  (\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\s+
  .*\s+
  \[(\d{1,2}\/\w+\/\d{2,4}:\d{2}:\d{2}:\d{2}\s[+-]\d{1,4})\]\s+
  "(\w+)\s+(.+)\s+([\w\/\.\\]+)\s*"\s+
  (\d{3})\s+(\d+|-)\s+
  "(.*)"\s+
  "(.*)"
  /ixm
  
  # For now assume scan parses just Apache Common Log Format logs
  def scan_line(line)
    if m = COMMON_FORMAT.match(line)
      ip = m[1]
      GeoInfo.new( geo_ip.city(ip), parse_date(m[2]) ) 
    else
      nil
    end
  end
  
  def default_geo_ip
    geo_db = File.join(File.dirname(__FILE__), "db", 'GeoLiteCity.dat')
    GeoIP.new(base)
  end

  DATE_FORMAT = '%d/%b/%Y:%H:%M:%S %Z'
  def parse_date(date)
    DateTime.strptime(date, DATE_FORMAT) #.to_time
  end

end

class Globi::GeoInfo
  attr_reader :country, :region, :city, :latitude, :longitude, :date, :country_code
    
  def initialize(city_data, date)
    @country_code = city_data[2]
    @country = city_data[4]
    @region = city_data[6]
    @city = city_data[7]
    @latitude = city_data[9]
    @longitude = city_data[10]
    @date = date
  end
  
  def to_s
    "Country: #{country} Region: #{region} City: #{city} Lat: #{latitude} Long: #{longitude}"
  end
  
end

class Globi::Formatter
  attr_writer :output_stream
  
  def output_stream
    @output_stream ||= $stdout
  end
  
  def open
    open_scan
    yield self
  ensure
    close_scan
  end
  
  def process_entry(geo_info)
    output_stream.puts process_geo_entry(geo_info)
  end
  
  def open_scan
    output_stream.puts process_open
  end
  
  def close_scan
    output_stream.puts process_close
  end
  
  protected
  
  # overwrite the following methods
  def process_open
  end
  
  def process_close
  end
  
  def process_geo_entry(geo_info)
  end  
    
end

class Globi::GroupedFormatter < Globi::Formatter
  
  def initialize
    @formatters = []
  end

  def <<(formatrtr)
    @formatters << formatter
  end
  
  def open_scan
    @formatters.each { |f| f.open_scan }
  end
  
  def close_scan
    @formatters.each { |f| f.close_scan }
  end
  
  def process_entry(geo_info)
    @formatters.each { |f| f.process_entry(geo_info) }
  end
  
end

# Simple debug formatter that outputs each geo_info data point
class Globi::PrintFormatter < Globi::Formatter
  def process_geo_entry(geo_info)
    output_stream.puts geo_info
  end
end

# Create a KML XML file suitable for GoogleEarth
class Globi::KMLFormatter < Globi::Formatter
  
  attr_accessor :destination_longitude, :destination_latitude, :destination_name
  
  def process_geo_entry(geo)
    <<-KML
    <Placemark>
      <name>#{geo.country} : #{geo.region} - #{geo.city}</name>
      <description>#{geo.country} : #{geo.region} - #{geo.city}</description>
      <TimeStamp>#{geo.date}</TimeStamp>
      <styleUrl>#yellowLineGreenPoly</styleUrl>
      <LineString>
        <extrude>1</extrude>
        <tessellate>1</tessellate>
        <coordinates>#{geo.longitude},#{geo.latitude}
        139.701204,35.655614
        </coordinates>
      </LineString>
    </Placemark>
    KML
  end
  
  def process_open
    <<KML
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
<Document>
  <name>Web Tokyo</name>
  <description>Web Requests to Tokyo around the world</description>
  <Style id="yellowLineGreenPoly">
    <LineStyle>
      <color>7f00ffff</color>
      <width>4</width>
    </LineStyle>
    <PolyStyle>
      <color>7f00ff00</color>
    </PolyStyle>
  </Style>
  <Placemark>
    <name>iKnow!</name>
    <description>Smar.fm home</description>
    <Point>
      <coordinates>139.701204,35.655614,0</coordinates>
    </Point>
  </Placemark>
KML
  end

  def process_close
    <<KML
</Document>
</kml>
KML
  end

end

# Creates a URL to a google chart with a map of the world where each country
# is colored based on the number of hits it gets
class Globi::GoogleChartFormatter < Globi::Formatter
  
  SYMBOLS = ("A".."Z").to_a + ("a".."z").to_a + ('0'..'9').to_a
  
  def initialize
    @hits = Hash.new(0)
  end

  def process_geo_entry(geo_info)
    @hits[geo_info.country_code] += 1
    nil # don't want output yet
  end

  def process_close
    max = @hits.values.max
    min = @hits.values.min
    chld = ""
    data = ""
    
    @hits.each do |country, val|
      chld << country
      data << SYMBOLS[(val - min) / max * SYMBOLS.size]
    end
    
    query = [
      "cht=t",
      "chs=440x220",
      "chtm=world",
      "chd=s:#{data}",
      "chco=ffffff,f4ed28,f11414",
      "chld=#{chld}",
      "chf=bg,s,EAF7FE"
    ]
    "http://chart.apis.google.com/chart?" + query.join("&")
  end

end

if __FILE__ == $0
  io = $stdin
  globi = Globi.new
  aggregate = Globi::GroupedFormatter.new
  globi.formatter = aggregate

  OptionParser.new do |opts|
    opts.banner = "Usage: #{File.basename(__FILE__)} [options]"
    opts.separator ""

    opts.on("-f", "--formatter Formatter") do |formatter|
      aggregate << const_get("Globi::#{formatter}").new
    end

    opts.on("-i", "--input input_file") do |input|
      io = input == "-" ? $stdin : File.new(input, "r")
    end

  end.parse!(ARGV)

  globi.scan(io)
end