require "pg_query"
require "yard"

def parse_sql(ast)
  if ast&.type.to_s == "list"
    string_literal_node = ast[0]
    if string_literal_node.type.to_s == "string_literal"
      query_node = string_literal_node[0]
      if query_node&.type.to_s == "string_content"
        sql = query_node.source
        if sql.start_with? "<"
          sql = handle_cross_line_string(sql)
        end
        if sql.downcase["alter table"]
          ast = parse_alter_query(sql)
          parse_db_constraint_file(ast)
        end
        return parse_sql_string(sql)
      end
    end
  end
end

# use pg query to handle sql query string
def parse_sql_string(sql)
  # in mastodon, we have:
  # "CREATE INDEX hashtag_search_index ON tags USING gin(to_tsvector(\\'simple\\', tags.name));"
  sql.gsub!("\\'", "'")
  type = ""
  begin
    sql_ast = PgQuery.parse(sql)
  rescue PgQuery::ParseError
    return
  end
  tree = sql_ast.tree[0]["RawStmt"]["stmt"]
  table_name = nil
  columns = []
  if tree["UpdateStmt"]
    type = "update"
    update_query = tree["UpdateStmt"]
    begin
      table_name = update_query["relation"]["RangeVar"]["relname"]
    rescue
    end
    update_query["targetList"].each do |v|
      begin
        column = v["ResTarget"]["name"]
        columns << column
      rescue
      end
    end
  end
  if insert_query = tree["InsertStmt"]
    type = "insert"
    begin
      table_name = insert_query["relation"]["RangeVar"]["relname"]
      insert_query["cols"].each do |col|
        col_name = col["ResTarget"]["name"]
        columns << col_name
      end
    rescue
    end
  end
  return table_name, columns, type
end

def handle_cross_line_string(sql)
  if sql.start_with? "<"
    sql = sql.lines[1...-1].join
    begin
      # puts "sql : #{sql}"
      PgQuery.parse(sql)
    rescue
      # puts "Illegal query reset to null"
      sql = ""
    end
    return sql
  end
  return ""
end
