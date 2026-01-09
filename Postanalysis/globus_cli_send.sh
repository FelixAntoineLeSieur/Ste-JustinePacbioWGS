#!/bin/bash
#SBATCH --job-name=Globus_${family_id}
#SBATCH --output=J-%x.%j.out
#SBATCH --account=def-rallard
#SBATCH --time=00:10:00

# This script is meant to use globus to send a fully processed folder
# This will ignore symlinks 

# On Narval the default destination the path is:
destination_path="$HOME/projects/ctb-rallard/COMMUN/PacBioData/OutputFamilies"


set -eu
echo "Arguments:"
for var in "$@"; do
 echo $var
done
usage() { echo "Usage: $0 [-i <familyID>] [-d <directory to clean>] [-c <optional config file (default .myconf.json)>] [-h <here_folder>]" 1>&2; exit 1; }
config_file="$(dirname $0)/../.myconf.json"

while getopts ":i:d:c:h:" o; do
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