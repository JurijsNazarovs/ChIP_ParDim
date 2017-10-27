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

# Arguments for condor job
argsCon=("\$(name1)"
         "\$(linkName1)"
         "\$(useLink1)"
         "\$(name2)"
         "\$(linkName2)"
         "\$(useLink2)"
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

# Since we might use links for dnase, names have to be changed accordingly
# and transfer just those files which do not have links
for i in "${!dnaseName[@]}"; do
  if [[ "${dnaseIsLink[$i]}" = false ]]; then
      dnaseNameTrans=("${dnaseNameTrans[@]}" "${dnaseName[$i]}")
      dnaseName[$i]="${dnaseName[$i]##*/}"
  else
    dnaseName[$i]="../${dnaseName[$i]#*../}"
  fi
done

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


## dnase
jobId="TrimdDnase"
# Calculate required memory, based on input files
requirSize=0
maxSize=0
for i in "${dnaseSize[@]}"; do
  if [[ "${dnaseIsLink[$i]}" = true ]]; then
      # skip size additing
      continue
  fi
  requirSize=$((requirSize + i))
  maxSize=$(Max $maxSize $i) # + this, since we create new trimmed file
done

hd=$((requirSize + maxSize)) #size in bytes.
hd=$((hd*1)) #increase size in 1 times
hd=$(echo $hd/1024^3 + 1 | bc) #in GB rounded to a bigger integer
hd=$((2*hd + 3)) #+1gb for safety + 2gb for software, *2 for output

# Job description
printf "JOB  $jobId $conFile\n" >> "$dagFile"

printf "VARS $jobId name1=\"$(JoinToStr "," "${dnaseName[@]}")\"\n"\
       >> "$dagFile"
printf "VARS $jobId linkName1=\"$(JoinToStr "," "${dnaseLinkName[@]}")\"\n"\
       >> "$dagFile"
printf "VARS $jobId useLink1=\"$(JoinToStr "," "${dnaseIsLink[@]}")\"\n"\
       >> "$dagFile"
printf "VARS $jobId trimLen=\"$trimLenDnase\"\n" >> "$dagFile"
printf "VARS $jobId hd=\"$hd\"\n" >> "$dagFile"
printf "VARS $jobId TransFiles=\"$(JoinToStr "," "${dnaseNameTrans[@]}")\"\n"\
       >> "$dagFile"

printf "VARS $jobId transOut=\"$transOut.dnase.tar\"\n" >> "$dagFile"
printf "VARS $jobId transMap=\"\$(transOut)=$resPath/\$(transOut)\"\n"\
       >> "$dagFile"
printf "\n" >> "$dagFile"


## chip/ctl
jobId="TrimRepCtl"
# Calculate required memory, based on input files
requirSize=0
maxSize=0
for i in "${repSize[@]}" "${ctlSize[@]}"; do
  requirSize=$((requirSize + i))
  maxSize=$(Max $maxSize $i) # + this, since we create new trimmed file
done

hd=$((requirSize + maxSize)) #size in bytes.
hd=$((hd*1)) #increase size in 1 times
hd=$(echo $hd/1024^3 + 1 | bc) #in GB rounded to a bigger integer
hd=$((2*hd + 3)) #+1gb for safety + 2gb for software, *2 for output

# Job description
printf "JOB  $jobId $conFile\n" >> "$dagFile"

printf "VARS $jobId name1=\"$(JoinToStr "," "${repName[@]##*/}")\"\n"\
       >> "$dagFile"
printf "VARS $jobId linkName1=\"$(JoinToStr "," "${repLinkName[@]}")\"\n"\
       >> "$dagFile"
printf "VARS $jobId name2=\"$(JoinToStr "," "${ctlName[@]##*/}")\"\n"\
       >> "$dagFile"
printf "VARS $jobId linkName2=\"$(JoinToStr "," "${ctlLinkName[@]}")\"\n"\
       >> "$dagFile"
printf "VARS $jobId trimLen=\"$trimLen\"\n" >> "$dagFile"
printf "VARS $jobId hd=\"$hd\"\n" >> "$dagFile"
printf "VARS $jobId TransFiles=\"$(JoinToStr "," "${repName[@]}" "${ctlName[@]}")\"\n"\
       >> "$dagFile"

printf "VARS $jobId transOut=\"$transOut.RepCtl.tar\"\n" >> "$dagFile"
printf "VARS $jobId transMap=\"\$(transOut)=$resPath/\$(transOut)\"\n"\
       >> "$dagFile"

## End
PrintfLine >> "$dagFile"
printf "# [End] Description of $dagFile\n" >> "$dagFile"
PrintfLine >> "$dagFile"

exit 0 #everything is ok
