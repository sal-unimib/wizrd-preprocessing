#!/usr/bin/ruby

require 'csv'
require 'json'
require 'net/http'

uri = URI('https://api.open-elevation.com/api/v1/lookup')
uri.query = "locations="
uri.freeze

SKIP=0
IN_NAME="rejects.csv"
OUT_NAME="pass3-elev.csv"
REJECT_NAME="pass3-reject.csv"
MAX_TRIES=1
SLEEP_S=2

$schema = {
    id: 0, x1: 1, y1: 2, x2: 3, y2: 4
}

$count = 0

$t_start = Time.now()
at_exit { puts "Processed #{$count} ways in #{(Time.now() - $t_start).round} seconds." }

out = CSV.open(OUT_NAME, "w")
$reject = CSV.open(REJECT_NAME, "w")

def spin(i)
    chars = ['|', '/', '-', '\\']
    printf("%s\b", chars[i % 4])
    return i+1
end

def lookup(uri, row, tries = 0)
    begin
        tries = tries + 1
        return JSON::parse(Net::HTTP.get(uri))
    rescue Exception => e
        puts "\nGot a #{e.class}; reason: #{e.message}"
        if tries >= MAX_TRIES
            puts "Maximum retries exceeded for: #{uri}"
            puts "Rejecting way #{row[$schema[:id]]}"
            $reject << row
            return nil
        end
        puts "Retrying in #{SLEEP_S*tries} seconds (#{tries}/#{MAX_RETRIES})."
        sleep(SLEEP_S*tries)
        return lookup(uri, row, tries)
    end
end

CSV.foreach(IN_NAME) do |row|
    id = row[$schema[:id]]
    # assume records are ORDERed BY id ASC
    next if Integer(id) <= SKIP
    _uri = uri.dup
    _uri.query += "#{row[$schema[:y1]]},#{row[$schema[:x1]]}|#{row[$schema[:y2]]},#{row[$schema[:x2]]}"
    req = lookup(_uri, row)
    unless req.nil?
        out_row = []
        out_row.push(id)
        req["results"].each do |req|
            out_row.push(req["elevation"].floor)
        end
        out << out_row
    end
    printf("  %4d\b\b\b\b\b\b", id)
    $count = spin($count)
end

exit(true)