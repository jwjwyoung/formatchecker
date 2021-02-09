require "pathname"

def os_walk(dir)
  root = Pathname(dir)
  # puts root
  files, dirs = [], []
  Pathname(root).find do |path|
    unless path == root
      dirs << path if path.directory?
      files << path if path.file?
    end
  end
  [root, files, dirs]
end

def read_constraint_files(application_dir = nil, version = "")
  puts application_dir
  if application_dir and version
    $app_dir2 = application_dir
  else
    # puts "application dir not defined or version number is not defined"
    return
  end
  # checkout to specified version
  if version != ""
    `cd #{$app_dir2};git stash; git checkout #{version}`
  end

  # puts "$application_dir #{$app_dir2}"
  root, files, dirs = os_walk($app_dir2)
  model_classes = {}
  model_files = []
  migration_files = []
  view_files = []
  controller_files = []
  for filename in files
    filename = filename.to_s
    if filename.include?("app/models/")
      model_files << filename
    end
    if filename.include?("db/migrate/")
      migration_files << filename
    end
    if filename.include?("db/schema.rb")
      replaced_files = migration_files.dup
      migration_files = [filename]
    end
    if filename.include?("app/views/")
      view_files << filename
    end
    if filename.include?("app/controllers/")
      controller_files << filename
    end
  end

  # puts "controller_files #{controller_files.length}"
  $write_action_num = 0
  $no_resuce_num = 0
  controller_files.each do |filename|
    begin
      file = open(filename)
      contents = file.readlines.reject { |l| /^\s*#/.match l }.join
      file.close
      $global_rescue = false
      $global_rescue = true if contents.include? "rescue_from.*ActiveRecord::StatementInvalid"
      ast = YARD::Parser::Ruby::RubyParser.parse(contents).root
      $code = ""
      $fn = filename
      parse_controller_file(ast)
      # if $code
      #   puts "#{filename} #{$write_action_num} #{$no_resuce_num}"
      #   puts $code
      # end
    rescue
    end
  end
  # puts "#{$write_action_num} #{$no_resuce_num}"
  exit if ENV["rescue"]
  model_files.each do |filename|
    begin
      file = open(filename)
      contents = file.readlines.reject { |l| /^\s*#/.match l }.join
      file.close
      # puts "*******reach here true #{filename}" if filename.include? "app/models/watcher.rb"
      ast = YARD::Parser::Ruby::RubyParser.parse(contents).root
      $cur_class = File_class.new(filename)
      $cur_class.ast = ast
      $cur_class.contents = contents
      $module_name = ""
      $classes = []
      parse_model_constraint_file(ast)
      model_classes[$cur_class.class_name] = $cur_class.dup
      #puts "$cur_class.class_name #{$cur_class.class_name}"
      $classes.each do |c|
        model_classes[c.class_name] = c
        # puts "add new class #{c.class_name} #{c.upper_class_name}"
      end
      # puts "add new class #{$cur_class.class_name} #{$cur_class.upper_class_name}"
    rescue => error
      puts error.backtrace.join("\n")
      puts "failed filename: #{filename}"
    end
  end

  # puts "finished handle model files #{model_files.length} #{model_classes.length}"
  $model_classes = model_classes
  $dangling_classes = {}
  # puts "********migration_files:********"
  # puts migration_files
  cnt = 0
  if $read_db
    migration_files.each do |filename|
      file = open(filename)
      contents = file.read
      file.close
      begin
        ast = YARD::Parser::Ruby::RubyParser.parse(contents).root
        $cur_class = File_class.new(filename)
        $cur_class.ast = ast
        parse_db_constraint_file(ast)
        cnt += 1
      rescue
      end
    end
  end
  puts "finished handle migration files #{migration_files.length} #{cnt}"

  # check customized constraints
  check_customized_constraints(model_classes)

  begin
    if $read_html
      read_html_file_ast(view_files)
    end
  rescue
  end
  return model_classes
end

def read_html_file_ast(view_files)
  view_files.each do |filename|
    #puts "filenmae: #{filename}"
    erb_filename = filename
    haml2html = File.join(File.expand_path(File.dirname(__FILE__)), "../constraint_analyzer/herbalizer")
    os = `uname -a`
    if os.include? "Linux"
      haml2html = "python3 #{File.join(File.expand_path(File.dirname(__FILE__)), "../constraint_analyzer/haml2html.py")}"
    end
    extract_erb = File.join(File.expand_path(File.dirname(__FILE__)), "../constraint_analyzer/extract_rubynhtml.rb")
    base = filename.gsub("/", "_").gsub(".", "")
    if filename.include? "haml"
      formalize_script = File.join(File.expand_path(File.dirname(__FILE__)), "../constraint_analyzer/formalize_haml.rb")
      formalized_filename = File.join(File.expand_path(File.dirname(__FILE__)), "../tmp/#{base}1.html.erb")
      erb_filename = File.join(File.expand_path(File.dirname(__FILE__)), "../tmp/#{base}2.html.erb")
      `ruby #{formalize_script} #{filename}  #{formalized_filename};`
      #puts "formalized_filename #{open(formalized_filename).read}"
      #puts "#{haml2html} #{formalized_filename} > #{erb_filename}"
      `#{haml2html} #{formalized_filename} > #{erb_filename}`
      #puts "contents #{open(erb_filename).read}"
      `rm #{formalized_filename}`
    end
    target = File.join(File.expand_path(File.dirname(__FILE__)), "../tmp/#{base}.rb")
    begin
      `ruby #{extract_erb} #{erb_filename} #{target}`
      file = open(target)
      contents = file.read
      file.close
      if erb_filename.include? "haml"
        # `rm #{erb_filename}`
      end
      `rm #{target}`
      if not(contents.include? "required" or contents.include? "maxlength" or contents.include? "minlength" or contents.include? "pattern")
        next
      end
      begin
        ast = YARD::Parser::Ruby::RubyParser.parse(contents).root
        $cur_class = File_class.new(filename)
        # puts "$cur_class #{$cur_class.filename}"
        parse_html_constraint_file(ast)
      rescue
      end
    rescue
      # puts "file doesn't exist"
    end
  end
end

def is_db_field(field, file)
  puts file.has_many_classes.to_s
  puts "[CHECK]----" + field + "  in " + file.class_name
  # puts file.getColumns.keys
  return (file.getColumns.key?(field)) || (file.getColumns.key?(field + "_id")) ||
           (file.getColumns.key?(field.split("_")[0]))
  # return true
end

def check_customized_constraints(model_classes)
  model_classes.each do |key, file|
    constraints = file.getConstraints().select { |k, v| k.include? "Customized_constraint_if" }
    constraints.each do |k, v|
      # check conditions of v
      if v.cond.empty?
        file.removeConstraintByKey(k)
      end
      valid = true
      v.fields.each do |field|
        valid = false if !is_db_field(field, file)
        if !is_db_field(field, file)
          puts field + " is not db field in " + file.class_name
        end
      end
      file.removeConstraintByKey(k) if !valid
    end
  end

  # After checking all customized constraints
  model_classes.each do |key, file|
    constraints = file.getConstraints().select { |k, v| k.include? "Customized_constraint_if" }
    constraints.each do |k, v|
      puts "==========================="
      puts file.filename
      puts v.src
      # puts v.fields.to_s
      # puts v.cond.to_s
      puts "==========================="
    end
  end
end
