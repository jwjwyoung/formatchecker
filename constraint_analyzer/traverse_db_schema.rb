class Version_class
  def compare_db_schema(old_vers)
    col_add = col_del = col_ren = tab_add = tab_del = 0
    @activerecord_files.each_key do |key|
      file = @activerecord_files[key]
      old_file = old_vers.activerecord_files[key]
      unless old_file
        # missing old file: added table
        puts "new table #{key}: #{file.filename}@#{@commit}"
        tab_add += 1
        next
      end
      # present in new file but missing in old file: added column
      file.columns.each_key.reject { |k| old_file.columns.keys.include? k }.each do |col|
        puts "new column #{col} in table #{key}: #{file.filename}@#{@commit}"
        col_add += 1
      end
      old_file.columns.each_key do |col|
        old_name = old_file.columns[col].column_name
        new_col = file.columns[col]
        if new_col.nil?
          # present in old file but missing in new file: deleted column
          puts "del column #{col} in table #{key}: #{file.filename}@#{@commit}"
          col_del += 1
          next
        end
        new_name = new_col.column_name
        if old_name != new_name
          puts "rename column #{old_name} → #{new_name}: #{file.filename}@#{@commit}"
          col_ren += 1
        end
      end
    end
    old_vers.activerecord_files.each_key.reject { |k| @activerecord_files[k] }.each do |key|
      # missing new file: delete table
      puts "del table #{key}: #{@commit}"
      tab_del += 1
    end
    [col_add, col_del, col_ren, tab_add, tab_del]
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
  version_with = { col_add: 0, col_del: 0, col_ren: 0, tab_add: 0, tab_del: 0 }
  # newest versions come first
  versions.each_cons(2).each do |newv, curv|
    col_add, col_del, col_ren, tab_add, tab_del = newv.compare_db_schema(curv)
    version_with[:col_add] += col_add
    version_with[:col_del] += col_del
    version_with[:col_ren] += col_ren
    version_with[:tab_add] += tab_add
    version_with[:tab_del] += tab_del
    puts "#{newv.commit[..7]} #{col_add}, #{col_del}, #{col_ren}, #{tab_add}, #{tab_del}"
  end
end
