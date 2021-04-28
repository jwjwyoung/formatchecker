require "rubygems"
require "write_xlsx"
require "date"
require "yaml"
# Create a new Excel workbook
def write_to_sheet(worksheet, api_data, format)
  # puts "api_data #{api_data.size}"
  (0...api_data.size).each do |row|
    contents = api_data[row]
    # puts "contents : #{contents.size}"
    (0...contents.length).each do |col|
      # puts "contents[col #{contents[col]}"
      worksheet.write(row, col, contents[col], format)
    end
  end
end

def count_average_commits_between_releases(directory)
  tags = `cd #{directory}; git tag -l --sort version:refname`
  app_name = directory.split("/")[-1]
  commits = tags.lines.reverse.map(&:strip)
  if commits&.length > 10
    f = open("../log/#{app_name}_commits.txt", "w")
    v1 = commits[0]
    total = 0
    cnt = 0
    sizes = []
    (1...commits.length).each do |i|
      v2 = commits[i]
      csize = `cd #{directory}; git log --pretty=oneline ^#{v2} #{v1}`.lines.size
      f.write("#{v2} #{v1} #{csize}\n")
      v1 = v2
      total += csize
      sizes << csize
      cnt += 1
    end
    average = 0
    average = total / cnt if cnt > 0
    f.write("average: #{average} median: #{median(sizes)}\n")
    f.close
  end
end

def median(array)
  ascend = array.sort
  length = array.length
  if length.odd?
    ascend[(length + 1) / 2.0]
  else
    (ascend[length / 2.0] + ascend[(length + 2) / 2.0]) / 2.0
  end
end

def extract_commits(directory, interval = nil, tag_unit = true, branch='master')
  # reset to the most up to date commit
  `git -C '#{directory}' checkout -fq #{branch}`

  tags = `git -C '#{directory}' for-each-ref --format '%(refname)' refs/tags | ./sort-versions.py`
  unless $CHILD_STATUS.success?
    raise "command for getting tags failed"
  end

  # app_version_size = { "discourse" => "316", "lobsters" => "19", "gitlabhq" => "1040", "redmine" => "159",
  #                      "spree" => "261", "ror_ecommerce" => "31", "fulcrum" => "7", "tracks" => "26",
  #                      "onebody" => "39", "diaspora" => "86", "falling-fruit" => "12",
  #                      "openstreetmap-website" => "95" }
  # app_name = directory.split("/")[-1]
  # version_size = app_version_size[app_name].to_i
  commits = tags.lines.reverse.map(&:strip) if tag_unit
  if !commits || commits.length < 10
    commits = `git -C '#{directory}' log --format=format:%H`.lines
    # default interval to 100
    interval = interval.nil? ? 100 : interval
  else
    interval = 1
  end
  versions = []
  i = 0
  commits.each do |commit|
    if i % interval == 0
      version = Version_class.new(directory, commit)
      # version.build
      versions << version if version
    end
    i += 1
  end
  # For applications not in `app_version_size.keys`, it's `version_size` is zero,
  # so don't chop the versions here.
  # versions = versions.reverse[0...version_size].reverse unless version_size.zero?
  #versions[0..300]
  return versions
end

def get_tags_before_certain_date(commit, directory)
  tags = `cd #{directory}; git for-each-ref --sort version:refname --format="%(refname:short) | %(creatordate)" refs/tags/*`
  tags = tags.lines.map { |x| x.strip.split("|") }
  tags = tags&.map { |a1, a2| [a1, Date.parse(a2).to_date] }
  commit_time_str = `cd #{directory};  git show -s --format=%ci #{commit}`
  commit_time = Date.parse(commit_time_str).to_date
  puts "tags #{tags.size}"
  tags.select { |_a1, a2| a2 <= commit_time }.map { |a1, _a2| a1 }
end

