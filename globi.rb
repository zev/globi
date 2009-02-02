#!/usr/env ruby

require 'rubygems'
require 'geoip'
require 'date'

COMMON_FORMAT = /
(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\s+
.*\s+
\[(\d{1,2}\/\w+\/\d{2,4}:\d{2}:\d{2}:\d{2}\s[+-]\d{1,4})\]\s+
"(\w+)\s+(.+)\s+([\w\/\.\\]+)\s*"\s+
(\d{3})\s+(\d+|-)\s+
"(.*)"\s+
"(.*)"
/ixm

base = "./db/"
$geo_city = GeoIP.new(base + 'GeoLiteCity.dat')

class GeoInfo
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

  def kml_placemark(time = nil)
    <<-KML
    <Placemark>
      <name>#{country} : #{region} - #{city}</name>
      <description>#{country} : #{region} - #{city}</description>
      <TimeStamp>#{date}</TimeStamp>
      <styleUrl>#yellowLineGreenPoly</styleUrl>
      <LineString>
        <extrude>1</extrude>
        <tessellate>1</tessellate>
        <coordinates>#{longitude},#{latitude}
        139.701204,35.655614
        </coordinates>
      </LineString>
    </Placemark>
    KML
  end
  
end

def scan(line)
  if m = COMMON_FORMAT.match(line)
    ip = m[1]
    GeoInfo.new( $geo_city.city(ip), parse_date(m[2]) ) 
  else
    nil
  end
end

DATE_FORMAT = '%d/%b/%Y:%H:%M:%S %Z'
def parse_date(date)
  DateTime.strptime(date, DATE_FORMAT) #.to_time
end


def open_kml
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
    <description>iKnow! home</description>
    <Point>
      <coordinates>139.701204,35.655614,0</coordinates>
    </Point>
  </Placemark>
KML
end

def close_kml
<<KML
</Document>
</kml>
KML
end

def kml(io)
  puts open_kml
  io.each_line do |line|
    if geo_info = scan(line)
      puts geo_info.kml_placemark
    end
  end
  puts close_kml
end

def print_scan(io)
  io.each_line do |line|
    if geo_info = scan(line)
      puts geo_info
    end
  end
end


$symbols = ("A".."Z").to_a + ("a".."z").to_a + ('0'..'9').to_a
def google_map(io)
  hits = Hash.new(0)
  io.each_line do |line|
     if geo_info = scan(line)
       hits[geo_info.country_code] += 1
     end
   end
   max = hits.values.max
   min = hits.values.min
   chld = ""
   data = ""
   hits.each do |country, val|
     chld << country
     data << $symbols[(val - min) / max * $symbols.size]
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

if __FILE__ == $0
  io = ARGV.first ? File.new(ARGV.first, "r") : $stdin
  #print_scan(io) 
  #kml(io)
  puts google_map(io)
end