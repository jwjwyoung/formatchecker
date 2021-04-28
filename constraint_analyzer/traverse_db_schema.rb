require "csv"
require "parallel"

def aggregate_many_one(belongs, has_manys, has_ones, has_belong)
  tmp = belongs.each_with_object({}) { |obj, memo| memo[obj] = :belongs }
  tmp = has_manys.each_with_object(tmp) { |obj, memo| memo[obj] = :many }
  tmp = has_ones.each_with_object(tmp) { |obj, memo| memo[obj] = :one }
  has_belong.each_with_object(tmp) { |obj, memo| memo[obj] = :has_belong }
end

class Version_class
  # Gets information about {table,column}{add,delete,rename}, column type change,
  # association (belongs_to (fk), has_many, has_one, has_and_belongs_to_many)
  # {add,delete,change} between `self` and `old_vers`. Provide a block to this
  # method to go through the differences. The arguments of the block should be
  # in the following order.
  #
  # 1. type of change, will be one of [:tab_add, :tab_del, :tab_ren,
  #      :col_add, :col_del, :col_ren, :col_type, :fk_add, :fk_del
  #      :has_one_add, :has_one_del, :has_many_add, :has_many_del,
  #      :has_belong_add, :has_belong_del, :assoc_change,
  #      :idx_add, :idx_del];
  # 2. the table involved in the change. For table rename, this is the new name;
  # 3. other arguments:
  #
  #      * `:tab_add`, `:tab_del`: no more arguments
  #      * `:tab_ren`: the previous table name
  #      * `:col_add`, `:col_del`: column key name and the added/deleted column's name
  #      * `:col_ren`: column key name, the new name and the previous name
  #      * `:col_type`: column key name, the column name, new type and old type
  #      * `:fk_add`, `:fk_del`: the added/deleted key
  #      * :has_{one,many,belong}_{add,del}: the model
  #      * `:assoc_change`: the model, new association type, old association type
  #      * :idx_{add,del}: the index name and an array of indexed columns
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
          puts "rename #{key} #{file.prev_class_name}"
          renamed_tab << file.prev_class_name
          yield :tab_ren, key, file.prev_class_name
        end
        next
      end

      # association
      new_fk = file.foreign_keys.to_set
      old_fk = old_file.foreign_keys.to_set
      new_many = file.has_many_classes.keys.to_set
      old_many = old_file.has_many_classes.keys.to_set
      new_one = file.has_one_classes.keys.to_set
      old_one = old_file.has_one_classes.keys.to_set
      new_both = file.has_belong_classes
      old_both = old_file.has_belong_classes

      new_has = aggregate_many_one(new_fk, new_many, new_one, new_both)
      old_has = aggregate_many_one(old_fk, old_many, old_one, old_both)
      new_keys = new_fk + new_one + new_many + new_both
      old_keys = old_fk + old_one + old_many + old_both

      # association change
      new_keys.intersection(old_keys).each do |k|
        if old_has[k] != new_has[k]
          yield :assoc_change, key, k, new_has[k], old_has[k]
        end
      end

      # association add
      (new_keys - old_keys).each do |k|
        case new_has[k]
        when :belongs
          yield :fk_add, key, k
        when :many
          yield :has_many_add, key, k
        when :one
          yield :has_one_add, key, k
        when :has_belong
          yield :has_belong_add, key, k
        end
      end

      # association delete
      (old_keys - new_keys).each do |k|
        case old_has[k]
        when :belongs
          yield :fk_del, key, k
        when :many
          yield :has_many_del, key, k
        when :one
          yield :has_one_del, key, k
        when :has_belong
          yield :has_belong_del, key, k
        end
      end

      # Index add/del
      idx = file.indices.keys.to_set
      old_idx = old_file.indices.keys.to_set
      (idx - old_idx).each do |i|
        yield :idx_add, key, i, file.indices[i].columns
      end
      (old_idx - idx).each do |i|
        yield :idx_del, key, i, old_file.indices[i].columns
      end

      file.columns.each do |ckey, col|
        # Add column: not deleted in new file but (missing in old file or deleted in old file)
        if old_file.columns[ckey].nil? || (old_file.columns[ckey].is_deleted && !col.is_deleted)
          yield :col_add, key, ckey, col.column_name
        end

        # Rename column
        if col.prev_column
          new_name = col.column_name
          prev_name = col.prev_column.column_name
          old_prev_name = old_file.columns[ckey]&.prev_column&.column_name
          if prev_name != new_name && (old_prev_name.nil? || old_prev_name != prev_name)
            yield :col_ren, key, ckey, new_name, prev_name
          end
        end
      end

      newfile_columns = file.columns.values.reject(&:is_deleted).map(&:column_name).to_set
      old_file.columns.each_key do |col|
        old_col = old_file.columns[col]
        old_name = old_col.column_name
        new_col = file.columns[col]
        # Delete column
        # 1. new_col will be nil if a migration file is deleted (typically in rollup migrations)
        #    (TracksApp/tracks@v1.6..v1.7, seven1m/onebody@3.6.0..3.7.0, etc.)
        # 2. the first occurrence of true of is_deleted marks a deletion
        if new_col.nil? || new_col.is_deleted
          if !old_col.is_deleted && !newfile_columns.include?(old_name)
            yield :col_del, key, col, old_name, new_col.nil?
          end
          next
        end

        # Change column type
        old_type = old_col.column_type
        new_type = new_col.column_type
        if old_type != new_type &&
           !old_type.start_with?(new_type) &&
           !new_type.start_with?(old_type) &&
           Set.new([old_type, new_type]) != Set.new(%w[double float])
          yield :col_type, key, col, new_col.column_name, new_type, old_type
        end
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

  def text_typed_index
    @activerecord_files.each_value do |file|
      file.indices.values.to_set.each do |idx|
        table_name = idx.table_name.classify
        columns = @activerecord_files[table_name].columns
        idx.columns.to_set.each do |col|
          yield table_name, columns[col].column_name if columns[col]&.column_type == "text"
        end
      end
    end
  end
