#!/usr/bin/ruby

require 'csv'
require 'json'
require 'net/http'

uri = URI('https://api.open-elevation.com/api/v1/lookup')
uri.query = "locations="
uri.freeze

SKIP = 0
IN_NAME = "ways.csv"
OUT_NAME = "elev.csv"
REJECT_NAME = "rejects.csv"
MAX_TRIES = 3
SLEEP_S = 2
THROTTLE_S = 0.25

$schema = {
    id: 0, x1: 1, y1: 2, x2: 3, y2: 4
}

$count = 0

$t_start = Time.now()
at_exit { puts "Processed #{$count} ways in #{(Time.now() - $t_start).round} seconds" }

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
        sleep(THROTTLE_S) if THROTTLE_S > 0
        return JSON::parse(Net::HTTP.get(uri))
    rescue Interrupt => i
        puts "\nInterrupted at #{row[$schema[:id]]}\nPress any key to continue, Ctrl-C again to exit"
        begin 
            gets
        rescue Interrupt
            exit(true)
        else
            puts "Continuing from #{row[$schema[:id]]}"
            return lookup(uri, row, tries - 1)
        end
    rescue Exception => e
        puts "\nGot a #{e.class}; reason: #{e.message}"
        if tries >= MAX_TRIES
            puts "Maximum retries exceeded for: #{uri}"
            puts "Rejecting way #{row[$schema[:id]]}"
            $reject << row
            return nil
        end
        puts "Retrying in #{SLEEP_S*tries} seconds (#{tries}/#{MAX_TRIES})"
        sleep(SLEEP_S*tries)
        return lookup(uri, row, tries)
    end
end

CSV.foreach(IN_NAME) do |row|
    id = row[$schema[:id]]
    printf("  %4d\b\b\b\b\b\b", id)
    $count = spin($count)
    # assume records are ORDERed BY id ASC
    next if Integer(id) <= SKIP
    _uri = uri.dup
    _uri.query += "#{row[$schema[:y1]]},#{row[$schema[:x1]]}|#{row[$schema[:y2]]},#{row[$schema[:x2]]}"
    out_row = []
    out_row.push(id)
    res = lookup(_uri, row)
    unless res.nil?
        begin
            res["results"].each do |res|
                out_row.push(res["elevation"].floor)
            end
        rescue Exception
            puts "Unxepected result"
            puts "Request: #{uri}"
            puts "Body: #{JSON.pretty_generate(res)}"
            exit(false)
        end
    else
        out_row.push(0)
        out_row.push(0)
    end
    out << out_row
end

exit(true)