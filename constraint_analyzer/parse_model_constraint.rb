def parse_model_constraint_file(ast)
  if ast.type.to_s == "list"
    ast.children.each do |child|
      parse_model_constraint_file(child)
    end
  end
  if ast.type.to_s == "module"
    moduleName = ast[0]&.source
    $module_name += moduleName
    if ast[1] && (ast[1].type.to_s == "list")
      ast[1].each do |child|
        parse_model_constraint_file(child)
      end
    end
    $module_name.chomp!(moduleName)
  end
  if ast.type.to_s == "class"
    c1 = ast.children[0]
    c2 = ast.children[1]
    if c1 && (c1.type.to_s == "const_ref") && c2 && ((c2.type.to_s == "var_ref") || (c2.type.to_s == "const_path_ref"))
      # puts "c1.source #{c1.source} class_name #{$cur_class.class_name}"
      if $cur_class.class_name
        $classes << $cur_class.dup
      end
      $cur_class.class_name = $module_name + c1.source
    end
    if c2 && ((c2.type.to_s == "var_ref") || (c2.type.to_s == "const_path_ref"))
      $cur_class.upper_class_name = c2.source
    end
    # puts"filename: #{$cur_class.filename} "
    # puts"classname: #{$cur_class.class_name} upper_class_name: #{$cur_class.upper_class_name}"
    c3 = ast.children[2]
    if c3
      parse_model_constraint_file(c3)
    end
  end
  if ast.type.to_s == "command"
    funcname = ast[0].source
    if $read_constraints && $validate_apis&.include?(funcname)
      # puts"funcname #{funcname} #{ast.source}"
      constraints = parse_validate_constraint_function($cur_class.class_name, funcname, ast[1])
      $cur_class.addConstraints(constraints) unless constraints.empty?
    end
    if funcname == "include"
      $cur_class.included_concerns << ast[1].source
    end
    if funcname == "belongs_to"
      key_field = parse_foreign_key(ast[1])
      if key_field
        # puts "foreign key: #{key_field}"
        $cur_class.addForeignKey(key_field)
      end
    end
    if %w[has_many has_one belongs_to has_and_belongs_to_many].include? funcname
      columns = []
      dic = {}
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
              if key && value
                dic[key] = value
              end
            end
          end
        end
      end
      case funcname
      when "has_many"
        columns.each do |column|
          # puts "#{column} #{dic}"
          $cur_class.addHasMany(column.singularize, dic)
          $cur_class.addRelation(column, dic, "has_many")
        end
      when "has_one"
        columns.each do |column|
          $cur_class.has_one_classes[column] = dic["dependent"] ? true : false
          $cur_class.addRelation(column, dic, "has_one")
        end
      when "has_and_belongs_to_many"
        columns.each do |column|
          $cur_class.has_belong_classes << column.singularize
          $cur_class.addRelation(column, dic, "has_and_belongs_to_many")
        end
      when "belongs_to"
        cs = []
        columns.each do |column|
          $cur_class.addRelation(column, dic, "belongs_to")
          unless dic["optional"]&.source == "true"
            type = Constraint::MODEL
            constraint = Presence_constraint.new($cur_class.class_name, column, type, nil, nil)
            cs << constraint
          end
        end
      end
      unless dic["polymorphic"].nil?
        columns.each do |column|
          type = Constraint::MODEL
          constraint = Inclusion_constraint.new($cur_class.class_name, column + "_type", type, nil, nil)
          cs << constraint
        end
      end
    end
  end
  if ast.type.to_s == "def"
    funcname = ast[0].source
    $cur_class.addFunction(funcname, ast)
  end
end

def parse_foreign_key(ast)
  dic = {}
  key_field = ""
  if ast[0].type.to_s == "symbol_literal"
    key_field = handle_symbol_literal_node(ast[0])
    if ast[1] && (ast[1].type.to_s == "list")
      ast[1].each do |child|
        if child.type.to_s == "assoc"
          key, value = handle_assoc_node(child)
          if key && value
            dic[key] = value
          end
        end
      end
    end
  end
  if !dic.empty? && dic.key?("foreign_key") && (dic["foreign_key"].type.to_s == "string_literal")
    key_field = handle_string_literal_node(dic["foreign_key"])
  end
  key_field
end

def parse_validate_constraint_function(table, funcname, ast)
  type = Constraint::MODEL
  constraints = []
  if (funcname == "validates") || (funcname == "validates!")
    constraints += parse_validates(table, funcname, ast)
  elsif funcname == "validate"
    cons = handle_validate(table, type, ast)
    constraints += cons
  elsif funcname == "validates_with" # https://guides.rubyonrails.org/active_record_validations.html#validates-with
    cons = parse_validates_with(table, type, ast)
    constraints += cons
  elsif funcname == "validates_each" # https://guides.rubyonrails.org/active_record_validations.html#validates-each
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
            if key && value
              dic[key] = value
            end
          end
        end
      end
    end
    allow_blank = false
    allow_nil = false
    if dic["allow_blank"] && (dic["allow_blank"].source == "true")
      allow_blank = true
    end
    if dic["allow_nil"] && (dic["allow_nil"].source == "true")
      allow_nil = true
    end
    unless columns.empty?
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
      if (funcname == "validates_length_of") || (funcname == "validates_size_of")
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
  constraints
end

def list_contains_conditional(list_node)
  result = false
  list_node.each do |child|
    if child.type.to_s == "assoc"
      cur_key, cur_value = handle_assoc_node(child)
      # puts "cur_constr #{cur_constr}"
      if (cur_key == "if") || (cur_key == "unless")
        result = true
      end
    end
  end

  result
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
                constraint.parse(dic)
                constraints << constraint
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
  constraints
end

def handle_validate(table, type, ast)
  constraints = []
  if ast.type.to_s === "list"
    ast.children.each do |c|
      if c.type.to_s == "symbol_literal"
        funcname = handle_symbol_literal_node(c)
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
