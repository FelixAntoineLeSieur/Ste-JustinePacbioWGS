#!/bin/bash
#SBATCH --time=5:00:00
#SBATCH --account=def-rallard
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --output=J-%x.%j.out
#SBATCH --mem=8G

#Runs SVTOPO and svtopovz inside an apptainer image
#Arguments:
# $1: Prefix for output files
# $2: Haplotagged BAM file
# $3: BAM index file
# $4: Supporting reads JSON file
# $5: VCF file with structural variants
# $6: Output directory
# $7: Resource folder (with gff3 and excluded regions bed)
# $8: Script folder (to have access to the Tools folder even in sbatch)

set -eu
module load apptainer/1.3.5
projects=$HOME/projects


echo "Arguments:"
for var in "$@"; do
 echo $var
done
prefix=${1%%_*} #Prefix cannot contain underscores
cp "$2" "$SLURM_TMPDIR/$(basename $2)" #Haplotag Bam
bam="$(basename $2)"
cp "$3" "$SLURM_TMPDIR/$(basename $3)" #Bam Index
cp "$4" "$SLURM_TMPDIR/$(basename $4)" #Supporting reads
supporting_reads="$(basename $4)"
cp "$5" "$SLURM_TMPDIR/$(basename $5)" #VCF
vcf="$(basename $5)"
outputDir=$6
resource_folder=$7
# We manually pass the script folder because on Fir $0 is in SLURMTMPDIR when launched from sbatch
here_folder=$8 

# #This is a home-made image, not hosted on dockerhub for now
image=$APPTAINER_CACHEDIR/svtopo_v0.3.0.sif
if [ ! -f $image ]; then
  echo "Building SVTopo apptainer image"
  apptainer build $image $here_folder/../Tools/SVTopo/svtopo.def
fi

cp $resource_folder/GRCh38/ensembl.GRCh38.101.reformatted.gff3.gz "$SLURM_TMPDIR"
cp $here_folder/../Tools/SVTopo/repeatmaskerUCSC.bed.gz "$SLURM_TMPDIR"
cp $resource_folder/cnv.excluded_regions.hg38.bed.gz "$SLURM_TMPDIR"
cp $image $SLURM_TMPDIR
#As suggested in https://github.com/PacificBiosciences/SVTopo/blob/main/docs/user_guide.md for annotation
zgrep -iE "L1|L2|LINE|SVA" $SLURM_TMPDIR/repeatmaskerUCSC.bed.gz \
    | awk '($3 - $2) >= 2000 { print $1, $2, $3, $4, $6 }' > $SLURM_TMPDIR/retrotransposons.bed

#Temporary script to run inside apptainer
cat << EOF > $SLURM_TMPDIR/svtopo_apptainer_script.sh
#!/bin/bash
set -eu

mkdir -p "SVTOPO_OUTPUTS/${prefix}_svtopo"

svtopo \
  --bam "$bam" \
  --variant-readnames "$supporting_reads" \
  --vcf "$vcf" \
  --svtopo-dir "SVTOPO_OUTPUTS/${prefix}_svtopo" \
  --exclude-regions "/app/SVTopo/cnv.excluded_regions.hg38.bed.gz"\
  --prefix "${prefix}"

svtopovz \
  --svtopo-dir "SVTOPO_OUTPUTS/${prefix}_svtopo" \
  --genes "ensembl.GRCh38.101.reformatted.gff3.gz" \
  --annotation-bed "repeatmaskerUCSC.bed.gz" "retrotransposons.bed" \
  --verbose
EOF
chmod +x $SLURM_TMPDIR/svtopo_apptainer_script.sh

mkdir -p $SLURM_TMPDIR/SVTOPO_OUTPUTS
apptainer exec -C -W $SLURM_TMPDIR -B $HOME -B $SLURM_TMPDIR \
  --pwd $SLURM_TMPDIR $SLURM_TMPDIR/$(basename $image) /bin/bash \
  $SLURM_TMPDIR/svtopo_apptainer_script.sh

mkdir -p "$outputDir/SVTOPO_OUTPUTS/${prefix}_svtopo"
cp -rv $SLURM_TMPDIR/SVTOPO_OUTPUTS/${prefix}_svtopo $outputDir/SVTOPO_OUTPUTS