def parse_db_constraint_file(ast)
	if ast.type.to_s == 'list'
		ast.children.each do |child|
			parse_db_constraint_file(child)
		end
  end
  # TODO: need to be refactored too messy. Done
  if ast.type.to_s == "call"
		if ast[-1]&.type&.to_s == "do_block"
      parse_db_constraint_file(ast[-1][-1])
		end
	end

	if ast.type.to_s == 'class'
		# puts"ast.children #{ast.children[0].source}"
		c3 = ast.children[2]
		if c3
			# puts"c3: #{c3.type}"
			parse_db_constraint_file(c3)
		end
	end
	if ast.type.to_s == "def" or ast.type.to_s == "defs"
		funcname = ast[0].source
		if ast[1] and ast[1].type.to_s == "period"
			funcname = ast[2].source
		end
		# puts"funcname: #{funcname} "
		if !funcname.include?"down"
			parse_db_constraint_file(ast[-1])
		end
	end
	if ast.type.to_s == "fcall" and ast[0].source == "reversible"
		handle_reversible(ast)
	end
	if ast.type.to_s == "fcall"
		funcname = ast[0].source
		puts ("fcall #{funcname}")
		parse_db_constraint_function(nil, funcname, ast)
	end
	if ast.type.to_s == "command"
		funcname = ast[0].source 
		puts "callname: #{funcname}"
		parse_db_constraint_function(nil, funcname, ast)
	end
end
def parse_db_constraint_function(table, funcname, ast)

	ast[1] = ast[1][0] if ast[1].type.to_s == "arg_paren"
	handle_add_column(ast[1]) if funcname == "add_column"
	handle_create_table(ast) if funcname == "create_table"
	handle_change_column(ast[1]) if funcname == "change_column"
	handle_change_table(ast) if funcname == "change_table"
	handle_change_column_null(ast) if funcname == "change_column_null"
	handle_remove_column(ast[1]) if funcname == "remove_column"
	parse_sql(ast[1]) if funcname == "execute"
	handle_create_join_table(ast) if funcname == "create_join_table"
	handle_drop_table(ast[1]) if funcname == "drop_table"
	handle_remove_timestamps(ast) if funcname == "remove_timestamps"
	handle_add_timestamps(ast[1]) if funcname == "add_timestamps"
	handle_add_index(ast[1]) if funcname == "add_index"
	handle_remove_index(ast[1]) if funcname == "remove_index"
	handle_rename_index(ast) if funcname == "rename_index"
	handle_remove_join_table(ast) if funcname == "remove_join_table"
	handle_change_column_default(ast[1]) if funcname == "change_column_default"
	handle_rename_table(ast[1]) if funcname == "rename_table"
	handle_rename_column(ast[1]) if funcname == "rename_column"
end
def handle_change_table(ast)
	handle_create_table(ast)
end

def handle_add_column(ast)
	handle_change_column(ast, false)
end

def handle_change_column(ast, is_deleted=false)
	puts "handle_change_column"
	children = ast.children
	puts "is_deleted: #{is_deleted}"
	# puts"ast.source #{ast.source}"
	table = nil
	column_name = nil
	column_type = nil
	table = handle_symbol_literal_node(children[0]) || handle_string_literal_node(children[0])
	column_name = handle_symbol_literal_node(children[1]) || handle_string_literal_node(children[1])
	column_type = handle_symbol_literal_node(children[2]) || handle_string_literal_node(children[2])
	dic = {}
	dic = extract_hash_from_list(children[-1])
	class_name = convert_tablename(table)
	table_class = $model_classes[class_name]
	table_class = $dangling_classes[class_name] if !table_class
	if !table_class 
		table_class = File_class.new("")
		$dangling_classes[class_name] = table_class
	end
	if is_deleted
		table_class.getColumns[column_name].is_deleted = true
		constraint_delete_keys = table_class.getConstraints.select do |k,v|
			k.start_with?"#{class_name}-#{column_name}"
		end
		table_class.getConstraints.delete_if {|k,v| constraint_delete_keys.include? k}
	end

	if table and column_name and column_type  
		column = Column.new(table_class, column_name, column_type, $cur_class, dic)
		column.is_deleted = is_deleted
		columns = table_class.getColumns
		column.prev_column =  columns[column_name]
		table_class.addColumn(column)
		constraint_delete_keys = table_class.getConstraints.select do |k,v|
				k.include? "#{class_name}-#{column_name}-#{Presence_constraint.to_s}-#{Constraint::DB}" or
						k.include? "#{class_name}-#{column_name}-#{Length_constraint.to_s}-#{Constraint::DB}"
		end
		table_class.getConstraints.delete_if {|k,v| constraint_delete_keys.include? k}
		constraints = create_constraints(class_name, column_name, column_type, Constraint::DB, dic)
		table_class.addConstraints(constraints)
	end
	# puts"table: #{table} column: #{column} column_type: #{column_type}"
