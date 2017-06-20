#!/bin/bash
#===============================================================================
# This script decides if ctl files have to be pooled or not
#
# Input: strings with names of files joined by comma
#	- ctlName
#       - repName
# Output: file, which says pool or notspecific ctl file		
#===============================================================================
## Libraries and options
shopt -s nullglob #allows create an empty array
shopt -s extglob #to use !
source "./funcList.sh" #need to transfer

curScrName=${0##*/} #delete last backSlash
EchoLineBold
echo "[Start] $curScrName"


## Input and default values
repName=$1
ctlName=$2
resDir=${3:-"resDir"}
outTar=${4:-"isPool.tar.gz"} #tarFile to return back on submit machine
ctlDepthRatio=${5:-"1.2"}
isDry=${6:-true}

readarray -t repName <<< "$(echo "$repName" | tr "," "\n")"


## Create a structure for ctlFiles to do the right output
mkdir -p "$resDir"
if [[ $? -ne 0 ]]; then
    ErrMsg "Cannot create a $resDir"
fi

readarray -t ctlName <<< "$(echo "$ctlName" | tr "," "\n")"
for i in "${!ctlName[@]}"; do
  ctlDir["$i"]="$resDir/$(dirname "${ctlName[$i]}")" #directory for flagOutput
  mkdir -p "${ctlDir["$i"]}"
  if [[ $? -ne 0 ]]; then
      ErrMsg "Directory: ${ctlDir["$i"]}
             was not created"
  fi

  ctlName["$i"]="$(basename "${ctlName[$i]}")"
done


## Decision to use pooled ctl
ctlNum=${#ctlName[@]}
repNum=${#repName[@]}
useCtlPool=() #whether ctl[i]=pool or not
for ((i=0; i<$ctlNum; i++)); do
  useCtlPool[$i]="false"
done

if [[ $ctlNum -gt 1 ]]; then	
    nLinesRep="" # of lines in rep
    nLinesCtl="" # of lines in ctl

    for ((i=0; i<$repNum; i++)); do
      nLinesRep[i]=$(GetNumLines "${repName[$i]}")
      nLinesCtl[i]=$(GetNumLines "${ctlName[$i]}")

      if [[ ${nLinesRep[$i]} -eq 0 ]]; then
          ErrMsg "File ${repName[$i]}
                 contains 0 lines"
      fi

      if [[ ${nLinesCtl[$i]} -eq 0 ]]; then
          ErrMsg "File ${ctlName[$i]}
                 contains 0 lines"
      fi
    done

    nLinesCtlMax=$(Max ${nLinesCtl[@]})
    nLinesCtlMin=$(Min ${nLinesCtl[@]})
    isPool="$(echo ${nLinesCtlMax}/${nLinesCtlMin} | bc -l)"
    isPool="$(echo "$isPool > $ctlDepthRatio" | bc -l)"

    if [[ $isPool -eq 1 ]]; then
	for ((i=0; i<$ctlNum; i++)); do				
	  useCtlPool[$i]=true
	done
    else	
      for ((i=0; i<$ctlNum; i++)); do
	if [[ ${nLinesCtl[i]} -lt ${nLinesRep[i]} ]]; then
	    useCtlPool[$i]=true
	fi
      done
    fi
fi


## Create corresponding flag files for pooled ctl
for i in ${!useCtlPool[@]}; do
  touch "${ctlDir[$i]}/${ctlName[$i]}.pool.${useCtlPool[$i]}"
done


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
