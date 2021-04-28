def load_validate_api
  $validate_apis = []
  validate_api = File.join(File.expand_path(File.dirname(__FILE__)), "../constraint_analyzer/validate_api")
  open(validate_api).readlines.each do |line|
    $validate_apis << line.strip
  end
  # puts $validate_apis
end

def load_html_constraint_api
  $html_constraint_api = []
  input_field = File.join(File.expand_path(File.dirname(__FILE__)), "../constraint_analyzer/input_field")
  open(input_field).readlines.each do |line|
    $html_constraint_api << line.strip
  end
  #puts $html_constraint_api
end

def convert_tablename(name)
  return nil unless name
  _name = Array.new
  _word_list = Array.new
  name.split("").each do |c|
    if c == "_"
      _word_list.push(_name.join)
      _name = Array.new
    else
      _name.push(c)
    end
  end
  _word_list.push(_name.join)
  _word_list.each do |w|
    w[0] = w[0]&.capitalize
  end
  _word_list[-1] = _word_list[-1]&.singularize
  temp_name = _word_list&.join
  return temp_name
end

def derive_length_constraint_from_format(constraint)
  return nil unless constraint.is_a? Format_constraint

  format = constraint.with_format
  min_value, max_value = derive_length_from_format(format)

  if min_value != 0 or max_value != -1
    len_constraint = Length_constraint.new(constraint.table, constraint.column, constraint.type)
    len_constraint.min_value = min_value
    len_constraint.max_value = max_value if max_value > 0
    return len_constraint
  else
    return nil
  end
end

def derive_length_from_format(format)
  min_value = 0
  max_value = -1

  begin
    examples = Regexp.new(format.gsub(/(\\A|\^|\\G|\$|\\Z|\\z|^\/|\/$|%r\{|\}$)/, "")).examples(max_repeater_variance: 40)
    min_value = examples.map(&:length).min
    if format =~ /(\\A|\^|\\G).*(\$|\\Z|\\z)/ and format !~ /([^\\]\*|[^\\]\+|\{\d,\})/
      max_value = examples.map(&:length).max
    end
  rescue
    # puts "cannot parse regex: #{format}"
  end

  return min_value, max_value
end

def compare_instance_variables(obj1, obj2)
  results = []

  obj1.instance_variables.map do |v|
    val1 = obj1.send(:instance_variable_get, v)
    val2 = obj2.send(:instance_variable_get, v)
    if val1 != val2
      results << v.to_s + "-" + val1.to_s + "-" + val2.to_s
    end
  end

  return results
end

def code_change(folder, commit1, commit2)
  diffs = `cd #{folder}; git diff --stat #{commit1} #{commit2}`.lines
  file = 0
  insertion = 0
  deletion = 0
  return 0, 0, 0 unless diffs
  diff = diffs[-1]
  if diff
    datas = diff.split(",")
    if datas.length >= 3
      if datas[0].include? "files changed"
        file = datas[0].to_i
      end
      if datas[1].include? "insertions(+)"
        insertion = datas[1].to_i
      end
      if datas[2].include? "deletions(-)"
        deletion = datas[2].to_i
      end
    end
  end
  return file, insertion, deletion
end

def is_number(obj)
  return true if obj =~ /\A\d+\Z/
  true if Float(obj) rescue false
end
