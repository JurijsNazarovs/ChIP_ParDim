#!/bin/bash
#===============================================================================
# This script creates a right version of a dag file of AQUAS pipeline,
# base on files in input directory (inpPath)
#
# The script supports a range of stages (first stage - last stage),
# according to which AQUAS pipeline should be executed and
# corresponding dag file should be constructed.

# This script can stop on any of a supported last stages, but 
# it CANNOT start with some first stage, if the script was not run
# until this first stage before.
# In other words, first stage works like a check point for current pipeline.
#
# Supported stages in an order:
#	- toTag. Not in this script, but in the whole pipeline
#	- pseudo
#	- xcor
#	- pool
#	- stgMacs2
#	- peaks
#	- idroverlap 
# Input:
#	- argsFile	 file with all arguments for this shell
#
# Possible arguments are described in a section: ## Default values		
#==============================================================================

## Libraries and options
shopt -s nullglob #allows create an empty array
homePath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" 
source "$homePath"/funcList.sh

curScrName=${0##*/} #delete last backSlash


## Input and default values
argsFile=${1:-"args.listDev"} 
dagFile=${2:-"preAquas.dag"} #create this
jobsDir=${3:-"preAquasTmp"} #working directory, provided with one of analysed dirs
resPath=${4:-"/tmp/isPool"} #return here on submit server. Read from file if empty
inpDataInfo=${5} #text file with input data
resDir=${6:-"resultedDir"} #directory where to save resutls
transOut=${7:-"preAquas"}
outPath="$resPath/$resDir" #Used as input for stages after job was done


## Default values, which can be read from the $argsFile
posArgs=("inpExt" "isInpNested"
         "exePath" "funcList")

inpExt="bam" #extension of original input data (before tagStage)
isInpNested="true" #if all files in one dir or in subdirs: rep$i, ctl$i
exePath="$homePath/exeAquas.sh"
funcList="$homePath/funcList.sh"

softTar="pipeInstallFiles.new.tar.gz"
softSize=9

if [[ -z $(RmSp "$resPath") ]]; then
    posArgs=("${posArgs[@]}" "resPath")
fi

ReadArgs "$argsFile" "1" "${curScrName%.*}" "${#posArgs[@]}" "${posArgs[@]}"\
         > /dev/null
PrintArgs "$curScrName" "${posArgs[@]}" "jobsDir"

for i in exePath funcList resPath; do
  eval "strTmp=\"\$$i\""
  if [[ "${strTmp:0:1}" != "/" ]]; then
    ErrMsg "The full path for $i has to be provided:
           Current value is: $strTmp"
fi
done

ChkValArg "isInpNested" "" "true" "false"
ChkValArg "inpExt" "" "bam" "filt_bam"


## Detect reps and ctls
DetectInput "$inpDataInfo" "2" "rep" "ctl" "$inpExt"\
            "$isInpNested" "true"

if [[ "$repNum" -eq 0 && "$ctlNum" -eq 0 ]]; then
    ErrMsg "No input is provided"
fi


## Condor
# Arguments for condor job
jobArgsFile="" #file  w/ argumetns corresponds to var argsFile, e.g. xcor1.args
argsCon=("\$(script)" "\$(argsFile)" "$resDir" "\$(transOut)" "$softTar" "false")
argsCon="$(JoinToStr "\' \'" "${argsCon[@]}")"

# Output directory for condor log files
conOut="$jobsDir/conOut"
mkdir -p "$conOut"

# Transfered files
transFiles=("$jobsDir/\$(argsFile)"
	    "http://proxy.chtc.wisc.edu/SQUID/nazarovs/$softTar"
            "\$(transFiles)"
            "$funcList")
transFiles="$(JoinToStr ", " "${transFiles[@]}")"

# Main condor file
conFile="$jobsDir/${curScrName%.*}.condor"
bash "$homePath"/makeCon.sh "$conFile" "$conOut" "$exePath"\
     "$argsCon" "$transFiles"\
     "\$(nCores)" "\$(ram)" "\$(hd)" "\$(transOut)" "\$(transMap)"\
     "\$(conName)" "true"
 

## Start the "$dagFile"
PrintfLine > "$dagFile" 
printf "# [Start] Description of $dagFile\n" >> "$dagFile"
PrintfLine >> "$dagFile"

jobName="toTag"

PrintfLine >> "$dagFile"
printf "# $jobName\n" >> "$dagFile" 
PrintfLine >> "$dagFile"

# Create the dag file
for ((i=0; i<=1; i++)); do #0 - rep, 1 - ctl 
  if [[ "$i" -eq 0 ]]; then
      labelTmp="Rep"
      numTmp=$repNum
      nameTmp=("${repName[@]}")
      sizeTmp=("${repSize[@]}")
  else
    labelTmp="Ctl"
    numTmp=$ctlNum
    nameTmp=("${ctlName[@]}")
    sizeTmp=("${ctlSize[@]}")
  fi
  
  for ((j=1; j<=$numTmp; j++)); do
    jobId="$jobName$labelTmp$j"
    jobArgsFile=("$jobsDir/$jobId.args")

    hd="${sizeTmp[$((j-1))]}" #size in bytes
    hd=$(echo $hd/1024^3 + 1 | bc) #in GB
    ram=$((hd*2))
    hd=$((hd + softSize)) #for software

    PrintfLineSh >> "$dagFile"
    printf "# $jobId\n" >> "$dagFile"
    PrintfLineSh >> "$dagFile"

    printf "JOB $jobId $conFile\n" >> "$dagFile"
    printf "VARS $jobId script=\"$jobName.bds\"\n" >> "$dagFile"
    printf "VARS $jobId argsFile=\"${jobArgsFile##*/}\"\n" >> "$dagFile"

    printf "VARS $jobId nCores=\"1\"\n" >> "$dagFile"
    printf "VARS $jobId hd=\"$hd\"\n" >> "$dagFile"
    printf "VARS $jobId ram=\"$ram\"\n" >> "$dagFile"

    transOutTmp="$transOut.$jobId.tar.gz"
    transMapTmp="$resPath/$transOutTmp"
    printf "VARS $jobId transFiles=\"${nameTmp[$((j-1))]}\"\n" >> "$dagFile"
    printf "VARS $jobId transOut=\"$transOutTmp\"\n"\
           >> "$dagFile"
    printf "VARS $jobId transMap=\"\$(transOut)=$transMapTmp\"\n"\
           >> "$dagFile"
    printf "VARS $jobId conName=\"$jobId.\"\n"\
           >> "$dagFile"
    
    # args file
    printf -- "-nth\t\t1\n" >> "$jobArgsFile"
    printf -- "-$inpExt\t\t${nameTmp[$((j-1))]##*/}\n" >> "$jobArgsFile"
    printf -- "-rep\t\t$j\n" >> "$jobArgsFile"
    printf -- "-ctl\t\t$i\n" >> "$jobArgsFile" #flag if ctl or not
  done
done
