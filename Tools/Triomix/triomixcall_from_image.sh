#!/bin/bash
#SBATCH --time=2:00:00
#SBATCH --account=def-rallard
#SBATCH --output=J-%x.%j.out
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G

#Runs Triomix inside an apptainer image
#Arguments:
# $1: Proband BAM file
# $2: Mother BAM file
# $3: Father line (either "null" if family is duo or "--father <fatherBAM>")
# $4: Fasta reference path
# $5: Output directory
# $6: Apptainer image path
set -euo pipefail

module load apptainer/1.3.5
proband_bam=$(basename $1)
mother_bam=$(basename $2)
father_line=$3
fasta_path=$(basename $4)
directory=$5

here_folder=$(dirname $0)

image=$APPTAINER_CACHEDIR/triomix_v0.0.2.sif
if [ ! -f $image ];then
	echo "Downloading Triomix apptainer image"
	apptainer pull $image docker://cjyoon/triomix:v0.0.2
fi

cp $image $SLURM_TMPDIR

if [ ! -f $SLURM_TMPDIR/$proband_bam ]; then
	cp $1 $SLURM_TMPDIR
	
fi
cp $1.bai $SLURM_TMPDIR
if [ ! -f $SLURM_TMPDIR/$mother_bam ]; then
  cp $2 $SLURM_TMPDIR
  
fi
cp $2.bai $SLURM_TMPDIR
if [ ! -f $SLURM_TMPDIR/$fasta_path ]; then
  cp $4 $SLURM_TMPDIR
  cp $4.fai $SLURM_TMPDIR
fi


if [ "$father_line" != "null" ]; then
	father_bam=$(echo $father_line | cut -d' ' -f2)
	if [ ! -f $SLURM_TMPDIR/$(basename $father_bam) ]; then
		cp $father_bam $SLURM_TMPDIR
		
	fi
	cp $father_bam.bai $SLURM_TMPDIR
	father_line="--father $SLURM_TMPDIR/$(basename $father_bam)"
fi



# cat << EOF >$SLURM_TMPDIR/triomixScript.sh
mkdir -p $SLURM_TMPDIR/Triomix_analyses
echo "apptainer exec -C -W $SLURM_TMPDIR -B $SLURM_TMPDIR -B $HOME \
	$SLURM_TMPDIR/$(basename $image)"
apptainer exec -C -W $SLURM_TMPDIR -B $SLURM_TMPDIR -B $HOME \
	$SLURM_TMPDIR/$(basename $image) \
	python3 /tools/triomix/triomix.py \
	$father_line \
	--mother $SLURM_TMPDIR/$mother_bam \
	--child $SLURM_TMPDIR/$proband_bam \
	--reference $SLURM_TMPDIR/$fasta_path \
	--parent \
	--thread 8 \
	--snp "/tools/triomix/common_snp/grch38_common_snp.bed.gz" \
	--output_dir $SLURM_TMPDIR/Triomix_analyses

mkdir -p $directory/Triomix_analyses
cp -r $SLURM_TMPDIR/Triomix_analyses/* $directory/Triomix_analyses/