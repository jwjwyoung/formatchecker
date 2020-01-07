
def findCommits(commits, directory,target="db/migrate/*")
	outputs = {}
	commits = commits.reverse
	bound = [1000000, commits.length].min
	cnt = 0
	i = 0
	while(true)
		if cnt >= bound or i+1 >= commits.length - 1
			break
		end
		c1 = commits[i].strip
		c2 = commits[i+1].strip
		i += 1
		print "i #{i} " if i%1000 == 0
		cmd = "cd #{directory}; git diff #{c1} #{c2} #{target}"
		#puts "cmd #{cmd}"
		output = `#{cmd}`
		if output != ""	
			k = "#{c1} vs #{c2}"
			v = output.lines
			outputs[k] = v
			#puts "length: #{v.length}"	
			cnt += 1
			print "cnt : #{cnt} " if cnt%1000 == 0
			files = checkConstraints(v)
			if files.length > 0
				puts "cmd #{cmd}"
				files.each do |fn, con|
					puts "version: #{k}"
					puts "filename: #{fn}"
					puts "con: #{con.join}"
				end
			end
		end
	end
	return outputs
end

def checkConstraints(output)
	indices = output.each_with_index.select{|x, i| x.start_with?"diff --git"}.map{|x,i| i}
	files = {}
	for i in 1...indices.length
		start = indices[i-1]
		over = indices[i]
		filename = output[start]
		#puts output[start]
		#puts output[over]
		files[filename] = output[start...over]
		#puts "========"
		#puts "filename: #{filename} #{files[filename].join}"
	end
	#puts "files.length: #{files.length}"
	results = {}
	files.each do |k, v|
		add = {}
		delete =  {}
		for line in v
			if line.include?"def down"
				break
			end
			if line.start_with?"+" and line.include?"create_table :"
				break
			end
			if line.start_with?"+"
				begin
					str = line[1..-1].strip
					add[str] = true
				rescue
				end
			end
			if line.start_with?"-"
				begin
					str = line[1..-1].strip
					delete[str] = true
				rescue
				end
			end
		end
		add.each do |line, value|
			if delete[line]
				# if the string also occurs in delete contents, it means there is no change in the content
				next
			end
			if k.include?("/db/migrate")
				if (line.include?("add_column") or line.include?("change_column") )and !line.include?"default"
					if line.include?("null: false") or line.include?("null => false")
						puts "hit line #{line}"
						results[k] = v
						puts "results: #{results.length}"
						next
					end
				end
				if line.include?"def down" or line.include?"def self.down"
					break
				end
			end
			if k.include?"/models/" 
				if line.include?"class "
					break
				end
				if line.include?"validates :" or line.include?"validate :" or line.include?"validates_presence_of :" \
					or line.include?("validate") or line.include?("validates_associated") \
					or line.include?("validates_confirmation_of") or line.include?("validates_each") \
					or line.include?("validates_exclusion_of") or line.include?("validates_form_of") \
					or line.include?("validates_inclusion_of") or line.include?("validates_length_of") \
					or line.include?("validates_numericality_of") or line.include?("validates_uniqueness_of")
                    
					if results[k]
						next
					end
					results[k] = v
					puts "hit line #{line}"
					next
				end
                #puts "line #{line}"
                # check if changing/adding column or changing multiples columns (table)
                if (line.include?("add_column") or line.include?("change_column") or
                    line.include?("change_table")) and !line.include?("default")
					if line.include?("null: false") or line.include?("null => false")
						puts "hit line #{line}"
						results[k] = v
                        puts "results: #{results.length}"
                    end
                # check if changing column null constraints
                elsif (line.include?("change_column_null") and !line.include?("default"))
                    puts "hit line #{line}"
                    results[k] = v
                    puts "results: #{results.length}"
                # check if validates was not present before
  				
				end
			end
		end
	end
	#puts "results #{results.length}"
	return results
end
location = "commits.txt"
directory = ARGV[0]
# fp = open(location,'r')
# commits = fp.readlines()
commits = `python commits.py #{directory}`
commits = commits.lines
puts commits.length
if ARGV[1]
	puts "target: #{ARGV[1]}"
	results = findCommits(commits,directory,ARGV[1])
else
	results = findCommits(commits,directory)
end
final = {}
# results.each do |k,v|
# 	# puts k
# 	# puts v
# 	files = checkConstraints(v)
# 	if files.length > 0
# 		puts "version: #{k}"
# 		files.each do |fn, con|
# 			puts "filename: #{fn}"
# 			puts "con: #{con.join}"
# 		end
# 	end
# end