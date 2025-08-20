require 'csv'
require 'json'
require 'unicode_utils'

INPUT_FILE = "item_buys.csv"       # Gathered CSV
NAMES_FILE = "names.json"          # JSON mapping IDs to names
OUTPUT_FILE = "purchase_summary.csv"

# Load item names from JSON
name_data = JSON.parse(File.read(NAMES_FILE))
id_to_name = {}
name_data["items"].each do |item|
  id_to_name[item["id"].to_s] = item["name"]
end

# Data structure per item:
# { item_id => {purchased:, min:, max:, spent:, market:, bazaar:} }
stats = Hash.new { |h, k| h[k] = { purchased: 0, min: Float::INFINITY, max: 0, spent: 0.0, market: 0, bazaar: 0 } }

CSV.foreach(INPUT_FILE, headers: true) do |row|
  item_id = row['item_id']
  qty = row['qty'].to_i
  cost_each = row['cost_each'].to_f
  category_flag = row['category_flag']

  s = stats[item_id]

  # Update stats
  s[:purchased] += qty
  s[:min] = [s[:min], cost_each].min
  s[:max] = [s[:max], cost_each].max
  s[:spent] += cost_each * qty

  # Update category counts
  case category_flag.to_s
  when "0"
    s[:market] += qty
  when "1"
    s[:bazaar] += qty
  end
end

# Helper to compute average
def avg_price(s)
  s[:purchased] > 0 ? (s[:spent] / s[:purchased]) : 0
end

puts "Press a Key for Sorting or Enter for Name:"
puts "1 = # Purchased"
puts "2 = Min Price"
puts "3 = Max Price"
puts "4 = Av. Price"
puts "5 = Total $ Spent"
puts "6 = Market Purchased"
puts "7 = Bazaar Purchased"
puts "8 = Name"
print "> "
choice = STDIN.gets.strip

sort_key = case choice
when "1" then "purchased"
when "2" then "min"
when "3" then "max"
when "4" then "avg"
when "5" then "spent"
when "6" then "market"
when "7" then "bazaar"
when "8" then "name"
else "name" # default
end

puts "Ascending or Descending? (press 'a' for Ascending, anything else for Descending)"
print "> "
dir_choice = STDIN.gets.strip.downcase
sort_dir = dir_choice == "a" ? :asc : :desc

# --- Confirmation Printout ---
dir_text = sort_dir == :asc ? "ascending" : "descending"
puts
puts "Sorting by #{sort_key.capitalize} (#{dir_text})"

# --- Sorting logic ---
sorted_stats = stats.sort_by do |item_id, s|
  case sort_key
  when "purchased" then s[:purchased]
  when "min"       then (s[:min] == Float::INFINITY ? 0 : s[:min])
  when "max"       then s[:max]
  when "avg"       then avg_price(s)
  when "spent"     then s[:spent]
  when "market"    then s[:market]
  when "bazaar"    then s[:bazaar]
  when "name"      then id_to_name[item_id.to_s] || item_id
    name = id_to_name[item_id.to_s] || item_id
	UnicodeUtils.nfkd(name).gsub(/\p{Mn}/, '').downcase
  else s[:purchased]
  end
end

# Reverse if descending
sorted_stats.reverse! if sort_dir == :desc

# --- Write summary CSV ---
CSV.open(OUTPUT_FILE, "w") do |csv|
  csv << ["Item Name/ID", "Total Purchased", "Min Price", "Max Price", "Average Price", "Total Spent", "Market Purchases", "Bazaar Purchases"]
  
  sorted_stats.each do |item_id, s|
    name = id_to_name[item_id.to_s] || item_id
    csv << [
      name,
      s[:purchased],
      s[:min] == Float::INFINITY ? 0 : s[:min],
      s[:max],
      avg_price(s).round(2),
      s[:spent].round(2),
      s[:market],
      s[:bazaar]
    ]
  end
end

puts "Processing complete. Sorted by #{sort_key} (#{sort_dir}). Summary written to #{OUTPUT_FILE}."