end

def handle_create_table(ast)
	table_name = nil
	# puts"handle_create\n#{ast.source}"
	# puts"ast[1] #{ast[1].source} #{ast[1].type.to_s}"
	if ast[1].type.to_s == "list"
		symbol_node = ast[1][0]
		table_name = handle_symbol_literal_node(symbol_node) || handle_string_literal_node(symbol_node)
		class_name = convert_tablename(table_name)
		# puts"class_name: #{class_name}"
		## puts"table_name: #{table_name}"
		return unless ast[2].type.to_s == "do_block"
		ast[2].children.each do |child|
			next unless child.type.to_s == 'list'
			child.children.each do |c|
				if c.type.to_s == "command_call"
					column_type = c[2].source
					if column_type == "references"
						column_type = "string"
					end
					column_ast = c[-1]
					if column_ast.class.name == "YARD::Parser::Ruby::AstNode" and  column_ast.type.to_s == "list"
						column_name = handle_symbol_literal_node(column_ast[0]) || handle_string_literal_node(column_ast[0])
						table_class = $model_classes[class_name]
						table_class = $dangling_classes[class_name] if !table_class
						if !table_class 
							table_class = File_class.new("")
							$dangling_classes[class_name] = table_class
						end
						column = Column.new(table_class, column_name, column_type, $cur_class)
						columns = table_class.getColumns
						column.prev_column =  columns[column_name]
						table_class.addColumn(column)
						dic = {}
						dic = extract_hash_from_list(column_ast.children[-1])
            column.parse(dic)
						constraints = create_constraints(class_name, column_name, column_type, Constraint::DB, dic)
						table_class.addConstraints(constraints)
					end
				end
			end
		end
	end
end
def handle_change_column_null(ast)
	puts "++++++++++handle_change_column_null++++++++++" if $debug_mode
	if ast[1].type.to_s == "list"
		table_name = nil
		column_name = nil
		null = true
		table_class = nil
		class_name = nil
		if ast[1][0].type.to_s == "symbol_literal"
			table_name = handle_symbol_literal_node(ast[1][0]) || handle_string_literal_node(ast[1][0])
			class_name = convert_tablename(table_name)
			table_class = $model_classes[class_name]
		end
		table_class = $dangling_classes[class_name] if !table_class
		if !table_class 
			table_class = File_class.new("")
			$dangling_classes[class_name] = table_class
		end
		if ast[1][1].type.to_s == "symbol_literal"
			column_name = handle_symbol_literal_node(ast[1][0])
		end
		if ast[1][2].type.to_s == "var_ref"
			null = ast[1][2].source
		end
		if class_name and table_class and column_name and null == "false"
			constraint = Presence_constraint.new(class_name, column_name, Constraint::DB)
			table_class.addConstraints([constraint])
		end
	end
