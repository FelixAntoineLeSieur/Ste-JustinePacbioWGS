#!/bin/bash
#SBATCH --time=00:10:00
#SBATCH --account=def-rallard
#SBATCH --output=J-%x.%j.out
#SBATCH --cpus-per-task=1
#SBATCH --mem=3G
#Runs Somalier inside an apptainer image
#Arguments:
# $-i <familyID>
# $-p <proband_name>
# $-m <mother_name>
# $-f <father_name>
# $-r <fasta_path>
# $-d <input_directory>

#It's not normally necessary to run in a sbatch, but for some reason,
#Running from images takes a long time for the pca step (same for Peddy)

set -eu
module load apptainer/1.3.5 python/3.11 htslib/1.22.1

echo "Arguments:"
for var in "$@"; do
 echo $var
done
usage() { echo "Usage: $0 [-i <familyID>] [-p <proband_name>] [-m <mother_name>] [-f <father_name>] [-r <fasta_path>] [-s <sites.hg38.vcf.gz>]" 1>&2; exit 1; }
sites_vcf="$APPTAINER_CACHEDIR/sites.hg38.vcf.gz"

while getopts ":p:m:f:i:r:d:s:" o; do
    case "${o}" in
        p)
            proband_name=${OPTARG}
            ;;
        m)
            mother_name=${OPTARG}
            ;;
        f)
            father_name=${OPTARG}
            ;;
        i)
			family_id=${OPTARG}
			;;
		r)
			fasta_path=${OPTARG}
			;;
        d)
            input_directory=${OPTARG}
            ;;
        s)
            sites_vcf=${OPTARG}
            ;;
		*)
            usage
            ;;
    esac
done

if [ -z "${proband_name:-}" ] || [ -z "${mother_name:-}" ] || [ -z "${family_id:-}" ] || [ -z "${fasta_path:-}" ]; then
	usage
fi

# #There is a 1-kg tar to extract to use this command, this won't work on Narval or Rorqual
# On these clusters, you need to download these from a login node, or from the postprocess1.sh script
if [ -z $APPTAINER_CACHEDIR ]; then
    echo """Warning: You should set an explicit directory for APPTAINER_CACHEDIR in ~/.bashrc IE:
    export APPTAINER_TMPDIR="~/scratch/singularity_cache/tmp"
    export APPTAINER_CACHEDIR="/home/felixant/scratch/singularity_cache"
"""
    echo "Using script folder for now"
    export APPTAINER_CACHEDIR="$here_folder/apptainer_cache"
    mkdir -p $APPTAINER_CACHEDIR
fi
if [ ! -f "$APPTAINER_CACHEDIR/1kg.somalier.tar.gz" ]; then
    echo "Downloading 1-kg somalier data"
    wget https://zenodo.org/record/3479773/files/1kg.somalier.tar.gz -O "$APPTAINER_CACHEDIR/1kg.somalier.tar.gz"
fi
if [ ! -d "$APPTAINER_CACHEDIR/1kg-somalier" ]; then
    tar -xzf "$APPTAINER_CACHEDIR/1kg.somalier.tar.gz" -C "$APPTAINER_CACHEDIR/"
fi

here_folder=$(realpath $(dirname $0))
image=$APPTAINER_CACHEDIR/somalier-v0.3.1.sif
if [ ! -f "$APPTAINER_CACHEDIR/somalier-v0.3.1.sif" ]; then
    echo "Downloading Somalier container"
    apptainer pull $APPTAINER_CACHEDIR/somalier-v0.3.1.sif docker://brentp/somalier:v0.3.1
fi

ped_file="$input_directory/${family_id}.ped"

function index_vcf() {
	if [ -f "$input_directory/$1.$family_id.normed.joint.GRCh38.small_variants.phased.vcf.gz" ]; then
		if [ ! -f "$input_directory/$1.$family_id.normed.joint.GRCh38.small_variants.phased.vcf.gz.tbi" ]; then
			tabix -p vcf "$input_directory/$1.$family_id.normed.joint.GRCh38.small_variants.phased.vcf.gz"
		fi
	else
		echo "VCF file $input_directory/$1.$family_id.normed.joint.GRCh38.small_variants.phased.vcf.gz not found"
		exit 1
	fi
}

function apptainer_extract() {
index_vcf "$1"
apptainer exec -C -B $HOME --pwd $input_directory \
  $image \
  somalier extract \
  -s "$2" \
  -f "$fasta_path" \
  -d  "$input_directory/Somalier_analyses/Extracted_profiles" \
  --sample-prefix "$1" \
  $input_directory/$1.$family_id.normed.joint.GRCh38.small_variants.phased.vcf.gz
}


#Get Required files if not present
if [ -z "$sites_vcf" ] || [ ! -f "$sites_vcf" ]; then
wget https://github.com/brentp/somalier/files/3412456/sites.hg38.vcf.gz -O $APPTAINER_CACHEDIR/sites.hg38.vcf.gz
fi
echo "Running Somalier extract on:"
echo $proband_name

apptainer_extract "$proband_name" "$sites_vcf"
echo $mother_name
apptainer_extract "$mother_name" "$sites_vcf"
if [ ! -z "$father_name" ]; then
	echo $father_name
	apptainer_extract "$father_name" "$sites_vcf"
fi

echo "Running Somalier relate"
apptainer exec -C -B $HOME --pwd $input_directory/Somalier_analyses/ \
  $image \
  somalier relate \
  -p "$ped_file" \
  "Extracted_profiles/*.somalier"


echo "Running Somalier compare to 1-kg"
echo "Folder: $input_directory/Somalier_analyses/1kg-somalier/*.somalier"
echo "input_directory: $input_directory/Somalier_analyses/"
apptainer exec -C -B $HOME --pwd $input_directory \
  $image \
  somalier ancestry \
  --labels /ancestry-labels-1kg.tsv \
  $APPTAINER_CACHEDIR/1kg-somalier/*.somalier \
   ++ $input_directory/Somalier_analyses/Extracted_profiles/*.somalier