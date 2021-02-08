def parse_model_constraint_file(ast, poly = false)
  if ast.type.to_s == "list"
    ast.children.each do |child|
      parse_model_constraint_file(child)
    end
  end
  if ast.type.to_s == "module"
    moduleName = ast[0]&.source
    $module_name += moduleName
    if ast[1] and ast[1].type.to_s == "list"
      ast[1].each do |child|
        parse_model_constraint_file(child)
      end
    end
    $module_name.chomp!(moduleName)
  end
  if ast.type.to_s == "class"
    c1 = ast.children[0]
    c2 = ast.children[1]
    if c1 and c1.type.to_s == "const_ref" and c2 and (c2.type.to_s == "var_ref" or c2.type.to_s == "const_path_ref")
      # puts "c1.source #{c1.source} class_name #{$cur_class.class_name}"
      if $cur_class.class_name
        $classes << $cur_class.dup
      end
      $cur_class.class_name = $module_name + c1.source
    end
    if c2 and (c2.type.to_s == "var_ref" or c2.type.to_s == "const_path_ref")
      $cur_class.upper_class_name = c2.source
    end
    # puts"filename: #{$cur_class.filename} "
    # puts"classname: #{$cur_class.class_name} upper_class_name: #{$cur_class.upper_class_name}"
    c3 = ast.children[2]
    if c3
      parse_model_constraint_file(c3)
    end
  end

  if ast.type.to_s == "vcall" && ast.source == "acts_as_watchable"
    $cur_class.addHasManyAs("watchable")
  end
  # TODO: These are too narrow, needs to be fixed
  if ast.type.to_s == "vcall" && ast.source == "acts_as_followable"
    $cur_class.addHasManyAs("followable")
  end
  if ast.type.to_s == "vcall" && ast.source == "acts_as_follower"
    $cur_class.addHasManyAs("follower")
  end
  if ast.type.to_s == "vcall" && ast.source == "acts_as_taggable"
    $cur_class.addHasManyAs("taggable")
  end

  if ast.type.to_s == "command"
    funcname = ast[0].source
    if funcname == "with_options" && ast.children[1].source.start_with?("polymorphic")
      do_block = ast.children[2].jump(:do_block)
      do_block[1].each do |cmd|
        parse_model_constraint_file(cmd, true)
      end
    end
    if funcname == "before_save"
      $cur_class.addBeforeSaveFcuntions(parse_before_saves(ast))
    end
    if $validate_apis and $validate_apis.include? funcname
      # puts"funcname #{funcname} #{ast.source}"
      constraints = parse_validate_constraint_function($cur_class.class_name, funcname, ast[1])
      $cur_class.addConstraints(constraints) if constraints.length > 0
    end
    if funcname == "belongs_to"
      key_field = parse_foreign_key(ast[1])
      if key_field
        $cur_class.addForeignKey(key_field)
      end
    end
    if funcname == "has_many" || funcname == "belongs_to" || funcname == "has_one"
      columns = []
      dic = {}
      # puts "#{funcname} #{ast.type}"
      ast[1].children.each do |child|
        if child.type.to_s == "symbol_literal"
          column = handle_symbol_literal_node(child)
          columns << column
        end
        # puts"child.type.to_s #{child.type.to_s} #{child.source}"
        if child.type.to_s == "list"
          child.each do |c|
            if c.type.to_s == "assoc"
              key, value = handle_assoc_node(c)
              if key and value
                dic[key] = value
              end
            end
          end
        end
        # puts "dict = #{dic} || columns = #{columns}"
        # puts ""
      end
      if funcname == "has_one"
        if dic.has_key? "as"
          $cur_class.addHasManyAs(handle_symbol_literal_node(dic["as"]))
        end
      end

      if funcname == "has_many"
        columns.each do |column|
          $cur_class.addHasMany(column, dic)
        end
        if dic.has_key? "as"
          $cur_class.addHasManyAs(handle_symbol_literal_node(dic["as"]))
        end
      end
      if funcname == "belongs_to"
        cs = []
        columns.each do |column|
          unless dic["optional"]&.source == "true"
            type = Constraint::MODEL
            constraint = Presence_constraint.new($cur_class.class_name, column, type, nil, nil)
            cs << constraint
            #$cur_class.addConstraints(cs) if cs.length > 0
          end
        end
        if (dic.has_key? "polymorphic" and dic["polymorphic"].source == "true") or poly
          if columns.length != 1
            puts "[Poly Error] Columns has length greater than 1, columns " + columns.to_s
          end
          $cur_class.addBelongsToPoly(columns[0])
        end
      end
      if !dic["polymorphic"].nil?
        columns.each do |column|
          type = Constraint::MODEL
          constraint = Inclusion_constraint.new($cur_class.class_name, column + "_type", type, nil, nil)
          cs << constraint
        end
      end
    end
    if funcname == "state_machine"
      # puts ast.source
      rets = parse_state_field(ast[1][0])
      column = rets[0]
      # step into do block
      possible_values = rets[1]
      ast[2].children[0].each do |ast|
        # possible_values += parse_cmd_get_fields(ast)
      end
      constraint = Inclusion_constraint.new($cur_class.class_name, column, Constraint::MODEL)
      constraint.range = possible_values.uniq
      #puts constraint.to_string
      $cur_class.addConstraints([constraint])
    end
  end
  if ast.type.to_s == "def"
    funcname = ast[0].source
    $cur_class.addFunction(funcname, ast)
    if $cur_class.getBeforeSaveFunctions().include? funcname
      cs = parse_before_save_constraint_function(ast)
      $cur_class.addConstraints(cs) if cs.length > 0
    end
    if $cur_class.getValidateFunction().include? funcname
      # puts "-----------"
      # puts ast.source
      # puts "-----------"
      parse_if_error_pattern(ast)
    end
  end

  if ast.type.to_s == "fcall" && ast[0].source == "before_save"
    # before_save do
    #  self.build_tags
    #  self.construct_full_name
    # end
    # step into do block
    ast[2].children[0].each do |child|
      if child[0].source == "self" &&
         child[1].source == "." &&
         child[2].type.to_s == "ident"
        $cur_class.addBeforeSaveFcuntions([child[2].source])
      end
    end
  end
