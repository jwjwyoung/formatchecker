class File_class
  attr_accessor :filename, :class_name, :upper_class_name, :ast, :is_activerecord, :is_deleted, :indices,
                :contents, :functions, :has_many_classes, :prev_class_name, :foreign_keys,
                :has_one_classes, :has_belong_classes, :included_concerns, :relations
  attr_reader :columns

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
    @has_one_classes = {}
    @has_belong_classes = Set.new
    @prev_class_name = nil
    @included_concerns = Set.new 
    @relations = []
  end

  def addRelation(column, dic, rel)
    class_name  = handle_string_literal_node(dic['class_name']) || handle_tstring_content_node(dic['class_name'])
    foreign_key = handle_string_literal_node(dic['foreign_key']) || handle_tstring_content_node(dic['foreign_key'])
    if not class_name
      class_name = column.singularize
    end
    class_name = class_name.capitalize
    relation = {:rel => rel, :field => column, :class_name => class_name, :column => foreign_key}
    @relations << relation
  end
  
  def to_schema()
    fields = {}
    @columns.map{|c, v| fields[v.column_name] = v.column_type}
    return @fields, @relations
  end

  def addFunction(funcname, ast)
    @functions[funcname] = ast
  end

  def printFunctions
    @functions.each do |k, v|
      printFunction(k, v)
    end
  end

  def addHasMany(column, dic)
    has_many_classes[column] = dic["dependent"] ? true : false
  end

  def printFunction(k, v)
    puts "====start of function #{k}===="
    puts v.source.to_s
    puts "====end of function #{k}===="
  end

  def addConstraints(constraints)
    constraints.each do |constraint|
      # puts"constraint #{constraint.class}"
      key = "#{@class_name}-#{constraint.column}-#{constraint.class.name}-#{constraint.type}"
      @constraints[key] = constraint
      constraint.table = class_name
    end
    puts "@constraints.size #{@constraints.length}" if $debug_mode
  end

  def check_whether_column_has_constraints
    @constraints.each do |_k, v|
      column = getColumns[v.column]
      column.has_constraints = true if column
    end
  end

  def getConstraints
    @constraints
  end

  def getColumns
    @columns
  end

  def getColumnsLength
    @columns.length
  end

  def addForeignKey(key_name)
    @foreign_keys << key_name
  end

  def getForeignKeys
    @foreign_keys
  end

  def addColumn(column)
    @columns[column.column_name] = column
  end

  def addIndex(index)
    @indices[index.name] = index
  end

  def getInstanceVarRefs
    @instance_var_refs
  end

  def num_columns_has_constraints
    check_whether_column_has_constraints
    num = @columns.select { |_k, v| v.has_constraints }.length
    [@columns.length, num]
  end

  def create_con_from_column_type
    return unless @columns

    @columns.each do |_k, v|
      next if v.is_deleted

      type = "db"
      column_type = v.column_type
      max_value = 255 if column_type == "string"
      max_value = 65_535 if column_type == "text"
      column_name = v.column_name
      puts "max_value from type: #{max_value} #{column_name} #{column_type} #{@class_name}" if $debug_mode
      if max_value
        constraint = Length_constraint.new(@class_name, column_name, type)
        constraint.max_value = max_value
        key = "#{@class_name}-#{constraint.column}-#{constraint.class.name}-#{constraint.type}"
        exist_con = @constraints[key]
        exist_con.max_value = max_value if exist_con && !(exist_con.max_value || exist_con.max_value == "nil")
        @constraints[key] = constraint unless exist_con
      end
      next unless %w[float integer decimal].include? column_type

      constraint = Numericality_constraint.new(@class_name, column_name, type)
      constraint.only_integer = true if column_type == "integer"
      key = "#{@class_name}-#{constraint.column}-#{constraint.class.name}-#{constraint.type}"
      @constraints[key] = constraint
    end
  end

  def create_con_from_index
    return unless @indices

    @indices.each do |_k, v|
      next unless v.unique

      type = "db"
      constraint = Uniqueness_constraint.new(@class_name, v.columns, type)
      key = "#{@class_name}-#{constraint.column}-#{constraint.class.name}-#{constraint.type}"
      @constraints[key] = constraint
    end
  end

  def create_con_from_format
    return unless @constraints

    cons = []
    @constraints.each do |_k, v|
      next unless v.is_a?(Format_constraint) && v.with_format

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

    addConstraints(cons)
  end

  def extract_instance_var_refs
    refs = []
    parse_model_var_refs(@ast, refs)
    @instance_var_refs = refs.uniq
  end
end

class Column
  # belongs to model class which is active record
  attr_accessor :column_type, :column_name, :file_class, :prev_column, :is_deleted, :default_value,
                :table_class, :auto_increment, :has_constraints

  def initialize(table_class, column_name, column_type, file_class, dic = {})
    @table_class = table_class
    @column_name = column_name
    @column_type = column_type
    @file_class = file_class
    @is_deleted = false
    @auto_increment = false
    @has_constraints = false
    parse(dic)
    puts "dic: #{dic}" if $debug_mode
  end

  def getTableClass
    @table_class
  end

  def setTable(table_class)
    @table_class = table_class
  end

  def parse(dic)
    puts "dic #{dic['default']&.type}" if $debug_mode
    ast = dic["default"]
    if ast
      value = dic["default"]&.source if dic["default"]&.type.to_s == "var_ref"
      @default_value = value || handle_symbol_literal_node(ast) || handle_string_literal_node(ast) ||
                       handle_numeric_literal_node(ast)
    end
    return unless dic["auto_increment"]

    value = handle_symbol_literal_node(ast) || handle_string_literal_node(ast)
    @auto_increment = true if value == "true"
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