end
def handle_reversible(ast)
	table_name = nil
	column_name = nil
	null = true
	table_class = nil
	class_name = nil
	dic = {}
	return unless ast[-1].type.to_s == "do_block"
	list_ast = ast[-1][-1]
	return unless list_ast&.type.to_s == "list"
	list_ast.children.each do |child|
		next unless child.type.to_s == "command"
		puts "#{child[1].type.to_s} child1 #{child[1][0].type.to_s}"
		next if !(child[1].type.to_s == "list" and child[1][0].type.to_s == "symbol_literal") if $debug_mode
		table_name = handle_symbol_literal_node(child[1][0]) || handle_string_literal_node(child[1][0])
		class_name = convert_tablename(table_name)
		table_class = $model_classes[class_name]
		table_class = $dangling_classes[class_name] if !table_class
		if !table_class 
			table_class = File_class.new("")
			$dangling_classes[class_name] = table_class
		end
		puts "table_name : #{table_name}" if $debug_mode
		next unless child[-1].type.to_s == "do_block"
		if child[-1][-1].type.to_s == "list"
			child[-1][-1].children.each do |cc|
				next unless cc.type.to_s == "call"
				next unless cc[2].source == "up"
				next unless cc[-1].type.to_s == "brace_block"
				next unless cc[-1][1][0]&.type.to_s == "command_call"
				ccc = cc[-1][1][0][-1]
				next unless ccc&.type.to_s == "list"
				column_name = handle_symbol_literal_node(ccc[0]) || handle_string_literal_node(ccc[0])
				column_type = handle_symbol_literal_node(ccc[1]) || handle_string_literal_node(ccc[1])
				dic == extract_hash_from_list(ast)
				old_column = table_class.getColumns[column_name]
				next if !(column_name and table_class and column_name) 
				column = Column.new(table_class, column_name, column_type, $cur_class)
				column.prev_column = old_column
				table_class.addColumn(column)
				constraints = create_constraints(class_name, column_name, column_type, Constraint::DB, dic)
				table_class.addConstraints(constraints)	
			end
		end
	end
end

def create_constraints(class_name, column_name, column_type, type, dic)
	return [] unless dic
	return [] unless dic.length > 0
	return [] if %w(timestamps spatial).include? column_type
	constraints = []
	if  dic["null"]
		null = dic["null"].source
		if null == "false"
			constraint = Presence_constraint.new(class_name, column_name, type)			
			constraints << constraint
		end
	end
	# 
	if dic['limit']
		limit = dic["limit"].source
		constraint = Length_constraint.new(class_name, column_name, type)
		constraint.max_value = limit.to_i if limit != "nil" and limit.to_i
		constraints << constraint
	end
	return constraints
end
def handle_remove_column(ast)
	handle_change_column(ast, true)
end
def handle_create_join_table(ast)
end

def handle_remove_join_table(ast)
	# not found yet
end

def handle_add_timestamps(ast)
	ast = ast[0] if ast.type.to_s == "arg_paren"
	children = ast.children
	table_name = handle_symbol_literal_node(children[0]) || handle_string_literal_node(children[0])
	dic = extract_hash_from_list(children[-1])
	class_name = convert_tablename(table_name)
	table_class = $model_classes[class_name] || $dangling_classes[class_name]
	return unless table_class
	column_type = "Timestamp"
	name1 = "created_at"
	name2 = "updated_at"
	column1 = Column.new(table_class, name1, column_type, $cur_class, dic)
	column2 = Column.new(table_class, name2, column_type, $cur_class, dic)
	table_class.addColumn(column1)
	table_class.addColumn(column2)
	constraints1 = create_constraints(class_name, name1, column_type, Constraint::DB, dic)
	constraints2 = create_constraints(class_name, name2, column_type, Constraint::DB, dic)
	table_class.addConstraints(constraints1)
	table_class.addConstraints(constraints2)
end

def handle_remove_timestamps(ast)
	# not found yet
end