end

def parse_state_field(ast)
  possible_fields = []
  column = nil
  if ast.type.to_s == "symbol_literal"
    column = handle_symbol_literal_node(ast)
  end
  if ast.type.to_s == "list"
    ast.each do |child|
      if handle_label_node(child[0]) == "initial"
        possible_fields << handle_symbol_literal_node(child[1])
      end
    end
  end
  if column.nil?
    column = "state"
  end
  return [column, possible_fields]
end

def check_condition(cond)
  fields = []
  if cond.type.to_s == "arg_paren" && cond.children[0].type.to_s == "string_literal"
    return true, fields
  end
  if cond.type.to_s == "vcall"
    fields << cond.source
    return true, fields
  end
  if cond.type.to_s == "int"
    return true, fields
  end
  if cond.type.to_s == "call" && cond[2].source == "include?" && cond[3][0][0].type.to_s == "string_literal"
    fields << cond[0].source
    return true, fields
  end
  # e = field.nil? or empty
  # s = s || e
  if cond.type.to_s == "call" &&
     (cond[2].source == "nil?" || cond[2].source == "length" \
       || cond[2].source == "size")
    fields << cond[0].source
    return true, fields
  end
  # lhs binop rhs
  # lhs or rhs can be constant
  lhs_ret = if cond.type.to_s == "binary"
      lhs_ret = check_condition(cond[0])
      rhs_ret = check_condition(cond[2])
      if lhs_ret[0] && rhs_ret[0]
        fields += lhs_ret[1] + rhs_ret[1]
        return true, fields
      end
      # return [{ "opt" => cond[1], "lhs" => cond[0].source, "rhs" => cond[2].source }
    end
  return false, []
end

def check_if_error_field(ast)
  conds = []
  fields = []
  if (ast.type.to_s == "command_call" || ast.type.to_s == "call") && ast[0].source == "errors"
    return true, [], []
  end
  # puts ast.type.to_s
  if ast.type.to_s == "if" || ast.type.to_s == "if_mod" || ast.type.to_s == "unless_mod"
    # check conditions only contains fields
    ret = check_condition(ast[0])
    if !ret[0]
      # puts ast.source + "   Condition not OK"
      return false, [], []
    end
    conds << ast[0]
    fields += ret[1]
    # puts "check body---" + ast[1].type.to_s
    # puts "check body---" + ast[1][0].source
    ret = check_if_error_field(ast[1])
    if ret[0]
      conds = conds + ret[1]
      fields = fields + ret[2]
      return true, conds, fields
    end
    ast[1].children.each do |child|
      ret = check_if_error_field(child)
      if ret[0]
        conds = conds + ret[1]
        fields = fields + ret[2]
        return true, conds, fields
      end
    end
  end
  return false, [], []
