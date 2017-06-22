#!/bin/bash
#===============================================================================
# This script creates a right version of a dag file to decide if ctl should be
# pooled. It is a pre script of AQUAS pipeline.
#
# 2 possible ways to read input files: nested - rep/ctl dirs, not nested - all
# files are in 1 dir.
# 
# Input:
#	- argsFile	 file with all arguments for this shell		
#==============================================================================
## Libraries and options
shopt -s nullglob #allows create an empty array
homePath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" 
source "$homePath"/funcList.sh

curScrName=${0##*/} #delete last backSlash


## Input and default values
argsFile=${1:-"args.listDev"} 
dagFile=${2:-"isPool.dag"} #create this
jobsDir=${3:-"isPoolTmp"} #working directory, provided with one of analysed dirs
resPath=${4:-"/tmp/isPool"} #return here on submit server. Read from file if empty
inpDataInfo=${5} #text file with input data
resDir=${6:-"resultedDir"}
transOut=${7:-"isPool"}


## Default values, which can be read from the $argsFile
posArgs=("isInpNested"
         "exePath"
         "ctlDepthRatio"
         "inpExt")

isInpNested="true" #inside rep/ctl dirs or not
exePath="$homePath/exeIsCtlPool.sh"
ctlDepthRatio="1.2"
inpExt="tagAlign.gz"

if [[ -z $(RmSp "$resPath") ]]; then
    posArgs=("${posArgs[@]}" "resPath")
fi

ReadArgs "$argsFile" "1" "${curScrName%.*}" "${#posArgs[@]}" "${posArgs[@]}" > /dev/null
if [[ "${resPath:0:1}" != "/" ]]; then
    ErrMsg "The full path for resPath has to be provided.
           Current value is: $resPath ."
fi

PrintArgs "$curScrName" "${posArgs[@]}" "jobsDir"
ChkValArg "isInpNested" "" "true" "false"


## Detect reps and ctls
DetectInput "$inpDataInfo" "2" "rep" "ctl" "$inpExt"\
            "$isInpNested" "true"

if [[ "$repNum" -eq 0 ]]; then
    ErrMsg "Number of replicates has to be more than 0"
fi

if !([[ "$ctlNum" -eq 0 || "$ctlNum" -eq 1 || "$ctlNum" -eq "$repNum" ]]); then
    ErrMsg "Confusing number of ctl files.
            Number of ctl: $ctlNum
            Number of rep: $repNum"
fi

requirSize=0
for i in "${repSize[@]}" "${ctlSize[@]}"; do
  requirSize=$((requirSize + i))
done


## Condor
# Calculate required memory, based on input files
hd=$requirSize #size in bytes
hd=$((hd*1)) #increase size in 1 times
hd=$(echo $hd/1024^3 + 1 | bc) #in GB rounded to a bigger integer
hd=$((hd + 1)) #+1gb for safety

# Arguments for condor job
argsCon=("\$(repName)" "\$(ctlName)" "$resDir" "\$(transOut)"
         "$ctlDepthRatio" "false")
argsCon=$(JoinToStr "\' \'" "${argsCon[@]}")

# Output directory for condor log files
conOut="$jobsDir/conOut"
mkdir -p "$conOut"

# Transfered files
transFiles=$(JoinToStr ", " "${repName[@]}" "${ctlName[@]}"\
                       "${exePath%/*}"/funcList.sh)

# Main condor file
conFile="$jobsDir/${curScrName%.*}.condor"
bash "$homePath"/makeCon.sh "$conFile" "$conOut" "$exePath"\
     "$argsCon" "$transFiles"\
     "1" "1" "$hd" "\$(transOut)" "\$(transMap)"


## Dag file
printf "" > "$dagFile"
jobId="isPool"
printf "JOB  $jobId $conFile\n" >> "$dagFile"

printf "VARS $jobId repName=\"$(JoinToStr "," "${repName[@]##*/}")\"\n"\
       >> "$dagFile"
printf "VARS $jobId ctlName=" >> "$dagFile"
printf "\"$(JoinToStr "," "${ctlName[@]##"$inpPath"}")\"\n"\
       >> "$dagFile"


printf "VARS $jobId transOut=\"$transOut.tar.gz\"\n" >> "$dagFile"
printf "VARS $jobId transMap=\"\$(transOut)=$resPath/\$(transOut)\"\n"\
       >> "$dagFile"
printf "\n" >> "$dagFile"
