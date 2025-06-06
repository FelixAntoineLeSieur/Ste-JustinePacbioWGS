import requests
import os,sys
import logging
import subprocess
import json
from configurator import Config
import subprocess

class GeneYX:
	"""
	Return object for interacting with GeneYX's API
	"""
	def __init__(self, config_file=os.path.expanduser(".myconf.json")):
		"""
		Load settings from config_file, if provided. Define instance vars to
		provide more readable access to settings in dict "configs".
		"""
		configs          = Config.from_path(config_file)
		self.geneyx_server   = configs.GeneYX.server
		self.geneyx_id   = configs.GeneYX.apiUserId
		self.geneyx_key   = configs.GeneYX.apiUserKey
		print("Sending to geneYX")

	def verify_response(self, response):
		"""
		Look for common API responses,
		return tuple ([Success, Error],contents)
		"""
		
		if "error" in response.json()["Code"] :
			logging.warning(f"API call returned error: {response}")
			return ("Error",response.text)
		else:
			print("Success")
			return ("Success", response.json())
	
	def group_assign(self, code, vcf_list):
		"""
		Assign a given sample list to a group on geneyx
		'code': code of the group the samples should be assigned to ['prag','decode','controle' or 'validation']
		'vcf_list': List of the vcfs that should have the given group assigned 
		"""
		match code:
			case "prag" : group = "Pragmatiq"
			case "decode" : group = "Decodeur"
			case "controle" : group = "ControleParent"
			case "validation" : group = "Validation"
			case _: 
				logging.warning(f"Enter a valid GeneYX code: 'prag','decode','controle' or 'validation'")
				sys.exit(1)
		
		errorList=[]

		for name in vcf_list:
			jsonDict={"SerialNumber":name,\
			"GroupAssignment":[{"Code": code,"Name":group}],\
			"ApiUserId":self.geneyx_id,\
			"ApiUserKey":self.geneyx_key}
		
			with open('groupReassign.json', 'w') as fp:
				jsonFile=json.dump(jsonDict,fp)

			data=loadDataJson("groupReassign.json")
			api=f"{self.geneyx_server}/api/SampleAssignment"
			print(f"Sending Group assignment {group} for {name}")
			r = requests.post(api, json=data)
			verified = self.verify_response(r)
			if verified[0] == "Success":
				data = verified[1]
				print(data)
			else:
				logging.warning(f"{name} could not be assigned to group {group}:")
				print(verified)
				sys.exit(1)

		if len(errorList) == len(vcf_list):
			print("All samples failed to be sent")
		elif len(errorList) > 0:
			print("Some samples could not be sent successfully:")
			for sample_name in errorList: print(sample_name)
		else:
			print("All samples sent successfully")
	
	def unify_vcfs(sample_name,output_path,structure_variant_vcf,cnv_vcf,tandem_repeat_vcf):
		print(output_path)
		if not os.path.isfile(f"{output_path}/{sample_name}-unifiedVCF.vcf.gz"):
			print(f"Unifying VCF for {sample_name}")
			result = subprocess.run([
				"python3",
				"Postanalysis/geneyx.analysis.api_CHUSJ/scripts/UnifyVcf/PacBioUnifyVcf.py",
				"-o", f"{output_path}/{sample_name}-unifiedVCF.vcf",
				"-s", structure_variant_vcf,
				"-c", cnv_vcf,
				"-r", tandem_repeat_vcf,
				"-b", "/home/felixant/scratch/MINIWDL/Ste-JustinePacbioWGS/Postanalysis/geneyx.analysis.api_CHUSJ/scripts/UnifyVcf/pathogenic_repeats.hg38.bed"], 
				capture_output=True, text=True)

			
			if result.stderr=='':
				print(result)
				print(result.stdout)
				print(f"Unify completed successfully for {sample_name}")
			else:
				print(logging.warning(f"Unify failed for {sample_name} with message: {result.stderr}"))
				sys.exit(1)

		else: print(f"Pre-existing unified VCF found for {sample_name}")


#Helper functions taken from GeneYX's github: https://github.com/geneyx/geneyx.analysis.api/tree/d8587302d22e0e5e59a328390f8c89dd04ff52e7/scripts
def loadYamlFile(file):
	with open(file, 'r') as stream:
		try:
			obj = yaml.safe_load(stream)
			return obj
		except yaml.YAMLError as exc:
			print(exc)


def loadDataJson(file):
	with open(file, 'r') as stream:
		try:
			data = json.load(stream)            
			return data
		except KeyError as exc:
			print(exc)