end

def parse_if_error_pattern(ast)
  ast[2].children.each do |child|
    ret = check_if_error_field(child)
    if ret[0]
      cs = Customized_constraint_if.new($cur_class.class_name, Random.rand(10).to_s, Constraint::MODEL, nil, nil)
      cs.src = ast.source
      if ret[1].length > 0
        # puts ret[1].to_s
        # puts "++++++++++++"
      end
      cs.cond = ret[1]
      cs.fields = ret[2]
      $cur_class.addConstraints([cs])
    end
  end
end

def parse_event_cmd(ast)
  possible_fields = []
  ast = ast.jump(:do_block)
  if ast.children.length != 1
    puts "[Error] even do block can only have one transition " + ast.children.to_
  end
  ast = ast.children[0][0]
  if ast[0].source == "transition"
    # transition available: :stopped
    ast = ast[1].jump(":assoc")[0]
    ast.each do |assoc|
      field1 = assoc[0].source if assoc[0].type.to_s == "vcall" # any
      field1 ||= handle_label_node(assoc[0]) if assoc[0].type.to_s == "label"
      next if field1 == "if"
      if field1 != "from" && field1 != "to" && field1 != "any"
        possible_fields << field1
      end
      if assoc[1].type.to_s == "array"
        fields = handle_array_node(assoc[1])
        possible_fields += fields if !fields.nil?
      elsif assoc[1].type.to_s == "symbol_literal"
        possible_fields << handle_symbol_literal_node(assoc[1])
      end
    end
  end
  return possible_fields
end

def parse_cmd_get_fields(cmd)
  possible_fields = []
  if cmd.children[0].source == "event"
    possible_fields += parse_event_cmd(cmd)
  end

  if cmd.children[0].source == "state"
    cmd.children[1].each do |child|
      if child && child.type.to_s == "symbol_literal"
        possible_fields << handle_symbol_literal_node(child)
      end
    end
  end
  return possible_fields
end

def parse_foreign_key(ast)
  dic = {}
  key_field = ""
  if ast[0].type.to_s == "symbol_literal"
    key_field = handle_symbol_literal_node(ast[0]) + "_id"
    if ast[1] and ast[1].type.to_s == "list"
      ast[1].each do |child|
        if child.type.to_s == "assoc"
          key, value = handle_assoc_node(child)
          if key and value
            dic[key] = value
          end
        end
      end
    end
  end
  if !dic.empty? and dic.has_key? "foreign_key" and dic["foreign_key"].type.to_s == "string_literal"
    key_field = handle_string_literal_node(dic["foreign_key"])
  end
  return key_field
end

def is_all_db_fields(fields)
  # fields.each do |field|
  #   if !$cur_class.getColumns().include? field
  #     return false
  #   end
  # end
  # puts "++++++++++++++++++++"
  # puts fields.to_s
  # puts $cur_class.getColumns().to_s
  # puts "++++++++++++++++++++"
  return true
end

def check_binary_opt_get_fields(ast)
  fields = []
  while ast.type.to_s == "binary"
    if !is_all_db_fields([ast[2].source])
      return []
    end
    fields << ast[2].source
    ast = ast[0]
  end
  return fields
end

def find_symbol_assignments(ast, ident)
  rhs_fields = []
  sources = []
  if ast.type.to_s == "assign" && ast[0].source == ident
    # check if only has binary operators
    fields = check_binary_opt_get_fields(ast[1])
    if fields.length == 0
      fields = check_built_in_get_fields(ast[1])[1]
    end

    sources += [ast.source]
    rhs_fields += fields
    return rhs_fields, sources
  end

  if ast.type.to_s == "opassign" && ast[0].source == ident
    rhs_fields += [ast[2].source]
    sources += [ast.source]
    return rhs_fields, sources
  end

  ast.children.each do |child|
    rets = find_symbol_assignments(child, ident)
    rhs_fields += rets[0]
    sources += rets[1]
  end
  return rhs_fields, sources
