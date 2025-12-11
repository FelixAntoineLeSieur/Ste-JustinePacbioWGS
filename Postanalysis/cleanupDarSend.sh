#!/bin/bash
#
#SBATCH --time=3:00:00
#SBATCH --account=def-rallard
#SBATCH --cpus-per-task=1
#SBATCH --output=J-%x.%j.out
#SBATCH --mem=4G

#A cleanup script meant to be run after samples are sent to GeneYX
#Will send a folder from scratch to project directory on narval, check on the size and write to cleanupReport.txt
#Will then move the Haplotagged BAM files and methylation files to S3-Storage dir to send to S3 bucket

#Depends on ssh config in ~/.ssh/config:
# Host NarvalRobot
#         HostName robot.narval.alliancecan.ca
#         User felixant
#         identityfile ~/.ssh/firRobot
#         identitiesonly yes
#         StrictHostKeyChecking no
#         requesttty no

# Host NarvalInteractiveRobot
#         HostName robot.narval.alliancecan.ca
#         User felixant
#         identityfile ~/.ssh/FirInteractive
#         identitiesonly yes
#         StrictHostKeyChecking no
#         requesttty no

set -eu

echo "Starting cleanupDarSend.sh script"
exit

if [ -z "$1" ]
  then
    echo "No argument supplied, please provide the Family ID (pXXX) and destination 'narval' or 'rorqual'"
    exit
fi

touch cleanupReport.txt
trioName=$1
scratch="$HOME/scratch"

if [ -f $scratch/SampleSheet/$trioName.txt ]; then
	family_sampleSheet="$scratch/SampleSheet/$trioName.txt"
else
	echo "Could not find samplesheet '$trioName.txt' in $scratch/SampleSheet"
	exit
fi

#"Outputs.json" will be default on narval. We rename the current one to "Fir"
if [ ! -f $scratch/$trioName/outputsFir.json ]; then
	cp "$scratch/$trioName/_LAST/outputs.json" "$scratch/$trioName/_LAST/outputsFir.json"
fi

if [[ "$2" == "rorqual" ]]; then
	prefix="Rorqual"
	destination="$HOME/links/projects/rrg-rallard/shared/PacBioDataRorqual/OutputFamilies"
	S3Destination="$HOME/links/projects/rrg-rallard/shared/PacBioDataRorqual/S3-Storage/"
	cp "$scratch/$trioName/_LAST/outputsFir.json" "$scratch/$trioName/_LAST/outputsRorqual.json"
	outputsFile="$scratch/$trioName/_LAST/outputsRorqual.json"

elif [[ "$2" == "narval" ]]; then
	prefix="Narval"
	destination="$HOME/projects/ctb-rallard/COMMUN/PacBioData/OutputFamilies"
	S3Destination="$HOME/projects/ctb-rallard/COMMUN/PacBioData/S3-Storage/"
	#Narval nomenclature is default
	cp "$scratch/$trioName/_LAST/outputsFir.json" "$scratch/$trioName/_LAST/outputs.json"
	outputsFile="$scratch/$trioName/_LAST/outputs.json"

else
	echo "Please provide a valid destination, 'narval' or 'rorqual'"
	exit
fi

if [ ! -f $outputsFile ]; then
	echo "Could not find output file $outputsFile file in $scratch/$trioName/_LAST/"
	exit
fi

echo "Starting cleanup for  $trioName"

#The alignment step splits the bams, we don't need to save chunks. (the real aligned bam is in call-merge_hifi_bams/work/*GRCh38.bam)
rm -rf $scratch/$trioName/*/call-upstream-*/call-pbmm2-0/call-pbmm2_align_wgs-*
rm -rf $scratch/$trioName/*/call-upstream-*/call-pbmm2-0/call-split_input_bam/work*

rm -rf $scratch/$trioName/*/call-upstream-*/call-samtools_merge/work*

#We don't need to keep the merged bam with failed reads
rm -rf $scratch/$trioName/*/call-upstream-*/call-merge_hifi_fail_bams/work*
rm -rf $scratch/$trioName/*/call-upstream-*/call-bait_fail_reads-*/work*
rm -rf $scratch/$trioName/*/call-upstream-*/call-align_captured_fail_reads-*/work*

#The aligned bam is an intermediate we don't necessarily need
rm -rf $scratch/$trioName/*/call-upstream-*/call-merge_hifi_bams/work*

#The deepvariant model files take significant space and we no longer need them
rm -rf $scratch/$trioName/*/call-upstream-*/call-deepvariant/call-deepvariant_make_examples-*

#Set the correct paths in outputs.json to the new folder
sed -i.bak2 "s,/scratch/felixant,$destination,g" "$outputsFile"

echo "Cleaning Done. Send Create S3 directory to $S3Destination and symlinks to $destination?"