def current_version_constraints_num(application_dir, commit = "master")
  `cd #{application_dir}; git checkout -f #{commit}`
  version = Version_class.new(application_dir, commit)
  version.build
  version.column_stats
  total_constraints = version.activerecord_files.map { |_k, v| v.getConstraints.map { |_k1, v1| v1 } }.reduce(:+)
  tables = total_constraints.select { |v| v.type == Constraint::DB }.group_by(&:table)
  tables.each do |table, tables|
    puts "table #{table} #{tables.size}"
    puts tables[0].to_string.to_s unless tables.empty?
  end
  commit_hash = `cd #{application_dir}; git rev-parse HEAD`
  puts "commit_hash: #{commit_hash}"
  puts "Latest Version Constraint Breakdown: #{version.loc} #{version.total_constraints_num} #{version.db_constraints_num} #{version.model_constraints_num} #{version.html_constraints_num} columnstats: #{version.column_stats}"
end

def print_validate_functions(application_dir, commit = "master")
  `cd #{application_dir}; git checkout -f #{commit}`
  version = Version_class.new(application_dir, commit)
  version.build
  contents = version.print_validate_functions
  app = application_dir.gsub("/", "_")
  app_name = application_dir.split("/")[-1]
  output = open("../log/validation_functions#{app_name}.log", "w")
  output.write(contents)
  output.close
end

def first_last_version_comparison_on_num(application_dir)
  `cd #{application_dir}; git stash; git checkout -f master`
  versions = extract_commits(application_dir, 1, false)
  app_name = application_dir.split("/")[-1]

  if versions.length <= 0
    puts "No versions"
    return
  end
  version0 = versions[0]
  version1 = versions[-1]
  version0.build
  version0.column_stats
  version1.build
  version1.column_stats
  puts "Latest Version Constraint Breakdown: #{version0.total_constraints_num} #{version0.db_constraints_num} #{version0.model_constraints_num} #{version0.html_constraints_num}"
  puts "First Version Constraint Breakdown: #{version1.total_constraints_num} #{version1.db_constraints_num} #{version1.model_constraints_num} #{version1.html_constraints_num}"
  output_c = "Latest Column #{version0.column_stats}\n"
  output_c += "First Column #{version1.column_stats}\n"
  output = open("../log/output_column_stats_#{app_name}.log", "w")
  output.write(output_c)
  output.close
end

def api_breakdown(application_dir)
  commit = "master"
  app_name = application_dir.split("/")[-1]
  output = open("../log/api_breakdown_#{app_name}.log", "w")
  # `cd #{application_dir}; git checkout -f #{commit}`
  # version = Version_class.new(application_dir, commit)
  # `cd #{application_dir}; git stash; git pull; git checkout master`
  `cd #{application_dir}; git stash;  git checkout -f master`
  version = Version_class.new(application_dir, commit)

  # versions = extract_commits(application_dir, 1, false)
  # if versions.length <= 0
  #   puts "No versions"
  #   return
  # end
  # version = versions[0]
  version.build
  db_constraints = version.getDbConstraints
  model_constraints = version.getModelConstraints
  html_constraints = version.getHtmlConstraints

  # get all types of constraints
  constraint_classes = Constraint.descendants
  db_dic = api_type_breakdown(db_constraints)
  model_dic = api_type_breakdown(model_constraints)
  html_dic = api_type_breakdown(html_constraints)
  # output the result to log file
  commit_hash = `cd #{application_dir}; git rev-parse HEAD`
  output.write("commit_hash #{commit_hash}")
  output.write("=======START BREAKDOWN of API\n")
  output.write("constraint_type #db #model #html\n")
  output.write("Layer_breakdown: #{version.total_constraints_num} #{version.db_constraints_num} #{version.model_constraints_num} #{version.html_constraints_num}\n")
  output.write("constraint_type #{version.total_constraints_num} #{db_constraints.size} #{model_constraints.size} #{html_constraints.size}\n")
  constraint_classes.each do |constraint_class|
    output.write("#{constraint_class} #{db_dic[constraint_class]} #{model_dic[constraint_class]} #{html_dic[constraint_class]}\n")
  end
  output.write("=======FINISH BREAKDOWN of API\n")
  output.close
end

def custom_error_msg_info(application_dir)
  commit = "master"
  `cd #{application_dir}; git checkout -f #{commit}`
  version = Version_class.new(application_dir, commit)
  version.build
  model_cons = version.getModelConstraints
  custom_error_msg_cons = model_cons.select { |c| c and c.custom_error_msg == true }
  built_in_cons = model_cons.select { |c| c and !(c.is_a? Customized_constraint or c.is_a? Function_constraint) }
  puts "============ CUSTOM ERROR MSG"
  puts "custom error msg count: #{custom_error_msg_cons.length}"
  puts "total model built-in count: #{built_in_cons.length}"
  puts "total model constraint count: #{model_cons.length}"
