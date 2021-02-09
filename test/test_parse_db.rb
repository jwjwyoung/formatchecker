require_relative "required_file.rb"

class TestParseDBConstriant < Test::Unit::TestCase
  def test_create_table
    contents = "class ChangeProductsPrice < ActiveRecord::Migration[5.0]
                def up
                  create_table :products do |t|
                    t.column :name, :string, limit: 60, default: 'abc'
                  end
                end
              end"
    ast = YARD::Parser::Ruby::RubyParser.parse(contents).root
    model_class = File_class.new("products.rb")
    model_class.class_name = "Product"
    model_class.upper_class_name == "ActiveRecord::Base"
    model_class.is_activerecord = true
    $model_classes = {}
    $model_classes[model_class.class_name] = model_class
    $cur_class = File_class.new("test.rb")
    $cur_class.ast = ast
    parse_db_constraint_file(ast)
    assert_equal 1, model_class.getColumns.length
    assert_equal 1, model_class.getConstraints.length
    column = model_class.getColumns.values[0]
    assert_equal "abc", column.default_value
  end

  def test_create_table_from_fcall
    contents = "class ChangeProductsPrice < ActiveRecord::Migration[5.0]
                def up
                  create_table(:products) do |t|
                    t.column :name, :string, limit: 60
                  end
                end
              end"
    ast = YARD::Parser::Ruby::RubyParser.parse(contents).root
    model_class = File_class.new("products.rb")
    model_class.class_name = "Product"
    model_class.upper_class_name == "ActiveRecord::Base"
    model_class.is_activerecord = true
    $model_classes = {}
    $model_classes[model_class.class_name] = model_class
    $cur_class = File_class.new("test.rb")
    $cur_class.ast = ast
    parse_db_constraint_file(ast)
    assert_equal 1, model_class.getColumns.length
    assert_equal 1, model_class.getConstraints.length
  end

  def test_parse_reversible
    contents = "class ChangeProductsPrice < ActiveRecord::Migration[5.0]
                def change
                  reversible do |dir|
                    change_table :products do |t|
                      dir.up   { t.change :price, :string }
                      dir.down { t.change :price, :integer }
                    end
                  end
                end
              end"
    ast = YARD::Parser::Ruby::RubyParser.parse(contents).root
    model_class = File_class.new("products.rb")
    model_class.class_name = "Product"
    model_class.upper_class_name == "ActiveRecord::Base"
    model_class.is_activerecord = true
    $model_classes = {}
    $model_classes[model_class.class_name] = model_class
    $cur_class = File_class.new("test.rb")
    $cur_class.ast = ast
    parse_db_constraint_file(ast)
    assert_equal 1, model_class.getColumns.length
    assert_equal 0, model_class.getConstraints.length
  end

  def test_remove_column
    contents = "class RemovePartNumberFromProducts < ActiveRecord::Migration[5.0]
                  def change
                    remove_column :products, :part_number, :string
                  end
                end"
    ast = YARD::Parser::Ruby::RubyParser.parse(contents).root
    model_class = File_class.new("products.rb")
    model_class.class_name = "Product"
    model_class.upper_class_name == "ActiveRecord::Base"
    model_class.is_activerecord = true
    $model_classes = {}
    $model_classes[model_class.class_name] = model_class
    $cur_class = File_class.new("test.rb")
    $cur_class.ast = ast
    parse_db_constraint_file(ast)
    assert_equal 1, model_class.getColumns.length
    assert_equal 0, model_class.getConstraints.length
    column = model_class.getColumns.values[0]
    assert_equal true, column&.is_deleted
    assert_equal "part_number", column.column_name
    assert_equal "string", column.column_type
    assert_equal "part_number", model_class.getColumns.keys[0]
  end

  def test_add_column
    contents = "class RemovePartNumberFromProducts < ActiveRecord::Migration[5.0]
                  def change
                    add_column :products, :part_number, :string, default: ''
                  end
                end"
    ast = YARD::Parser::Ruby::RubyParser.parse(contents).root
    puts "ast: #{ast.source}"
    model_class = File_class.new("products.rb")
    model_class.class_name = "Product"
    model_class.upper_class_name == "ActiveRecord::Base"
    model_class.is_activerecord = true
    $model_classes = {}
    $model_classes[model_class.class_name] = model_class
    $cur_class = File_class.new("test.rb")
    $cur_class.ast = ast
    parse_db_constraint_file(ast)
    assert_equal 1, model_class.getColumns.length
    assert_equal 0, model_class.getConstraints.length
    column = model_class.getColumns.values[0]
    assert_equal false, column&.is_deleted
    assert_equal "part_number", column.column_name
    assert_equal "string", column.column_type
    assert_equal "part_number", model_class.getColumns.keys[0]
    assert_equal "", column.default_value
  end

  def test_change_column_default
    contents = "class RemovePartNumberFromProducts < ActiveRecord::Migration[5.0]
                  def change
                      add_column :products, :approved, :boolean, default: true
                  end
                end"
    ast = YARD::Parser::Ruby::RubyParser.parse(contents).root

    model_class = File_class.new("products.rb")
    model_class.class_name = "Product"
    model_class.upper_class_name == "ActiveRecord::Base"
    model_class.is_activerecord = true
    $model_classes = {}
    $model_classes[model_class.class_name] = model_class
    $cur_class = File_class.new("test.rb")
    $cur_class.ast = ast
    parse_db_constraint_file(ast)
    assert_equal 1, model_class.getColumns.length
    assert_equal 0, model_class.getConstraints.length
    column = model_class.getColumns.values[0]
    assert_equal false, column&.is_deleted
    assert_equal "approved", column.column_name
    assert_equal "boolean", column.column_type
    assert_equal "true", column.default_value

    contents1 = "class RemovePartNumberFromProducts < ActiveRecord::Migration[5.0]
                  def change
                      change_column_default :products, :approved, from: true, to: false
                  end
                end"
    ast1 = YARD::Parser::Ruby::RubyParser.parse(contents1).root

    $cur_class = File_class.new("test2.rb")
    $cur_class.ast = ast1
    parse_db_constraint_file(ast1)
    assert_equal 1, model_class.getColumns.length
    assert_equal 0, model_class.getConstraints.length
    column = model_class.getColumns.values[0]
    assert_equal false, column&.is_deleted
    assert_equal "approved", column.column_name
    assert_equal "boolean", column.column_type
    assert_equal "false", column.default_value
  end

  def test_rename_table
    contents = "class RemovePartNumberFromProducts < ActiveRecord::Migration[5.0]
                  def change
                      add_column :admin_logs, :approved, :boolean, default: true, null: false
                  end
                end"
    ast = YARD::Parser::Ruby::RubyParser.parse(contents).root

    model_class = File_class.new("products.rb")
    model_class.class_name = "StaffActionLog"
    model_class.upper_class_name == "ActiveRecord::Base"
    model_class.is_activerecord = true
    $model_classes = {}
    $dangling_classes = {}
    $model_classes[model_class.class_name] = model_class
    $cur_class = File_class.new("test.rb")
    $cur_class.ast = ast
    parse_db_constraint_file(ast)
    assert_equal 0, model_class.getColumns.length
    assert_equal 0, model_class.getConstraints.length
    column = $dangling_classes["AdminLog"].getColumns.values[0]
    assert_equal false, column&.is_deleted
    assert_equal "approved", column.column_name
    assert_equal "boolean", column.column_type
    assert_equal "true", column.default_value

    contents1 = "class RemovePartNumberFromProducts < ActiveRecord::Migration[5.0]
                  def change
                      rename_table :admin_logs, :staff_action_logs
                  end
                end"
    ast1 = YARD::Parser::Ruby::RubyParser.parse(contents1).root

    $cur_class = File_class.new("test2.rb")
    $cur_class.ast = ast1
    parse_db_constraint_file(ast1)
    assert_equal 1, model_class.getColumns.length
    assert_equal 1, model_class.getConstraints.length
    assert_equal "Presence_constraint", model_class.getConstraints.values[0].class.name
    column = model_class.getColumns.values[0]
    assert_equal false, column&.is_deleted
    assert_equal "approved", column.column_name
    assert_equal "boolean", column.column_type
    assert_equal "true", column.default_value
  end

  def test_drop_column
    contents = "class RemovePartNumberFromProducts < ActiveRecord::Migration[5.0]
                  def change
                      drop_table :admin_logs
                  end
                end"
    ast = YARD::Parser::Ruby::RubyParser.parse(contents).root

    model_class = File_class.new("products.rb")
    model_class.class_name = "AdminLog"
    model_class.upper_class_name == "ActiveRecord::Base"
    model_class.is_activerecord = true
    $model_classes = {}
    $dangling_classes = {}
    $model_classes[model_class.class_name] = model_class
    $cur_class = File_class.new("test.rb")
    $cur_class.ast = ast
    parse_db_constraint_file(ast)
    assert_equal true, model_class.is_deleted
  end

  def test_rename_column
    contents = "class RemovePartNumberFromProducts < ActiveRecord::Migration[5.0]
                  def change
                      add_column :admin_logs, :password, :boolean, default: true, null: false
                  end
                end"
    ast = YARD::Parser::Ruby::RubyParser.parse(contents).root

    model_class = File_class.new("products.rb")
    model_class.class_name = "AdminLog"
    model_class.upper_class_name == "ActiveRecord::Base"
    model_class.is_activerecord = true
    $model_classes = {}
    $dangling_classes = {}
    $model_classes[model_class.class_name] = model_class
    $cur_class = File_class.new("test.rb")
    $cur_class.ast = ast
    parse_db_constraint_file(ast)

    contents1 = "class RemovePartNumberFromProducts < ActiveRecord::Migration[5.0]
                  def change
                    rename_column :admin_logs, 'password', 'crypted_password'
                  end
                end"
    ast1 = YARD::Parser::Ruby::RubyParser.parse(contents1).root

    $cur_class = File_class.new("test2.rb")
    $cur_class.ast = ast1
    parse_db_constraint_file(ast1)
    assert_equal 1, model_class.getColumns.length
    assert_equal 1, model_class.getConstraints.length
    assert_equal "Presence_constraint", model_class.getConstraints.values[0].class.name
    column = model_class.getColumns.values[0]
    assert_equal "crypted_password", column.column_name
  end

  def test_add_timestamps_from_fcall
    contents = "class RemovePartNumberFromProducts < ActiveRecord::Migration[5.0]
                  def change
                      add_timestamps(:admin_logs, null: false)
                  end
                end"
    ast = YARD::Parser::Ruby::RubyParser.parse(contents).root
    model_class = File_class.new("")
    model_class.class_name = "AdminLog"
    model_class.upper_class_name == "ActiveRecord::Base"
    model_class.is_activerecord = true
    $model_classes = {}
    $dangling_classes = {}
    $model_classes[model_class.class_name] = model_class
    $cur_class = File_class.new("test.rb")
    $cur_class.ast = ast
    parse_db_constraint_file(ast)
    columns = model_class.getColumns
    constraints = model_class.getConstraints
    assert_equal 2, columns.length
    assert_equal %w[created_at updated_at], columns.keys
    assert_equal 2, constraints.length
    assert_equal %w[created_at-Presence_constraint-db updated_at-Presence_constraint-db], constraints.keys
    assert_equal [nil, nil], columns.map { |_k, v| v.default_value }
  end

  def test_add_timestamps_from_command
    contents = "class RemovePartNumberFromProducts < ActiveRecord::Migration[5.0]
                  def change
                      add_timestamps :admin_logs, null: false
                  end
                end"
    ast = YARD::Parser::Ruby::RubyParser.parse(contents).root
    model_class = File_class.new("")
    model_class.class_name = "AdminLog"
    model_class.upper_class_name == "ActiveRecord::Base"
    model_class.is_activerecord = true
    $model_classes = {}
    $dangling_classes = {}
    $model_classes[model_class.class_name] = model_class
    $cur_class = File_class.new("test.rb")
    $cur_class.ast = ast
    parse_db_constraint_file(ast)
    columns = model_class.getColumns
    constraints = model_class.getConstraints
    assert_equal 2, columns.length
    assert_equal %w[created_at updated_at], columns.keys
    assert_equal 2, constraints.length
    assert_equal %w[created_at-Presence_constraint-db updated_at-Presence_constraint-db], constraints.keys
    assert_equal [nil, nil], columns.map { |_k, v| v.default_value }
  end

  def test_handle_create_join_table
    contents = "class ChangeProductsPrice < ActiveRecord::Migration[5.0]
                def up
                  create_table :products do |t|
                    t.column :name, :string, limit: 60
                  end
                end
              end"
    ast = YARD::Parser::Ruby::RubyParser.parse(contents).root
    model_class = File_class.new("products.rb")
    model_class.class_name = "Product"
    model_class.upper_class_name == "ActiveRecord::Base"
    model_class.is_activerecord = true
    $model_classes = {}
    $model_classes[model_class.class_name] = model_class
    $cur_class = File_class.new("test.rb")
    $cur_class.ast = ast
    parse_db_constraint_file(ast)
    assert_equal 1, model_class.getColumns.length
    assert_equal 1, model_class.getConstraints.length
    contents1 = "class ChangeProductsPrice < ActiveRecord::Migration[5.0]
                def up
                  add_index :products, :name
                end
              end"
    ast1 = YARD::Parser::Ruby::RubyParser.parse(contents1).root
    $cur_class = File_class.new("add_index.rb")
    $cur_class.ast = ast1
    parse_db_constraint_file(ast1)
    assert_equal 1, model_class.indices.size
    temp_model_class = model_class
    contents = "class ChangeProductsPrice < ActiveRecord::Migration[5.0]
                def up
                  create_table :products do |t|
                    t.column :name, :string, limit: 60
                  end
                end
              end"
    ast = YARD::Parser::Ruby::RubyParser.parse(contents).root
    model_class = File_class.new("products.rb")
    model_class.class_name = "Product"
    model_class.upper_class_name == "ActiveRecord::Base"
    model_class.is_activerecord = true
    $model_classes = {}
    $model_classes[model_class.class_name] = model_class
    $cur_class = File_class.new("test.rb")
    $cur_class.ast = ast
    parse_db_constraint_file(ast)
    assert_equal 1, model_class.getColumns.length
    assert_equal 1, model_class.getConstraints.length
    contents1 = "class ChangeProductsPrice < ActiveRecord::Migration[5.0]
                def up
                  add_index(:products, :name)
                end
              end"
    ast1 = YARD::Parser::Ruby::RubyParser.parse(contents1).root
    $cur_class = File_class.new("add_index.rb")
    $cur_class.ast = ast1
    parse_db_constraint_file(ast1)
    assert_equal 1, model_class.indices.size
    assert_equal model_class.getColumns[0], temp_model_class.getColumns[0]
    assert_equal model_class.indices[0], temp_model_class.indices[0]
  end
end
