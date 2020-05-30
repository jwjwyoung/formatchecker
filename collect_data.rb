app_file = "sigmod_apps.txt"
apps = open(app_file).readlines.map{|x| x.strip}
types = %w(presence_no_default presence_default unique format inclusion_exclusion unique length)
results = []
key = "model_present_db_absent"
for app in apps
  result = {}
  result["app"] = app
  absent_log_name = "./log/absent_constraints_#{app}.csv"
  contents = open(absent_log_name).readlines
  contents.each do |c|
    values = c.split(",")
    if values[1] == key
      for t in types
        if values[2] == t
          result[t] = values[3].to_i  
        end
      end
    end 
  end
  mismatch_fn = "./log/mismatch_constraints_#{app}.csv"
  length_n = `grep "Length_constraint,DB-Model" #{mismatch_fn} | wc -l`
  result["length"] = length_n.to_i
  results << result
end
print(" ")
for t in types 
 print(t + " ") 
end
puts ""
for r in results
  print(r["app"] + " ")
  for t in types
    print(r[t])
    print(" ")
  end
  puts ""
end
