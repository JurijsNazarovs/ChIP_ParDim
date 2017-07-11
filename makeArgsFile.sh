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
scriptsPath="$homePath/ParDimLibs"
source "$scriptsPath"/funcList.sh

curScrName="${0##*/}" #delete last backSlash

EchoLineBold
echo "[Start] $curScrName"

EchoLineSh
lenStr=${#curScrName}
lenStr=$((25 + lenStr))
printf "%-${lenStr}s %s\n"\
        "The location of $curScrName:"\
        "$homePath"
printf "%-${lenStr}s %s\n"\
        "The $curScrName is executed from:"\
        "$PWD"
EchoLineSh


## Input and default values
argsFile="${1:-args.ChIP}"
argsFile="$(readlink -m "$argsFile")"
shift
isAppend="${1:-false}"
ChkValArg "isAppend" "" "true" "false"
shift
tasks=("$@")


## Creating the argsFile
if ! [[ -f "$argsFile" && "$isAppend" = true ]]; then
    echo "File $argsFile is creating"
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
      printf "%-${maxLenStr}s %s\n" "exePath" "$scriptsPath/exeTrim.sh"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "funcList" "$scriptsPath/funcList.sh"\
             >> "$argsFile"
      printf "\n" >> "$argsFile"
      
      printf "%-${maxLenStr}s %s\n" "isInpNested" "false"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "inpExt" "fastq.gz"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "inpType" "rep, ctl"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "isOrigName" "true"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "trimLen" ""\
             >> "$argsFile"

      printf "\n" >> "$argsFile"
      continue
  fi

  if [[ "$task" = makeToTagDag ]]; then
      maxLenStr=30
      printf "##[ $task ]##\n" >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "exePath" "$scriptsPath/exeAquas.sh"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "funcList" "$scriptsPath/funcList.sh"\
             >> "$argsFile"
      printf "\n" >> "$argsFile"
      
      printf "%-${maxLenStr}s %s\n" "isInpNested" "false"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "inpExt" "bam"\
             >> "$argsFile"

      printf "\n" >> "$argsFile"
      continue
  fi

  if [[ "$task" = makeIsCtlPoolDag ]]; then
      maxLenStr=30
      printf "##[ $task ]##\n" >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "exePath" "$scriptsPath/exeIsCtlPool.sh"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "funcList" "$scriptsPath/funcList.sh"\
             >> "$argsFile"
      printf "\n" >> "$argsFile"
      
      printf "%-${maxLenStr}s %s\n" "isInpNested" "true"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "inpExt" "tagAlign.gz"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "ctlDepthRatio" "1.2"\
             >> "$argsFile"

      printf "\n" >> "$argsFile"
      continue
  fi

  if [[ "$task" = makeAquasDag ]]; then
      maxLenStr=30
      printf "##[ $task ]##\n" >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "exePath" "$scriptsPath/exeAquas.sh"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "funcList" "$scriptsPath/funcList.sh"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "postScript" "$scriptsPath/postScript.sh"\
             >> "$argsFile"
      printf "\n" >> "$argsFile"

      printf "%-${maxLenStr}s %s\n" "isInpNested" "true"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "inpExt" "nodup.tagAlign.gz"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "firstStage" "pseudo"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "lastStage" "idroverlap"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "trueRep" "false"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "coresPeaks" "1"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "coresStg" "1"\
             >> "$argsFile"
      printf "\n" >> "$argsFile"
      
      printf "%-${maxLenStr}s %s\n" "specName" "hg19"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "specList" "$homePath/species.list"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "chrmSz" "$homePath/species/hg19.chrom.sizes"\
             >> "$argsFile"
      printf "%-${maxLenStr}s %s\n" "blackList" "$homePath/species/blackList.bed"\
             >> "$argsFile"

      printf "\n" >> "$argsFile"
      continue
  fi

  WarnMsg "Task $task is not recognised"
done

## End
echo "[End]  $curScrName"
EchoLineBold
