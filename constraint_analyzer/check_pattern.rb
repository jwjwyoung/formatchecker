def check_code(app_dir, commit, model, column)
  `git -C '#{app_dir}' checkout -fq #{commit}`
  unless $CHILD_STATUS.success?
    raise "command for checkout version failed"
  end

  Dir["#{app_dir}/app/**/*.rb"].each do |filename|
    ast = File.open(filename) do |f|
      YARD::Parser::Ruby::RubyParser.parse(f.read).ast
    end
    rel_filename = Pathname.new(filename).relative_path_from app_dir
    ast.traverse do |it|
      get_query_call(it) do |line, query, mod, col|
        if (model.nil? || column.nil?) || (model == mod && col.include?(column))
          puts "\e[36m#{rel_filename}\e[37;0m:\e[33;1m#{line}\e[37;0m #{mod}.#{query}: #{col}"
        end
      end
    end
  end
end

def get_query_call(ast)
  return if !ast.call? ||
            ast[0]&.type != :var_ref ||
            !ast[1]&.respond_to?(:type) ||
            ast[1].type != :period

  model_name = ast[0].source
  query_name = ast[2].source
  args = ast[3]
  return unless args && args[0]

  case query_name
  when "order"
    args = args[0] if args.type == :arg_paren
    bys = args.children.filter_map do |arg|
      handle_symbol_literal_node(arg) ||
        handle_string_literal_node(arg)&.split&.fetch(0) ||
        handle_hash_node(arg)&.keys
    end.flatten
    yield args.line, query_name, model_name, bys
  when "create", "where"
    args = args[0][0]
    case args.type
    when :string_literal
      str = handle_string_literal_node(args)
      col = /([a-zA-Z_]+)\s*\=\s*\?/.match(str)
      if col && col[1]
        yield args.line, query_name, model_name, [col[1]]
      end
    when :hash, :list
      dic = handle_hash_node(args)
      yield args.line, query_name, model_name, dic.keys
    end
  end
end
