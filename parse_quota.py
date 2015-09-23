#!/usr/bin/python
import subprocess
import re
import sys

if len(sys.argv) != 5:
	sys.stderr.write('argument number error\n')
	print "ERROR"
	exit(1)

qtype = sys.argv[1]
qarg = sys.argv[2]
device = sys.argv[3]
spec = sys.argv[4]

if qtype != "-u" and qtype != "-g" and qtype != "-P":
	sys.stderr.write('quota type error\n')

def run(command):
	p = subprocess.Popen(command,
			     shell = True,
			     stdout = subprocess.PIPE,
			     stderr = subprocess.PIPE)
	stdout, stderr = p.communicate()
	ret = p.wait()
	return ret, stdout, stderr

ret, stdout, stderr = run("quota -v " + qtype + " " + qarg)

if len(device) > 15:
	start = stdout.find(device + "\n")
else:
	start = stdout.find(device + " ")

if start < 0:
	sys.stderr.write('command error\n')
	print "ERROR"
	exit(1)

start += len(device) + 1 # Space after device name

start_string = stdout[start:]

#sys.stderr.write('start : (%s)\n' % (start_string))

end = start_string.find("\n")
if end < 0:
	sys.stderr.write('command error\n')
	print "ERROR"
	exit(1)

full_values = start_string[1:end]

#sys.stderr.write('full : (%s)\n' % (full_values))

values = re.findall('[^ \t\n\r\f\v]+', full_values)
value_number = len(values)

specs = {}

if value_number == 6:
	specs['bgrace'] = "0"
	specs['curinodes'] = values[3].replace('*', '\0')
	specs['isoftlimit'] = values[4]
	specs['ihardlimit'] = values[5]
	specs['igrace'] = "0"
elif value_number == 7:
	#sys.stderr.write('values[6] = (%s)\n' % (values[6]))
	if values[6].isdigit():
		specs['bgrace'] = values[3]
		specs['curinodes'] = values[4].replace('*', '\0')
		specs['isoftlimit'] = values[5]
		specs['ihardlimit'] = values[6]
		specs['igrace'] = "0"
	else:
		specs['bgrace'] = "0"
		specs['curinodes'] = values[3].replace('*', '\0')
		specs['isoftlimit'] = values[4]
		specs['ihardlimit'] = values[5]
		specs['igrace'] = values[6]
elif value_number == 8:
	specs['bgrace'] = values[3]
	specs['curinodes'] = values[4].replace('*', '\0')
	specs['isoftlimit'] = values[5]
	specs['ihardlimit'] = values[6]
	specs['igrace'] = values[7]
else:
	sys.stderr.write('command output field number, %d\n' % (value_number))
	print "ERROR"
	exit(1)

specs['curspace'] = values[0].replace('*', '\0')
specs['bsoftlimit'] = values[1]
specs['bhardlimit'] = values[2]

#for key in specs:
#	sys.stderr.write('key=%s, value=%s\n' % (key, specs[key]))

try:
	print specs[spec]
except Exception:
	print "ERROR"
	exit(1)