select yn in "yes" "no"; do
    case $yn in
	yes)
	    
		mkdir -p $scratch/S3-Storage/$trioName
		tail -n +2 $family_sampleSheet | while read p; do
			role=$(echo $p | cut -d: -f1)
			name=$(echo $p | cut -d, -f1 | cut -d: -f2)
			roleDestination=$scratch/S3-Storage/$trioName/$role
			mkdir -p "$roleDestination"
			newDest="$destination/$trioName"
			echo "$role/$name/$trioName,$newDest/" >>fullsampleSheet.csv
			old_path="$HOME/projects/ctb-rallard/COMMUN/PacBioData/OutputFamilies"
			new_path="../../../OutputFamilies"
			bamFile=$(grep -m 1 -A 3 "humanwgs_family.merged_haplotagged_bam" "$outputsFile" | grep "$name" | cut -d\" -f2)
			new_bamFile=${bamFile/$old_path/$new_path}
			bamIndexFile=$(grep -m 1 -A 3 "humanwgs_family.merged_haplotagged_bam_index" "$outputsFile" | grep "$name" | cut -d\" -f2)
			new_bamIndexFile=${bamIndexFile/$old_path/$new_path}
			methylFile=$(grep -m 1 -A 3 "humanwgs_family.cpg_combined_bed" "$outputsFile" | grep "$name" | cut -d\" -f2)
			new_methylFile=${methylFile/$old_path/$new_path}
			methIndexFile=$(grep -m 1 -A 3 "humanwgs_family.cpg_combined_bed_index" "$outputsFile" | grep "$name" | cut -d\" -f2)
			new_methIndexFile=${methIndexFile/$old_path/$new_path}
			methHap1=$(grep -m 1 -A 3 "humanwgs_family.cpg_hap1_bed" "$outputsFile" | grep "$name" | cut -d\" -f2)
			new_methHap1=${methHap1/$old_path/$new_path}
			methHap1Index=$(grep -m 1 -A 3 "humanwgs_family.cpg_hap1_bed_index" "$outputsFile" | grep "$name" | cut -d\" -f2)
			new_methHap1Index=${methHap1Index/$old_path/$new_path}
			methHap2=$(grep -m 1 -A 3 "humanwgs_family.cpg_hap2_bed" "$outputsFile" | grep "$name" | cut -d\" -f2)
			new_methHap2=${methHap2/$old_path/$new_path}
			methHap2Index=$(grep -m 1 -A 3 "humanwgs_family.cpg_hap2_bed_index" "$outputsFile" | grep "$name" | cut -d\" -f2)
			new_methHap2Index=${methHap2Index/$old_path/$new_path}
			echo "Bamfile: $bamFile"
			echo "Basepath: ${bamFile##*/}"
			echo "S3Destination: $roleDestination"
			ln -sf "$new_bamFile" "$roleDestination/${name}.haplotagged.bam"
			ln -sf "$new_bamIndexFile" "$roleDestination/${name}.haplotagged.bam.bai"
			ln -sf "$new_methylFile" "$roleDestination/${name}.GRCh38.cpg_pileup.combined.bed.gz"
			ln -sf "$new_methIndexFile" "$roleDestination/${name}.GRCh38.cpg_pileup.combined.bed.gz.tbi"
			ln -sf "$new_methHap1" "$roleDestination/${name}.GRCh38.cpg_pileup.hap1.bed.gz"
			ln -sf "$new_methHap1Index" "$roleDestination/${name}.GRCh38.cpg_pileup.hap1.bed.gz.tbi"
			ln -sf "$new_methHap2" "$roleDestination/${name}.GRCh38.cpg_pileup.hap2.bed.gz"
			ln -sf "$new_methHap2Index" "$roleDestination/${name}.GRCh38.cpg_pileup.hap2.bed.gz.tbi"

		done
		echo "Sending S3-Storage to $S3Destination"
		echo "Rsync command:"
		echo "rsync -rlv $scratch/S3-Storage/$trioName "${prefix}InteractiveRobot:$S3Destination""
		rsync -rlv $scratch/S3-Storage/$trioName "${prefix}InteractiveRobot:$S3Destination"
		find "$scratch/$trioName" -type l -printf '%P\n' | \
  			rsync -rlvP --files-from=- "$scratch/$trioName" "NarvalInteractiveRobot:$destination/$trioName"
		echo "Rsync Complete"
		break
	    ;;
	no)
	    break
	    ;;
	*)
	    echo "please select 1 or 2"
	    ;;
    esac
done

echo "Check size of $scratch/$trioName ?"
select yn in "yes" "no"; do
    case $yn in
	yes)
		du -h $scratch/$trioName | grep -e "[0-9]G"
	    break
	    ;;
	no)
	    break
	    ;;
	*)
	    echo "please select 1 or 2"
	    ;;
    esac
done

cat $scratch/SampleSheet/$trioName.txt
tail -n +2 $scratch/SampleSheet/$trioName.txt | while read line || [[ -n $line ]]; do
	bamFile=$(echo $line | cut -d, -f2 )
	bamDirectory=$(dirname $(dirname $bamFile))
	echo "Remove directory $bamDirectory ?"
	select yn in "yes" "no"; do
		case $yn in
			yes)
				rm -rv "$bamDirectory"			
				break
			;;
			no)
				break
				;;
			*)
				echo "please select 1 or 2"
				;;
		esac
	done </dev/tty # needed to read input inside a loop
done


echo "Send full directory to $prefix$destination ?"

select yn in "yes" "no"; do
    case $yn in
	yes)
		mkdir -p "$scratch/Tars/$trioName"
		sbatch -J "$trioName TarSendUntar" -D "$scratch/Tars/$trioName" \
			$scratch/Scripts/tarSendUntar.sh \
			"$trioName" \
			"$destination" \
			"${prefix}Robot"
	    break
	    ;;
	no)
	    break
	    ;;
	*)
	    echo "please select 1 or 2"
	    ;;
    esac
done