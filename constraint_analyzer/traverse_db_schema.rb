require "csv"
require "parallel"

class Version_class
  # Gets information about {table,column}{add,delete,rename} and column type change
  # between `self` and `old_vers`. Provide a block to this method to go through the
  # differences. The arguments of the block should be in the following order.
  #
  # 1. type of change, will be one of [:tab_add, :tab_del, :tab_ren, :col_add, :col_del,
  #      :col_ren, :col_type];
  # 2. the table involved in the change. For table rename, this is the new name;
  # 3. other arguments:
  #
  #      * `:tab_add`, `:tab_del`: no more arguments
  #      * `:tab_ren`: the previous table name
  #      * `:col_add`, `:col_del`: column key name and the added/deleted column's name
  #      * `:col_ren`: column key name, the new name and the previous name
  #      * `:col_type`: column key name, the column name, new type and old type
  def compare_db_schema(old_vers)
    raise "please provide a block to compare_db_schema" unless block_given?

    renamed_tab = Set.new
    @activerecord_files.each_key do |key|
      file = @activerecord_files[key]
      old_file = old_vers.activerecord_files[key]
      unless old_file
        if file.prev_class_name.nil?
          # Add table: missing old file, don't have prev_class_name
          yield :tab_add, key
        else
          # Rename table: has prev_class_name
          yield :tab_ren, key, file.prev_class_name
          renamed_tab << file.prev_class_name
        end
        next
      end

      # Add column: present in new file but missing in old file
      file.columns.each_key.reject { |k| old_file.columns.keys.include? k }.each do |col|
        yield :col_add, key, col, file.columns[col].column_name
      end

      old_file.columns.each_key do |col|
        old_col = old_file.columns[col]
        old_name = old_col.column_name
        new_col = file.columns[col]
        # Delete column
        # 1. new_col will be nil if a migration file is deleted (typically in rollup migrations)
        #    (TracksApp/tracks@v1.6..v1.7, seven1m/onebody@3.6.0..3.7.0, etc.)
        # 2. the first occurrence of true of is_deleted marks a deletion
        if new_col.nil? || new_col.is_deleted
          yield :col_del, key, col, old_name, new_col.nil? unless old_col.is_deleted ||
                                                                  old_col.prev_column
          next
        end

        # Rename column
        new_name = new_col.column_name
        yield :col_ren, key, col, new_name, old_name if old_name != new_name

        # Change column type
        old_type = old_col.column_type
        new_type = new_col.column_type
        yield :col_type, key, col, new_name, new_type, old_type if old_type != new_type
      end
    end

    # Delete table: missing new file
    dtab = old_vers.activerecord_files.each_key.reject do |k|
      @activerecord_files[k] || renamed_tab.include?(k)
    end
    dtab.each do |key|
      yield :tab_del, key
    end
  end
end

# Builds a `Version_class` and save it to cache
def build_version(yaml_root, version)
  yaml_dump = File.join(yaml_root, version.commit.gsub("/", "-"))
  return if File.exist? yaml_dump

  version.build
  version.clean
  File.open(yaml_dump, "w") { |f| f.write(Psych.dump(version)) }
end

# Loads a vendored `Version_class` from cache
def load_version(yaml_root, version)
  yaml_dump = File.join(yaml_root, version.commit.gsub("/", "-"))
  raise "#{yaml_dump} does not exist" unless File.exist? yaml_dump

  Psych.load_file(yaml_dump)
end

def shorten_commit(commit)
  commit.start_with?("refs/tags/") ? commit.sub("refs/tags/", "") : commit[..7]
end

# Prints the number of different types of changes in every version and the
# total number in all versions to a CSV file specified by `path`.
#
# ==== Examples
#
#  output_csv_schema_change(File.expand_path("../tmp/#{app_name}.csv", __dir__),
#                           version_chg, total_action)
def output_csv_schema_change(path, version_chg, total_action)
  CSV.open(path, "wb") do |csv|
    csv << ["version", "column add", "column delete", "column rename", "column change type",
            "table add", "table delete", "table rename"]
    version_chg.each do |ver, chg|
      csv << [shorten_commit(ver), chg[:col_add], chg[:col_del], chg[:col_ren], chg[:col_type],
              chg[:tab_add], chg[:tab_del], chg[:tab_ren]]
    end
    csv << ["TOTAL", total_action[:col_add], total_action[:col_del], total_action[:col_ren],
            total_action[:col_type], total_action[:tab_add], total_action[:tab_del],
            total_action[:tab_ren]]
  end
end

# Gets the versions for `app_dir`. If the file "#{app_dir}/versions" exists, every line
# in the file is treated as a version. Otherwise use the original `extract_commits`.
def get_versions(app_dir, interval)
  if File.readable?(File.join(app_dir, "versions"))
    File.read(File.join(app_dir, "versions")).lines.map { |v| Version_class.new(app_dir, v) }
  else
    extract_commits(app_dir, interval)
  end
end

def traverse_all_for_db_schema(app_dir, interval = nil)
  versions = get_versions(app_dir, interval)
  return if versions.length <= 0

  app_name = File.basename(app_dir)
  version_his_folder = File.expand_path("../log/vhf_#{app_name}", __dir__)
  Dir.mkdir(version_his_folder) unless Dir.exist? version_his_folder

  versions.each { |v| build_version(version_his_folder, v) }
  versions = Parallel.map(versions) { |v| load_version(version_his_folder, v) }
  # number of versions that include an action
  version_with = { col_add: 0, col_del: 0, col_ren: 0, col_type: 0, tab_add: 0, tab_del: 0, tab_ren: 0 }
  # version and it's change counts
  version_chg = []
  # total number of actions
  total_action = { col_add: 0, col_del: 0, col_ren: 0, col_type: 0, tab_add: 0, tab_del: 0, tab_ren: 0 }
  # newest versions come first
  versions.each_cons(2).each do |newv, curv|
    this_version_has = Hash.new 0
    newv.compare_db_schema(curv) do |action, table, *args|
      this_version_has[action] += 1
    end
    version_chg << [newv.commit, this_version_has]
    this_version_has.each do |ac, num|
      version_with[ac] += 1 unless num.zero?
      total_action[ac] += num
    end
  end
  ver_with_change = 0
  version_chg.each do |_ver, chg|
    ver_with_change += 1 unless chg.values.all?(&:zero?)
  end
end
