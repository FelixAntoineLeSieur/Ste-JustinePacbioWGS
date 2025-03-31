import os, sys
import yaml,json
import requests

#API call to retrieve the list of all samples from GeneYX
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


if __name__ == "__main__":

	config=loadYamlFile("/home/felixant/scratch/MINIWDL/GeneYX/geneyx.analysis.api/scripts/ga.config.yml")

	jsonDict={"ApiUserId":config['apiUserId'],"ApiUserKey":config['apiUserKey']}

	with open('config.json', 'w') as fp:
		jsonFile=json.dump(jsonDict,fp)

	data=loadDataJson("config.json")
	api='https://analysis.geneyx.com/api/Samples'
	print("Requesting sample list from GeneYX")
	r = requests.post(api, json=data)


	code = r.text
	print(code)

	if "error" in code :
		print("Error")
	else:
		print("Success")
		samples = r.json()["Data"]
		print(len(samples))
		with open('allGeneYXSampleList.json', 'w') as fr:
			sampleFile=json.dump(samples,fr)


	