end

def api_type_breakdown(constraints)
  num_dic = {}
  constraint_classes = Constraint.descendants
  constraint_classes.each do |c|
    num_dic[c] = 0
  end
  constraints&.each do |c|
    c_class = c.class
    num_dic[c_class] = 1 unless num_dic[c_class]
    num_dic[c_class] += 1
  end
  num_dic
end

def total_number_comparison(application_dir, commit = "master")
  `cd #{application_dir}; git checkout -f #{commit}`
  version = Version_class.new(application_dir, commit)
  version.build
  puts "Latest Version Constraint Breakdown: #{version.total_constraints_num} #{version.db_constraints_num} #{version.model_constraints_num} #{version.html_constraints_num}"
end

def traverse_constraints_code_curve(application_dir, interval, tag_unit = true)
  versions = extract_commits(application_dir, interval, tag_unit)
  puts "versions.length: #{versions.length}"
  return if versions.length <= 0

  app_name = application_dir.split("/")[-1]
  output = open("../log/output_loc_constraints_#{app_name}.log", "w")
  (0...versions.length).each do |i|
    version = versions[i]
    version.build
    content = "#{version.loc} #{version.total_constraints_num} #{version.db_constraints_num} #{version.model_constraints_num} #{version.html_constraints_num}\n"
    output.write(content)
  end
  output.close
end

def traverse_for_custom_validation(application_dir, interval, tag_unit = true)
  $read_db = false
  $read_html = false
  versions = extract_commits(application_dir, interval, tag_unit)
  puts "versions.length: #{versions.length}"
  return if versions.length <= 0

  app_name = application_dir.split("/")[-1]
  versions[0].build
  output_customchange = open("../log/customchange_#{app_name}.log", "w")
  c1 = c2 = c3 = c4 = 0
  s1 = s2 = s3 = s4 = 0
  results = []
  (1...versions.length).each do |i|
    new_version = versions[i - 1]
    version = versions[i]
    version.build
    cf, af, df = new_version.compare_custom_constriants(version)
    s1 += cf.size
    s2 += af.size
    s3 += df.size
    results += cf.map { |_k, v| [version.commit, new_version.commit, v[0].source, v[1].source] }
    results += af.map { |_k, v| [version.commit, new_version.commit, "", v.source] }
    results += df.map { |_k, v| [version.commit, new_version.commit, v.source, ""] }
    c1 += 1 unless cf.empty?
    c2 += 1 unless af.empty?
    c3 += 1 unless df.empty?
    c4 += 1 if !cf.empty? || !af.empty? || !df.empty?
  end
  s4 = s1 + s2 + s3
  contents = "#{versions.length} #{c1} #{c2} #{c3} #{c4}\n"
  contents += "#{versions.length} #{s1} #{s2} #{s3} #{s4}\n"
  puts contents
  output_customchange.write(contents)
  output_customchange.close

  workbook = WriteXLSX.new("../output/compare-custom-#{app_name}.xlsx")
  format = workbook.add_format
  worksheet = workbook.add_worksheet("compare")
  format.set_align("left")
  write_to_sheet(worksheet, results, format)
  workbook.close
end

