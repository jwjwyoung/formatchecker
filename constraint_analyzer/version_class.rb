class Version_class
  attr_accessor :app_dir, :commit, :total_constraints_num, :db_constraints_num, :model_constraints_num,
                :html_constraints_num, :loc, :activerecord_files, :validation_functions, :concerns, :queries, :scope, :schema, :raw_queries

  def initialize(app_dir, commit)
    @app_dir = app_dir
    @commit = commit.strip
    @files = {}
    @concerns = {}
    @activerecord_files = {}
    @total_constraints_num = 0
    @db_constraints_num = 0
    @model_constraints_num = 0
    @html_constraints_num = 0
    @db_constraints = []
    @model_constraints = []
    @html_constraints = []
    @loc = 0
    @validation_functions = {}
    @queries = nil
    @scope = nil
    @schema = nil
  end
  
  def to_schema()

    @activerecord_files.each do |k, v|
      v.to_schema()
    end

  end
  
  def getDbConstraints
    @db_constraints
  end

  def getModelConstraints
    @model_constraints
  end

  def getHtmlConstraints
    @html_constraints
  end

  def extract_files
    @files, @concerns = read_constraint_files(@app_dir, @commit) if @app_dir && @commit
  end
    
  def extract_queries
    app_name = @app_dir.split("/")[-1]
    options, app_dir = get_config(app_name)
    puts "CONFIG : #{options} #{app_dir}"
    `cd #{app_dir}; git checkout -f #{self.commit}`
    @raw_queries, @scopes, @schema = load_queries_and_schema(@app_dir, options[:tmp_dir], options[:rails_best_practices_cmd], self)
    puts "QUERY NUM #{@raw_queries.length}"
    #print_detail_with_sql(@raw_queries, @scopes, @schema, change)
    #exit
  end 
  def check_queries(change)
    print_detail_with_sql(@raw_queries, @scopes, @schema, change)
  end

  def extract_constraints
    num = 0
    @activerecord_files.each do |_key, file|
      # puts"#{key} #{file.getConstraints.length}"
      file.create_con_from_column_type
      file.create_con_from_index
      file.create_con_from_format
    end
    @activerecord_files.each do |_key, file|
      # file.extract_instance_var_refs
      num += file.getConstraints.length
      file.getConstraints.each do |k, constraint|
        if constraint.type == Constraint::DB
          @db_constraints_num += 1
          @db_constraints << constraint
        elsif constraint.type == Constraint::MODEL
          @model_constraints_num += 1
          @model_constraints << constraint
        elsif constraint.type == Constraint::HTML
          @html_constraints_num += 1
          @html_constraints << constraint
        else
          puts "k: #{k}"
        end
      end
    end
    @total_constraints_num = @db_constraints_num + @model_constraints_num + @html_constraints_num
    total_constraints = @activerecord_files.map { |_k, v| v.getConstraints.length }.reduce(:+)
    # puts "total_constraints #{total_constraints} #{@total_constraints_num} #{num}"
  end

  def extract_case_insensitive_columns
    ci_columns = {}
    email_columns = {}
    @activerecord_files.each do |key, file|
      constraints = file.getConstraints
      validation_constraints = constraints.select { |k, _v| k.include? Constraint::MODEL }
      uniqueness_constraints = validation_constraints.select do |_k, v|
        v.instance_of? Uniqueness_constraint and v.case_sensitive == false
      end
      sensitive_uniq_constraints = validation_constraints.select do |_k, v|
        v.instance_of? Uniqueness_constraint and v.case_sensitive == true
      end
      # puts "uniqueness_constraints #{uniqueness_constraints.size}"

      columns = file.getColumns
      # puts "Columns #{file.class_name} #{columns.map{|k,v| v.column_name}.join(" ,")}" if columns.size > 0
      uniqueness_constraints.each do |_k, v|
        column_name = v.column
        if columns[column_name]
          key = "#{file.class_name}-#{column_name}"
          ci_columns[key] = columns[column_name]
        end
      end
      sensitive_uniq_constraints.each do |_k, v|
        column_name = v.column
        email_columns[key] = v.to_string if columns[column_name] && (column_name == "email")
      end
    end
    [ci_columns, email_columns]
  end

  def annotate_model_class
    not_active_files = []
    @files.values.each do |file|
      if ["ActiveRecord::Base", "Spree::Base"].include? file.upper_class_name
        file.is_activerecord = true
      else
        not_active_files << file
      end
    end
    loop do
      length = not_active_files.length
      not_active_files.each do |file|
        key = file.upper_class_name
        if @files[key]&.is_activerecord
          file.is_activerecord = true
          not_active_files.delete(file)
        end
      end
      break if not_active_files.length == length
    end

    # extract the constraints from the active record file
    @activerecord_files = @files.select { |_key, x| x.is_activerecord }
    # @activerecord_files.each do |k,v|
    #   puts "#{k} #{v.getColumns.size}"
    # end
    # @activerecord_files = @files.select { |key, x| x.is_activerecord and x.getColumns.size > 0}
    # puts " ======== "
    # @activerecord_files.each do |k, v|
    #   puts "#{k} #{v.getColumns.size}"
    # end
  end

  def get_activerecord_files
    @activerecord_files
  end

  def print_columns
    # puts"---------------columns-----------------"
    get_activerecord_files.each do |key, file|
      # puts"#{key} #{file.getColumns.length}"
      file.getColumns.each do |key, column|
        # puts"\t#{column.column_name}"
      end
    end
  end

  def compare_custom_constriants(old_version)
    changed_functions = {}
    added_functions = {}
    deleted_functions = {}
    old_functions = old_version.validation_functions.map { |k, v| [k, v[1]] }.to_h
    new_functions = validation_functions.map { |k, v| [k, v[1]] }.to_h

    new_functions.each do |fn, ast|
      if old_functions[fn]
        changed_functions[fn] = [old_functions[fn], ast] if old_functions[fn].source != ast.source
      else
        added_functions[fn] = ast
      end
    end
    deleted_functions = old_functions.reject { |k, _v| new_functions[k] }

    [changed_functions, added_functions, deleted_functions]
  end

  def compare_constraints(old_version)
    newly_added_constraints = []
    changed_constraints = []
    existing_column_constraints = []
    new_column_constraints = []
    not_match_html_constraints = []
    @activerecord_files.each do |key, file|
      old_file = old_version.get_activerecord_files[key]
      # if the old file doesn't exist, which means it's newly created
      next unless old_file

      constraints = file.getConstraints
      old_constraints = old_file.getConstraints
      old_columns = old_file.getColumns
      constraints.each do |column_keyword, constraint|
        if old_constraints[column_keyword]
          unless constraint.is_same(old_constraints[column_keyword])
            changed_constraints << constraint
            if (constraint.type == Constraint::HTML) && !is_html_constraint_match_validate(old_constraints, column_keyword, constraint)
              not_match_html_constraints << constraint
            end
          end
        else
          newly_added_constraints << constraint
          column_name = constraint.column
          if old_columns[column_name]
            existing_column_constraints << constraint
          else
            new_column_constraints << constraint
          end
          if (constraint.type == Constraint::HTML) && !is_html_constraint_match_validate(old_constraints, column_keyword, constraint)
            not_match_html_constraints << constraint
          end
        end
      end
    end
    [newly_added_constraints, changed_constraints, existing_column_constraints, new_column_constraints, not_match_html_constraints]
  end

  def get_all_table_column_size
    col_size = {}
    @activerecord_files.each do |key, file|
      col_size[key] = file.getColumnsLength
    end
    col_size
  end

  def get_table_original_column_size(old_version)
    results = {}
    @activerecord_files.each do |key, file|
      old_file = old_version.get_activerecord_files[key]
      # if the old file doesn't exist, which means it's newly created
      next unless old_file

      constraints = file.getConstraints
      old_constraints = old_file.getConstraints
      old_columns = old_file.getColumns
      constraints.each do |column_keyword, constraint|
        if old_constraints[column_keyword]
        else
          column_name = constraint.column
          if old_columns[column_name]
          else
            results[key] = file.getColumnsLength
          end
        end
      end
    end
    results
  end

  def is_html_constraint_match_validate(old_constraints, column_keyword, constraint)
    key = column_keyword.gsub(Constraint::HTML, Constraint::MODEL)
    key2 = column_keyword.gsub(Constraint::HTML, Constraint::DB)
    old_model_constraint = old_constraints[key]
    old_db_constraint = old_constraints[key2]
    return true if constraint.is_same_notype(old_model_constraint) || constraint.is_same_notype(old_db_constraint)

    false
  end

  def compare_absent_constraints
    db_present_model_absent = []
    model_present_db_absent = []
    @activerecord_files.each do |_key, file|
      db_cons = file.getConstraints.select { |k, _v| k.include? "-#{Constraint::DB}" }
      model_cons = file.getConstraints.select { |k, _v| k.include? "-#{Constraint::MODEL}" }
      html_cons = file.getConstraints.select { |k, _v| k.include? "-#{Constraint::HTML}" }

      db_cons.each do |k, v|
        k2 = k.gsub("-#{Constraint::DB}", "-#{Constraint::MODEL}")
        column = file.getColumns[v.column]

        next if !column || column.is_deleted || model_cons[k2]

        if v.is_a?(Length_constraint) || v.is_a?(Presence_constraint)
          inclusion_key = k2.gsub(/Length_constraint|Presence_constraint/, "Inclusion_constraint")
          if model_cons[inclusion_key] && !model_cons[inclusion_key].range.nil?
            # do not consider constraint to be absent
            puts "Found replacement: #{inclusion_key}"
            next
          end
        end
        if v.is_a? Numericality_constraint
          inclusion_key = k2.gsub("Numericality_constraint", "Inclusion_constraint")
          if model_cons[inclusion_key] && !model_cons[inclusion_key].range.nil? &&
             model_cons[inclusion_key].range.all? { |v| is_number(v) }
            # do not consider constraint to be absent
            puts "Found replacement: #{inclusion_key}"
            next
          end
        end

        if (v.instance_of?(Uniqueness_constraint) || v.instance_of?(Presence_constraint)) && column.auto_increment
          db_present_model_absent << { name: k, category: :self_satisfied, value: v }
        elsif v.instance_of?(Presence_constraint) && column.default_value
          db_present_model_absent << { name: k, category: :self_satisfied, value: v }
        elsif model_cons[k.gsub("-#{v.class.name}-", "-#{Customized_constraint}-")]
          db_present_model_absent << { name: k, category: :other, value: v }
        elsif (v.column == "updated_at") || (v.column == "created_at")
          db_present_model_absent << { name: k, category: :timestamp, value: v }
        elsif file.getForeignKeys.include? v.column
          db_present_model_absent << { name: k, category: :fk, value: v }
        elsif v.is_a?(Length_constraint) && ((v.max_value == 255) || (v.max_value >= 65_535))
          db_present_model_absent << { name: k, category: :str_unlimited, value: v }
        elsif !file.contents.include? v.column
          db_present_model_absent << { name: k, category: :not_accessed, value: v }
        else
          db_present_model_absent << { name: k, category: :other, value: v }
        end
      end

      model_cons.each do |k, v|
        k2 = k.gsub("-#{Constraint::MODEL}", "-#{Constraint::DB}")
        column = file.getColumns[v.column]
        next if db_cons[k2]

        # Function constraints may not be associated with a column, so check this first
        if v.instance_of?(Customized_constraint) || v.instance_of?(Function_constraint)
          model_present_db_absent << { name: k, category: :custom, value: v }
          next
        elsif !column
          next
        elsif v.has_cond
          next
        end

        if v.instance_of?(Presence_constraint) && !column.default_value
          model_present_db_absent << { name: k, category: :presence_no_default, value: v }
        elsif v.instance_of?(Presence_constraint) && column.default_value
          model_present_db_absent << { name: k, category: :presence_has_default, value: v }
        elsif v.instance_of? Format_constraint
          model_present_db_absent << { name: k, category: :format, value: v }
        elsif v.instance_of?(Inclusion_constraint) || v.instance_of?(Exclusion_constraint)
          # puts "Inclusion #{v.to_string} #{column.column_type}"
          begin
            next if v.range && (eval(v.range) == [true, false]) && (column.column_type == "boolean")
          rescue SyntaxError => se
          end
          model_present_db_absent << { name: k, category: :inclusion_exclusion, value: v }
        elsif v.instance_of? Uniqueness_constraint
          model_present_db_absent << { name: k, category: :unique, value: v }
          # elsif v.instance_of?Customized_constraint or v.instance_of?Function_constraint
          #	model_present_db_absent << {:name => k, :category => :custom, :value => v}
        else
          model_present_db_absent << { name: k, category: :other, value: v }
        end
      end
    end

    puts "absent_category_count\tAppName\tAbsenceType\tCategory\tCount"
    puts "absent_category_count\t#{@app_dir}\tdb_present_model_absent\tself_satisfied\t#{db_present_model_absent.select { |v| v[:category] == :self_satisfied }.count}"
    puts "absent_category_count\t#{@app_dir}\tdb_present_model_absent\tfk\t#{db_present_model_absent.select { |v| v[:category] == :fk }.count}"
    puts "absent_category_count\t#{@app_dir}\tdb_present_model_absent\tstr_unlimited\t#{db_present_model_absent.select { |v| v[:category] == :str_unlimited }.count}"
    puts "absent_category_count\t#{@app_dir}\tdb_present_model_absent\tnot_accessed\t#{db_present_model_absent.select { |v| v[:category] == :not_accessed }.count}"
    puts "absent_category_count\t#{@app_dir}\tdb_present_model_absent\tother\t#{db_present_model_absent.select { |v| v[:category] == :other }.count}"

    puts ""

    puts "absent_category_count\t#{@app_dir}\tmodel_present_db_absent\tpresence_no_default\t#{model_present_db_absent.select { |v| v[:category] == :presence_no_default }.count}"
    puts "absent_category_count\t#{@app_dir}\tmodel_present_db_absent\tpresence_default\t#{model_present_db_absent.select { |v| v[:category] == :presence_has_default }.count}"
    puts "absent_category_count\t#{@app_dir}\tmodel_present_db_absent\tformat\t#{model_present_db_absent.select { |v| v[:category] == :format }.count}"
    puts "absent_category_count\t#{@app_dir}\tmodel_present_db_absent\tinclusion_exclusion\t#{model_present_db_absent.select { |v| v[:category] == :inclusion_exclusion }.count}"
    puts "absent_category_count\t#{@app_dir}\tmodel_present_db_absent\tunique\t#{model_present_db_absent.select { |v| v[:category] == :unique }.count}"
    puts "absent_category_count\t#{@app_dir}\tmodel_present_db_absent\tcustom\t#{model_present_db_absent.select { |v| v[:category] == :custom }.count}"
    puts "absent_category_count\t#{@app_dir}\tmodel_present_db_absent\tother\t#{model_present_db_absent.select { |v| v[:category] == :other }.count}"

    # not_accessed_total = 0
    # db_present_model_absent.select{|v| v[:category] == :not_accessed}.each do |v|
    # 		puts "Searching app for instances of #{v[:value].column}"
    # 	 	search_output = `grep -Rn --include=\\*{app,lib,script}/\\*.rb --exclude-dir={db,test,spec,views,log} #{v[:value].column} #{@app_dir} | grep -v "^\s*#" | wc -l`
    # 		puts "Search output: #{search_output}"
    # 		not_accessed_total += 1 if search_output.strip.to_i == 0
    # end
    # puts "absent_constraint\t#{@app_dir}\tdb_present_model_absent\tnot_accessed_total\t#{not_accessed_total}"

    db_present_model_absent.each do |v|
      puts "absent_constraint\t#{@app_dir}\tdb_present_model_absent\t#{v[:category]}\t#{v[:name]}"
    end

    model_present_db_absent.each do |v|
      puts "absent_constraint\t#{@app_dir}\tmodel_present_db_absent\t#{v[:category]}\t#{v[:name]}"
    end
  end

  def get_model_constraints
    total_constraints = @activerecord_files.map { |_k, v| v.getConstraints.length }.reduce(:+)
    output = []
    @activerecord_files.each do |_key, file|
      constraints = file.getConstraints
      model_cons = constraints.select { |k, _v| k.include? "-#{Constraint::MODEL}" }
      db_cons = file.getConstraints.select { |k, _v| k.include? "-#{Constraint::DB}" }
      model_cons.each do |k, v|
        exists_in_db = (db_cons[k.gsub("-#{Constraint::MODEL}", "-#{Constraint::DB}")] != nil)
        if v.instance_of? Presence_constraint
          output << { type: :presence, table: v.table, fields: v.column, exists_in_db: exists_in_db, if_cond: v.if_cond }
        elsif v.instance_of? Inclusion_constraint
          output << { type: :inclusion, table: v.table, fields: v.column, exists_in_db: exists_in_db, if_cond: v.if_cond }
        elsif v.instance_of? Uniqueness_constraint
          output << { type: :uniqueness, table: v.table, fields: [v.column] + v.scope, exists_in_db: exists_in_db, if_cond: v.if_cond }
        elsif v.instance_of? Format_constraint
          output << { type: :format, table: v.table, fields: v.column, exists_in_db: exists_in_db, value: v.with_format, if_cond: v.if_cond }
        end
      end
    end
    output
  end

  def compare_self
    # puts "@activerecord_files: #{@activerecord_files.length}"
    total_constraints = @activerecord_files.map { |_k, v| v.getConstraints.length }.reduce(:+)
    db_cons_num = 0
    model_cons_num = 0
    html_cons_num = 0
    mm_cons_num = 0
    absent_cons = {}
    absent_cons2 = {}
    mm_cons_num2 = 0
    puts "mismatch_constraint\tAppDir\tConstraintType\tCategory\tKey\tMin1\tMax1\tMin2\tMax2\tMismatchFields"
    @activerecord_files.each do |_key, file|
      constraints = file.getConstraints
      model_cons = constraints.select { |k, _v| k.include? "-#{Constraint::MODEL}" }
      db_cons = constraints.select { |k, _v| k.include? "-#{Constraint::DB}" }
      html_cons = constraints.select { |k, _v| k.include? "-#{Constraint::HTML}" }
      model_cons_num += model_cons.length
      db_cons_num += db_cons.length
      html_cons_num += html_cons.length
      db_cons.each do |k, v|
        k2 = k.gsub("-#{Constraint::DB}", "-#{Constraint::MODEL}")
        k3 = k2.gsub("-#{v.class.name}-", "-#{Customized_constraint}-")
        puts "k2 #{k2}"
        begin
          column_name = v.column
          column = file.getColumns[column_name]
          db_filename = column.file_class.filename
        rescue StandardError
          column_name = "nocolumn"
          db_filename = "nofile"
        end
        next unless column # if the column doesn't exist
        next if column.is_deleted # if the column is deleted

        # if column is auto increment, then uniquness constraint and presence constraint are not needed in models
        if v.instance_of?(Uniqueness_constraint) || v.instance_of?(Presence_constraint)
          next if column.auto_increment
        end
        # if column has default value, then the presence constraint is not needed.
        if v.instance_of? Presence_constraint
          next if column.default_value
        end
        if model_cons[k3]
          puts "customized constraints"
          next
        end
        if model_cons[k2]
          v2 = model_cons[k2]

          unless v.is_same_notype(v2)
            mismatch_category = "DB-Model"
            constraint_key = k2.gsub("-validate", "")
            db_min = v.is_a?(Length_constraint) && v.min_value ? v.min_value : ""
            db_max = v.is_a?(Length_constraint) && v.max_value ? v.max_value : ""
            model_min = v2.is_a?(Length_constraint) && v2.min_value ? v2.min_value : ""
            model_max = v2.is_a?(Length_constraint) && v2.max_value ? v2.max_value : ""
            mismatch_fields = compare_instance_variables(v, v2).reject { |a| a == "@type-db-validate" }

            mm_cons_num += 1

            puts "mismatch_constraint\t#{@app_dir}\t#{v.class.name}\t#{mismatch_category}\t#{constraint_key}\t#{db_min}\t#{db_max}\t#{model_min}\t#{model_max}\t#{mismatch_fields}"
          end
        else
          absent_cons[k] = v
          v.self_print
          puts "absent: #{column_name} #{v.table} #{db_filename} #{v.class.name} #{@commit}"
        end
      end

      model_cons.each do |k, v|
        k2 = k.gsub("-#{Constraint::MODEL}", "-#{Constraint::HTML}")
        puts "k2 #{k2}"
        begin
          column_name = v.column
          column = file.getColumns[column_name]
          model_filename = column.file_class.filename
        rescue StandardError
          column_name = "nocolumn"
          model_filename = "nofile"
        end
        if html_cons[k2]
          v2 = html_cons[k2]

          unless v.is_same_notype(v2)
            mismatch_category = "Model-HTML"
            constraint_key = k2.gsub("-#{Constraint::HTML}", "")
            model_min = v.is_a?(Length_constraint) && v.min_value ? v.min_value : ""
            model_max = v.is_a?(Length_constraint) && v.max_value ? v.max_value : ""
            html_min = v2.is_a?(Length_constraint) && v2.min_value ? v2.min_value : ""
            html_max = v2.is_a?(Length_constraint) && v2.max_value ? v2.max_value : ""
            mismatch_fields = compare_instance_variables(v, v2).reject { |a| a == "@type-validate-html" }

            mm_cons_num2 += 1

            puts "mismatch_constraint\t#{@app_dir}\t#{v.class.name}\t#{mismatch_category}\t#{constraint_key}\t#{model_min}\t#{model_max}\t#{html_min}\t#{html_max}\t#{mismatch_fields}"
          end
        else
          absent_cons2[k] = v
          v.self_print
          puts "absent2: #{column_name} #{v.table} #{model_filename} #{v.class.name} #{@commit}"
        end
      end
    end
    compare_absent_constraints
    puts "total absent: #{absent_cons.size} total_constraints: #{total_constraints} model_cons_num: #{model_cons_num} db_cons_num: #{db_cons_num} mm_cons_num: #{mm_cons_num}"
    puts "total absent2: #{absent_cons2.size} total_constraints: #{total_constraints} html_cons_num: #{html_cons_num} model_cons_num: #{model_cons_num}  mm_cons_num2: #{mm_cons_num2}"
  end

  def column_stats
    num_column = 0
    num_column_has_constraints = 0
    @activerecord_files.each do |_k, v|
      n, nh = v.num_columns_has_constraints
      num_column += n
      num_column_has_constraints += nh
    end
    [num_column, num_column_has_constraints]
  end

  def clean
    @files = nil
    @concerns = nil
    @validation_functions = nil
    @activerecord_files.each do |_key, file|
      file.ast = nil
      file.functions = nil
      file.contents = nil
      file.included_concerns = nil
      file&.getColumns.each do |_name, column|
        column.file_class&.ast = nil
        column.prev_column&.file_class&.ast = nil
      end
    end
  end

  def build
    extract_files
    annotate_model_class
    extract_constraints
    apply_concerns
    print_columns
    #extract_queries
    begin
      calculate_loc
    rescue StandardError
    end
    extract_validate_functions
  end

  def apply_concerns
    @activerecord_files.each_value do |file|
      file.included_concerns.each do |con_name|
        con = @concerns[con_name]
        next unless con

        file.has_many_classes = con.has_manys.each_with_object(file.has_many_classes) do |obj, memo|
          # TODO: dic["dependent"]
          memo[obj] = true
        end
        file.has_one_classes = con.has_ones.each_with_object(file.has_one_classes) do |obj, memo|
          # TODO: dic["dependent"]
          memo[obj] = true
        end
        file.foreign_keys += con.belongs_tos.to_a
        file.has_belong_classes += con.has_belongs
      end
    end
  end

  def extract_validate_functions
    all_functions = {}
    @activerecord_files.each do |_key, file|
      functions = file.functions
      functions.each do |k, v|
        all_functions[k] = v
      end
    end
    @activerecord_files.each do |_key, file|
      file.getConstraints.each do |_k, constraint|
        next unless constraint.type == Constraint::MODEL

        next unless constraint.instance_of? Function_constraint

        funcname = constraint.funcname
        v = all_functions[funcname]
        validation_functions[funcname] = [file, v] if v
      end
    end
  end

  def print_validate_functions
    contents = ""
    validation_functions.each do |k, value|
      file = value[0]
      v = value[1]
      contents += "====start of function #{k}====\n"
      contents += "in file: #{file.filename}\n"
      contents += "#{v.source}\n"
      contents += "====end of function #{k}====\n"
    end
    contents
  end

  def calculate_loc
    app_subdir = File.join(@app_dir, "app")
    db_subdir = File.join(@app_dir, "db")
    if app_dir.include? "spree"
      app_subdir = File.join(@app_dir, "*/app")
      db_subdir = File.join(@app_dir, "*/db")
    end
    output = `cloc --json #{app_subdir} #{db_subdir}`
    begin
      json_output = JSON.parse(output)

      ruby_loc = json_output.fetch("Ruby", {}).fetch("code", 0)
      erb_loc = json_output.fetch("ERB", {}).fetch("code", 0)
      haml_loc = json_output.fetch("Haml", {}).fetch("code", 0)
      html_loc = json_output.fetch("HTML", {}).fetch("code", 0)

      @loc = ruby_loc + erb_loc + haml_loc + html_loc
    rescue StandardError
      @loc = 0
    end
  end

  def find_non_destroy_assoc
    non_destroy_assocs = []
    @activerecord_files.each do |key, file|
      no_destroy_tables = file.has_many_classes.reject { |_k, v| v }.map { |k, _v| k }
      puts "no_destroy_tables: #{no_destroy_tables.size}"
      no_destroy_tables.each do |column|
        class_name = convert_tablename(column)
        class_class = @activerecord_files[class_name] || @activerecord_files["Spree" + class_name]
        # puts "class_name: #{class_name}"
        # puts @activerecord_files.keys
        next unless class_class

        key = key[5..-1] if key.include? "Spree"
        p_c_k = "#{class_name}-#{key.downcase}-#{Presence_constraint}-#{Constraint::MODEL}"
        p_c_k2 = "Spree" + p_c_k
        # puts "p_c_k #{p_c_k}"
        # puts "#{class_class.getConstraints.map{|k,v| k}}"
        if class_class.getConstraints[p_c_k] || class_class.getConstraints[p_c_k2]
          non_destroy_assocs << [key, column]
          # puts "#{p_c_k} #{non_destroy_assocs.size}"
        end
      end
    end
    non_destroy_assocs
  end

  def class_with_custom_function
    cwcf = {}
    cnt = 0
    @activerecord_files.each do |key, file|
      size = file.getConstraints.select { |_k, v| v.instance_of? Customized_constraint or v.instance_of? Function_constraint }.size
      if size > 0
        cwcf[key] = size
        cnt += 1
      end
    end
    cwcf
  end
end
