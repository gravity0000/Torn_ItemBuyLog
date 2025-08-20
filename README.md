# Torn Item Buy Logging and Processing
*Creates a CSV spreadsheat of your purchase history from torn.</br>
*Requires RUBY to be installed.</br>
*Needs at least one package to be installed:</br>
rb install unicode_utils     &nbsp; &nbsp;&nbsp;&nbsp;&nbsp;&nbsp; <--- This is for special characters like: Ç</br>

There are three files:
  1. First, edit then run "itemgather.rb" &nbsp;&nbsp; (This file produces a "item_buys.csv" and it will be updated if the file exists. Feel free to delete and start a fresh file, but it is better to not make the extra api calls. If the log does go to far back for your liking, then you will need to delete the "item_buys.csv" and start fresh.)
  2. Second, after "itemgather.rb" is finished run "itemprc.rb"&nbsp;&nbsp; This script will prompt you for sorting order in Ascending or Descending by: Number purchased, Min Price Bought for, Max price bought for, Average Price Spent, Total Spent per Ithem, Number purchased in the Market, or Number purchased in Bazaars.</br> &nbsp;&nbsp; This will produce your finalized "purchase_summary.csv" that you can open in MS Excel, Google Sheets, or equivalent.)
  4. "names.json" is used by "itemprc.rb" to give item names instead of IDs.

For editing "itemgather.rb":</br>
  1. Api_key= Add your "full" api key
  2. Don't change the catagory number from 15
  3. Limit= 100 items per call(this is the max and best setting for less calls total)
  4. Max calls per day= 5000 You can increase up to 10,000 but I recommend leaving it or lowering it, because you likely won't make that many API calls.
  5. Seconds between calls= 2.5 Should be good for keeping the speed down to 50 api calls per minute, but increase the time if you want it to go slower(less calls per minute).
  6. CSV_File= "item_buys.csv" leave it or the second file won't work.
  7. Pick a UTC timestamp(there are many generators for this on google) that works for you for how far back you want the logs to be from.</br>&nbsp;&nbsp;Example for 2024/1/1 timestamp:   1704096000


Packages used:</br>
  require 'unicode_utils'</br>
  require 'net/http'</br>
  require 'json'</br>
  require 'csv'</br>
  require 'time'</br>
  require 'set'</br>

Please report any issues or questions to Gravity(2131364) in torn or discord.</br> https://www.torn.com/profiles.php?XID=2131364</br> 
https://discordapp.com/users/237708716726550529