end

def parse_before_save_constraint_function(ast)
  constraints = []
  constraints += parse_downcase_and_equal_constraint(ast)
  constraints += parse_builtin_assign(ast)
  # puts "----[Before save constraints]-----" + constraints.length.to_s
  return constraints
end

def find_vars(ast)
  vars = []
  if ast.type.to_s == "var_ref"
    vars << ast.source
  end
  ast.children.each do |child|
    vars += find_vars(child)
  end
  return vars
end

def check_built_in_get_fields(ast)
  fields = []
  if ast.type.to_s == "call"
    if !["many?", "first", "split", "downcase", "strip", "size"].include? ast[2].source
      return false, []
    end
    fields << ast[0].source
  end
  ast.children.each do |child|
    if !check_built_in_get_fields(child)[0]
      return false, []
    end
  end
  return true, fields
end

# def set_environment_type
#   names = name.split('/')
#   self.environment_type = names.many? ? names.first : nil
# end

# def update_storage_size
#   storage_size = repository_size + wiki_size + lfs_objects_size + build_artifacts_size + packages_size
#   # The `snippets_size` column was added on 20200622095419 but db/post_migrate/20190527194900_schedule_calculate_wiki_sizes.rb
#   # might try to update project statistics before the `snippets_size` column has been created.
#   storage_size += snippets_size if self.class.column_names.include?("snippets_size")

#   # The `pipeline_artifacts_size` column was added on 20200817142800 but db/post_migrate/20190527194900_schedule_calculate_wiki_sizes.rb
#   # might try to update project statistics before the `pipeline_artifacts_size` column has been created.
#   storage_size += pipeline_artifacts_size if self.class.column_names.include?("pipeline_artifacts_size")

#   # The `uploads_size` column was added on 20201105021637 but db/post_migrate/20190527194900_schedule_calculate_wiki_sizes.rb
#   # might try to update project statistics before the `uploads_size` column has been created.
#   storage_size += uploads_size if self.class.column_names.include?("uploads_size")

#   self.storage_size = storage_size
# end
def parse_builtin_assign(ast)
  constraints = []
  body = ast[2]
  body.children.each do |child|
    left_field = child[0].jump(:ident).source
    if child.type.to_s == "assign" && is_all_db_fields([left_field])
      vars = find_vars(child[1]).uniq
      if check_built_in_get_fields(child[1])[0]
        input_fields = []
        fds = []
        vars.each do |var|
          if var != "nil" && var != "self"
            rets = find_symbol_assignments(body, var)
            fds += rets[1]
            input_fields += rets[0]
          end
        end
        if input_fields.length > 0
          fds << child.source
          cs = FD_constraint.new($cur_class.class_name, left_field, Constraint::DB)
          cs.input_fields = input_fields
          cs.fd = fds
          constraints << cs
          puts cs.to_string
          puts "----------"
        end
      end
    end
  end
  return constraints
end

def parse_downcase_and_equal_constraint(ast)
  constraints = []
  if ast.type.to_s == "assign"
    rhs = ast[1]
    lhs = ast[0]

    left_field = lhs.jump(:ident).source
    if is_all_db_fields([left_field])
      # self.name_lower = name.downcase
      # self.full_name = [self.first_name, self.last_name].join(' ').downcase.strip
      # self.markdown_character_count = body_markdown.size
      if (rhs.type.to_s == "call" && rhs[2].source == "downcase") ||
         (rhs.type.to_s == "call" && rhs[2].source == "strip" && rhs[0][2].source == "downcase") ||
         (rhs.type.to_s == "call" && rhs[2].source == "size")
        rhs_fields = []
        rhs.jump(:array)[0].each do |field|
          rhs_fields << field.jump(:ident).source
        end
        rhs_fields = [rhs[0].source] if rhs_fields.length == 0
        # check if right/left fields are db fields
        if is_all_db_fields(rhs_fields)
          cs = FD_constraint.new($cur_class.class_name, left_field, Constraint::DB)
          cs.input_fields = rhs_fields
          cs.fd = rhs.source
          puts cs.to_string
          puts "----------"
          constraints << cs
        end
      end
    end
  end
  ast.children.each do |child|
    constraints += parse_downcase_and_equal_constraint(child)
  end
  return constraints
end

