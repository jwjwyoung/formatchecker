import xlrd 
import xlsxwriter

def getType(t, types):
	for i in range(len(types)):
		ty = types[i]
		#print ty, "|", t, "|",  ty in t
		if ty in t:
			return i
	return -1  
# Give the location of the file 
loc = ("upgrade-issues.xlsx") 
apps = ['discourse', 'lobsters', 'gitlab', 'redmine',  'spree', 'ror', 'fulcrum', 'tracks', 'diaspora', 'onebody',  'ff',  'osm']
app_abbrs = [ 'Ds', 'Lo', 'Gi', 'Re',  'Sp', 'Ro',  'Fu', 'Tr',  'Da', 'On',  'FF', 'OSM']
types = ["WHERE", \
		"WHAT vs. code", \
		"WHAT vs. user", \
		"WHEN Inconsistency between old data and new constraints", \
		"Missing information from error message", \
		#"configuration", \
		#"migration error", \ 
		]
wb = xlrd.open_workbook(loc) 
results = [[]] * len(apps)
results2 = [[]] * len(apps)
results3 = [[]] * len(apps)
for i in range(len(apps)):
	results[i] = [0] *  len(types)
	results2[i] = [[]] *  len(types)
	results3[i] = [[]] *  len(types)
for i in range(len(apps)):
	for j in range(len(types)):
		results2[i][j] = []
for i in range(len(apps)):
	app = apps[i]
	#print app
	sheet = wb.sheet_by_name(app) 
  	for j in range(sheet.nrows):
  		t = sheet.cell_value(j, 4)
  		tindex = getType(t, types)
  		if tindex != -1:
  			results[i][tindex] += 1
  			#results2[i][tindex].append(sheet.cell_value(j, 7))
  			#results3[i][tindex].append(sheet.cell_value(j, 4))
total = 0
print " |",
for i in range(len(types)):
	print types[i], "|",
print ""
for i in range(len(apps)):
	print apps[i], "|",
	sum = 0
	for j in range(len(types)):
		print results[i][j], "|",
		sum += results[i][j]
	print sum,
	total += sum
	print ""
print total
# print "<br/>"
# for i in range(len(apps)):
# 	print apps[i], "|",
# 	sum = 0
# 	for j in range(len(types)):
# 		for k in range(len(results2[i][j])):
# 			print "<a href='", results3[i][j][k] ,"'>", results2[i][j][k], "</a>",
# 		print "|",
# 	print "<br/>"
# Create a workbook and add a worksheet.
workbook = xlsxwriter.Workbook('output.xlsx')
worksheet = workbook.add_worksheet()



for i in range(len(apps)):
	worksheet.write(i+1,0, app_abbrs[i])
	for j in range(len(types)):
		worksheet.write(0,j+1, types[j])
		worksheet.write(i+1, j+1, results[i][j])
# Some data we want to write to the worksheet.

for i in range(len(apps)):
	worksheet.write(i+1+15,0, apps[i])
	for j in range(len(types)):
		worksheet.write(15,j+1, types[j])
		worksheet.write(i+1 + 15, j+1, " ".join(results2[i][j]))
		#print "length:", len(results2[i][j])

# Extracting number of rows 
workbook.close()
