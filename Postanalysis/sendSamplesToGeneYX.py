import os, sys, json
import argparse
from configurator import Config
from GeneYX import GeneYX
import logging

#from geneyx_analysis_api_CHUSJ.scripts.UnifyVcf.UnifyVcf import run
sys.path.append(sys.path[0]+'/geneyx.analysis.api_CHUSJ/scripts/UnifyVcf')
import PacBioUnifyVcf

#Send a group of samples to GeneYX, including sending analysis cases, qc data and assigning the appropriate group
if __name__ == "__main__":
	parser = argparse.ArgumentParser(
		prog = 'assignListToGeneYXGroup.py',
		usage = "python3 %(prog)s [-l list_of_names_to_assign] [-f csv_export_of_geneYX_vcf_full_list] [-g group to assign (validation, prag, decode, controle)] [--config config_file (optional)]",	
		description='Assigns a group to a list of sample on GeneYX.')
	parser.add_argument('-r', '--run',help='Run id containing the list of sample name and path to the samplesheet, or direct link to the samplesheet',required=True) 
	#parser.add_argument('-f', '--full',help='Up to date csv export of all VCFs on GeneYX',const='Postanalysis/geneYXnamesList.csv', default='Postanalysis/geneYXnamesList.csv')
	parser.add_argument('-g', '--group',help='The group to which the samples should be assigned to', default='')
	parser.add_argument('-c', '--config', nargs='?', const='.myconf.json', default='.myconf.json')
	args = parser.parse_args()
	
	configs  	= Config.from_path(args.config)
	output_path = configs.Paths.output_path
	sample_sheet_path	= configs.Paths.sample_sheet_path
	sample_list_name	= args.run
	sample_list = []

	if os.path.isfile(f"{args.run}_samples"):
		sample_list_name = f"{args.run}_samples"
	elif not os.path.isfile(sample_list_name):
		print(f"Filepath not found for {sample_list_name}")
		sys.exit(1)
	

	with open(sample_list_name, 'r') as fr:
		for line in fr:
			full_line=tuple(line.rstrip().split(','))
			sample_list.append(full_line)
			print(full_line)
			#If group args is empty, we expect the groups to be defined in the list itself (individual assignment vs group assignment)
			sample_name = full_line[0]
			sample_json = full_line[1]

			if args.group != '':
				print(f"Using given group name {args.group} for all samples")
				group = args.group
			elif len(full_line) == 3:
				logging.warning(f"No given group for sample {sample_name}")
				group = ''
			elif len(full_line) == 4:
				group = full_line[3]
			else:
				logging.warning(f"error: review number of fields in line {full_line}")
				sys.exit()
			
			if os.path.exists()


			


	print(sample_list)

	


			