def parse_validate_constraint_function(table, funcname, ast)
  type = Constraint::MODEL
  constraints = []
  if funcname == "validates" or funcname == "validates!"
    constraints += parse_validates(table, funcname, ast)
  elsif funcname == "validate"
    cons = handle_validate(table, type, ast)
    constraints += cons
  elsif funcname == "validates_with" #https://guides.rubyonrails.org/active_record_validations.html#validates-with
    cons = parse_validates_with(table, type, ast)
    constraints += cons
  elsif funcname == "validates_each" #https://guides.rubyonrails.org/active_record_validations.html#validates-each
    # puts "funcname is : validates_each #{ast.type.to_s}"
    cons = parse_validates_each(table, type, ast)
    constraints += cons
  elsif funcname.include? "_"
    columns = []
    dic = {}
    ast.children.each do |child|
      if child.type.to_s == "symbol_literal"
        column = handle_symbol_literal_node(child)
        columns << column
      end
      # puts"child.type.to_s #{child.type.to_s} #{child.source}"
      if child.type.to_s == "list"
        child.each do |c|
          if c.type.to_s == "assoc"
            key, value = handle_assoc_node(c)
            if key and value
              dic[key] = value
            end
          end
        end
      end
    end
    allow_blank = false
    allow_nil = false
    if dic["allow_blank"] and dic["allow_blank"].source == "true"
      allow_blank = true
    end
    if dic["allow_nil"] and dic["allow_nil"].source == "true"
      allow_nil = true
    end
    if columns.length > 0
      if funcname == "validates_exclusion_of"
        columns.each do |column|
          constraint = Exclusion_constraint.new(table, column, type, allow_nil, allow_blank)
          constraint.parse(dic)
          constraints << constraint
        end
      end
      if funcname == "validates_inclusion_of"
        columns.each do |column|
          constraint = Inclusion_constraint.new(table, column, type, allow_nil, allow_blank)
          constraint.parse(dic)
          constraints << constraint
        end
      end
      if funcname == "validates_presence_of"
        columns.each do |column|
          constraint = Presence_constraint.new(table, column, type, allow_nil, allow_blank)
          constraint.parse(dic)
          constraints << constraint
        end
      end
      if funcname == "validates_length_of" or funcname == "validates_size_of"
        columns.each do |column|
          constraint = Length_constraint.new(table, column, type, allow_nil, allow_blank)
          constraint.parse(dic)
          constraints << constraint
        end
      end
      if funcname == "validates_format_of"
        columns.each do |column|
          constraint = Format_constraint.new(table, column, type, allow_nil, allow_blank)
          constraint.parse(dic)
          constraints << constraint
        end
      end
      if funcname == "validates_uniqueness_of"
        columns.each do |column|
          constraint = Uniqueness_constraint.new(table, column, type, allow_nil, allow_blank)
          constraint.parse(dic)
          constraints << constraint
        end
      end
      if funcname == "validates_numericality_of"
        columns.each do |column|
          constraint = Numericality_constraint.new(table, column, type, allow_nil, allow_blank)
          constraint.parse(dic)
          constraints << constraint
        end
      end
      if funcname == "validates_acceptance_of"
        columns.each do |column|
          constraint = Acceptance_constraint.new(table, column, type)
          constraint.parse(dic)
          constraints << constraint
        end
      end
    end
  end
  return constraints
end

def list_contains_conditional(list_node)
  result = false
  list_node.each do |child|
    if child.type.to_s == "assoc"
      cur_key, cur_value = handle_assoc_node(child)
      # puts "cur_constr #{cur_constr}"
      if cur_key == "if" or cur_key == "unless"
        result = true
      end
    end
  end

  return result
end

def parse_before_saves(ast)
  columns = []
  ast[1].children.each do |child|
    if child.type.to_s == "symbol_literal"
      column = handle_symbol_literal_node(child)
      columns << column
    end
  end
  return columns
end

