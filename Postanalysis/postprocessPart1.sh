#!/bin/bash
#
set -eo pipefail

#This version is meant to accelerate the interactive processes by asking the questions first
#Steps can be skipped if prompted at the start
#If any step fails the script will exit, then you can retry and skip the succeeded steps

#Upload files to geneyx according to their API for trios. 
#Provide the trio name as input. 
#First, it will use geneYX's script "PacBioUnifyVCF.py" with the 3 necessary vcfs
#Then, we build a JSON file with the paths to the correct files and use geneYX's "JSON_Sample_upload.py" to send the files over.
#Finally, we send "Cases" to start the analysis for the new files
#Postprocessing is done last, which includes :
#PEDDY report, 
#multiqc report,
#44SNP comparison with short reads (if desired, currently non-functionnal outside Narval)
#Cleanup and storage to /projects/share/PacBioDataRorqual/OutputFamilies

module load python/3.11 htslib/1.22.1 bcftools/1.22 bedtools/2.31.0 apptainer/1.3.5 arrow/21.0.0 libyaml

usage() { 
	printf "Usage: \n $0 [-i <familyID>]  [-g <group (i.e. Pragmatiq, decodeur)>] \n
 [-s {to run every step, otherwise will enter interactive mode}] \n
 [-c <Optional_config_file>] \n" 
 1>&2; exit 1; }

run_all=false
while getopts "i:c:g:s" o; do
	case "${o}" in
		i)
			id=${OPTARG}
			echo "Family ID set to: $id"
			;;
		c)
			config_file=${OPTARG}
			;;
		g)
			group=${OPTARG}
			if [ "$group" == "Pragmatiq" ] || [ "$group" == "prag" ] ; then
				echo "Using Pragmatiq group, if decodeur specify second argument 'd'"
				group_name="Pragmatiq"
				group_code="prag"
			elif [ "$group" == "Decodeur" ] || [ "$group" == "decode" ]; then
				echo "Using Decodeur group, if pragmatiq specify second argument 'p'"
				group_name="Decodeur"
				group_code="decode"
			else 
				echo "Use either 'Pragmatiq' or 'Decodeur' for group name or their code 'prag' or 'decode'"
				exit
			fi
			;;
		s)
			run_all=true
			;;
		:)
			echo "Error: -${OPTARG} requires an argument."
			exit 1
			;;
		*)
			usage
			;;
	esac
done


here_folder=$(realpath "$(dirname $0)")
if [ -z "$1" ]; then
	usage
fi

if [ -z "${id}" ] || [ -z "${group}" ]; then
	usage
fi
if [ -z "${config_file:-}" ]; then
	echo "No config file provided, using default location $here_folder/../.myconf.json"
	config_file="$here_folder/../.myconf.json"
elif [ ! -f "${config_file}" ]; then
	echo "Config file not found!"
	usage
fi

#samplesheet=$(python3 -c "import json; print(json.load(open('${config_file}'))['Paths']['sample_sheet_path'])")/${id}.json
samplesheet=$(jq -r '.Paths.sample_sheet_path' ${config_file})/${id}.json




#------Functions------#
#This function loads the environment for GeneYX scripts
function loadEnv(){
	ENVDIR=$here_folder/../Tools/$1
	if [ -d "$ENVDIR" ]; then
		source $ENVDIR/bin/activate
	else
		virtualenv --no-download $ENVDIR
		source $ENVDIR/bin/activate
		pip install --no-index --upgrade pip
		if [ "$1" == "GeneYX_env" ]; then
			echo "Loading GeneYX environment"
			pip install -r $here_folder/../Tools/requirementsGeneYXUpload.txt
		elif [ "$1" == "Globus_env" ]; then
			echo "Loading Globus environment"
			pip install -r $here_folder/../Tools/requirementsGlobus.txt
		fi
	fi
}

function ask_yes_no() {
	local question="$1"
	local var_name="$2"
	local result
	echo "$question"
	select yn in "yes" "no"; do
		case $yn in
		yes)
			result=true; break ;;
		no)
			result=false; break ;;
		*)
			echo "please select 1 or 2" ;;
		esac
	done
	printf -v "$var_name" '%s' "$result"
}

