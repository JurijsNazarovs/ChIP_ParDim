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
inpDataInfo=${4} #text file with input data
resPath=${5:-"/tmp/isPool"} #return on submit server. Can be read from file if empty
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

ReadArgs "$argsFile" "1" "Preaquas" "${#posArgs[@]}" "${posArgs[@]}" > /dev/null
if [[ "${resPath:0:1}" != "/" ]]; then
    ErrMsg "The full path for resPath has to be provided.
           Current value is: $resPath ."
fi

PrintArgs "$curScrName" "${posArgs[@]}" "jobsDir"

ChkValArg "isInpNested" "" "true" "false"


## Detect reps and ctls
requirSize=0
inpPath="$(awk 'NR==1{print $1; exit}' "$inpDataInfo")"
inpPath="${inpPath%:}"
if [[ "$isInpNested" = true ]]; then
    inpPathTmp="$inpPath"align
    inpType=("rep" "ctl") #names of searched dirs with data

    for i in "${inpType[@]}"; do
      readarray -t inpDir <<<\
                "$(awk -F "\n"\
                       -v pattern="^$inpPathTmp/$i[0-9]*:$"\
                       '{ if ($0 ~ pattern) {print $0} }' "$inpDataInfo"
                 )"
      
      if [[ -z $(RmSp "$inpDir") ]]; then
          ErrMsg "No directories are found corresponding to the pattern:
                 $inpPathTmp/$i[0-9]*
                 Maybe option isInpNested should be false?"
      fi

      for j in "${!inpDir[@]}"; do
        readarray -t strTmp <<< \
                  "$(awk -F "\t"\
                         -v dir="${inpDir[$j]}"\
                         -v file="$inpExt$"\
                         '{ 
                            if ($0 ~ dir) {f = 1; next}
                            if ($0 ~ "^/.*:$") {f = 0}
                            if (f == 1 && $1 ~ file) {print $0} 
                          }' "$inpDataInfo"
                    )"
	
	if [[ ${#strTmp[@]} -ne 1 ]]; then
	    ErrMsg "Cannot detect replicate name from ${inpDir[$j]}"
	else #just one possible file in directory
          strTmp=(${strTmp[@]})
          requirSize=$((requirSize + strTmp[1]))
	  eval $i"Name[\"$j\"]=${inpDir[$j]%:}/\"${strTmp[0]}\""  #repName
        fi
      done
      eval "strTmp=(\${"$i"Name[@]})"
      if [[ -n  $(ArrayGetDupls "${strTmp[@]##*/}") ]]; then
          ErrMsg "Duplicates in names are prohibeted on this stage."
      fi #because files are moving in condor without structure saving
      eval $i"Num=\${#"$i"Name[@]}" #repNum
    done
else  #have to allign in this pipeline
  inpType=("rep" "ctl") #names of searched files
  posEnd=("ctl" "dnase")

  for i in "${inpType[@]}"; do
    readarray -t strTmp <<< \
              "$(awk -F "\t"\
                     -v dir="${inpDir[$j]}"\
                     -v file="$inpExt$"\
                     '{ 
                       if ($0 ~ dir) {f = 1; next}
                       if ($0 ~ "^/.*:$") {f = 0}
                       if (f == 1 && $1 ~ file) {print $0} 
                     }' "$inpDataInfo"
              )"
    
    if [[ "$i" != "rep" ]]; then
        inpExtTmp=".$i.$inpExt"
        readarray -t inpName <<<\
                  "$(awk -F "\t"\
                         -v dir="$inpPath:$"\
                         -v file="$inpExtTmp$"\
                         '{ if ($0 ~ dir) {f = 1; next}
                            if ($0 ~ "^/.*:$") {f = 0}
                            if (f ==1 && $1 ~ file && NF > 1) {print $0} 
                         }' "$inpDataInfo"
                  )"
    else
      posEndTmp=."$(JoinToStr ".|." "${posEnd[@]}")."
      readarray -t inpName <<<\
                "$(awk -F "\t"\
                       -v dir="$inpPath:$"\
                       -v file="$posEndTmp"\
                       -v ext="$inpExt$"\
                       '{ if ($0 ~ dir) {f = 1; next}
                          if ($0 ~ "^/.*:$") {f = 0}
                          if (f==1 && $1 !~ file && $1 ~ ext && NF > 1)
                             {print $0}
                       }' "$inpDataInfo"
                 )"
    fi

    if [[ -z $(RmSp "$inpName") ]]; then
         eval $i"Num=0"
        continue
    fi

    # Fill variables with full path to files and size
    for j in "${!inpName[@]}"; do
      strTmp=(${inpName[$j]})
      requirSize=$((requirSize + strTmp[1]))
      eval $i"Name[\"$j\"]=$inpPath\"${strTmp[0]}\""  
    done
    eval $i"Num=\${#inpName[@]}" #repNum
  done  
fi

if [[ "$repNum" -eq 0 ]]; then
    ErrMsg "Number of replicates has to be more than 0"
fi

if !([[ "$ctlNum" -eq 0 || "$ctlNum" -eq 1 || "$ctlNum" -eq "$repNum" ]]); then
    ErrMsg "Confusing number of ctl files.
            Number of ctl: $ctlNum
            Number of rep: $repNum"
fi


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
