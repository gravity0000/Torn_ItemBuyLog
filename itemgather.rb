#!/usr/bin/env ruby
require 'net/http'
require 'json'
require 'csv'
require 'time'
require 'set'

API_KEY = "Place_API_Key_Here" # <-- put your full key
CATEGORY = 15
LIMIT = 100
MAX_CALLS_PER_DAY = 5000
SECONDS_BETWEEN_CALLS = 5
CSV_FILE = "item_buys.csv"
STARTING_TIMESTAMP = 1704096000 # stop when older than this

# ---------------------------
# HTTP: fetch a page of logs
# ---------------------------
def fetch_logs(to_ts)
  url = "https://api.torn.com/v2/user/log?cat=#{CATEGORY}&limit=#{LIMIT}&key=#{API_KEY}"
  url += "&to=#{to_ts}" if to_ts
  res = Net::HTTP.get_response(URI(url))
  raise "HTTP Error #{res.code}" unless res.is_a?(Net::HTTPSuccess)
  JSON.parse(res.body)
end

# ---------------------------------------------------
# Gather backward: only write market/bazaar purchases
# Page based on the FULL batch (not filtered subset)
# ---------------------------------------------------
def gather_backward(to_ts:, start_ts:, existing_ids:, calls:, total_added:)
  new_rows = []

  loop do
    break if calls >= MAX_CALLS_PER_DAY
    break if to_ts && to_ts < start_ts

    data = fetch_logs(to_ts)
    calls += 1
    sleep SECONDS_BETWEEN_CALLS

    batch = data["log"] || []
    # Torn's "empty" page pattern
    break if batch.empty? || (batch.first.is_a?(Hash) && batch.first["id"] == "string")

    # Oldest timestamp of the *entire* batch (for pagination)
    # Determine the time range of this batch for logging
    batch_timestamps = batch.map { |e| e["timestamp"].to_i }
    batch_oldest_ts = batch_timestamps.min
    batch_newest_ts = batch_timestamps.max

    # Filter to purchases we care about, but DO NOT use this for pagination
    purchase_entries = batch.select do |e|
      d = e["details"]
      d && ["Item market buy", "Bazaar buy"].include?(d["title"])
    end

    added_this_page = 0
    purchase_entries.each do |entry|
      ts = entry["timestamp"].to_i
      next if ts < start_ts

      log_id = entry["id"]
      next if existing_ids.include?(log_id)

      # Extract fields (assumes at least one item)
      item = entry.dig("data", "items")&.first
      next unless item # skip malformed rows safely

      category_flag =
        case entry.dig("details", "category")
        when "Item market" then 0
        when "Bazaars"     then 1
        else "" # unknown
        end

      row = [
        ts,
        item["id"],
        item["qty"],
        entry.dig("data", "cost_each"),
        entry.dig("data", "cost_total"),
        category_flag,
        log_id
      ]

      new_rows << row
      existing_ids << log_id
      total_added += 1
      added_this_page += 1
    end

if added_this_page > 0
  last_added_ts = new_rows.last[0]
  puts ""
  puts "Calls made so far: #{calls}"
  puts "Total gathered so far: #{total_added}"
  puts "Batch covered: #{Time.at(batch_newest_ts).utc.strftime('%Y-%m-%d %H:%M')} → #{Time.at(batch_oldest_ts).utc.strftime('%Y-%m-%d %H:%M')}"
  puts "Last entry timestamp: #{Time.at(last_added_ts).utc.strftime('%Y-%m-%d %H:%M')}"
else
  puts ""
  puts "Calls made so far: #{calls} (no new purchases)"
  puts "Batch covered: #{Time.at(batch_newest_ts).utc.strftime('%Y-%m-%d %H:%M')} → #{Time.at(batch_oldest_ts).utc.strftime('%Y-%m-%d %H:%M')}"
end

    # Page backward using the full batch's oldest timestamp
    to_ts = batch_oldest_ts - 1

    # If API returned fewer than LIMIT items, we've reached the end of available logs
    break if batch.size < LIMIT
  end
