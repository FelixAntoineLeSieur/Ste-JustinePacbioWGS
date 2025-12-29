#!/bin/bash
#SBATCH --job-name=multiqc_${family_id}
#SBATCH --output=J-%x.%j.out
#SBATCH --account=def-rallard
#SBATCH --mem=4G
#SBATCH --time=01:00:00

# This script is meant to dar a fully processed folder
# then send it to Narval
# Note that you can use the robot nodes to automate this
# Follow the instructions here: 
# https://msss365-my.sharepoint.com/:p:/g/personal/nicolas_perrot_hsj_ssss_gouv_qc_ca/IQBk4eS7U82LS7RY-GDUzAotAb5FslgG8GfcCOw3VRsNF0s?e=3xbdHn 
# If you don't have access to NarvalInteractiveRobot, you can use the default Narval login
# but you will have to enter your password manually

# On Narval the default destination the path is:
destination_path="$HOME/projects/ctb-rallard/COMMUN/PacBioData/OutputFamilies"


set -eu
echo "Arguments:"
for var in "$@"; do
 echo $var
done
usage() { echo "Usage: $0 [-i <familyID>] [-d <directory to clean>] [-c <optional config file (default .myconf.json)>] [-h <here_folder>]" 1>&2; exit 1; }
config_file="$(dirname $0)/../.myconf.json"
cluster="narval.alliancecan.ca"
identity_line=""
while getopts ":i:d:c:rh:" o; do
	case "${o}" in
		i)
			family_id=${OPTARG}
			;;
		d)
			directory=${OPTARG}
			if [ ! -d "$directory" ]; then
				echo "Could not find directory $directory"
				exit
			fi
			;;
		c)
			config_file=${OPTARG}
			;;
		r)
			#Use robot node (automation but requires setup)
			cluster="robot.narval.alliancecan.ca"
			identity_file=$(jq -r '.Transfers.identity_file' "$config_file")
			if [ ! -f "$identity_file" ]; then
				echo "Could not find identity file $identity_file"
				exit
			fi
			identity_line="-e \"ssh -i $identity_file\""
			;;
		h)
			here_folder=${OPTARG}
			;;
		*)
			usage
			;;
	esac
done

if [ -z "${family_id:-}" ] || [ -z "${directory:-}" ]; then
	usage
fi

if [ ! -f "$config_file" ]; then
	echo "Could not find config file $config_file"
	exit
fi

#We send only symlinks to allow globus to do the real file transfers
#(Globus avoids symlinks)
echo "Sending symlinks from $directory to $USER@$cluster:$destination_path/$family_id"
echo "rsync -rlPv $identity_line--files-from=- \"$directory\" \"$USER@$cluster:$destination_path/$family_id\""
if [ ! -n "$identity_line" ]; then
	find "$directory" -type l -printf '%P\n' | \
		rsync -rlPv --files-from=- "$directory" "$USER@$cluster:$destination_path/$family_id"
else
	find "$directory" -type l -printf '%P\n' | \
		rsync -rlPv -e "ssh -i $identity_file" --files-from=- "$directory" "$USER@$cluster:$destination_path/$family_id"
fi
echo "here folder: $here_folder/../Tools/Globus_env"
ENVDIR=$here_folder/../Tools/Globus_env
if [ -d "$ENVDIR" ]; then
	echo "using existing Globus environment at $ENVDIR"
	source $ENVDIR/bin/activate
else
	virtualenv --no-download $ENVDIR
	source $ENVDIR/bin/activate
	pip install --no-index --upgrade pip
	echo "Loading Globus environment"
	pip install -r $here_folder/../Tools/requirementsGlobus.txt
fi
# ENVDIR=/tmp/$RANDOM
# virtualenv --no-download $ENVDIR
# source $ENVDIR/bin/activate
# pip install --no-index --upgrade pip
# pip install -r $(dirname $0)/../Tools/requirementsGlobus.txt
# python3 globus_send.py -c "$config_file" -d "$directory"

cat << EOF > globusFlow_$family_id.json
{
	"source": {
		"id": "$(jq -r '.Transfers.origin_collection' $config_file)",
		"path": "$directory/"
	},
	"destination": {
		"id": "$(jq -r '.Transfers.destination_collection' $config_file)",
		"path": "$destination_path/$family_id/"
	},
	"transfer_label": "Transfer $family_id to Narval",
	"verify_checksum": true
}
EOF
cat globusFlow_$family_id.json
move_flow=6336492e-e308-4a67-b78e-13684c747472 ##UUID of the move and delete flow
globus flows start --input file:globusFlow_$family_id.json $move_flow 
rm globusFlow_$family_id.json
