#!/bin/bash

set -eu
module load apptainer/1.3.5 python/3.11 htslib/1.22.1

echo "Arguments:"
for var in "$@"; do
 echo $var
done

usage() { echo "Usage: $0 [-i <familyID>] [-p <proband_name>] [-m <mother_name>] [-f <father_name>]" 1>&2; exit 1; }

while getopts ":p:m:f:i:d:" o; do
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
        d)
            input_directory=${OPTARG}
            ;;
		*)
            usage
            ;;
    esac
done
if [ -z "${proband_name:-}" ] || [ -z "${mother_name:-}" ] || [ -z "${family_id:-}" ]; then
	usage
fi
here_folder=$(realpath $(dirname $0))

#Setup the images
if [ -z $APPTAINER_CACHEDIR ]; then
    echo """Warning: You should set an explicit directory for APPTAINER_CACHEDIR in ~/.bashrc IE:
    export APPTAINER_TMPDIR="~/scratch/singularity_cache/tmp"
    export APPTAINER_CACHEDIR="/home/felixant/scratch/singularity_cache"
"""
    echo "Using script folder for now"
    export APPTAINER_CACHEDIR="$here_folder/apptainer_cache"
    mkdir -p $APPTAINER_CACHEDIR
fi

image=$APPTAINER_CACHEDIR/peddy_v0.4.8.sif
if [ ! -f $image ]; then
	apptainer build $image $here_folder/peddy.def
fi


ped_file="$input_directory/${family_id}.ped"

cd $input_directory

function index_vcf() {
	if [ -f "$1.$family_id.normed.joint.GRCh38.small_variants.phased.vcf.gz" ]; then
		if [ ! -f "$1.$family_id.normed.joint.GRCh38.small_variants.phased.vcf.gz.tbi" ]; then
			tabix -p vcf "$1.$family_id.normed.joint.GRCh38.small_variants.phased.vcf.gz"
		fi
	else
		echo "VCF file $1.$family_id.normed.joint.GRCh38.small_variants.phased.vcf.gz not found"
		exit 1
	fi
}

index_vcf "$proband_name"
index_vcf "$mother_name"
if [ ! -z "$father_name" ]; then
	index_vcf "$father_name"
fi	


here_folder=$(realpath $(dirname $0))

#We start with a normalized vcf separated for each individual, we just need to merge it again
if [ ! -f "$family_id.merged.normed.joint.GRCh38.small_variants.phased.vcf.gz" ]; then
		echo "Merging normed VCFs"
		if [ ! -z "$father_name" ]; then
			if [ ! -f "$father_name.$family_id.normed.joint.GRCh38.small_variants.phased.vcf.gz.tbi" ]; then
				tabix -p vcf "$father_name.$family_id.normed.joint.GRCh38.small_variants.phased.vcf.gz"
			fi 
			bcftools merge \
				"$proband_name.$family_id.normed.joint.GRCh38.small_variants.phased.vcf.gz" \
				"$mother_name.$family_id.normed.joint.GRCh38.small_variants.phased.vcf.gz" \
				"$father_name.$family_id.normed.joint.GRCh38.small_variants.phased.vcf.gz" \
				-o "$family_id.merged.normed.joint.GRCh38.small_variants.phased.vcf.gz" -O z
		else #duo
			bcftools merge \
				"$proband_name.$family_id.normed.joint.GRCh38.small_variants.phased.vcf.gz" \
				"$mother_name.$family_id.normed.joint.GRCh38.small_variants.phased.vcf.gz" \
				-o "$family_id.merged.normed.joint.GRCh38.small_variants.phased.vcf.gz" -O z

		fi
		echo "Generating Index for merged normed VCFs"
		tabix -f -p vcf "$family_id.merged.normed.joint.GRCh38.small_variants.phased.vcf.gz"
	fi


mkdir -p "$input_directory/Peddy_analyses"
echo "Running Peddy relate"
# We want this to run on the interactive node, no access to multi-threading
# export OMP_NUM_THREADS=1 
# export OPENBLAS_NUM_THREADS=1
# export GOTO_NUM_THREADS=1
apptainer exec -C -B $SCRATCH --pwd "$input_directory/Peddy_analyses" \
	$image \
	python -m peddy --plot --sites hg38 --prefix "${family_id}_peddy" \
	"$input_directory/$family_id.merged.normed.joint.GRCh38.small_variants.phased.vcf.gz" \
	"$ped_file"

echo "Peddy complete"