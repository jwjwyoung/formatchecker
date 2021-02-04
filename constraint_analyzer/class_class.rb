class File_class
  attr_accessor :filename, :class_name, :upper_class_name, :ast, :is_activerecord, :is_deleted, :indices, :contents, :functions, :has_many_classes

  def initialize(filename)
    @filename = filename
    @is_activerecord = false
    @class_name = nil
    @upper_class_name = nil
    @ast = nil
    @constraints = {}
    @columns = {}
    @is_deleted = false
    @indices = {}
    @foreign_keys = []
    @instance_var_refs = []
    @contents = ""
    @functions = {}
    @has_many_classes = {}
    @has_many_as = []
    @belongs_to_poly = []
    @before_save_functions = []
    @validate_functions = []
  end

  def addHasManyAs(v)
    @has_many_as << v
  end

  def getHasManyAs
    return @has_many_as
  end

  def addBelongsToPoly(v)
    @belongs_to_poly << v
  end

  def getBelongsToPoly
    return @belongs_to_poly
  end

  def addValidateFunction(funcname)
    @validate_functions << funcname
  end

  def getValidateFunction()
    @validate_functions
  end

  def addFunction(funcname, ast)
    @functions[funcname] = ast
  end

  def printFunctions
    @functions.each do |k, v|
      printFunction(k, v)
    end
  end

  def addBeforeSaveFcuntions(funcnames)
    @before_save_functions += funcnames
  end

  def getBeforeSaveFunctions()
    return @before_save_functions
  end

  def addHasMany(column, dic)
    if dic["dependent"]
      has_many_classes[column] = true
    else
      has_many_classes[column] = false
    end
    # puts "#{column} #{has_many_classes[column]}"
  end

  def printFunction(k, v)
    puts "====start of function #{k}===="
    puts "#{v.source}"
    puts "====end of function #{k}===="
  end

  def removeConstraintByKey(k)
    @constraints.delete(k)
  end

  def addConstraints(constraints)
    constraints.each do |constraint|
      # puts"constraint #{constraint.class}"
      key = "#{@class_name}-#{constraint.column}-#{constraint.class.name}-#{constraint.type}"
      @constraints[key] = constraint
      constraint.table = self.class_name
    end
    # puts "@constraints.size #{@constraints.length}" if $debug_mode
  end

  def check_whether_column_has_constraints
    @constraints.each do |k, v|
      column = self.getColumns[v.column]
      if column
        column.has_constraints = true
      end
    end
  end

  def getConstraints
    return @constraints
  end

  def getColumns
    return @columns
  end

  def getColumnsLength
    return @columns.length
  end

  def addForeignKey(key_name)
    @foreign_keys << key_name
  end

  def getForeignKeys
    return @foreign_keys
  end

  def addColumn(column)
    @columns[column.column_name] = column
  end

  def addIndex(index)
    @indices[index.name] = index
  end

  def getInstanceVarRefs
    return @instance_var_refs
  end

  def num_columns_has_constraints
    check_whether_column_has_constraints
    num = @columns.select { |k, v| v.has_constraints }.length
    return @columns.length, num
  end

  def create_con_from_column_type
    return unless @columns
    @columns.each do |k, v|
      next if v.is_deleted
      type = "db"
      column_type = v.column_type
      if column_type == "string"
        max_value = 255
      end
      if column_type == "text"
        max_value = 65535
      end
      column_name = v.column_name
      #puts "max_value from type: #{max_value} #{column_name} #{column_type} #{@class_name}" if $debug_mode
      if max_value
        constraint = Length_constraint.new(@class_name, column_name, type)
        constraint.max_value = max_value
        key = "#{@class_name}-#{constraint.column}-#{constraint.class.name}-#{constraint.type}"
        exist_con = @constraints[key]
        if exist_con and (not exist_con.max_value || exist_con.max_value == "nil")
          exist_con.max_value = max_value
        end
        if not exist_con
          @constraints[key] = constraint
        end
      end
      if ["float", "integer", "decimal"].include? column_type
        constraint = Numericality_constraint.new(@class_name, column_name, type)
        if column_type == "integer"
          constraint.only_integer = true
        end
        key = "#{@class_name}-#{constraint.column}-#{constraint.class.name}-#{constraint.type}"
        @constraints[key] = constraint
      end
    end
  end

  def create_con_from_index
    return unless @indices
    @indices.each do |k, v|
      if v.unique
        type = "db"
        constraint = Uniqueness_constraint.new(@class_name, v.columns, type)
        key = "#{@class_name}-#{constraint.column}-#{constraint.class.name}-#{constraint.type}"
        @constraints[key] = constraint
      end
    end
  end

  def create_con_from_format
    return unless @constraints
    cons = []
    @constraints.each do |k, v|
      if v.is_a? Format_constraint and v.with_format
        constraint = derive_length_constraint_from_format(v)
        next if constraint.nil?

        key = "#{@class_name}-#{constraint.column}-#{constraint.class.name}-#{constraint.type}"
        if (existing_constraint = @constraints[key])
          existing_constraint.min_value = [constraint.min_value, existing_constraint.min_value].compact.max
          existing_constraint.max_value = [constraint.max_value, existing_constraint.max_value].compact.min
        else
          cons << constraint
        end
      end
    end

    self.addConstraints(cons)
  end

  def extract_instance_var_refs
    refs = []
    parse_model_var_refs(@ast, refs)
    @instance_var_refs = refs.uniq
  end
end

class Column
  # belongs to model class which is active record
  attr_accessor :column_type, :column_name, :file_class, :prev_column, :is_deleted, :default_value, :table_class, :auto_increment, :has_constraints

  def initialize(table_class, column_name, column_type, file_class, dic = {})
    @table_class = table_class
    @column_name = column_name
    @column_type = column_type
    @file_class = file_class
    @is_deleted = false
    @auto_increment = false
    @has_constraints = false
    self.parse(dic)
    #puts "dic: #{dic.to_s}" if $debug_mode
  end

  def getTableClass
    return @table_class
  end

  def setTable(table_class)
    @table_class = table_class
  end

  def parse(dic)
    #puts "dic #{dic["default"]&.type}" if $debug_mode
    ast = dic["default"]
    if ast
      value = dic["default"]&.source if dic["default"]&.type.to_s == "var_ref"
      @default_value = value || handle_symbol_literal_node(ast) || handle_string_literal_node(ast) || handle_numeric_literal_node(ast)
    end
    if dic["auto_increment"]
      value = handle_symbol_literal_node(ast) || handle_string_literal_node(ast)
      if value == "true"
        @auto_increment = true
      end
    end
  end
end

class Index
  # belongs to model class which is active record
  attr_accessor :name, :table_name, :columns, :unique, :where, :length, :order

  def initialize(name, table_name, columns)
    @name = name
    @table_name = table_name
    @columns = columns
    @unique = false
  end
end
