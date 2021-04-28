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
$read_html = true
$read_db = true
$read_constraints = true
app_dir = "/Users/junwenyang/Research/ruby_apps/fulcrum"
commits = ["5ca41404f226b43e61cd6a40a4a819f3a101ce00", "36d5748ef00e1442e6c7ca7eb92a02a24206b942"]
versions = commits.map{|commit| Version_class.new(app_dir, commit)}
versions[0].build
versions[0].extract_queries
versions[0].raw_queries.each do |q|
  puts q.stmt
end