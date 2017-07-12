#!/bin/bash
#===============================================================================
# This script trims files based on common mimum length or set length
#
# Input: strings with names of files joined by comma
#       - repName
#	- ctlName
#	- dnaseName
# Output: trimmed files
#
# Possible error codes:
# 1 - general error
# 2 - cannot instal software
#===============================================================================
## Libraries and options
shopt -s nullglob #allows create an empty array
shopt -s extglob #to use !
homePath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" 
source "$homePath"/funcList.sh #need to transfer

curScrName=${0##*/} #delete last backSlash
trimSoft="Trimmomatic-0.36/trimmomatic-0.36.jar"
EchoLineBold
echo "[Start] $curScrName"

TrimSE(){
  local fileInp=${1}
  local trimLen=${2}
  local isOrigName=${3:-false}
  local resDir=${4:-.}
  
  local fileTmp="$(mktemp -uq tmp.XXX)"

  java -jar "$trimSoft" SE "$fileInp" "$fileTmp"\
       CROP:"$trimLen"

  if [[ $? -ne 0 ]]; then
      ErrMsg "$fileInp was not trimmed.
             Process is stopped."
      if [[ -f "$fileTmp"  ]]; then
          rm -rf "$fileTmp"
      fi
  else
    mkdir -p "$resDir"
    
    if [[ "$isOrigName" = true ]]; then
        strTmp="$resDir/$(basename "$fileInp")"
        echo "$strTmp"
        mv "$fileTmp" "$strTmp"
    else
      readarray -t strTmp <<< "$(echo "$fileInp" | tr "." "\n")"
      strTmp=($(JoinToStr "." "${strTmp[0]}" trim "${strTmp[@]:1}"))
      strTmp="$resDir/$(basename "$strTmp")"
      echo "$strTmp"
      mv "$fileTmp" "$strTmp"
    fi

    if [[ $? -ne 0 ]]; then
        ErrMsg "Not able to move $fileTmp to $strTmp"
    fi
  fi
}


## Input and default values
repName=$1
ctlName=$2
dnaseName=$3
trimLen=$4
isOrigName=${5:-"false"}
resDir=${6:-"trimResDir"}
outTar=${7:-"isPool.tar.gz"} #tarFile to return back on submit machine
softZip=${8:-"Trimmomatic-0.36.zip"}
isDry=${9:-true}

posTypes=(rep ctl dnase)


## Detect names and number of files for every type
for i in "${posTypes[@]}"; do
  eval "readarray -t tmpName <<< \"\$(echo \$${i}Name | tr \",\" \"\n\")\""
  if [[ -z $(RmSp "$tmpName") ]]; then
      eval "${i}Num=0"
  else
    for j in "${tmpName[@]}"; do
      ChkExist f "$j" "Input file: $j\n"
    done
    
    eval "${i}Num=${#tmpName[@]}"
    eval "${i}Name=(\"\${tmpName[@]}\")"
  fi
done


## Main part - trimming
unzip "$softZip"
if [[ $? -ne 0 ]]; then
    ErrMsg "Cannot unzip $softZip" "2"
else
  rm -rf "$softZip"
fi

if [[ -n "$trimLen" ]]; then
    for i in "${repName[@]}" "${ctlName[@]}" "${dnaseName[@]}"; do
      if [[ -z "$i" ]]; then
          continue
      fi
      
      TrimSE "$i" "$trimLen" "$isOrigName" "$resDir"
    done
else
  # Detect the trimming length
  EchoLineSh
  echo "Detecting the trimming length ..."
  echo ""
  for i in "${posTypes[@]}"; do
    eval "tmpName=(\"\${${i}Name[@]}\")"
    
    if [[ -z "$tmpName" ]]; then
        continue
    fi

    for j in "${!tmpName[@]}"; do
      fileTmp="${tmpName[j]}"
      extTmp="${fileTmp##*.}"
      
      minLenTmp=$(awk  'NR==2 {print length($0); exit}' "$fileTmp")
      minLenTmp=$((if [[ "$extTmp" = gz ]]; then
                       gunzip -c "$fileTmp";
                   else
                     cat "$fileTmp";
                   fi)|\
                      awk -v minLen=minLenTmp\
                      'NR%4 == 2 {if (length($0) < minLen){minLen = length($0)}}
                      END{print minLen}')

      eval "${i}MinLen[$j]=$minLenTmp"
      echo "Min of $i$((j+1)): $minLenTmp bp"
    done
  done
  echo "Done!"

  # Copy length in case of several rep for an easy use
  if [[ $repNum -gt 1 && $ctlNum -eq 1 ]]; then
      for ((i=1; i<$repNum; i++)); do
        ctlName[$i]="${ctlName[0]}"
        ctlMinLen[$i]=${ctlMinLen[0]}
      done
  fi

  # Trimming
  echo "Trimming ..."
  if [[ $repNum -gt 0 && $ctlNum -gt 0 ]]; then
      for ((i=0; i<$repNum; i++)); do
        trimLenTmp=$(Min ${repMinLen[$i]} ${ctlMinLen[$i]})
        TrimSE "${repName[$i]}" "$trimLenTmp" "$isOrigName" "$resDir"
        TrimSE "${ctlName[$i]}" "$trimLenTmp" "$isOrigName" "$resDir"
      done
  fi

  if [[ $repNum -gt 0 && $ctlNum -eq 0 ]]; then
      for ((i=0; i<$repNum; i++)); do
        TrimSE "${repName[$i]}" "${repMinLen[$i]}" "$isOrigName" "$resDir"
      done
  fi

  if [[ $ctlNum -gt 0 && $repNum -eq 0 ]]; then
      for ((i=0; i<$ctlNum; i++)); do
        TrimSE "${ctlName[$i]}" "${ctlMinLen[$i]}" "$isOrigName" "$resDir"
      done
  fi

  if [[ $dnaseNum -gt 0 ]]; then
      for ((i=0; i<$dnaseNum; i++)); do
        TrimSE "${dnaseName[$i]}" "${dnaseMinLen[$i]}" "$isOrigName" "$resDir"
      done
  fi
  echo "Done!"
fi


## Prepare tar to move results back
tar -czf "$outTar" "$resDir"
if [[ $? -ne 0 ]]; then
    ErrMsg "Cannot create a $outTar"
fi


# Has to hide all unnecessary files in tmp directories
if [[ "$isDry" = false ]]; then
    mv !("$resDir") "$resDir"
    mv "$resDir"/_condor_std* ./
    mv "$resDir/$outTar" ./
fi

echo "[End]  $curScrName"
EchoLineBold
exit 0