def traverse_all_versions(application_dir, interval, tag_unit = true)
  versions = extract_commits(application_dir, interval, tag_unit)
  puts "versions.length: #{versions.length}"
  return if versions.length <= 0

  app_name = application_dir.split("/")[-1]
  version_his_folder = "../log/vhf_#{app_name}/"
  Dir.mkdir(version_his_folder) unless File.exist? version_his_folder
  build_version(version_his_folder, versions[0])
  versions[0] = load_version(version_his_folder, versions[0])
  output = open("../log/output_#{app_name}.log", "w")
  output_diff_codechange = open("../log/codechange_#{app_name}.log", "w")
  log_dir = "../log/#{app_name}_log/"
  version = versions[0]
  content = "#{version.loc} #{version.total_constraints_num} #{version.db_constraints_num} #{version.model_constraints_num} #{version.html_constraints_num}\n"
  output_diff_codechange.write(content)
  Dir.mkdir(log_dir) unless File.exist? log_dir
  output_html_constraints = File.open("#{log_dir}/html_constraints.log", "w")
  cnt = 0
  sum1 = sum2 = sum3 = sum4 = sum5 = sum6 = sum7 = sum8 = sumh1 = sumh2 = sumh3 = sumh4 = 0
  count1 = count2 = count3 = count4 = count5 = count6 = count7 = count8 = counth1 = counth2 = counth3 = counth4 = 0
  start = Time.now
  (1...versions.length).each do |i|
    puts "=============#{i} out of #{versions.length}============="
    new_version = versions[i - 1]
    build_version(version_his_folder, versions[i])
    versions[i] = load_version(version_his_folder, versions[i])
    puts "Duration of reading: #{Time.now - start}"
    ncs, ccs, eccs, nccs, nmhcs = new_version.compare_constraints(version)
    # nmhcs => not matched html constraints with previous html/validate constraints
    cnt += 1 if !ncs.empty? || !ccs.empty?
    file, insertion, deletion = code_change(application_dir, new_version.commit, version.commit)
    model_ncs = ncs.select { |x| x.type == Constraint::MODEL }
    db_ncs = ncs.select { |x| x.type == Constraint::DB }
    html_ncs = ncs.select { |x| x.type == Constraint::HTML }
    model_ccs = ccs.select { |x| x.type == Constraint::MODEL }
    db_ccs = ccs.select { |x| x.type == Constraint::DB }
    html_ccs = ccs.select { |x| x.type == Constraint::HTML }
    c1 = model_ncs.length
    c2 = db_ncs.length
    ch1 = html_ncs.length
    c3 = model_ccs.length
    c4 = db_ccs.length
    ch2 = html_ccs.length
    model_eccs = eccs.select { |x| x.type == Constraint::MODEL }
    db_eccs = eccs.select { |x| x.type == Constraint::DB }
    html_eccs = eccs.select { |x| x.type == Constraint::HTML }
    model_nccs = nccs.select { |x| x.type == Constraint::MODEL }
    db_nccs = nccs.select { |x| x.type == Constraint::DB }
    html_nccs = nccs.select { |x| x.type == Constraint::HTML }
    c5 = model_eccs.length
    c6 = db_eccs.length
    ch3 = html_eccs.length
    c7 = model_nccs.length
    c8 = db_nccs.length
    ch4 = html_nccs.length
    sum1 += c1 # model ncs
    sum2 += c2 # db ncs
    sum3 += c3 # model ccs
    sum4 += c4 # db ccs
    sum5 += c5 # model eccs
    sum6 += c6 # db eccs
    sum7 += c7 # model nccs
    sum8 += c8 # db nccs
    sumh1 += ch1 # html ncs
    sumh2 += ch2 # html ccs
    sumh3 += ch3 # html eccs
    sumh4 += ch4 # html nccs
    count1 += 1 if c1 > 0
    count2 += 1 if c2 > 0
    count3 += 1 if c3 > 0
    count4 += 1 if c4 > 0
    count5 += 1 if c5 > 0
    count6 += 1 if c6 > 0
    count7 += 1 if c7 > 0
    count8 += 1 if c8 > 0
    counth1 += 1 if ch1 > 0
    counth2 += 1 if ch2 > 0
    counth3 += 1 if ch3 > 0
    counth4 += 1 if ch4 > 0
    content = "#{version.loc} #{version.total_constraints_num} #{version.db_constraints_num} #{version.model_constraints_num} #{version.html_constraints_num}\n"
    output_diff_codechange.write(content)
    versions[i - 1] = nil
    output_html_constraints.write("======#{new_version.commit} vs #{version.commit}=====\n")
    nmhcs.each do |c|
      output_html_constraints.write(c.to_string)
      output_html_constraints.write("\n------------------\n")
    end
    output_html_constraints.write("=========================================\n")
    puts "Duration: #{Time.now - start}"
    start = Time.now
  end
  output.write("VERSION number #{count1} #{count2} #{count3} #{count4} #{count5} #{count6} #{count7} #{count8} #{counth1} #{counth2} #{counth3} #{counth4}\n")
  output.write("#{versions.length} #{cnt} #{sum1} #{sum2} #{sum3} #{sum4} #{sum5} #{sum6} #{sum7} #{sum8} #{sumh1} #{sumh2} #{sumh3} #{sumh4}\n")
  output.close
  output_diff_codechange.close
  output_html_constraints.close