end

# Builds a `Version_class` and save it to cache
def build_version(yaml_root, version)
  # yaml_dump = File.join(yaml_root, version.commit.gsub("/", "-"))
  # return if File.exist? yaml_dump

  version.build
  version.clean
  #File.open(yaml_dump, "w") { |f| f.write(Psych.dump(version)) }
  #exit
end

# Loads a vendored `Version_class` from cache
def load_version(yaml_root, version)
  yaml_dump = File.join(yaml_root, version.commit.gsub("/", "-"))
  raise "#{yaml_dump} does not exist" unless File.exist? yaml_dump

  Psych.load_file(yaml_dump)
end

# Gets the versions for `app_dir` and build them. If the file "#{app_dir}/versions"
# exists, every line in the file is treated as a version. Otherwise use the original
# `extract_commits`.
def get_versions(app_dir, interval)
  versions = if File.readable?(File.join(app_dir, "versions"))
               File.read(File.join(app_dir, "versions")).lines.map do |v|
                 Version_class.new(app_dir, v)
               end
             else
               #extract_commits(app_dir, interval, false)
               extract_commits(app_dir, 10, false)
             end
  # app_name = File.basename(app_dir)
  # version_his_folder = File.expand_path("../log/vhf_#{app_name}", __dir__)
  # Dir.mkdir(version_his_folder) unless Dir.exist? version_his_folder
  # versions.each { |v| build_version(version_his_folder, v) }
  # Parallel.map(versions) { |v| load_version(version_his_folder, v) }
end

