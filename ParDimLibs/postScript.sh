#!/bin/bash
#===============================================================================
# This is a POST SCRIPT for condor job, which "clean" files after job is done.
# It is executed in the same directory as condor job.
# Example JOB1 1.condor DIR dagTmp =>
# => post script job is executed in dagTmp
#===============================================================================
## Libraries/Input
shopt -s nullglob #allows create an empty array
homePath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" #cur. script locat.
source "$homePath"/funcList.sh
curScrName=${0##*/}

task="${1,,}" #${a,,} = lower case
shift

UntarFiles(){
  # Usage: UntarFile "${files[@]}"
  local files=("$@")
  local file exFl
  local outPath
  
  for file in "${files[@]}"; do
    ChkExist f "$file" "File to untar: $file"
    outPath="$(dirname "$file")"
    
    tar -xzf "$file" -C "$outPath"
    exFl=$?
    if [[ "$exFl" -ne 0 ]]; then
        ErrMsg "$file cannot be unzip" "$exFl"
    else
      rm -rf "$file"
    fi
  done
}

FillListOfDirs(){
  local inpPath="${1}"
  local outfile="$2"
  ChkEmptyArgs "outfile" "inpPath"
  ls -d "$inpPath/"*/ > "$outfile"
  if [[ "$?" -ne 0 ]]; then
      ErrMsg "Something went wrong with filling the list $outfile.
               Error: $?" "$?"
  fi
}

FillListOfContent(){
  local inpFile="$1"
  local outFile="$2"
  ChkEmptyArgs "inpFile" "outFile"

  printf ""  > "$outFile"
  while IFS='' read -r dirPath || [[ -n "$dirPath" ]]; do
    ls -lR "$dirPath" |
        awk\
    '{
        if ($0 ~ "total.*") {next}
        if (NF > 2) {print $9 "\t" $5}
        if (NF == 1) {print}
     }' >> "$outFile"
  done < "$inpFile"
}

## Main part - selection based on task
EchoLineBold
echo "[Start] $curScrName"
EchoLineSh
echo "Task is $task"
EchoLineSh
echo "$PWD"

# Fill list with directories from inpPath
if [[ "$task" = filllistofdirs ]]; then
    #1: inpDir, #2: outFile
    FillListOfDirs "$1" "$2"
    exit 0
fi

# Fill list with all content of directories from file
if [[ "$task" = filllistofcontent ]]; then
    #1: inpFile, #2: outFile
    FillListOfContent "$1" "$2"
    exit 0
fi

# Fill list of dirs and create file with content
if [[ "$task" = filllistofdirsandcontent ]]; then
    #1: inpDir, #2: outFile
    FillListOfDirs "$1" "$2"
    #1: inpFile, #2: outFile
    FillListOfContent "$2" "$3"
    exit 0
fi

# Untar files by providing files
if [[ "$task" = untarfiles ]]; then
    UntarFiles "$@"
    exit 0
fi

# Untar files from directory
if [[ "$task" = untarfilesfromdir ]]; then
    dirPath=$1
    ChkAvailToWrite "dirPath"
    files=("$dirPath"/*.tar.gz)
    if [[ "${#files[@]}" -eq 0 ]]; then
        echo "No .tar.gz files in $dirPath"
        exit 0
    fi
    UntarFiles "${files[@]}"
    exit 0
fi

ErrMsg "Unfamiliar task. Possible tasks are:
       FillListOfDirs - fill a list with all directories of inpPath
       UntarFiles - untar all files
       UNtarFilesFromDir - untar files in a specific directory"

echo "[End] $curScrName"
EchoLineBold
