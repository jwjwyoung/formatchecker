require File.join(File.expand_path(File.dirname(__FILE__)), "../constraint_analyzer/parse_sql.rb")
require File.join(File.expand_path(File.dirname(__FILE__)), "../constraint_analyzer/validate.rb")
require File.join(File.expand_path(File.dirname(__FILE__)), "../constraint_analyzer/parse_model_constraint.rb")
require File.join(File.expand_path(File.dirname(__FILE__)), "../constraint_analyzer/parse_model_metadata.rb")
require File.join(File.expand_path(File.dirname(__FILE__)), "../constraint_analyzer/parse_controller_file.rb")
require File.join(File.expand_path(File.dirname(__FILE__)), "../constraint_analyzer/parse_html_constraint.rb")
require File.join(File.expand_path(File.dirname(__FILE__)), "../constraint_analyzer/parse_db_constraint.rb")
require File.join(File.expand_path(File.dirname(__FILE__)), "../constraint_analyzer/parse_alter_query.rb")
require File.join(File.expand_path(File.dirname(__FILE__)), "../constraint_analyzer/read_files.rb")
require File.join(File.expand_path(File.dirname(__FILE__)), "../constraint_analyzer/class_class.rb")
require File.join(File.expand_path(File.dirname(__FILE__)), "../constraint_analyzer/helper.rb")
require File.join(File.expand_path(File.dirname(__FILE__)), "../constraint_analyzer/version_class.rb")
require File.join(File.expand_path(File.dirname(__FILE__)), "../constraint_analyzer/extract_statistics.rb")
require File.join(File.expand_path(File.dirname(__FILE__)), "../constraint_analyzer/ast_handler.rb")
require "optparse"
require "yard"
require "active_support"
require "active_support/inflector"
require "active_support/core_ext/string"
require "regexp-examples"
load_validate_api # load the model api
load_html_constraint_api #load the html api
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: main.rb -a APP_DIR [options]"

  opts.on("-a", "--app app", "please specify application dir") do |v|
    options[:app] = v
    puts "v #{v}"
  end
  opts.on("-c", "--commit commit", "please specify which commit for parse single version (default is master)") do |v|
    options[:commit] = v
  end
  opts.on("-i", "--interval interval", "please specify interval") do |v|
    options[:interval] = v.to_i
  end
  opts.on("-t", "--tva", "whether to traverse all") do |v|
    options[:tva] = true
    puts "will travese_all_versions"
  end
  opts.on("-s", "--single", "whether to parse single version") do |v|
    options[:single] = true
  end
  opts.on("-m", "--all_mismatch", "please specify whether you want to find all versions' mismatch") do |v|
    options[:mismatch] = true
  end
  opts.on("-l", "--latest-version", "please specify that you want to get the current versions breakdown") do |v|
    options[:latest] = true
  end
  opts.on("--first-last-num", "please specify that you want to compare the first and last verison constraint num") do |v|
    options[:fln] = true
  end
  opts.on("--commit-unit", "please specify whether using commit as unit") do |v|
    options[:commit_unit] = true
  end
  opts.on("--api-breakdown", "please specify whether to get the API breakdown") do |v|
    options[:api_breakdown] = true
  end
  opts.on("--custom-error-msg", "please specify whether to get custom error messages") do |v|
    options[:custom_error_msg] = true
  end
  opts.on("--curve", "please specify whether you want the curve of # constraints # loc") do |v|
    options[:curve] = true
  end
  opts.on("--pvf", "please specify whether you want to print the validation functions") do |v|
    options[:pvf] = true
  end
  opts.on("--commit-hash", "please specify whether you want to get the commit hash") do |v|
    options[:commit_hash] = true
  end
  opts.on("--count-commits", "please specify whether you want to count the average commits") do |v|
    options[:count_commits] = true
  end  
  opts.on("--count-destory", "please specify whether you want to count the destroy") do |v|
    options[:destroy] = true
  end
  opts.on("--custom-change", "please specify whether you want to check the custom function") do |v|
    options[:custom_change] = true
  end
  opts.on("--if-checking", "please specify whether you want to check the custom function") do |v|
    options[:if_checking] = true
  end
  
end.parse!

$read_html = true
$read_db = true

if !options[:app]
  abort("Error: you must specify an application directory with the -a/--app option")
end

application_dir = options[:app]
puts "application_dir #{application_dir}"

interval = 1
if options[:interval]
  interval = options[:interval].to_i
end
if options[:tva] and interval
  $read_html = false
  puts "travese_all_versions start options[:commit_unit] #{options[:commit_unit]}"
  if options[:commit_unit]
    traverse_all_versions(application_dir, interval, false)
  else
    traverse_all_versions(application_dir, interval, true)
  end
end

if options[:custom_change] and interval
  puts "traverse to see custom change  options[:commit_unit] #{options[:commit_unit]}"
  if options[:commit_unit]
    traverse_for_custom_validation(application_dir, interval, false)
  else
    traverse_for_custom_validation(application_dir, interval, true)
  end
end

if options[:single]
  $read_html = false
  if options[:commit]
    find_mismatch_oneversion(options[:app], options[:commit])
  else
    find_mismatch_oneversion(options[:app])
  end
end
if options[:mismatch]
  puts "interval parse: #{interval.class.name}"
  find_all_mismatch(options[:app], interval)
end
if options[:latest]
  current_version_constraints_num(application_dir)
end
if options[:fln]
  first_last_version_comparison_on_num(application_dir)
end
if options[:api_breakdown]
  api_breakdown(application_dir)
end
if options[:custom_error_msg]
  custom_error_msg_info(application_dir)
end

if options[:curve]
  interval = 100
  puts "interval #{interval}"
  traverse_constraints_code_curve(application_dir, interval, false)
end

if options[:pvf]
  puts "print validation function"
  print_validate_functions(application_dir)
end

if options[:commit_hash]
  puts `cd #{application_dir}; git rev-parse HEAD`
end

if options[:count_commits]
  count_average_commits_between_releases(application_dir)
end

if options[:destroy]
  count_non_destroy(application_dir)
end
if options[:if_checking]
  $read_html = false
  $read_db = false
  $if_output = open("../log/ifcheck.txt", "a")
  version = Version_class.new(application_dir, "master")
  version.build
end
