class Version_class
  def compare_db_schema(old_vers)
    col_add = col_del = col_ren = tab_add = tab_del = tab_ren = 0
    renamed_tab = []
    @activerecord_files.each_key do |key|
      file = @activerecord_files[key]
      old_file = old_vers.activerecord_files[key]
      unless old_file
        if file.prev_class_name.nil?
          # Add table: missing old file, don't have prev_class_name
          puts "new table #{key}: #{file.filename}@#{@commit}"
          tab_add += 1
        else
          # Rename table: has prev_class_name
          puts "rename table #{file.prev_class_name} → #{key}: #{file.filename}@#{@commit}"
          tab_ren += 1
          renamed_tab.push(file.prev_class_name)
        end
        next
      end

      # Add column: present in new file but missing in old file
      file.columns.each_key.reject { |k| old_file.columns.keys.include? k }.each do |col|
        puts "new column #{col} in table #{key}: #{file.filename}@#{@commit}"
        col_add += 1
      end

      old_file.columns.each_key do |col|
        old_col = old_file.columns[col]
        old_name = old_col.column_name
        new_col = file.columns[col]
        # Delete column
        # 1. new_col will be nil if a migration file is deleted (typically in rollup migrations)
        #    (TracksApp/tracks@v1.6..v1.7, seven1m/onebody@3.6.0..3.7.0, etc.)
        if new_col.nil?
          puts "--del column #{old_name} in table #{key}: #{file.filename}@#{@commit}"
          col_del += 1
          next
        end
        # 2. the first occurrence of true of is_deleted marks a deletion
        if new_col.is_deleted && !old_col.is_deleted
          puts "del column #{old_name} in table #{key}: #{file.filename}@#{@commit}"
          col_del += 1
          next
        end

        # Rename column
        new_name = new_col.column_name
        if old_name != new_name
          puts "rename column #{old_name} → #{new_name} in table #{key}: #{file.filename}@#{@commit}"
          col_ren += 1
        end
      end
    end

    # Delete table: missing new file
    dtab = old_vers.activerecord_files.each_key.reject do |k|
      @activerecord_files[k] || renamed_tab.include?(k)
    end
    dtab.each do |key|
      puts "del table #{key}: #{@commit}"
      tab_del += 1
    end
    [col_add, col_del, col_ren, tab_add, tab_del, tab_ren]
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
  version_with = { col_add: 0, col_del: 0, col_ren: 0, tab_add: 0, tab_del: 0, tab_ren: 0 }
  # newest versions come first
  versions.each_cons(2).each do |newv, curv|
    col_add, col_del, col_ren, tab_add, tab_del, tab_ren = newv.compare_db_schema(curv)
    version_with[:col_add] += col_add
    version_with[:col_del] += col_del
    version_with[:col_ren] += col_ren
    version_with[:tab_add] += tab_add
    version_with[:tab_del] += tab_del
    version_with[:tab_ren] += tab_ren
  end
end
