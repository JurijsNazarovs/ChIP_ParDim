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
         "trimLenDnase"
         "isOrigName")

exePath="$homePath/exeTrim.sh"
funcList="$homePath/funcList.sh"

isInpNested="true" #inside rep/ctl dirs or not
inpExt="fastq.gz"
inpType="rep, ctl" #rep,ctl,dnase
trimLen=""
trimLenDnase=""
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
if [[ -n $(RmSp "$trimLenDnase") && ! "$trimLenDnase" =~ ^[0-9]+$ ]] ; then
    ErrMsg "The trimming length for Dnase has to be an integer number or empty"
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


## Condor file
# Arguments for condor job according to exeTrim.sh
argsCon=("\$(name1)"
         "\$(useLink1)"
         "\$(linkName1)"
         "\$(name2)"
         "\$(useLink2)"
         "\$(linkName2)"
         "\$(trimLen)"
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
transFiles=("\$(TransFiles)"
            "$funcList"
            "http://proxy.chtc.wisc.edu/SQUID/nazarovs/$softZip")
transFiles="$(JoinToStr ", " "${transFiles[@]}")"

# Main condor file
conFile="$jobsDir/${curScrName%.*}.condor"
bash "$homePath"/makeCon.sh "$conFile" "$conOut" "$exePath"\
     "$argsCon" "$transFiles"\
     "1" "2" "\$(hd)" "\$(transOut)" "\$(transMap)"


## Dag file
PrintfLine > "$dagFile" 
printf "# [Start] Description of $dagFile\n" >> "$dagFile"
PrintfLine >> "$dagFile"

## Dnase
# Since we might use links for dnase, names have to be changed accordingly
# and transfer just those files which do not have links
for i in "${!dnaseName[@]}"; do
  if [[ "${dnaseIsLink[$i]}" = false ]]; then
      dnaseNameTrans=("${dnaseNameTrans[@]}" "${dnaseName[$i]}")
      dnaseName[$i]="${dnaseName[$i]##*/}"
  else
    dnaseNameTrans=("${dnaseNameTrans[@]}" "")
    dnaseName[$i]="../${dnaseName[$i]#*../}" #name is used to create a link
  fi
done

for i in "${!dnaseName[@]}"; do
  jobId="TrimdDnase$((i + 1))"
  
  # Calculate required memory, based on input files
  hd="${dnaseSize[$i]}" #size in bytes.
  hd=$(echo $hd/1024^3 + 1 | bc) #in GB rounded to a bigger integer
  hd=$((2*hd + 3)) #+1gb for safety + 2gb for software, *2 for output
  
  # Job description
  printf "JOB  $jobId $conFile\n" >> "$dagFile"
  
  printf "VARS $jobId name1=\"${dnaseName[$i]}\"\n" >> "$dagFile"
  printf "VARS $jobId useLink1=\"${dnaseIsLink[$i]}\"\n" >> "$dagFile"
  printf "VARS $jobId linkName1=\"${dnaseLinkName[$i]}\"\n"  >> "$dagFile"
  printf "VARS $jobId trimLen=\"$trimLenDnase\"\n" >> "$dagFile"
  printf "VARS $jobId hd=\"$hd\"\n" >> "$dagFile"
  printf "VARS $jobId TransFiles=\"${dnaseNameTrans[$i]}\"\n" >> "$dagFile"
  
  printf "VARS $jobId transOut=\"$transOut.$jobId.tar\"\n" >> "$dagFile"
  printf "VARS $jobId transMap=\"\$(transOut)=$resPath/\$(transOut)\"\n"\
         >> "$dagFile"
  printf "\n" >> "$dagFile"
done

## chip/ctl

# Copy ctl information for easy use in case of several reps and 1 ctl
if [[ $repNum -gt $ctlNum && $ctlNum -eq 1 ]]; then
    for ((i=1; i<$num1; i++)); do
      ctlName[$i]="${ctlName[0]}"
      ctlLinkName[$i]="${ctlLinkName[0]}"
    done
fi

iterNum=$(Max $repNum $ctlNum)
for (( i=0; i<${iterNum}; i++ )); do
  jobId="TrimRepCtl$((i + 1))"
  # Calculate required memory, based on input files
  hd=$((repSize[$i] + ctlSize[$i])) #size in bytes
  hd=$(echo $hd/1024^3 + 1 | bc) #in GB rounded to a bigger integer
  hd=$((2*hd + 3)) #+1gb for safety + 2gb for software, *2 for output
  
  # Job description
  printf "JOB  $jobId $conFile\n" >> "$dagFile"
  
  printf "VARS $jobId name1=\"${repName[$i]##*/}\"\n" >> "$dagFile"
  printf "VARS $jobId linkName1=\"${repLinkName[$i]}\"\n" >> "$dagFile"
  printf "VARS $jobId name2=\"${ctlName[$i]##*/}\"\n" >> "$dagFile"
  printf "VARS $jobId linkName2=\"${ctlLinkName[$i]}\"\n" >> "$dagFile"
  printf "VARS $jobId trimLen=\"$trimLen\"\n" >> "$dagFile"
  printf "VARS $jobId hd=\"$hd\"\n" >> "$dagFile"
  printf "VARS $jobId TransFiles=\"$(JoinToStr "," "${repName[$i]}" "${ctlName[$i]}")\"\n"\
         >> "$dagFile"
  
  printf "VARS $jobId transOut=\"$transOut.$jobId.tar\"\n" >> "$dagFile"
  printf "VARS $jobId transMap=\"\$(transOut)=$resPath/\$(transOut)\"\n"\
         >> "$dagFile"
  printf "\n" >> "$dagFile"
done


## End
PrintfLine >> "$dagFile"
printf "# [End] Description of $dagFile\n" >> "$dagFile"
PrintfLine >> "$dagFile"

exit 0 #everything is ok