#Left-align and normalize SNV VCF for GeneYX
function Normalize() {
	local norm_output="$directory/$1.$family_id.normed.joint.GRCh38.small_variants.phased.vcf.gz"
	if [[ ! -f "$norm_output" ]]; then
		bcftools norm -m-any --check-ref -w -f "$fasta_path" -Oz -o "$norm_output" "$2"
	fi
	if [ ! -f "$norm_output.tbi" ]; then
		tabix -p vcf "$norm_output"
	fi
	echo "$norm_output"
}

#Unifies the 4 differemt VCFs must be done for all samples in group
function UnifyVCF() {
if [ ! -f "$directory/$1-unifiedTrioVCFv2.vcf.gz" ]; then
	python3 $here_folder/geneyx.analysis.api_CHUSJ/scripts/UnifyVcf/PacBioUnifyVcf.py -o "$directory/$1-unifiedTrioVCFv2.vcf" -s "$3" -r "$2" -b $here_folder/geneyx.analysis.api_CHUSJ/scripts/UnifyVcf/STRchive-disease-loci.hg38.TRGT.bed
fi

ls "$directory/$1-unifiedTrioVCFv2.vcf.gz"
}

#Heredoc to build the samplefiles

function buildSamplefiles() {
	cat << EOF >>$directory/modifiedGeneYXTrio$family_id.json
	{
		"snvVcf": "$3",
		"svVcf": "$2",
		"genomeBuild": "hg38",
		"patientId": "$1",
		"SampleTarget": "WholeGenomeLR",
		"sampleQcData": "QCData/${family_id}_${1}_QC_new.json",
		"patientGender": "$4",
		"ExcludeFromLAF": "$5",
		"groupAssignmentName": "$group_name",
		"groupAssignmentCode": "$group_code"
	},
EOF
}
#Put the extracted API-ID and pass in the geneyx Config
function geneYXConfig() {
	if [ ! -f $here_folder/../.myGeneYXConf.yml ]; then
		api_ID=$(python3 -c "import json; print(json.load(open('${config_file}'))['GeneYX']['apiUserId'])")
		api_key=$(python3 -c "import json; print(json.load(open('${config_file}'))['GeneYX']['apiUserKey'])")
		sed -e "s,enter-your-userid,$api_ID,g" $here_folder/geneyx.analysis.api_CHUSJ/scripts/ga.config.yml >$here_folder/../.myGeneYXConf.yml
		sed -ie "s,enter-your-userkey,$api_key,g" $here_folder/../.myGeneYXConf.yml

	fi
	ls "$here_folder/../.myGeneYXConf.yml"
}

