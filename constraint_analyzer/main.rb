require_relative "./parse_sql.rb"
require_relative "./validate.rb"
require_relative "./parse_model_constraint.rb"
require_relative "./parse_model_metadata.rb"
require_relative "./parse_controller_file.rb"
require_relative "./parse_html_constraint.rb"
require_relative "./parse_db_constraint.rb"
require_relative "./parse_alter_query.rb"
require_relative "./read_files.rb"
require_relative "./class_class.rb"
require_relative "./helper.rb"
require_relative "./version_class.rb"
require_relative "./extract_statistics.rb"
require_relative "./ast_handler.rb"
require_relative "./traverse_db_schema.rb"
require_relative "./parse_concerns.rb"
require_relative "./check_pattern.rb"
require "optparse"
require "yard"
require "active_support"
require "active_support/inflector"
require "active_support/core_ext/string"
require "regexp-examples"
load_validate_api # load the model api
load_html_constraint_api # load the html api

require "/Users/junwenyang/Research/query_constraint_analyzer/query_parser_with_sql.rb"
require "/Users/junwenyang/Research/query_constraint_analyzer/load.rb"
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: main.rb -a APP_DIR [options]"

  opts.on("-a", "--app app", "please specify application dir") do |v|
    options[:app] = v
  end
  opts.on("-c", "--commit commit", "please specify which commit for parse single version (default is master)") do |v|
    options[:commit] = v
  end
  opts.on("-i", "--interval interval", "please specify interval") do |v|
    options[:interval] = v.to_i
  end
  opts.on("-t", "--tva", "whether to traverse all") do |_v|
    options[:tva] = true
    puts "will travese_all_versions"
  end
  opts.on("-s", "--single", "whether to parse single version") do |_v|
    options[:single] = true
  end
  opts.on("-m", "--all_mismatch", "please specify whether you want to find all versions' mismatch") do |_v|
    options[:mismatch] = true
  end
  opts.on("-l", "--latest-version", "please specify that you want to get the current versions breakdown") do |_v|
    options[:latest] = true
  end
  opts.on("--first-last-num", "please specify that you want to compare the first and last verison constraint num") do |_v|
    options[:fln] = true
  end
  opts.on("--commit-unit", "please specify whether using commit as unit") do |_v|
    options[:commit_unit] = true
  end
  opts.on("--api-breakdown", "please specify whether to get the API breakdown") do |_v|
    options[:api_breakdown] = true
  end
  opts.on("--custom-error-msg", "please specify whether to get custom error messages") do |_v|
    options[:custom_error_msg] = true
  end
  opts.on("--curve", "please specify whether you want the curve of # constraints # loc") do |_v|
    options[:curve] = true
  end
  opts.on("--pvf", "please specify whether you want to print the validation functions") do |_v|
    options[:pvf] = true
  end
  opts.on("--commit-hash", "please specify whether you want to get the commit hash") do |_v|
    options[:commit_hash] = true
  end
  opts.on("--count-commits", "please specify whether you want to count the average commits") do |_v|
    options[:count_commits] = true
  end
  opts.on("--count-destory", "please specify whether you want to count the destroy") do |_v|
    options[:destroy] = true
  end
  opts.on("--custom-change", "please specify whether you want to check the custom function") do |_v|
    options[:custom_change] = true
  end
  opts.on("--if-checking", "please specify whether you want to check the custom function") do |_v|
    options[:if_checking] = true
  end
  opts.on("--compare-column-size", "please specify whether you want to compare the column size") do |_v|
    options[:compare_column_size] = true
  end
  opts.on("--dump-constraints filename", "please specify which file to dump all constraints") do |v|
    options[:dump_constraints] = true
    options[:dump_filename] = v
  end
  opts.on("--tschema", "traverse DB schema") do |_|
    options[:tschema] = true
  end
  opts.on("--check", "check errors") do |_|
    options[:check] = true
  end
  opts.on("--cvers version", "which version to check") do |v|
    options[:check_vers] = v
  end
  opts.on("--column Table.column", "which column to check") do |v|
    tab, col = v.split ".", 2
    if tab && col
      options[:check_tab] = tab
      options[:check_col] = col
    end
  end
end.parse!

$read_html = true
$read_db = true
$read_constraints = true

abort("Error: you must specify an application directory with the -a/--app option") unless options[:app]

application_dir = options[:app]

interval = options[:interval] ? options[:interval].to_i : 1
if options[:tva] && interval
  $read_html = false
  puts "travese_all_versions start options[:commit_unit] #{options[:commit_unit]}"
  if options[:commit_unit]
    traverse_all_versions(application_dir, interval, false)
  else
    traverse_all_versions(application_dir, interval, true)
  end
end

if options[:check]
  check_code(application_dir, options[:check_vers] || "master", options[:check_tab], options[:check_col])
end

if options[:tschema]
  $read_html = false
  $read_constraints = false
  traverse_all_for_db_schema(application_dir, options[:interval])
end

extract_table_size_comparison(application_dir, interval) if options[:compare_column_size] && interval

if options[:custom_change] && interval
  puts "traverse to see custom change  options[:commit_unit] #{options[:commit_unit]}"
  if options[:commit_unit]
    traverse_for_custom_validation(application_dir, interval, false)
  else
    traverse_for_custom_validation(application_dir, interval, true)
  end
end

if options[:single]
  if options[:commit]
    find_mismatch_oneversion(options[:app], options[:commit])
  else
    find_mismatch_oneversion(options[:app])
  end
end

if options[:dump_constraints] && options[:dump_filename]
  dump_constraints(options[:app], options[:dump_filename], options[:commit])
end
if options[:mismatch]
  puts "interval parse: #{interval.class.name}"
  find_all_mismatch(options[:app], interval)
end
current_version_constraints_num(application_dir) if options[:latest]
first_last_version_comparison_on_num(application_dir) if options[:fln]
api_breakdown(application_dir) if options[:api_breakdown]
custom_error_msg_info(application_dir) if options[:custom_error_msg]

if options[:curve]
  interval = 100
  puts "interval #{interval}"
  traverse_constraints_code_curve(application_dir, interval, false)
end

if options[:pvf]
  puts "print validation function"
  print_validate_functions(application_dir)
end

puts `cd #{application_dir}; git rev-parse HEAD` if options[:commit_hash]

count_average_commits_between_releases(application_dir) if options[:count_commits]

count_non_destroy(application_dir) if options[:destroy]
if options[:if_checking]
  $read_html = false
  $read_db = false
  $if_output = open("../log/ifcheck.txt", "a")
  version = Version_class.new(application_dir, "master")
  version.build
end
