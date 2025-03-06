import sys,os
import json
import subprocess
from Sample import Sample
from pathlib import Path
from configurator import Config

"""
Generate the WDL samplesheet for each sample in the given run name.
Give the run name (ie r84196_20250210_150130) as argument and a config file, optionally
the run folder must be present in the run_path specified in the config file (see ../.myconf.json for an example)
"""
if __name__ == "__main__":
	if len(sys.argv) < 2:
			print("Usage: python singletonSampleSheet.py <run_name> <config_file>(optional)")
			sys.exit(1)

	#The configuration file can be provided, optionally
	if len(sys.argv) == 3:
		config_file = sys.argv[2]
	else:
		config_file = "../.my_config.json"

	#The paths specific to your Narval configuration should be in the Paths section of the configs
	configs  = Config.from_path(config_file)
	run_path = configs.Paths.run_path
	sample_sheet_path = configs.Paths.sample_sheet_path

	run_name=sys.argv[1]
	run_folder = Path(run_path + run_name)
	#For our run, each sample is contained in a "well" folder (ex 1_A01, 1_B01...)
	directory_list = [f for f in run_folder.resolve().glob('*') if not f.is_file()]
	sample_list=[]

	for well_folder in directory_list:
		#The sample name is contained in this metadata file, in the pb_format folder
		grep_command = f"grep -o \"BioSample Name=\".*\"\" {well_folder}/pb_formats/*_s*.hifi_reads.bc*.consensusreadset.xml | cut -f2 -d'\"' | tr -d '\n'"
		grep_result = subprocess.run(grep_command, shell=True, capture_output=True, text=True)
		given_name = grep_result.stdout
		well = str(well_folder).split("/")[-1]
		sample = Sample(run_name,well,given_name,config_file=config_file)
		sample_list.append(sample)
		sample.write_singleton_samplesheet()

	#Print the samples sorted by well (1_A01, 1_B01...)
	sorted_list = sorted(sample_list,key=lambda x: x.well.lower())
	for sample in sorted_list: print(sample)

	#Write the list of sample name for this run and the path to their samplesheet
	#Avoid expanding on an already existing list
	if os.path.exists(f"{sample_sheet_path}/{run_name}_samples"):
		os.remove(f"{sample_sheet_path}/{run_name}_samples")
	for sample in sorted_list:
		with open(f"{sample_sheet_path}/{run_name}_samples",'a') as fw:
			fw.write(f"{sample.name},{sample.run_id}_{sample.well}_{sample.name}.json\n")


