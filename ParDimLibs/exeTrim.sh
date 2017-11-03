#!/bin/bash
#===============================================================================
# This script trims files based on common mimum length or set length
#
# Input: strings with names of files joined by comma
#       - repName
#	- ctlName
#	- dnaseName
#       - isOrigName: false => save with additional .trim.
# Output: trimmed files
#
# Possible trimming:
# 0. Use trimLen if provided
# 1. Detect min length for all files
# 2.1. rep > 0, ctl > 0: trim using min(minRep(i), minCtl(i))
# 2.2. rep > 0, ctl = 0: trim using minRep(i)
# 2.3. rep = 0, ctl > 0: trim using minCtl(i)
# 3. dnase > 0: trim using minDnase(i)
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
ls

TrimSE(){
  local fileInp=${1}
  local trimLen=${2}
  local isOrigName=${3:-false}
  local resDir=${4:-.}

  ## Detect output name
  local fileOut
  if [[ "$isOrigName" = true ]]; then
        fileOut="$resDir/$(basename "$fileInp")"
  else
    readarray -t fileOut <<< "$(echo "$fileInp" | tr "." "\n")"
    fileOut=($(JoinToStr "." "${fileOut[0]}" trim "${fileOut[@]:1}"))
    fileOut="$resDir/$(basename "$fileOut")"
  fi
  mkdir -p "$resDir"

  ## Trimming
  java -jar "$trimSoft" SE "$fileInp" "$fileOut"\
       CROP:"$trimLen"
  
  if [[ $? -ne 0 ]]; then
      if [[ -f "$fileOut"  ]]; then
          rm -rf "$fileOut"
      fi
      mv !("$resDir") "$resDir"
      mv "$resDir"/_condor_std* ./
      ErrMsg "$fileInp was not trimmed.
             Process is stopped."
  else
    echo "Trimmed: $fileInp -> $fileOut"
  fi
}


## Input and default values
name1=$1
useLink1=$2
linkName1=$3
name2=$4
useLink2=$5
linkName2=$6
trimLen=$7
isOrigName=${8:-"false"}
resDir=${9:-"trimResDir"}
outTar=${10:-"isPool.tar.gz"} #tarFile to return back on submit machine
softZip=${11:-"Trimmomatic-0.36.zip"}
#ram=${9:-1}
isDry=${12:-true}

posTypes=(1 2) #at least now code considers just 2 groups of files
#export _JAVA_OPTIONS="-Xms256M -Xmx512M -XX:ParallelGCThreads=1"
export _JAVA_OPTIONS="-Xms512M -Xmx1G -XX:ParallelGCThreads=1"

## Detect names and number of files for every type
for i in "${posTypes[@]}"; do
  eval "readarray -t tmpName <<< \"\$(echo \$name${i} | tr \",\" \"\n\")\""
  if [[ -z $(RmSp "$tmpName") ]]; then
      eval "num${i}=0"
  else
    eval "readarray -t tmpUseLink <<< \"\$(echo \$useLink${i} | tr \",\" \"\n\")\""
    eval "readarray -t tmpLinkName <<< \"\$(echo \$linkName${i} | tr \",\" \"\n\")\""
    for j in "${!tmpName[@]}"; do
      if [[ "${tmpUseLink[$j]}" != true ]]; then
          # if it is true, I do not send file to condor
          ChkExist f "${tmpName[$j]}" "Input file: ${tmpName[$j]}\n"
      fi
    done
    
    eval "num${i}=${#tmpName[@]}"
    eval "name${i}=(\"\${tmpName[@]}\")"
    eval "useLink${i}=(\"\${tmpUseLink[@]}\")"
    eval "linkName${i}=(\"\${tmpLinkName[@]}\")"
  fi
done


## Main part - trimming
unzip "$softZip"
if [[ $? -ne 0 ]]; then
    ErrMsg "Cannot unzip $softZip" "2"
else
  rm -rf "$softZip"
fi

## Define trimming length
if [[ -n "$trimLen" ]]; then
    # Update trimLenTmp just for non-zero group
    for ((i=0; i<$((num1 + num2)); i++)); do
      trimLenTmp[$i]="$trimLen"
    done
