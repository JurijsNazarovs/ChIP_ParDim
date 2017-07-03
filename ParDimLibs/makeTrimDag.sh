#!/bin/bash
#===============================================================================
# This script creates a right version of a dag file to trim files
#
# 2 possible ways to read input files: nested - rep/ctl dirs, not nested - all
# files are in one directory.
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
dagFile=${2:-"Trim.dag"} #create this
jobsDir=${3:-"TrimTmp"} #working directory, provided with one of analysed dirs
resPath=${4:-"/tmp/Trim"} #return here on submit server. Read from file if empty
inpDataInfo=${5} #text file with input data
resDir=${6:-"TrimResDir"}
transOut=${7:-"Trim"}


## Default values, which can be read from the $argsFile
posArgs=("exePath"
         "funcList"
         "isInpNested"
         "inpExt"
         "inpType"
         "trimLen"
         "isOrigName")

exePath="$homePath/exeTrim.sh"
funcList="$homePath/funcList.sh"

isInpNested="true" #inside rep/ctl dirs or not
inpExt="fastq.gz"
inpType="rep, ctl" #rep,ctl,dnase
trimLen=""
isOrigName=true
softZip="Trimmomatic-0.36.zip"

if [[ -z $(RmSp "$resPath") ]]; then
    posArgs=("${posArgs[@]}" "resPath")
fi

ReadArgs "$argsFile" "1" "${curScrName%.*}" "${#posArgs[@]}" "${posArgs[@]}"\
         > /dev/null

for i in exePath funcList resPath; do
  eval "strTmp=\"\$$i\""
  if [[ "${strTmp:0:1}" != "/" ]]; then
    ErrMsg "The full path for $i has to be provided:
           Current value is: $strTmp"
  fi
done

PrintArgs "$curScrName" "${posArgs[@]}" "jobsDir"


## Initial checking
ChkValArg "isInpNested" "" "true" "false"
ChkValArg "isOrigName" "" "true" "false"

if [[ -n $(RmSp "$trimLen") && ! "$trimLen" =~ ^[0-9]+$ ]] ; then
    ErrMsg "The trimming length has to be an integer number or empty"
fi
WarnMsg "The input has to be in fastq format, despite the extension"

readarray -t inpType <<<\
          "$(awk\
            '{ gsub(/,[[:space:]]*/, "\n"); print }' <<< "$inpType"
           )"

for i in "${inpType[@]}"; do
  ChkValArg "i" "Input type\n" "rep" "ctl" "dnase"
done


## Detect reps and ctls
DetectInput "$inpDataInfo" "${#inpType[@]}" "${inpType[@]}" "$inpExt"\
            "$isInpNested" "true"

if !([[ "$ctlNum" -eq 0 || "$ctlNum" -eq 1 || "$ctlNum" -eq "$repNum" || \
      "$repNum" -eq 0 ]]); then
    ErrMsg "Confusing number of ctl files.
            Number of ctl: $ctlNum
            Number of rep: $repNum"
fi

if [[ "$ctlNum" -eq 0 && "$repNum" -eq 0 && "$dnaseNum" -eq 0 ]]; then
    ErrMsg "No input is detected"
fi


requirSize=0
maxSize=0
for i in "${repSize[@]}" "${ctlSize[@]}" "${dnaseSize[@]}"; do
  requirSize=$((requirSize + i))
  maxSize=$(Max $maxSize $i) # + this, since we create new trimmed file
done


## Condor
# Calculate required memory, based on input files
hd=$((requirSize + maxSize)) #size in bytes.
hd=$((hd*1)) #increase size in 1 times
hd=$(echo $hd/1024^3 + 1 | bc) #in GB rounded to a bigger integer
hd=$((hd + 3)) #+1gb for safety + 2gb for software

# Arguments for condor job
argsCon=("\$(repName)"
         "\$(ctlName)"
         "\$(dnaseName)"
         "$trimLen"
         "$isOrigName"
         "$resDir"
         "\$(transOut)"
         "$softZip"
         "false")
argsCon=$(JoinToStr "\' \'" "${argsCon[@]}")

# Output directory for condor log files
conOut="$jobsDir/conOut"
mkdir -p "$conOut"

# Transfered files
transFiles=("${repName[@]}"
            "${ctlName[@]}"
            "${dnaseName[@]}"
            "$funcList.sh"
            "http://proxy.chtc.wisc.edu/SQUID/nazarovs/$softZip")
transFiles="$(JoinToStr ", " "${transFiles[@]}")"

# Main condor file
conFile="$jobsDir/${curScrName%.*}.condor"
bash "$homePath"/makeCon.sh "$conFile" "$conOut" "$exePath"\
     "$argsCon" "$transFiles"\
     "1" "1" "$hd" "\$(transOut)" "\$(transMap)"


## Dag file
printf "" > "$dagFile"
jobId="Trim"
printf "JOB  $jobId $conFile\n" >> "$dagFile"

printf "VARS $jobId repName=\"$(JoinToStr "," "${repName[@]##*/}")\"\n"\
       >> "$dagFile"
printf "VARS $jobId ctlName=\"$(JoinToStr "," "${ctlName[@]##*/}")\"\n"\
       >> "$dagFile"
printf "VARS $jobId dnaseName=\"$(JoinToStr "," "${dnaseName[@]##*/}")\"\n"\
       >> "$dagFile"


printf "VARS $jobId transOut=\"$transOut.tar.gz\"\n" >> "$dagFile"
printf "VARS $jobId transMap=\"\$(transOut)=$resPath/\$(transOut)\"\n"\
       >> "$dagFile"
