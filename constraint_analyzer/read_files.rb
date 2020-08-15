require "pathname"

def os_walk(dir)
  root = Pathname(dir)
  # puts root
  files = []
  dirs = []
  Pathname(root).find do |path|
    unless path == root
      dirs << path if path.directory?
      files << path if path.file?
    end
  end
  [root, files, dirs]
end

def read_constraint_files(application_dir = nil, version = "")
  if application_dir && version
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
  concern_files = []
  migration_files = []
  view_files = []
  controller_files = []
  files.each do |filename|
    filename = filename.to_s
    # filter out dependency files
    next if filename.include?("vendor/bundle/") || filename.include?("spec/fixtures")

    # filter out garbage in diaspora/app/assets
    if filename.include?("app/models/") && filename.ends_with?(".rb")
      if filename.include?("app/models/concerns/")
        concern_files << filename
      else
        model_files << filename
      end
    end
    if filename.include?("db/migrate/")
      migration_files << filename
    end
    # if filename.include?("db/schema.rb")
    #   replaced_files = migration_files.dup
    #   migration_files = [filename]
    # end
    if filename.include?("app/views/")
      view_files << filename
    end
    if filename.include?("app/controllers/")
      controller_files << filename
    end
  end

  $write_action_num = 0
  $no_resuce_num = 0
  controller_files.each do |filename|
    file = File.open(filename)
    contents = file.readlines.reject { |l| /^\s*#/.match l }.join
    file.close
    $global_rescue = false
    $global_rescue = true if contents.include? "rescue_from.*ActiveRecord::StatementInvalid"
    ast = YARD::Parser::Ruby::RubyParser.parse(contents).root
    $code = ""
    $fn = filename
    parse_controller_file(ast)
  rescue StandardError
  end
  exit if ENV["rescue"]
  model_files.each do |filename|
    file = File.open(filename)
    contents = file.readlines.reject { |l| /^\s*#/.match l }.join
    file.close
    ast = YARD::Parser::Ruby::RubyParser.parse(contents).root
    $cur_class = File_class.new(filename)
    $cur_class.ast = ast
    $cur_class.contents = contents
    $module_name = ""
    $classes = []
    parse_model_constraint_file(ast)
    model_classes[$cur_class.class_name] = $cur_class.dup
    $classes.each do |c|
      model_classes[c.class_name] = c
    end
  rescue StandardError => error
    puts error
  end
  concerns = concern_files.each_with_object({}) do |filename, memo|
    File.open(filename) do |file|
      ast = YARD::Parser::Ruby::RubyParser.parse(file.read).root
      concern = Concern.from_ast(ast)
      memo[concern.name] = concern
    end
  end
  $model_classes = model_classes
  $dangling_classes = {}
  cnt = 0
  if $read_db
    migration_files.each do |filename|
      file = File.open(filename)
      contents = file.read
      file.close
      begin
        ast = YARD::Parser::Ruby::RubyParser.parse(contents).root
        $cur_class = File_class.new(filename)
        $cur_class.ast = ast
        parse_db_constraint_file(ast)
        cnt += 1
      rescue StandardError
      end
    end
  end
  # puts "finished handle migration files #{migration_files.length} #{cnt}"
  begin
    if $read_html
      read_html_file_ast(view_files)
    end
  rescue StandardError
  end
  [model_classes, concerns]
end

def read_html_file_ast(view_files)
  view_files.each do |filename|
    # puts "filenmae: #{filename}"
    erb_filename = filename
    haml2html = File.join(__dir__, "../constraint_analyzer/herbalizer")
    os = `uname -a`
    if os.include? "Linux"
      haml2html = "python3 #{File.join(__dir__, '../constraint_analyzer/haml2html.py')}"
    end
    extract_erb = File.join(__dir__, "../constraint_analyzer/extract_rubynhtml.rb")
    base = filename.gsub("/", "_").gsub(".", "")
    if filename.include? "haml"
      formalize_script = File.join(__dir__, "../constraint_analyzer/formalize_haml.rb")
      formalized_filename = File.join(__dir__, "../tmp/#{base}1.html.erb")
      erb_filename = File.join(__dir__, "../tmp/#{base}2.html.erb")
      `ruby #{formalize_script} #{filename}  #{formalized_filename};`
      # puts "formalized_filename #{open(formalized_filename).read}"
      # puts "#{haml2html} #{formalized_filename} > #{erb_filename}"
      `#{haml2html} #{formalized_filename} > #{erb_filename}`
      # puts "contents #{open(erb_filename).read}"
      `rm #{formalized_filename}`
    end
    target = File.join(__dir__, "../tmp/#{base}.rb")
    begin
      `ruby #{extract_erb} #{erb_filename} #{target}`
      file = open(target)
      contents = file.read
      file.close
      if erb_filename.include? "haml"
        # `rm #{erb_filename}`
      end
      `rm #{target}`
      unless contents.include?("required") || contents.include?("maxlength") || contents.include?("minlength") || contents.include?("pattern")
        next
      end

      begin
        ast = YARD::Parser::Ruby::RubyParser.parse(contents).root
        $cur_class = File_class.new(filename)
        # puts "$cur_class #{$cur_class.filename}"
        parse_html_constraint_file(ast)
      rescue StandardError
      end
    rescue StandardError
      # puts "file doesn't exist"
    end
  end
end