def handle_change_column_default(ast)
	puts "handle_change_column_default" if $debug_mode
	children = ast.children
	puts"ast.source #{ast.source} \n#{ast[0].type}"
	table = nil
	column_name = nil
	column_type = nil
	table = handle_symbol_literal_node(children[0]) || handle_string_literal_node(children[0])
	column_name = handle_symbol_literal_node(children[1]) || handle_string_literal_node(children[1])
	dic = {}
	dic = extract_hash_from_list(children[-1])
	puts "#{table} = #{column_name} = #{column_type} --- #{dic}" if $debug_mode
	class_name = convert_tablename(table)
	table_class = $model_classes[class_name]
	table_class = $dangling_classes[class_name] if !table_class
	if !table_class 
		table_class = File_class.new("")
		$dangling_classes[class_name] = table_class
	end
	if table and column_name  and table_class
		table_class = $model_classes[class_name]
		columns = table_class.getColumns
		column  = columns[column_name]
		new_default = dic["to"].source if dic["to"].type.to_s == "var_ref" 
		new_default = new_default ||  handle_symbol_literal_node(dic["to"]) \
						|| handle_string_literal_node(dic["to"])
		column.default_value = new_default
	end
end

def handle_rename_table(ast)
	children = ast.children
	old_table_name = handle_symbol_literal_node(children[0]) || handle_string_literal_node(children[0])
	new_table_name = handle_symbol_literal_node(children[1]) || handle_string_literal_node(children[1])
	old_class_name = convert_tablename(old_table_name)
	new_class_name = convert_tablename(new_table_name)
	puts "n: #{new_class_name} o: #{old_class_name}" if $debug_mode
	old_class = $model_classes[old_table_name]
	old_class = $dangling_classes[old_class_name] if !old_class
	new_class= $model_classes[new_class_name]
	return if !(old_class and new_class)
	old_class.getColumns.each do |k, v|
		new_class.addColumn(v)
		v.table_class = new_class
	end
	old_class.is_deleted = true
	new_class.addConstraints(old_class.getConstraints.values)
end

def handle_drop_table(ast)
	children = ast.children
	table_name = handle_symbol_literal_node(children[0]) || handle_string_literal_node(children[0])
	class_name = convert_tablename(table_name)
	table_class = $model_classes[class_name]
	table_class = $dangling_classes[class_name] unless table_class
	if table_class
		table_class.is_deleted = true
	end
end

def handle_add_index(ast)
	puts "handle_add_index" if $debug_mode
	children = ast.children
	table_name = handle_symbol_literal_node(children[0]) ||  handle_symbol_literal_node(children[0])
	column = handle_symbol_literal_node(children[1]) || handle_string_literal_node(children[1])
	class_name = convert_tablename(table_name)
	table_class = $model_classes[class_name] || $dangling_classes[class_name]
	if !table_class
		table_class = File_class.new("")
		$dangling_classes[class_name] = table_class
	end
	columns = []
	columns << column if column
	columns = handle_array_node(children[1]) unless column
	dic = extract_hash_from_list(children[2])
	index_name = dic["name"]&.source || handle_symbol_literal_node(dic["name"]) || handle_string_literal_node(dic["name"])
	index_name = index_name || "#{table_name}_#{columns.join("_")}"
	new_index = Index.new(index_name, table_name, columns)
	if dic["unique"]&.source == "true"
		new_index.unique = true
	end
	table_class.addIndex(new_index)
end

def handle_remove_index(ast)
end

def handle_rename_column(ast)
	children = ast.children
	table_name = handle_symbol_literal_node(children[0]) || handle_string_literal_node(children[0])
	old_column_name = handle_symbol_literal_node(children[1]) || handle_string_literal_node(children[1])
	new_column_name = handle_symbol_literal_node(children[2]) || handle_string_literal_node(children[2])
	class_name = convert_tablename(table_name)
	table_class = $model_classes[class_name]
	table_class = $dangling_classes[class_name] unless table_class
	if table_class
		column = table_class.getColumns[old_column_name]
		column.column_name = new_column_name
		constraints = table_class.getConstraints
		new_constraints = []
		constraints.each do |k, v|
			prefix = "#{class_name}-#{old_column_name}-"
			if k.start_with?prefix
				v.column = new_column_name
				new_constraints << v
				# delete the old key instead of setting it to be nil
				constraints.delete(k)
			end
		end
		table_class.addConstraints(new_constraints)
	end
end

def handle_rename_index(ast)
end