def parse_validates(table, funcname, ast)
  type = "validate"
  constraints = []
  columns = []
  cur_constrs = []
  dic = {}
  # puts "ast: #{ast&.children&.length}"
  ast.children.each do |child|
    if child.type.to_s == "symbol_literal"
      column = handle_symbol_literal_node(child)
      columns << column
    end
    if child.type.to_s == "list"
      # first check for conditional
      has_conditional = list_contains_conditional(child)
      child.each do |c|
        node = c
        if node.type.to_s == "assoc"
          cur_constr, cur_value_ast = handle_assoc_node(node)
          # puts "cur_constr #{cur_constr}"
          next unless cur_constr
          if cur_value_ast.type.to_s == "hash"
            dic = handle_hash_node(cur_value_ast)
          end
          if cur_constr == "presence"
            cur_value = cur_value_ast.source
            if cur_value == "true"
              columns.each do |c|
                constraint = Presence_constraint.new(table, c, type)
                constraint.parse(dic)
                constraint.has_cond = has_conditional
                constraints << constraint
              end
            end
          end
          if cur_constr == "format"
            if dic
              columns.each do |c|
                constraint = Format_constraint.new(table, c, type)
                constraint.parse(dic)
                constraints << constraint
              end
            end
          end
          if cur_constr == "inclusion"
            cur_value = cur_value_ast.source
            columns.each do |c|
              constraint = Inclusion_constraint.new(table, c, type)
              constraint.parse_range(cur_value_ast)
              constraint.parse(dic)
              constraints << constraint
              if cur_value_ast.type.to_s == "array"
                constraint.range = cur_value
              end
            end
          end
          if cur_constr == "exclusion"
            cur_value = cur_value_ast.source
            columns.each do |c|
              constraint = Exclusion_constraint.new(table, c, type)
              constraint.range = cur_value
              constraint.parse(dic)
              constraints << constraint
            end
          end
          if cur_constr == "length"
            if dic
              columns.each do |c|
                constraint = Length_constraint.new(table, c, type)
                success_parse = constraint.parse(dic)
                if success_parse
                  constraints << constraint
                end
              end
            end
          end
          if cur_constr == "numericality"
            if cur_value_ast&.source == "true"
              dic = {}
            end
            if dic
              columns.each do |c|
                constraint = Numericality_constraint.new(table, c, type)
                constraint.parse(dic)
                constraints << constraint
              end
            end
          end
          if cur_constr == "uniqueness"
            if cur_value_ast.source == "true"
              dic = {}
            end
            if dic
              columns.each do |c|
                constraint = Uniqueness_constraint.new(table, c, type)
                constraint.parse(dic)
                constraints << constraint
              end
            end
          end
          if cur_constr == "acceptance"
            if cur_value_ast.source == "true"
              dic = {}
            end
            if dic
              columns.each do |c|
                constraint = Acceptance_constraint.new(table, c, type)
                constraint.parse(dic)
                constraints << constraint
              end
            end
          end
          if cur_constr == "confirmation"
            cur_value = cur_value_ast.source
            if cur_value == "true"
              dic = {}
            end
            if dic
              columns.each do |c|
                constraint = Confirmation_constraint.new(table, c, type)
                constraint.parse(dic)
                constraints << constraint
              end
            end
          end
        end
      end
    end
  end
  return constraints
end

def handle_validate(table, type, ast)
  constraints = []
  if ast.type.to_s === "list"
    ast.children.each do |c|
      if c.type.to_s == "symbol_literal"
        funcname = handle_symbol_literal_node(c)
        $cur_class.addValidateFunction(funcname)
        con = Function_constraint.new(table, nil, type)
        con.funcname = funcname
        constraints << con
      end
    end
  end
  constraints
end

def parse_validates_with(table, type, ast)
  constraints = []
  if ast.type.to_s === "list"
    ast.children.each do |c|
      if c.type.to_s == "symbol_literal"
        column = handle_symbol_literal_node(c)
        con = Customized_constraint.new(table, column, type)
        constraints << con
      end
    end
  end
  constraints
end

def parse_validates_each(table, type, ast)
  constraints = []
  # puts "ast.type.to_s #{ast.type.to_s}"
  if ast.type.to_s === "list"
    ast.children.each do |c|
      # puts "c: #{c.type.to_s}|#{c.source}"
      column = handle_symbol_literal_node(c) || handle_string_literal_node(c)
      # puts "column: #{column} #{column==nil}"
      if column
        con = Customized_constraint.new(table, column, type)
        constraints << con
      end
    end
  end
  # puts "create parse_validates_each constriants #{constraints.size} #{constraints[0].column}-#{constraints[0].class.name}-#{type}" if constraints.size > 0
  constraints
end
