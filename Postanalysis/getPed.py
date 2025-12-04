import json, sys
import os.path

#Small script to generate PED format pedigree:
#https://github.com/brentp/slivar/wiki/pedigree-file
#PED file example:


# p054    25-01142-T1     25-01144-T1     25-01146-T1     1       2
# p054    25-01146-T1                     2       1
# p054    25-01144-T1                     1       1

#Input trioName, script will recover SampleSheet/[trioName].json to infer ped data
#This input json file is expected to follow the format of the WGS-WDL V3:
#https://github.com/PacificBiosciences/HiFi-human-WGS-WDL/blob/main/workflows/family.inputs.json

def main():
	home="/home/felixant"
	scratch=f"{home}/scratch"
	if len(sys.argv) < 2:
		print("Usage: python script.py <trio_name_list>")
		sys.exit(1)

	trioName = sys.argv[1]
	if not os.path.isfile(f"{scratch}/SampleSheet/{trioName}.json"):
		print(f"Could not find file {trioName}.json in directory {scratch}/SampleSheet")
		sys.exit(1)

	with open(f"{scratch}/SampleSheet/{trioName}.json",'r') as fileJson:
		sampleSheet = json.load(fileJson)['humanwgs_family.family']

	probandID = sampleSheet['samples'][0]['sample_id']
	probandGender = sampleSheet['samples'][0]['sex']
	if probandGender == 'Male' or probandGender == 'MALE' or probandGender == 'M':
		probandCode = '1'
	elif probandGender == 'Female' or probandGender == 'FEMALE' or probandGender == 'F':
		probandCode = '2'
	else:
		print(f"Could not infer gender {probandGender}")
		sys.exit(1)

	if "father_id" in sampleSheet['samples'][0].keys():
		fatherID = sampleSheet['samples'][0]['father_id']
		fatherLine = f"""
{trioName}\t{fatherID}\t\t\t1\t1"""
	else:
		fatherID = ""
		fatherLine = ""
	motherID = sampleSheet['samples'][0]['mother_id']

	with open(f"{trioName}.ped",'w') as pedFile:
		pedFile.write(
f"""{trioName}\t{probandID}\t{fatherID}\t{motherID}\t{probandCode}\t2
{trioName}\t{motherID}\t\t\t2\t1{fatherLine}
""")
	print(f"{trioName}.ped")

if __name__ == "__main__":
    main()