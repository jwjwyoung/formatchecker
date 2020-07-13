class Version_class
  def compare_db_schema(old_vers)
    @activerecord_files.each_key do |key|
      file = @activerecord_files[key]
      old_file = old_vers.activerecord_files[key]
      unless old_file
        # missing old file: added table
        puts "add table #{key}: #{file.filename}@#{@commit[..8]}"
        next
      end
      # present in old file but missing in new file: deleted column
      old_file.columns.each_key.reject { |k| file.columns.keys.include? k }.each do |col|
        puts "del column #{col} in table #{key}: #{file.filename}@#{@commit[..8]}"
      end
      # present in new file but missing in old file: added column
      file.columns.each_key.reject { |k| old_file.columns.keys.include? k }.each do |col|
        puts "new column #{col} in table #{key}: #{file.filename}@#{@commit[..8]}"
      end
    end
    old_vers.activerecord_files.each_key.reject { |k| @activerecord_files[k] }.each do |key|
      # missing new file: delete table
      puts "del table #{key}: #{@commit[..8]}"
    end
  end
end

def build_version(yaml_root, version)
  yaml_dump = File.join(yaml_root, version.commit.gsub("/", "-"))
  if File.exist?(yaml_dump)
    Psych.load_file(yaml_dump)
  else
    version.build
    version.clean
    File.open(yaml_dump, "w") { |f| f.write(Psych.dump(version)) }
    version
  end
end

def traverse_all_for_db_schema(app_dir, interval = nil)
  versions = extract_commits(app_dir, interval)
  return if versions.length <= 0

  app_name = File.basename(app_dir)
  version_his_folder = File.expand_path("../log/vhf_#{app_name}", __dir__)
  Dir.mkdir(version_his_folder) unless Dir.exist? version_his_folder

  versions.map! { |v| build_version(version_his_folder, v) }
  # newest versions comes first
  versions.each_cons(2).each do |newv, curv|
    newv.compare_db_schema(curv)
  end
end
