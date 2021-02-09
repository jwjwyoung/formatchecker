require "yard"

def parse_alter_query(sql_string)
  l_sql_string = sql_string.downcase
  l_sql_string = l_sql_string.gsub("`", "")
  if l_sql_string["alter table"]
    # puts "Alter query"
    code = ""
    strings = l_sql_string.split(" ")
    table = strings[2]
    if l_sql_string["add column"]
      column = strings[5]
      column_type = strings[6]
      code = "add_column :#{table}, :#{column}"
      if index = strings.index("default")
        default_value = strings[index + 1]
        code += ", default: #{default_value}"
      end
      if l_sql_string["not null"]
        code += ", null: false"
      end
    end
    if l_sql_string["add constraint"]
      if l_sql_string["foreign key"]
        key_name = strings[5]
        if index = strings.index("references")
          column = strings[index - 1]
          ref_table = strings[index + 1].split("(")[0]
          code = "add_foreign_key :#{table}, :#{ref_table}"
        end
      end
    end
    if l_sql_string["rename column"]
      if index = strings.index("to")
        old_column = strings[index - 1]
        new_column = strings[index + 1]
        code = "rename :#{old_column}, :#{new_column}"
      end
    end
    if l_sql_string["drop column"]
      column = strings[5]
      code = "remove_column :#{table}, #{column}"
    end

    if l_sql_string["drop constraint"]
    end

    if l_sql_string["drop foreign key"]
      column = strings[6]
      code = "remove_foreign_key :#{table}, :#{column}"
    end

    if l_sql_string["alter column"]
      column = strings[5]
      if l_sql_string["drop not null"]
        code = "change_column_null :#{table}, :#{column}, true"
      end
      if l_sql_string["set not null"]
        code = "change_column_null :#{table}, :#{column}, false"
      end
      if index = strings.index("type")
        type = strings[index + 1]
        code = "change_column :#{table}, :#{column}, #{type}"
      end
    end
    if l_sql_string["modify"] and not l_sql_string["modify column"]
      column = strings[4]
      type = strings[5]
      code = "change_column :#{table}, :#{column}, #{type}"
    end

    # puts "code: #{code}"
    begin
      ast = YARD::Parser::Ruby::RubyParser.parse(code).root
      return ast
    rescue
    end
  end
end

def test
  sql_string = "alter table forum_thread_users add constraint test_starred_at check(starred = false or starred_at is not null)"
  sql_string = "ALTER TABLE share_visibilities ADD COLUMN shareable_type VARCHAR(60) NOT NULL DEFAULT 'Post'"
  sql_string = "alter table users drop column ip_address"
  sql_string = "ALTER TABLE aspect_visibilities RENAME COLUMN post_id TO shareable_id"
  sql_string = "ALTER TABLE invites ALTER COLUMN email DROP NOT NULL"
  sql_string = "alter table states drop foreign key fk_states_countries"
  sql_string = "ALTER TABLE notifications ALTER COLUMN data TYPE VARCHAR(1000)"
  sql_string = "ALTER TABLE tags MODIFY name varchar(255) CHARACTER SET utf8 COLLATE utf8_bin;"
  sql_string = "ALTER TABLE weblogs MODIFY `uuid` varchar(200) CHARACTER SET utf8"
  sql_string = "alter table user_roles add constraint fk_user_roles_user_id foreign key (user_id) references users(id)"
  parse_alter_query(sql_string)
end

# test