end

def extract_table_size_comparison(application_dir, interval, tag_unit = true)
  versions = extract_commits(application_dir, interval, tag_unit)
  puts "versions.length: #{versions.length}"
  return if versions.length <= 0

  app_name = application_dir.split("/")[-1]
  version_his_folder = "../log/vhf_#{app_name}/"
  Dir.mkdir(version_his_folder) unless File.exist? version_his_folder
  yaml_version = version_his_folder + versions[0].commit.gsub("/", "-")
  if File.exist?(yaml_version)
    versions[0] = YAML.safe_load(File.read(yaml_version))
  else
    versions[0].build
    versions[0].clean
    File.open(yaml_version, "w") { |f| f.write(YAML.dump(versions[0])) }
  end
  output = open("../log/columnsizecomp_#{app_name}.log", "w")
  version = versions[0]
  start = Time.now
  final_results = {}
  first_results = {}
  version.activerecord_files.each do |key, file|
    final_results[key] = file.getColumnsLength
  end
  g_as_s = [] # gitlab application setting table size
  as_name = "User"
  if (as_size = version.get_all_table_column_size[as_name])
    g_as_s << as_size
  end
  (1...versions.length).each do |i|
    puts "=============#{i} out of #{versions.length}============="
    new_version = versions[i - 1]
    version = versions[i]
    yaml_version = version_his_folder + version.commit.gsub("/", "-")
    if File.exist?(yaml_version)
      version = versions[i] = YAML.safe_load(File.read(yaml_version))
    else
      version.build
      version.clean
      File.open(yaml_version, "w") { |f| f.write(YAML.dump(version)) }
    end
    puts "Duration of reading: #{Time.now - start}"
    results = new_version.get_table_original_column_size(version)
    first_results = first_results.merge(results)
    if i == versions.length - 1
      version.activerecord_files.each do |key, file|
        first_results[key] = file.getColumnsLength
      end
    end
    if (as_size = version.get_all_table_column_size[as_name])
      g_as_s << as_size
    end
  end
  growths = []
  tables = []
  puts "final_results: #{final_results.size}"
  final_results.each do |key, size|
    next unless (ori_size = first_results[key])

    growth = size - ori_size
    growths << growth
    tables << key
  end
  puts "growths: #{growths.size}"
  output.write(growths.join(" "))
  output.write("\n")
  output.write(tables.join(" "))
  output.write("\n")
  output.write("max min average\n")
  average = "NULL"
  average = growths.reduce(:+) * 1.0 / growths.size unless growths.empty?
  output.write("#{growths.max} #{growths.min} #{average}\n")
  output.write("#{g_as_s.join(' ')}\n")
  output.write("#{g_as_s.size}\n")
  output.close
end

def find_all_mismatch(application_dir, interval)
  puts "interval: #{interval.class.name}"
  versions = extract_commits(application_dir, interval)
  return if versions.length <= 0

  versions.each do |v|
    find_mismatch_oneversion(application_dir, v.commit)
  end
end

def find_mismatch_oneversion(directory, commit = "master")
  `cd #{directory}; git checkout -f #{commit}`
  version = Version_class.new(directory, commit)
  version.build
  version.compare_self
end

def dump_constraints(application_dir, dump_filename, commit)
  commit ||= "master"
  `cd #{application_dir}; git checkout -f #{commit}`
  version = Version_class.new(application_dir, commit)
  version.build
  constraints = version.get_model_constraints

  File.open(dump_filename, "wb") { |f| f.write(Marshal.dump(constraints)) }
end

def count_non_destroy(directory, commit = "master")
  `cd #{directory}; git checkout -f #{commit}`
  version = Version_class.new(directory, commit)
  version.build
  nda = version.find_non_destroy_assoc
  cwcf = version.class_with_custom_function
  app_name = directory.split("/")[-1]
  output = open("../log/destroy#{app_name}.log", "w")
  nda.each do |k1, k2|
    output.write("#{k1} #{k2}\n")
  end
  output.close
  puts "non_destroy_assocs #{nda.size} cwcf: #{cwcf.size} #{version.activerecord_files.size}"
end