def traverse_all_for_db_schema(app_dir, interval = nil, versions=[])
  if versions.size == 0
    versions = get_versions(app_dir, interval)
  end

  app_name = File.basename(app_dir)
  version_his_folder = File.expand_path("../log/vhf_#{app_name}", __dir__)
  Dir.mkdir(version_his_folder) unless Dir.exist? version_his_folder
  puts("LENGTH: #{versions.length}")
  return if versions.length <= 0

  # versions << Version_class.new(app_dir, "00000000")
  # version and it's change counts
  version_chg = []
  # number of versions that include an action
  version_with = %i[
    col_add col_del col_ren col_type tab_add tab_del tab_ren fk_add fk_del
    has_many_add has_many_del has_one_add has_one_del
    has_belong_add has_belong_del assoc_change
    idx_add idx_del
  ].each_with_object({}) { |obj, memo| memo[obj] = 0 }
  # total number of actions
  total_action = version_with.clone
  # change in columns: column_changes[table_name][column_name] = count
  column_changes = Hash.new { |hash, k| hash[k] = Hash.new 0 }
  # newest versions come first
  build_version(version_his_folder, versions[0])
  versions.each_cons(2).each do |newv, curv|
    build_version(version_his_folder, curv)
    this_version_has = Hash.new 0
    shortv = shorten_commit(newv.commit)
    shortvo = shorten_commit(curv.commit)
    newv.to_schema()
    change = {}
    [:tab_del, :col_del].each do |action| 
      change[action] = []
    end
    change[:col_ren] = {}
    change[:tab_ren] = {}
    newv.compare_db_schema(curv) do |action, table, *args|
      case action
      when :tab_del
        change[action] << "#{table}"
        puts "#{shortvo} #{shortv} \e[31;1m#{action}\e[37;0m #{table}"   
      when :tab_ren
        change[action][args[0]] = table
      when :col_ren, :col_del, :col_type, :col_add
        col = args[0]
        column_changes[table][col] += 1 unless action == :col_add
        if action == :col_del
          puts "#{shortvo} #{shortv} \e[31;1m#{action}\e[37;0m #{table} #{args}"       
          change[action] << "#{table}_#{args[0]}"
          puts change
        end
        if action == :col_ren
          puts "#{shortvo} #{shortv} \e[31;1m#{action}\e[37;0m #{table} #{args}"         
          change[action]["#{table}_#{args[-1]}"] = args[1]
          puts change
        end
      when :fk_del, :has_one_del, :has_many_del
        puts "#{shortvo} #{shortv} \e[31;1m#{action}\e[37;0m #{table} #{args[0]}"
      when :assoc_change
        puts "#{shortvo} #{shortv} \e[33;1m#{action}\e[37;0m #{table} #{args[0]} #{args[-1]} → #{args[-2]}"
      when :idx_del
        puts "#{shortvo} #{shortv} \e[34;1m#{action}\e[37;0m #{table} #{args[0]} #{args[1]}"
      end
      this_version_has[action] += 1
    end
    if change.values.map{|x| x.length}.sum > 0    
      #exit
      # checkout to current version
      newv.extract_queries
      newv.check_queries(change)
    end
    version_chg << [newv.commit, this_version_has]
    this_version_has.each do |ac, num|
      version_with[ac] += 1 unless num.zero?
      total_action[ac] += num
    end
  end
  p "#{version_with_change(version_chg)}/#{version_chg.length}"
  p freq_change_column(column_changes).join "/"
  p total_action
end

def text_typed_indexes(app_dir, interval = nil)
  versions = get_versions(app_dir, interval)
  return if versions.length <= 0

  versions.each do |vers|
    shortv = shorten_commit(vers.commit)
    vers.text_typed_index do |tab, col|
      puts "#{shortv} #{tab}.#{col}"
    end
  end
end

# Finds how many columns are changed once/twice/more
#
# ==== Examples
#
#  puts freq_change_column(column_changes).join "/"
def freq_change_column(column_changes)
  once = twice = more = 0
  column_changes.each do |_tab, val|
    val.each do |_col, count|
      if count > 2
        more += 1
      elsif count == 2
        twice += 1
      else
        once += 1
      end
      # puts "#{count} #{_tab}.#{_col}"
    end
  end
  [once, twice, more]
end

# Finds how many versions have changed schema
#
# ==== Examples
#
#  puts "#{version_with_change(version_chg)}/#{version_chg.length}"
def version_with_change(version_chg)
  count = 0
  version_chg.each do |_ver, chg|
    count += 1 unless chg.values.all?(&:zero?)
  end
  count
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
            "table add", "table delete", "table rename", "foreign key add", "foreign key del"]
    version_chg.each do |ver, chg|
      csv << [shorten_commit(ver), chg[:col_add], chg[:col_del], chg[:col_ren], chg[:col_type],
              chg[:tab_add], chg[:tab_del], chg[:tab_ren], chg[:fk_add], chg[:fk_del]]
    end
    csv << ["TOTAL", total_action[:col_add], total_action[:col_del], total_action[:col_ren],
            total_action[:col_type], total_action[:tab_add], total_action[:tab_del],
            total_action[:tab_ren], total_action[:fk_add], total_action[:fk_del]]
  end
end

def shorten_commit(commit)
  commit.start_with?("refs/tags/") ? commit.sub("refs/tags/", "") : commit[0..7]
end