#Give the dependency list and the function will print a line to be used in sbatch
function dependencyLine() {
	local dependencies=("$@")
	if [ ${#dependencies[@]} -eq 0 ]; then
		local dependencyCallLine=""
	else
		local dependencyCallLine="-d afterok:"
		IFS=":" dependencyCallLine+="${dependencies[*]}"
	fi
	echo "$dependencyCallLine"
}

# Function to pull images before script runs
# I would normally put this in each respective script,but some clusters don't have internet on job nodes
# $1 is imagename $2 is dockerhub
function apptainerGet() {
	if [ -z $APPTAINER_CACHEDIR ]; then
		echo """Warning: You should set an explicit directory for APPTAINER_CACHEDIR in ~/.bashrc IE:
		export APPTAINER_TMPDIR="~/scratch/singularity_cache/tmp"
		export APPTAINER_CACHEDIR="/home/felixant/scratch/singularity_cache"
	"""
		echo "Using script folder for now"
		export APPTAINER_CACHEDIR="$here_folder/apptainer_cache"
		mkdir -p $APPTAINER_CACHEDIR
	fi
	if [ ! -f "$APPTAINER_CACHEDIR/$1" ]; then
		# We have some home-made images that we saved as .def
		if [[ "$2" != *".def"* ]]; then
			apptainer pull $APPTAINER_CACHEDIR/$1 $2
		else
			apptainer build $APPTAINER_CACHEDIR/$1 $2
		fi
	fi
}

#Gathers QC data for all samples
function buildQCData() {
	stat_file="$directory/_LAST/out/stats_file/$family_id.stats.txt"
	upstream_folder=$(cd "$directory"/_LAST/call-upstream-"$2"-* ; pwd)
	bam_reads=$(grep "$1" "$stat_file" | cut -f2)
	map_reads=$(grep "$1" "$stat_file" | cut -f8)
	mean_cov=$(grep "$1" "$stat_file" | cut -f12)
	index=$( expr "$2" + 1 )
	bam_file=$(grep 'hifi_reads.bc' "$samplesheet" | sed "${index}q;d" | cut -d'"' -f2)
	bam_directory=$(dirname $(dirname $bam_file)) #/.../1_X01
	failed_reads=$(grep -w '<Q20 Reads' /"$bam_directory"/statistics/m*.ccs_report.txt | cut -d: -f2 | cut -d' ' -f2 | sed "s/,//g")
	num_snp=$(grep "$1" "$stat_file" | cut -f22)
	ratio_hethom=$(grep "$1" "$stat_file" | cut -f24)
	num_het=$(grep -w '^PSC' "$directory/_LAST/out/small_variant_stats/$2/$1.GRCh38.small_variants.vcf.stats.txt" | cut -f6)
	num_hom=$(grep -w '^PSC' "$directory/_LAST/out/small_variant_stats/$2/$1.GRCh38.small_variants.vcf.stats.txt" | cut -f5)
	total_var=$(tail -n 1 "$directory/_LAST/out/phase_stats/$2/$1.GRCh38.hiphase.stats.tsv" | cut -d$'\t' -f3)
	snv_VCF="$upstream_folder/out/small_variant_vcf/$1.GRCh38.small_variants.vcf.gz"
	snv_index="$upstream_folder/out/small_variant_vcf_index/$1.GRCh38.small_variants.vcf.gz.tbi"
	snpY=$(bcftools view -H -r chrY -f PASS "$snv_VCF##idx##$snv_index" | wc -l)
	snpX=$(bcftools view -H -r chrX -f PASS "$snv_VCF##idx##$snv_index" | wc -l)
	ratio_xy=$(echo "scale=2;$snpX/$snpY" | bc | sed "s/^\./0\./g")

	index2=($(($index+1)))
	mosdepth_dir=$(dirname $(readlink -f $(grep -m 1 -A 3 "humanwgs_family.mosdepth_region_bed" $output_file | sed "${index2}q;d" | cut -d'"' -f2)))
	if [ -f "$mosdepth_dir/thresholdsTable.tsv" ]; then	
		ratio5X=$(tail -n 1 "$mosdepth_dir/thresholdsTable.tsv" | cut -f1)
		per5X=$(echo "scale=2;$ratio5X*100" | bc | sed "s/^\./0\./g")
		message5X="\"Percent5x\": $per5X,"$'\n'$'\t'
		ratio20X=$(tail -n 1 "$mosdepth_dir/thresholdsTable.tsv" | cut -f2)
		per20X=$(echo "scale=2;$ratio20X*100" | bc | sed "s/^\./0\./g")
		message20X="\"Percent20x\": $per20X,"$'\n'$'\t'
		ratio50X=$(tail -n 1 "$mosdepth_dir/thresholdsTable.tsv" | cut -f3)
		per50X=$(echo "scale=2;$ratio50X*100" | bc | sed "s/^\./0\./g")
		message50X="\"Percent50x\": $per50X,"$'\n'$'\t'
	else
		message5X=""
		message20X=""
		message50X=""
	fi

	#QC data
	mkdir -p $SCRATCH/QCData
	>$SCRATCH/QCData/${family_id}_${1}_QC_new.json
	cat << EOF >>"$SCRATCH/QCData/${family_id}_${1}_QC_new.json"
	{
		"sampleSn": "$1",
		"PassedReadsNum": $bam_reads,
		"FailedReadsNum": $failed_reads,
		"MappedReadsNum": $map_reads,
		"MeanCoverage": $mean_cov,
		$message5X$message20X$message50X"ChrXSnpsCount": $snpX,
		"TotalVariants": $total_var,
		"SnpCount": $num_snp,
		"TotalHeteroCount": $num_het,
		"TotalHomoCount": $num_hom,
		"HetHomRatio": $ratio_hethom,
		"ChrYSnpsCount": $snpY,
		"XySnpsRatio": $ratio_xy
	}

EOF
ls "$SCRATCH/QCData/${family_id}_${1}_QC_new.json"
}

#Generate Plink Ped file if not present
function getPed(){
	if [ ! -f "$directory/${family_id}.ped" ]; then
		echo "Generating .ped Pedigree with Postanalysis/getPed.py"
		python3 "$here_folder/getPed.py" "$family_id" "$samplesheet"
		if [ ! -f "$directory/$family_id.ped" ]; then
			cp "${family_id}.ped" "$directory/" 
		fi
	fi
	if [ ! -f "$directory/${family_id}.ped" ]; then 
		echo "Could not generate PED file" ; exit 1 ; fi
}


#-----Start of Main script------#
family_id=$id

#fasta_path="$SCRATCH/hifi-wdl-resources-v3.1.0/GRCh38/human_GRCh38_no_alt_analysis_set.fasta"
resource_file=$(python3 -c "import json; print(json.load(open('${config_file}'))['Paths']['ref_maps'])")
resource_folder=$(dirname "$resource_file")
tertiary_map=$(python3 -c "import json; print(json.load(open('${config_file}'))['Paths']['tertiary_maps'])")
fasta_path=$(grep -wm 1 'fasta' "${resource_file}" | cut -f2)
if [ ! -f "$fasta_path" ]; then
	echo "Could not find fasta at $fasta_path"
	exit 1
fi

if [[ -d "$SCRATCH/$family_id" ]]; then
	echo "Directory found at $SCRATCH/$family_id"
	directory="$SCRATCH/$family_id"
else
	echo "Directory not found for $family_id"
	exit
fi
if [ -f "$directory/_LAST/outputs.json" ]; then
	output_file="$directory/_LAST/outputs.json"
else
	echo "Could not find outputs.json file in $directory/_LAST/"
	exit
fi


#Get the haplotagged bams for each sample
for sample in $directory/_LAST/out/merged_haplotagged_bam/*/;do
	sample_dir=$(basename "$sample")	
	if [[ "$sample_dir" == "0" ]]; then
		proband_bam=$(ls "$directory/_LAST/out/merged_haplotagged_bam/$sample_dir/"*GRCh38.haplotagged.bam)
		ln -sf "../../merged_haplotagged_bam_index/0/$(basename "$proband_bam").bai" "$(dirname "$proband_bam")/$(basename "$proband_bam").bai"
		proband_bam_bai=$proband_bam.bai

	elif [[ "$sample_dir" == "1" ]]; then
		mother_bam=$(ls "$directory/_LAST/out/merged_haplotagged_bam/$sample_dir/"*GRCh38.haplotagged.bam)
		ln -sf "../../merged_haplotagged_bam_index/1/$(basename "$mother_bam").bai" "$(dirname "$mother_bam")/$(basename "$mother_bam").bai"
		#mother_bam_bai=$(ls "$directory/_LAST/out/merged_haplotagged_bam_index/$sample_dir/"*GRCh38.haplotagged.bam.bai)
		mother_bam_bai=$mother_bam.bai
	elif [[ "$sample_dir" == "2" ]]; then
		father_bam=$(ls "$directory/_LAST/out/merged_haplotagged_bam/$sample_dir/"*GRCh38.haplotagged.bam)
		ln -sf "../../merged_haplotagged_bam_index/2/$(basename "$father_bam").bai" "$(dirname "$father_bam")/$(basename "$father_bam").bai"
		#father_bam_bai=$(ls "$directory/_LAST/out/merged_haplotagged_bam_index/$sample_dir/"*GRCh38.haplotagged.bam.bai)
		father_bam_bai=$father_bam.bai
	else
		echo "Role unknown at $sample : $sample_dir"
		exit
	fi 
done

if [ -z "$father_bam" ]; then
	mode="duo"
else
	mode="trio"
fi
echo "Mode set to: $mode"


proband_name=$(cat "$samplesheet" | grep  '"sample_id": ' | cut -d'"' -f4 | head -n 1)
mother_name=$(cat "$samplesheet" | grep  '"sample_id": ' | cut -d'"' -f4 | sed '2q;d')
if [ "$mode" == "duo" ]; then father_name="null"
else father_name=$(cat "$samplesheet" | grep  '"sample_id": ' | cut -d'"' -f4 | sed '3q;d')
fi
echo Family ID: $family_id
proband_small_variant=$(ls "$directory/_LAST/out/phased_small_variant_vcf/0/$proband_name.$family_id.joint.GRCh38.small_variants.phased.vcf.gz")
proband_TRGT=$(ls "$directory"/_LAST/out/phased_trgt_vcf/0/$proband_name.GRCh38.trgt.sorted.phased.vcf.gz)
proband_SV=$(ls "$directory"/_LAST/out/phased_sv_vcf/0/$proband_name.$family_id.joint.GRCh38.structural_variants.phased.vcf.gz)
mother_small_variant=$(ls "$directory/_LAST/out/phased_small_variant_vcf/1/$mother_name.$family_id.joint.GRCh38.small_variants.phased.vcf.gz")
mother_TRGT=$(ls "$directory"/_LAST/out/phased_trgt_vcf/1/$mother_name.GRCh38.trgt.sorted.phased.vcf.gz)
mother_SV=$(ls "$directory"/_LAST/out/phased_sv_vcf/1/$mother_name.$family_id.joint.GRCh38.structural_variants.phased.vcf.gz)

if [ "$mode" == "duo" ]; then
	father_small_variant="null"
	father_TRGT="null"
	father_SV="null"
else
	father_small_variant=$(ls "$directory/_LAST/out/phased_small_variant_vcf/2/$father_name.$family_id.joint.GRCh38.small_variants.phased.vcf.gz")
	father_TRGT=$(ls "$directory"/_LAST/out/phased_trgt_vcf/2/$father_name.GRCh38.trgt.sorted.phased.vcf.gz)
	father_SV=$(ls "$directory"/_LAST/out/phased_sv_vcf/2/$father_name.$family_id.joint.GRCh38.structural_variants.phased.vcf.gz)
fi

#We normalize the small variant vcfs before sending them to GeneYX
echo "Normalizing variants"
proband_normalized_SNV=$(Normalize "$proband_name" "$proband_small_variant")
mother_normalized_SNV=$(Normalize "$mother_name" "$mother_small_variant")
if [ "$mode" == "duo" ]; then father_normalized_SNV="null"
else father_normalized_SNV=$(Normalize "$father_name" "$father_small_variant")
fi

#Unify the 4 different VCFs into one for each sample
echo "Unifying variants"
proband_unified_vcf=$(UnifyVCF "$proband_name" "$proband_TRGT" "$proband_SV")
mother_unified_vcf=$(UnifyVCF "$mother_name" "$mother_TRGT" "$mother_SV")
if [ "$mode" == "duo" ]; then father_unified_vcf="null"
else father_unified_vcf=$(UnifyVCF "$father_name" "$father_TRGT" "$father_SV")
fi

#Gender
real_gender=$(grep -m1 '"sex": ' "$samplesheet" | cut -d'"' -f4)
#mosdepthfile=$(grep 'hifi_reads.bc' "$samplesheet" | sed "${index}q;d" | cut -d'"' -f2)
inferred_gender=$(grep -A 3 humanwgs_family.inferred_sex $output_file | sed "2q;d" | cut -d\" -f2)
mother_inferred_gender=$(grep -A 3 humanwgs_family.inferred_sex $output_file | sed "3q;d" | cut -d\" -f2)
father_inferred_gender=$(grep -A 3 humanwgs_family.inferred_sex $output_file | sed "4q;d" | cut -d\" -f2)
genderError=false
if [ "$mother_inferred_gender" != "FEMALE" ]; then
	echo "Warning: Mother's inferred gender is not female: $mother_inferred_gender"
	genderError=true
fi

if [ "$father_inferred_gender" != "MALE" ]; then
	echo "Warning: Father's inferred gender is not male: $father_inferred_gender"
	genderError=true
fi

if [ "$real_gender" = "null" ] && [ "$inferred_gender" = "null" ];then
	echo "Warning: gender is set to 'null'"
	final_gender=""
else
	if [ "$real_gender" = "$inferred_gender" ];then
		echo "Proband Gender confirmed to be $real_gender"
		final_gender=$(echo $real_gender | cut -c1-1)
	elif [ "$real_gender" = "null" ];then
		echo "Using inferred gender: $inferred_gender"
		final_gender=$(echo "$inferred_gender" | cut -c1-1)
	elif [ "$inferred_gender" = "null" ];then
		echo "Using given gender: $real_gender"
		final_gender=$(echo "$real_gender" | cut -c1-1)
	else
		echo "Warning: Given gender ($real_gender) does not fit inferred gender ($inferred_gender)."
		final_gender=$(echo "$real_gender" | cut -c1-1)
		genderError=true
	fi
fi

if [ "$genderError" == "true" ]; then exit
fi


#-----Steps-----#

if [ $run_all == true ]; then
	echo "Running all steps without prompt"
else
	echo "Interactive mode enabled, will prompt for each step"
	ask_yes_no "Send to GeneYX?" send_to_geneyx
	ask_yes_no "Send Case to GeneYX?" send_case_to_geneyx
	ask_yes_no "Send QC info to GeneYX?" send_qc_to_geneyx
	ask_yes_no "Include SVTopo?" include_svtopo
	ask_yes_no "Include TrioMix?" include_triomix
	ask_yes_no "Include Somalier?" include_somalier
	ask_yes_no "Include PEDDY?" include_peddy
	ask_yes_no "Include MultiQC?" include_multiqc
	ask_yes_no "Include cleanup and send?" include_cleanup

fi

#Send to GeneYX step
if [ "$send_to_geneyx" == true ] || [ "$run_all" == true ]; then
	loadEnv "GeneYX_env"
	my_config=$(geneYXConfig)
	#Building the JSON file for GeneYX upload
	printf "{\n\t\"samples\": [\n\t" >$directory/modifiedGeneYXTrio$family_id.json

	#Heredocs for iterative file building
	buildSamplefiles "$proband_name" "$(basename "$proband_unified_vcf")" "$(basename "$proband_normalized_SNV")" "$final_gender" "True"
	buildSamplefiles "$mother_name" "$(basename "$mother_unified_vcf")" "$(basename "$mother_normalized_SNV")" "F" "False"
	if [ "$mode" == "duo" ]; then echo "Skipping father, duo mode"
	else buildSamplefiles "$father_name" "$(basename "$father_unified_vcf")" "$(basename "$father_normalized_SNV")" "M" "False"
	fi
	echo "done building samplesheets"
	#Remove comma from last line
	ed -s $directory/modifiedGeneYXTrio$family_id.json <<< '$-'$((n-1))$',$s/},/}/g\nwq'
	printf "\t]\n}" >>$directory/modifiedGeneYXTrio$family_id.json
	cat $directory/modifiedGeneYXTrio$family_id.json
	cd $directory
	python3 $here_folder/geneyx.analysis.api_CHUSJ/scripts/JSON_Sample_Upload.py --jsonFile $directory/modifiedGeneYXTrio$family_id.json -c $my_config
fi

#Send Case to GeneYX step
if [ "$send_case_to_geneyx" == true ] || [ "$run_all" == true ]; then
	loadEnv "GeneYX_env"
	my_config=$(geneYXConfig)
	hpoTerms=$(cat "$samplesheet" | grep 'phenotypes": ' | cut -d'"' -f4)
	if [ "$mode" == "duo" ]; then
		fatherDesc=""
		fatherString=""
	else
		fatherDesc="and Father: $father_name"
		fatherString=",
				{
				\"Relation\": \"Father\",
				\"SampleId\": \"$father_name\",
				\"Affected\": \"Unaffected\"
				}"
	fi
	echo "building Case upload file"
	>$directory/modifiedTrioCaseUpload$family_id.json
	cat << EOF >>$directory/modifiedTrioCaseUpload$family_id.json
	{
		"ProtocolId": "LR_Trio",
		"Name": "${proband_name}_${mode}_${family_id}",
		"Description": "$mode analysis for FamilyID: $family_id, composed of proband: $proband_name, mother: $mother_name $fatherDesc",
		"SubjectId": "$proband_name",
		"Phenotypes": "$hpoTerms",
		"ProbandSampleId": "$proband_name",
		"AssociatedSamples": [ 
			{
			"Relation": "Mother",
			"SampleId": "$mother_name",
			"Affected": "Unaffected"
			}$fatherString
		]
	}
EOF
	cat $directory/modifiedTrioCaseUpload$family_id.json
	cd  $directory
	python3 $here_folder/geneyx.analysis.api_CHUSJ/scripts/ga_CreateCase.py --data $directory/modifiedTrioCaseUpload$family_id.json -c $my_config

fi

#Send QC Data to GeneYX step
if [ "$send_qc_to_geneyx" == true ] || [ "$run_all" == true ]; then
	loadEnv "GeneYX_env"
	my_config=$(geneYXConfig)
	#Building the JSON file for GeneYX upload
	echo "Retrieving QC data for proband..."
	probandQCData=$(buildQCData "$proband_name" "0" "$(basename $proband_normalized_SNV)")
	echo "Retrieving QC data for mother..."
	motherQCData=$(buildQCData "$mother_name" "1" "$(basename $mother_normalized_SNV)")
	cat "$probandQCData"
	cat "$motherQCData"
	python3 $here_folder/geneyx.analysis.api_CHUSJ/scripts/ga_addQcData.py -d "$probandQCData" -c $my_config
	python3 $here_folder/geneyx.analysis.api_CHUSJ/scripts/ga_addQcData.py -d "$motherQCData" -c $my_config
	if [[ $mode == "duo" ]]; then
		echo "Skipping father, duo mode"
	else
		echo "Retrieving QC data for father..."
		fatherQCData=$(buildQCData "$father_name" "2" "$(basename $father_normalized_SNV)")
		cat "$fatherQCData"
		python3 $here_folder/geneyx.analysis.api_CHUSJ/scripts/ga_addQcData.py -d "$fatherQCData" -c $my_config
	fi
fi

#Initializes a list of dependencies as slurm-id of sbatch jobs
#This will make sure that steps are run in order
dependencies=()
echo "Launch step time"
#SVTopo step
if [ "$include_svtopo" == true ] || [ "$run_all" == true ]; then
	cp $here_folder/../Tools/SVTopo/svtopo_requirements.txt $APPTAINER_CACHEDIR/
	apptainerGet "svtopo_v0.3.0.sif" $here_folder/../Tools/SVTopo/svtopo.def
	supporting_reads="$directory/_LAST/out/sv_supporting_reads/${family_id}.joint.GRCh38.structural_variants.supporting_reads.json.gz"
	
	echo "Launching SVTopo with Scripts/svtopocall_from_image.sh"
	dependencies+=("$(sbatch --parsable -J svtopo_${family_id}_proband -D $directory/SVTOPO_OUTPUTS $here_folder/../Tools/SVTopo/svtopocall_from_image.sh -p "$family_id-proband-${proband_name}" -b "$proband_bam" -i "$proband_bam_bai" -s "$supporting_reads" -v "$proband_SV" -r "$resource_folder" -o $directory -h $here_folder)")
	dependencies+=("$(sbatch --parsable -J svtopo_${family_id}_mother -D $directory/SVTOPO_OUTPUTS $here_folder/../Tools/SVTopo/svtopocall_from_image.sh -p "$family_id-mother-${mother_name}" -b "$mother_bam" -i "$mother_bam_bai" -s "$supporting_reads" -v "$mother_SV" -r "$resource_folder" -o $directory -h $here_folder)")
	if [ "$mode" == "trio" ]; then
		dependencies+=("$(sbatch --parsable -J svtopo_${family_id}_father -D $directory/SVTOPO_OUTPUTS $here_folder/../Tools/SVTopo/svtopocall_from_image.sh -p "$family_id-father-${father_name}" -b "$father_bam" -i "$father_bam_bai" -s "$supporting_reads" -v "$father_SV" -r "$resource_folder" -o $directory -h $here_folder)")
	fi
fi

#Triomix step
if [ "$include_triomix" == true ] || [ "$run_all" == true ]; then
	apptainerGet "triomix_v0.0.2.sif" "docker://cjyoon/triomix:v0.0.2"
	cd "$directory"
	echo "Launching Triomix"
	mkdir -p Triomix_analyses
	# father_line="null"
	# if [ "$mode" == "trio" ]; then father_line="--father $father_bam" ; fi
	dependencies+=("$(sbatch --parsable -J triomix_${family_id} -D $directory/Triomix_analyses $here_folder/../Tools/Triomix/triomixcall_from_image.sh -p "$proband_bam" -m "$mother_bam" -f "$father_bam" -r "$fasta_path" -o "$directory")")
fi

#Somalier step
if  [ "$run_all" == true ] || [ "$include_somalier" == true ]; then
	apptainerGet somalier-v0.3.1.sif docker://brentp/somalier:v0.3.1

	#Some extra prerequisites for Ancestry
	if [ ! -f "$APPTAINER_CACHEDIR/1kg.somalier.tar.gz" ]; then
		echo "Downloading 1-kg somalier data"
		wget https://zenodo.org/record/3479773/files/1kg.somalier.tar.gz -O "$APPTAINER_CACHEDIR/1kg.somalier.tar.gz"
	fi
	if [ ! -d "$APPTAINER_CACHEDIR/1kg-somalier" ]; then
		tar -xzf "$APPTAINER_CACHEDIR/1kg.somalier.tar.gz" -C "$APPTAINER_CACHEDIR/"
	fi
	
	getPed
	cd "$directory"
	echo "Launching Somalier"
	echo "bash $here_folder/../Tools/Somalier/somaliercall_from_image.sh -p "$proband_name" -m "$mother_name" -f "$father_name" -r $fasta_path -i $family_id -d "$directory""
	dependencies+=("$(sbatch --parsable -J somalier_${family_id} -D $directory/Somalier_analyses $here_folder/../Tools/Somalier/somaliercall_from_image.sh -p "$proband_name" -m "$mother_name" -f "$father_name" -r $fasta_path -i $family_id -d "$directory" -s $here_folder/../Tools/Somalier/sites.hg38.vcf.gz)")
	#dependencies+=("$(sbatch -J somalier_${family_id} -D Somalier_analyses somalierScript.sh)")
	cd "$here_folder"
fi

#Peddy step
if [ "$include_peddy" == true ] || [ "$run_all" == true ]; then
	cp $here_folder/../Tools/Peddy/peddy_requirements.txt $APPTAINER_CACHEDIR/
	apptainerGet peddy_v0.4.8.sif $here_folder/../Tools/Peddy/peddy.def
	getPed
	cd "$directory"
	echo "running PEDDY for merged.$family_id.normed.joint.GRCh38.small_variants.phased.merged.vcf.gz"
	echo "bash $here_folder/../Tools/Peddy/peddycall_from_image.sh -p "$proband_name" -m "$mother_name" -f "$father_name" -i $family_id -d "$directory""
	dependencies+=("$(sbatch --parsable -J peddy_${family_id} -D $directory/Peddy_analyses $here_folder/../Tools/Peddy/peddycall_from_image.sh -p "$proband_name" -m "$mother_name" -f "$father_name" -i $family_id -d "$directory")")
fi

#MultiQC step
if [ "$include_multiqc" == true ] || [ "$run_all" == true ]; then
	cd "$directory"
	apptainerGet multiqc_v1.3.3.sif docker://multiqc/multiqc:v1.33
	dependencyCallLine=$(dependencyLine "${dependencies[@]}")
	echo "dependency line: $dependencyCallLine"
	echo "sbatch $dependencyCallLine --parsable -J multiqc_${family_id} -D $directory $here_folder/../Tools/MultiQc/multiQccall_from_image.sh"
	#I use an sbatch so we can use job dependencies and run this AFTER the other steps
	dependencies+=("$(sbatch $dependencyCallLine --parsable -J multiqc_${family_id} -D $directory $here_folder/../Tools/MultiQc/multiQccall_from_image.sh)")
fi

#Cleanup step
if [ "$include_cleanup" == true ] || [ "$run_all" == true ]; then
	dependencyCallLine=$(dependencyLine "${dependencies[@]}")
	echo "dependency line for Cleanup: $dependencyCallLine"
	bash $here_folder/cleanup.sh -i $family_id -d $directory -c $config_file
	bash $here_folder/outputs_Json.sh -i $family_id -d $directory -c $config_file
	bash $here_folder/send_Symlinks_Narval.sh -i $family_id -d $directory -c $config_file -h $here_folder -r

	loadEnv "Globus_env"
	flow=6336492e-e308-4a67-b78e-13684c747472 # move and delete flow
	destination_endpoint=$(jq -r '.Transfers.destination_endpoint' ${config_file}) # Narval endpoint UUID
	destination_collection=":$(jq -r '.Transfers.destination_collection' ${config_file})" # Narval collection UUID
	source_endpoint=$(jq -r '.Transfers.origin_endpoint' ${config_file})
	source_collection=":$(jq -r '.Transfers.origin_collection' ${config_file})"
	if [ -z $source_endpoint ] || [ -z $destination_endpoint ]; then
		echo "Given cluster endpoint for origin or destination not found."
		exit 1
	fi
	globus login --flow $flow --gcs ${destination_endpoint}${destination_collection} --gcs ${source_endpoint}${source_collection}
	echo "sbatch $dependencyCallLine -J Globus_$family_id $here_folder/globus_cli_send.sh -i $family_id -d $directory -c $config_file -h $here_folder"
	sbatch $dependencyCallLine -J Globus_$family_id $here_folder/globus_cli_send.sh -i $family_id -d $directory -c $config_file -h $here_folder
	exit
fi