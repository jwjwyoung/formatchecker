args = ARGV

def header_line(command)
	header_line = ""
	if command == '-l'
		header_line = "APP loc total_constraints_num db_constraints_num model_constraints_num html_constraints_num columnstats: [total, associated_with_constraints]\n"
	end
	if ["--tva", '-t'].include?command
		header_line = "APP #versions	added/changed_versions	model_newconstraints	db_newconstraints	model_changedconstraints	db_changedconstraints	model_existing_columns	db_existing_columns	model_new_columns	db_new_columns	html_newconstraints	html_changedconstraints	html_exisitng_columns	html_new_columns"
	end
	return header_line
end

apps = open('app_names.txt').readlines
apps = apps.map{|x| x.strip}

commit_index = {}
if args.include? "--commit-index"
  commit_index = Hash[open("app_with_commit.txt").readlines.map{|x| x.strip.split("\t")}]
  args -= ["--commit-index"]
end

main_folder = 'constraint_analyzer'
app_folder = '../apps'
command = args[0] || "-s"
return unless app_folder

count = {}
log = open("log/output.log",'w')
header_line = header_line(command)
log.write(header_line)
apps.each do |app|
	if app.start_with?'#'
		next
	end

    if commit_index[app]
      command += " --commit #{commit_index[app]}"
    end

	execute = "cd #{main_folder}; ruby main.rb -a #{app_folder}/#{app} #{command}"
	puts "#{execute}"
	lines = `#{execute}`
	log.write("======#{app}======\n")
	log.write(lines)
	log.write("\n")
	
	lines = lines.lines
	absent_total = lines[-1].strip
	count[app] = absent_total
	log.write("#{app} ")
	log.write(absent_total)
	log.write("\n")
	#puts "#{app} #{absent_total}"
	# `cd #{main_folder}; ruby main.rb #{app_folder}/#{app}`
	# lines = open("./log/output_#{app}.log").readlines
	# data = lines[-1].strip.split(" ")
end
log.close
count.each do |k, v|
	puts "#{k} #{v.gsub("total absent: ", "")}"
end