else
  # Detect the trimming length
  EchoLineSh
  echo "Detecting the trimming length ..."
  echo ""
  for i in "${posTypes[@]}"; do
    eval "tmpName=(\"\${name${i}[@]}\")"
    eval "tmpUseLink=(\"\${useLink${i}[@]}\")"
    
    if [[ -z "$tmpName" ]]; then
        continue
    fi

    for j in "${!tmpName[@]}"; do
      if [[ "${tmpUseLink[$j]}" = true ]]; then
          echo "Min of ${tmpName[j]}: skipped because it is a link"
          continue
      fi

      fileTmp="${tmpName[j]}"
      extTmp="${fileTmp##*.}"
      
      minLenTmp=$(awk  'NR==2 {print length($0); exit}' "$fileTmp")
      minLenTmp=$((if [[ "$extTmp" = gz ]]; then
                       gunzip -c "$fileTmp";
                   else
                     cat "$fileTmp";
                   fi)|\
                      awk -v minLen=$minLenTmp\
                      'NR%4 == 2 {if (length($0) < minLen){minLen = length($0)}}
                      END{print minLen}')

      eval "minLen$i[$j]=$minLenTmp"
      echo "Min of ${tmpName[j]}: $minLenTmp bp"
    done
  done
  echo "Done!"

  # Assign trimLenTmp to do trimming later
  # Copy length in case of several rep for an easy use
  # Have to fix to repeat same procedure for num2 and num1
  if [[ $num1 -gt 1 && $num2 -eq 1 ]]; then #chip then ctl
      for ((i=1; i<$num1; i++)); do
        name2[$i]="${name2[0]}"
        minLen2[$i]=${minLen2[0]}
      done
  fi

  if [[ $num1 -gt 0 && $num2 -gt 0 ]]; then #they have same size from above
      # Can be changed for a flag if more than 2 groups present
      for ((i=0; i<$num1; i++)); do
        trimLenTmp[$i]=$(Min ${minLen1[$i]} ${minLen2[$i]})
        trimLenTmp[$((i + num1))]=${trimLenTmp[$i]}
      done
  else
    # Update trimLenTmp just for non-zero group
    for i in "${posTypes[@]}"; do
      eval "numTmp=\$num$i"
      for ((j=0; j<$numTmp; j++)); do
        eval "minLenTmp=\${minLen$i[$j]}"
        trimLenTmp[$j]="$minLenTmp"
      done
    done
  fi
fi


## Trimming
echo "Trimming ..."
iter=0
for i in "${posTypes[@]}"; do
  eval "tmpName=(\"\${name${i}[@]}\")"
  if [[ -z "$tmpName" ]]; then
      continue
  fi
  eval "tmpUseLink=(\"\${useLink${i}[@]}\")"
  eval "tmpLinkName=(\"\${linkName${i}[@]}\")"

  for j in "${!tmpName[@]}"; do
    # Create a link instead of trimming
    if [[ "${tmpUseLink[$j]}" = true ]]; then
        mkdir -p "$resDir"
        ln -s "${tmpName[$j]}" "$resDir/${tmpLinkName[$j]}"
        ((iter++))
        continue
    fi

    # Rename target(original) file with link file for current experiment
    if [[ -n "${tmpLinkName[$j]}" ]]; then
        # Problem that several reps, ctls might have link to the same target,
        # so, when condor transfer the target it transfer just one of them.
        # But we still have to truncate them separately. Thus,
        # if there is duplicate of target files, then copy and mv the copy
        # if no duplicates, then just mv it.
        readarray -t ind <<<\
                  "$(ArrayGetInd "1" "${tmpName[$j]}" "${tmpName[@]:$j}")"
        if [[ "${#ind[@]}" -gt 1 ]]; then
            cp "${tmpName[$j]}" "${tmpLinkName[$j]}"
        else
          mv "${tmpName[$j]}" "${tmpLinkName[$j]}"
        fi
        tmpName[$j]="${tmpLinkName[$j]}"
    fi
    
    TrimSE "${tmpName[$j]}" "${trimLenTmp[$iter]}" "$isOrigName" "$resDir"
    ((iter++))
  done
done
echo "Done"

## Prepare tar to move results back
tar -cf "$outTar" "$resDir"
if [[ $? -ne 0 ]]; then
    ErrMsg "Cannot create a $outTar"
fi


# Has to hide all unnecessary files in tmp directories
if [[ "$isDry" = false ]]; then
    echo "Final step: moving files in $outTar"
    mv !("$resDir") "$resDir"
    mv "$resDir"/_condor_std* ./
    mv "$resDir/$outTar" ./
fi

echo "[End]  $curScrName"
EchoLineBold
exit 0