if new_rows.empty?
    puts ""
    puts "No purchases found between #{Time.at(start_ts).utc.strftime('%Y-%m-%d')} and #{Time.at(to_ts).utc.strftime('%Y-%m-%d')}"
  else
    last_ts = new_rows.last[0]
	puts ""
    puts "Reached end of history. No more purchases before #{Time.at(last_ts).utc}"
  end
  [calls, total_added, new_rows]
end

# ---------------------------
# Load existing CSV (if any)
# ---------------------------
existing_ids = Set.new
existing_rows = []

if File.exist?(CSV_FILE) && File.size?(CSV_FILE)
  CSV.foreach(CSV_FILE, headers: true) do |row|
    existing_rows << row
    existing_ids << row["log_id"]
  end
end

# Compute oldest/newest we already have (robust to any order)
timestamps = existing_rows.map { |r| r["timestamp"].to_i }
oldest_ts  = timestamps.min
newest_ts  = timestamps.max

# ---------------------------
# Run phases
# ---------------------------
calls = 0
total_added = 0
accum_new_rows = [] # arrays: [ts, item_id, qty, cost_each, cost_total, category_flag, log_id]

if newest_ts
  puts "Fetching new entries since #{Time.at(newest_ts).utc.strftime('%Y-%m-%d %H:%M')}"
  calls, total_added, rows = gather_backward(
    to_ts: Time.now.to_i,
    start_ts: newest_ts + 1,           # only newer than what we already have
    existing_ids: existing_ids,
    calls: calls,
    total_added: total_added
  )
  accum_new_rows.concat(rows)
end

if oldest_ts && STARTING_TIMESTAMP < oldest_ts
  # Backfill further into the past (but never before STARTING_TIMESTAMP)
  puts "Backfilling from #{Time.at(STARTING_TIMESTAMP).utc.strftime('%Y-%m-%d %H:%M')} to #{Time.at(oldest_ts - 1).utc.strftime('%Y-%m-%d %H:%M')}"
  calls, total_added, rows = gather_backward(
    to_ts: oldest_ts - 1,
    start_ts: STARTING_TIMESTAMP,
    existing_ids: existing_ids,
    calls: calls,
    total_added: total_added
  )
  accum_new_rows.concat(rows)
end

if existing_rows.empty?
  # Fresh start
  puts "Starting fresh from #{Time.at(STARTING_TIMESTAMP).utc.strftime('%Y-%m-%d %H:%M')}"
  calls, total_added, rows = gather_backward(
    to_ts: Time.now.to_i,
    start_ts: STARTING_TIMESTAMP,
    existing_ids: existing_ids,
    calls: calls,
    total_added: total_added
  )
  accum_new_rows.concat(rows)
end

# -----------------------------------
# Write CSV with newest rows on top
# -----------------------------------
if existing_rows.empty? && accum_new_rows.empty?
  # No data at all — just create header
  CSV.open(CSV_FILE, "w") do |csv|
    csv << ["timestamp", "item_id", "qty", "cost_each", "cost_total", "category_flag", "log_id"]
  end
else
  # Convert existing_rows (CSV::Row) -> arrays (same column order)
  existing_as_arrays = existing_rows.map do |r|
    [
      r["timestamp"].to_i,
      r["item_id"],
      r["qty"],
      r["cost_each"],
      r["cost_total"],
      r["category_flag"],
      r["log_id"]
    ]
  end

  merged = (accum_new_rows + existing_as_arrays)
  # Final safety dedupe by log_id (keep the first occurrence, i.e., newest-first order after sort)
  merged.sort_by! { |row| -row[0].to_i } # newest first
  seen = Set.new
  merged_uniq = merged.reject do |row|
    dup = seen.include?(row[6])
    seen << row[6]
    dup
  end

  CSV.open(CSV_FILE, "w") do |csv|
    csv << ["timestamp", "item_id", "qty", "cost_each", "cost_total", "category_flag", "log_id"]
    merged_uniq.each { |row| csv << row }
  end
end


puts "Finished gathering. Total calls: #{calls}, total new rows added: #{total_added}"
