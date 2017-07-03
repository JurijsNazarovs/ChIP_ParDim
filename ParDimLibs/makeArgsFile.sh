#!/bin/bash
#===============================================================================
# This script creates an argument file for ParDim stages for a ChIP-Seq
# analysis. It covers following stages:
#   - makeTrimDag
#   - makeToTagDag
#   - makeIsCtlPoolDag
#   - makeAquasDag
#
# It is important to run this script first to create right pathed for libraries.
#
# Input:
#   - argsFile - output file with arguments
#   - isAppend - true => append  to existing argsFile, false => rewrite.
#                Default is false
#   - list all interesting stages using spaces.
#==============================================================================
## Libraries and options
shopt -s nullglob #allows create an empty array
homePath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" 
source "$homePath"/funcList.sh

curScrName=${0##*/} #delete last backSlash

EchoLineBold
echo "[Start] $curScrName"
EchoLineSh
printf "%-35s %s\n"\
        "The location of $curScrName:"\
        "$homePath"
printf "%-35s %s\n"\
        "The $curScrName is executed from:"\
        "$PWD"
EchoLineSh


## Input and default values
argsFile=${1:-"args.listDev"}
argsFile="$(readlink -m "$argsFile")"
shift
isAppend=${1:-"false"}
shift
tasks=("$@")


## Creating the argsFile
if ! [[ -f "$argsFile" && "$isAppend" = true ]]; then
    echo "File $argsFile is created"
    printf "" > "$argsFile"
else
  echo "$argsFile is going to be updated"
  printf "\n" >> "$argsFile"
fi
EchoLineSh


for task in "${tasks[@]}"; do
  if [[ "$task" = makeTrimDag ]]; then
      maxLenStr=30
      printf "##[ $task ]##\n" >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "exePath" "$homePath/exeTrim.sh"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "funcList" "$homePath/funcList.sh"\
             >> "$argsFile"
      printf "\n" >> "$argsFile"
      printf "isInpNested\n" >> "$argsFile"
      printf "inpExt\n" >> "$argsFile"
      printf "inpType\n" >> "$argsFile"
      printf "trimLen\n" >> "$argsFile"
      printf "isOrigName\n" >> "$argsFile"

      printf "\n" >> "$argsFile"
      continue
  fi

  if [[ "$task" = makeToTagDag ]]; then
      maxLenStr=30
      printf "##[ $task ]##\n" >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "exePath" "$homePath/exeAquas.sh"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "funcList" "$homePath/funcList.sh"\
             >> "$argsFile"
      printf "\n" >> "$argsFile"
      printf "isInpNested\n" >> "$argsFile"
      printf "inpExt\n" >> "$argsFile"

      printf "\n" >> "$argsFile"
      continue
  fi

  if [[ "$task" = makeIsCtlPoolDag ]]; then
      maxLenStr=30
      printf "##[ $task ]##\n" >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "exePath" "$homePath/exeIsCtlPool.sh"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "funcList" "$homePath/funcList.sh"\
             >> "$argsFile"
      printf "\n" >> "$argsFile"
      printf "isInpNested\n" >> "$argsFile"
      printf "ctlDepthRatio\n" >> "$argsFile"

      printf "\n" >> "$argsFile"
      continue
  fi

  if [[ "$task" = makeAquasDag ]]; then
      maxLenStr=30
      printf "##[ $task ]##\n" >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "exePath" "$homePath/exeTrim.sh"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "funcList" "$homePath/funcList.sh"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "postScript" "$homePath/postScript.sh"\
             >> "$argsFile"
      printf "\n" >> "$argsFile"
      printf "isInpNested\n" >> "$argsFile"
      printf "inpExt\n" >> "$argsFile"
      printf "firstStage\n" >> "$argsFile"
      printf "lastStage\n" >> "$argsFile"
      printf "trueRep\n" >> "$argsFile"
      printf "coresPeaks\n" >> "$argsFile"
      printf "coresStg\n" >> "$argsFile"
      printf "\n" >> "$argsFile"
      printf "specName\n" >> "$argsFile"
      printf "specList\n" >> "$argsFile"
      printf "chrmSz\n" >> "$argsFile"
      printf "blackList\n" >> "$argsFile"

      printf "\n" >> "$argsFile"
      continue
  fi

  WarnMsg "Task $task is not recognised"
done

## End
echo "[End]  $curScrName"
EchoLineBold
