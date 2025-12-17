import globus_sdk
from globus_sdk.globus_app import UserApp
import sys
import os
import argparse
from configurator import Config

#Script needs globus sdk installed with:
#pip install globus-sdk

def main(SRC_PATH,TARGET_DIR,USERNAME,ORIGIN_CLUSTER):

	NATIVE_CLIENT_ID = "43ecdcab-d9d6-4c39-816f-3ca89c81c079"
	USER_APP = UserApp("CHUSJPacbioGlobusTransfers", client_id=NATIVE_CLIENT_ID)

	if ORIGIN_CLUSTER == "Rorqual":
		SRC_COLLECTION = "f19f13f5-5553-40e3-ba30-6c151b9d35d4" # Rorqual
	elif ORIGIN_CLUSTER == "Fir":
		SRC_COLLECTION = "8dec4129-9ab4-451d-a45f-5b4b8471f7a3" # Fir
	else:
		print(f"Did not recognize origin cluster {ORIGIN_CLUSTER}")
		sys.exit(1)

	DST_COLLECTION = "a1713da6-098f-40e6-b3aa-034efe8b6e5b" # Narval
	# Default destination on Narval
	DST_PATH = f"/home/{USERNAME}/projects/ctb-rallard/COMMUN/PacBioData/OutputFamilies/{TARGET_DIR}"

	transfer_client = globus_sdk.TransferClient(app=USER_APP)

	transfer_client.add_app_data_access_scope(SRC_COLLECTION)
	transfer_client.add_app_data_access_scope(DST_COLLECTION)

	transfer_request = globus_sdk.TransferData(SRC_COLLECTION, DST_COLLECTION)
	transfer_request.add_item(SRC_PATH, DST_PATH)

	task = transfer_client.submit_transfer(transfer_request)
	print(f"Submitted transfer. Task ID: {task['task_id']}.")


if __name__ == "__main__":
	script_path = os.path.dirname(os.path.abspath(__file__))
	parser = argparse.ArgumentParser(
		prog = 'globus_send.py',
		usage = "python3 %(prog)s [-u <Alliance $USER> -d <input_directory>] [--config config_file (optional)]",	
		description='given a family_id and a directory to send, send the data to Narval using Globus')
	#parser.add_argument('-i', '--id',help='family ID',required=True)
	parser.add_argument('-d', '--dir',help='Directory to send',required=True)
	parser.add_argument('-c', '--config', nargs='?', const=f"{script_path}/../.myconf.json", default=f"{script_path}/../.myconf.json")
	
	args		= parser.parse_args()
	configs  	= Config.from_path(args.config)
	user		= os.environ['USER']
	dir_name	= os.path.basename(args.dir)
	full_dir	= os.path.realpath(args.dir)
	print(f"Preparing to send directory {full_dir} in folder {dir_name}")
	origin_cluster = configs.Transfers.origin_cluster
	main(full_dir,dir_name,user,origin_cluster)