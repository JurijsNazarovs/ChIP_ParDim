#!/bin/bash
#========================================================
# File contains description of different functions
#========================================================


## Different printing lines
EchoLine(){
  echo "-------------------------------------------------------------------------------------"
}

EchoLineSh(){
  echo "----------------------------------------"
}

EchoLineBold(){
  echo "====================================================================================="
}

EchoLineBoldSh(){
  echo "========================================"
}

PrintfLine(){
  #printf "#"
  #printf -- "-%.0s" $(seq 1 85)
  #printf "\n"
  printf "#--------------------------------------------------------------------------------\n"
}

PrintfLineSh(){
  printf "#----------------------------------------\n"
}

PrintfLineBold(){
  printf "#================================================================================\n"
}

PrintfLineBoldSh(){
  printf "#========================================\n"
}


## Base functions. Functions, which are included in other

RmSp(){
  # Function returns the same line but without any spaces
  # Execution: $(RmSp "hui. t ebe"))
  echo "$1" | tr -d '\040\011\012\015'
}

JoinToStr(){
  # Join all element of an array in one string
  # $1 is the splitting character
  # >$1 everything to combine (spaces are skipped)
  # Usage: JoinToStr "\' \'" "$a" "$b" ... or ("$a[@]")
  local spC=$1
  shift

  local args="$1"
  shift

  local i
  for i in "$@"; do
    if [[ -n $(RmSp "$i") ]]; then
         args="$args$spC$i"
    fi
  done

  echo "$args"    
}

WarnMsg(){
  # Function displays an error message $1 and returns exit code $2
  # Use:  errMsg "Line1!
  #               Line2" 1
  # Function replace \n[\t]+ with \n, so, no tabs.
  # It is done to make code beautiful, so that in code I can put tabs.
  msg=${1:-"Default message about warning"}

  echo "*******************************************"  >> /dev/stderr

  local strTmp="WARNING!\n$msg\n"
  # Replace \n[\t]+ with \n
  printf "$strTmp" | sed -e ':a;N;$!ba;s/\n[ \t]\+/\n/g' >> /dev/stderr
  
  echo "*******************************************"  >> /dev/stderr
}

ErrMsg(){
  # Function displays an error message $1 and returns exit code $2
  # Use:  ErrMsg "Line1!
  #               Line2" 1
  # Function replace \n[\t]+ with \n, so, no tabs.
  # It is done to make code beautiful, so that in code I can put tabs.
  local msg=${1:-"Default message about an error"}
  local exFl=${2:-"1"} #default exit code

  EchoLineBoldSh >> /dev/stderr
  
  local strTmp="ERROR!\n$msg\n"
  # Replace \n[\t]+ with \n
  printf "$strTmp" | sed -e ':a;N;$!ba;s/\n[ \t]\+/\n/g' >> /dev/stderr
  
  EchoLineBoldSh >> /dev/stderr
  exit $exFl
}

## Some functions - still not sure about name
GetNumLines(){
  # Function returns number of lines in the file
  fileName=$1

  if [[ "${fileName##*.}" = "gz" ]]; then
      echo "$(zcat $fileName | wc -l)"
  else
    echo "$(cat $fileName | wc -l)"
  fi
}

Max(){
  # Function returns the maximum element among the input
  # Input: max 1 2 3 4 5 Or max ${arr[@]}
  local res=$1
  shift 
  local i

  for i in $@
  do
    ((i > res)) && res="$i"
  done

  echo "$res"
}

Min(){
  # Function returns the minimum element among the input
  # Input: min 1 2 3 4 5 Or min ${arr[@]}
  local res=$1
  shift
  local i

  for i in $@
  do
    ((i < res)) && res="$i"
  done

  echo "$res"
}


## Status functions. Functions, which check some conditions (boolean)
ChkEmptyArgs(){
  ## Function checks if any of arguments is empty.
  # Usage: ChkEmptyArgs "${argLab[@]}"
  # Empty args are missed, e.g. ChkEmptyArgs "" "a" => 1-st value is skipped
  local argLab
  local arg
  
  for argLab in "$@"
  do
    if [[ -z $(RmSp "$argLab") ]]; then
        WarnMsg "One of args provided to ChkEmptyArgs is empty
                or consists of spaces."
        continue
    fi

    eval arg='$'$argLab
    if [[ -z $(RmSp "$arg") ]]; then
        ErrMsg "Input argument \"$argLab\" is empty"
    fi
  done
}

ChkValArg(){
  ## Function checks if $argLab($1) has one of following valuesm and add msg($2)
  # in ErrMsg.
  # Usage: ChkValyArg "isSubmit" "msg" "1" "0" "-1"
  local argLab=${1}
  if [[ -z $(RmSp "$argLab") ]]; then
      ErrMsg "Argument provided tp ChkValArg is empty
                or consists of spaces."
      continue
  fi
  shift
  local msg=${1}
  shift
  local vals=("$@")
  if [[ "${#vals[@]}" -eq 0 ]]; then
      ErrMsg "No possible values are provided"
  fi

  eval arg='$'$argLab #get the value assigned to argLab
  
  local i isWrong=true
  for i in "${vals[@]}"; do
    if [[ "$arg" == "$i" ]]; then
        isWrong=false
        break
    fi
  done
  
  if [[ "$isWrong" = "true" ]]; then
    local strTmp=$(JoinToStr "\", \"" "${vals[@]}")
    ErrMsg "${msg}The value of $argLab = $arg is not recognised.
            Possible values are: \"$strTmp\".
            Please, check the value."
  fi
}

ChkExist(){
  # $1 - input type: d,f,etc
  # $2 - path to the folder, file, etc
  # $3 - label to show in case of error
  # Usage: ChkExist f "$script" "Script for task: $script\n"

  local inpLbl="$3"
  if [[ -z $(RmSp "$inpLbl") ]]; then
      inpLbl="$2"
  fi

  if [[ -z $(RmSp "$2") ]]; then
      ErrMsg "$inpLbl is empty."
  else
    if [ ! -$1 "$2" ]; then 
        ErrMsg "$inpLbl does not exist."
    fi
  fi
}

ChkAvailToWrite(){
  ## Function checks if it is possible to write in path $1
  # Usage: ChkAvailToWrite "inpPath" "outPath"
  ChkEmptyArgs "$@"

  local pathLab
  local path
  local outFile
  for pathLab in "$@"; do
    eval path='$'$pathLab
    outFile=$(mktemp -q "$path"/outFile.XXXXXXXXXX.) #try to create file inside
    if [[ -z $(RmSp "$outFile") ]]; then
        ErrMsg "Impossible to write in $path"
    else
      rm -rf "$outFile" #delete what we created
    fi
  done
}

ChkUrl(){
  local string=$1
  local regex='^(https?|ftp|file)://'
  regex+='[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-‌​A-Za-z0-9\+&@#/%=~_|‌​]$'
  if [[ $string =~ $regex ]]
  then 
      echo "true"
  else
    echo "false"
  fi
}

ChkStages(){
  local fStage=$1
  local lStage=$2
  if [[ "$fStage" -eq -1 ]]; then
      ErrMsg "First stage is not supported." 
  fi

  if [[ "$lStage" -eq -1 ]]; then
      ErrMsg "Last stage is not supported."
  fi

  if [[ "$ftStage" -gt "$lStage" ]]; then 
      ErrMsg "First stage cannot be after the last stage."
  fi
}


## Mapping functions
InterInt(){
  # Function intersect 2 intervals
  # Is used to find inclussion of stages
  # output: 1-intersect, 0 -no
  
  if [ "$#" -ne 2 ]; then
      ErrMsg "Wrong input! Two intervals has to be provided and not $# value(s)"
  fi

  local a=($1) 
  local b=($2)
  
  if [[ ${#a[@]} -ne 2 || ${#b[@]} -ne 2 ]]; then
      ErrMsg "Wrong input! Intervals shoud have 2 finite boundaries"
  fi

  local aMinVal=$(Min ${a[@]})
  local aMaxVal=$(Max ${a[@]})
  local bMinVal=$(Min ${b[@]})
  local bMaxVal=$(Max ${b[@]})

  local maxMinVal=$(Max $aMinVal $bMinVal)
  local minMaxVal=$(Min $aMaxVal $bMaxVal)
  
  if [ $maxMinVal -le $minMaxVal ]; then
      echo 1
  else
    echo 0
  fi
} 

ArrayGetInd(){ 
  # Function returns all indecies of elements (for every element in array)
  # founded in array (exactly or contain, to search for containing,
  # element should be provided with *, for example: peak*)
  # Input: size of "elements to find", elements, array
  # Output: array of indecies 
  # Use: readarray -t ind <<<\
  #               "$(ArrayGetInd "{#elem[@]}" "${elem[@]}" "${array[@]}")"

  local nElem=${1:-""}
  shift
  local elem
  local tmp
  while (( nElem -- > 0 )) ; do
    tmp="$1"
    elem+=( "$tmp" )
    shift
  done
  local array=("$@")
  #if [[ ${#array[@]} -eq 0 ]]; then
  #    ErrMsg "ArrayGetInd: Array is empty"
  #fi


  local i j
  for i in "${elem[@]}"; do
    for j in "${!array[@]}";  do
      if [[ "${array[$j]}" == $i ]]; then
          printf "$j\n"
      fi
    done
  done
}

ArrayDelInd(){
  # Function returns an array $3-... without the indecies $2 (array of indecies)
  # Output: array without indecies
  # Use: readarray -t varsList <<<\
  #       "$(ArrayDelInd "${#indicies[@]}" "${indecies[@]}" "${array[@]}")"

  local nIndDel=${1:-""}
  shift
  local indDel
  local tmp
  while (( nIndDel -- > 0 )) ; do
    tmp="$1"
    indDel+=( "$tmp" )
    shift
  done
  local array=("$@")

  local ind=($(echo "${indDel[@]}" "${!array[@]}" |
                   tr " " "\n" |
                   sort |
                   uniq -u))
  local i
  for i in "${ind[@]}"; do
    printf -- "${array[$i]}\n"
  done
}

ArrayDelElem(){
  # Function returns an array $3,... without the elements $2 - array
  # Output: array without deleted elements
  # Use:readarray -t arrayNoElem <<<\
  #              "$(ArrayDelElem "{#elems[@]}" "${elems[@]}" "${array[@]}")"
  local nElem=${1:-""}
  shift
  local elem
  local tmp
  while (( nElem -- > 0 )) ; do
    tmp="$1"
    elem+=( "$tmp" )
    shift
  done
  local array=("$@")

  readarray -t indToDel <<<\
            "$(ArrayGetInd "${#elem[@]}" "${elem[@]}" "${array[@]}")"
  readarray -t arrayNoElem <<<\
            "$(ArrayDelInd "${#indToDel[@]}" "${indToDel[@]}" "${array[@]}")"
  local i
  for i in "${arrayNoElem[@]}"; do
    printf -- "$i\n"
  done
}

ArrayGetDupls(){
  # Function returns an array of duplicates from an input array
  # Function ignores spaces. So, if just spaces are duplicated, then
  # nothing will be returned.
  # Use:readarray -t arrayDupls <<< "$(ArrayGetDupls "${array[@]}")"
  
  local array=("$@")
  local arrayNoDupl
  arrayNoDupl=($(echo "${array[@]}" | tr " " "\n" | sort | uniq))
  if [[ ${#arrayNoDupl[@]} -ne ${#array[@]} ]]; then
      local arrayUniq arrayDupl
      # Just values which are repeated once
      arrayUniq=($(echo "${array[@]}" | tr " " "\n" | sort | uniq -u))
      arrayDupl=($(echo "${arrayNoDupl[@]}" "${arrayUniq[@]}" |
                         tr " " "\n" |
                         sort |
                         uniq -u))
      local i
      for i in "${arrayDupl[@]}"; do
        printf -- "$i\n"
      done
  fi
}

ReadArgs(){
  # Function ReadArgs() read arguments from the file $1 according to
  # label ##[ scrLab ]## and substitute values in the code.
  # Example, in the file we have: foo     23
  # then in the code, where this file sourced and function ReadArgs is called
  # "echo $foo" returns 23.
  #
  # If the variable is defined before reading file, and in file it is empty,
  # then default value remains.
  #
  # If no labels find at all, the whole file is read.
  #
  # Input:
  #       -argsFile   file with arguments
  #       -scrLabNum  number of script labels
  #       -scrLabList vector of name of scripts to search for arguments
  #        based on the patern: ##[    scrLab  ]## - Case sensetive. Might be
  #        spaces before, after and inside, but cannot split scrLab..
  #        If scrLab = "", the whole file is searched for arguments,
  #        and the last entry is selected
  #       -posArgNum  number of arguments to read
  #       -posArgList possible arguments to search for
  #       -reservArg  reserved argument which can't be duplicated
  #       -isSkipLabErr true = no error for missed labels, if other labels
  #        exist. No arguments are read.
  #
  # args.list has to be written in a way:
  #      argumentName(no spaces) argumentValue(spaces, tabs, any symbols)
  # That is after first column space has to be provided!
  #
  # Use: ReadArgs "$argsFile" "$scrLabNum" "${scrLabList[@]}"\
  #               "$posArgsNum" "${posArgs[@]}" "$reservArg" "$isSkipLab"

  ## Input
  local argsFile="$1"
  ChkExist "f" "$argsFile" "File with arguments"
  shift

  # Get list of labels to read
  local scrLabNum=${1:-"0"} #0-read whole file
  shift

  local scrLabList
  local scrLab
  if [[ $scrLabNum -eq 0 ]]; then
      scrLabList=""
  else
    while (( scrLabNum -- > 0 )) ; do
      scrLab="$1"
      if [[ $(RmSp "$scrLab") != "$scrLab" ]]; then
          ErrMsg "Impossible to read arguments for \"$scrLab\".
                  Remove spaces: $scrLab"
      fi

      scrLabList+=( "$scrLab" )
      shift
    done
  fi

  # Get list of arguments to read
  local posArgNum=${1:-"0"} 
  shift
  if [[ $posArgNum -eq 0 ]]; then
      ErrMsg "No arguments to read from $argsFile"
  fi

  local posArgList
  local posArg
  if [[ $posArgNum -eq 0 ]]; then
      posArgList=""
  else
    while (( posArgNum -- > 0 )) ; do
      posArg="$1"
      if [[ $(RmSp "$posArg") != "$posArg" ]]; then
          ErrMsg "Possible argument cannot have spaces: $posArg"
      fi

      posArgList+=( "$posArg" )
      shift
    done
  fi

  # Other inputs
  local reservArg=${1:-""}
  shift

  local isSkipLabErr=${1:-"false"}
  shift

  if [[ "$isSkipLabErr" != true && "$isSkipLabErr" != false ]]; then
      WarnMsg "The value of isSkipLabErr = $isSkipLabErr is not recognised.
               Value false is assigned"
  fi

  # Detect start and end positions to read between and read arguments
  local scrLab
  for scrLab in "${scrLabList[@]}"; do
    local rawStart="" #will read argFile from here
    local rawEnd="" #until here

    if [[ -n "$scrLab" ]]; then
        local awkPattern
         awkPattern="\
^([[:space:]]*##)\
\\\[[[:space:]]*$scrLab+[[:space:]]*\\\]\
(##[[:space:]]*)$\
"
        readarray -t rawStart <<<\
                  "$(awk -v pattern="$awkPattern"\
                   '{
                     if ($0 ~ pattern){
                        print (NR + 1)
                     }
                    }' < "$argsFile"
                    )"
        
        if [[ ${#rawStart[@]} -gt 1 ]]; then
            rawStart=("$(JoinToStr ", " "${rawStart[@]}")")
            ErrMsg "Impossible to detect arguments for $scrLab
                   in $argsFile.
                   Label: ##[ $scrLab ]## appears several times.
                   Lines: $rawStart"
        fi

        if [[ -n "$rawStart" ]]; then
            readarray -t rawEnd <<<\
                      "$(awk -v rawStart="$rawStart"\
                       '{ 
                         if (NR < rawStart) {next}
 
                         gsub (" ", "", $0)
                         if ($0 ~ /^##\[.*\]##$/){
                          print (NR - 1)
                          exit
                         }
                        }' < "$argsFile"
                     )"
        else
          # Check if any other labels appear. rawEnd here is label, not number
          readarray -t rawEnd <<<\
                    "$(awk\
                      '{
                        origLine = $0
                        gsub (" ", "", $0)
                        if ($0 ~ /^##\[.*\]##$/){
                           print origLine
                        }
                       }' < "$argsFile"
                     )"
          
          if [[ -n "$rawEnd" ]]; then
              if [[ "$isSkipLabErr" = true ]]; then
                  return "2"
              else
                rawEnd=("$(JoinToStr ", " "${rawEnd[@]}")")
                ErrMsg "Can't find label: ##[ $scrLab ]## in $argsFile,
                        while other labels exist:
                        $rawEnd"    
              fi
          fi
        fi
        
    fi

    if [[ -z "$rawStart" ]]; then
        rawStart=1
    fi

    if [[ -z "$rawEnd" ]]; then
        rawEnd=$(awk 'END{print NR}' < "$argsFile")
    fi

    if [[ "$rawStart" -gt "$rawEnd" ]]; then
        ErrMsg "No arguments after ##[ $scrLab ]## 
                in $argsFile!"
    fi
    
    EchoLineSh
    if [[ -n "$scrLab" ]]; then
        echo "Reading arguments in $scrLab section from $argsFile"
    else
      echo "Reading arguments from $argsFile"
    fi
    echo "Starting line: $rawStart"
    echo "Ending line:   $rawEnd"
    
    declare -A varsList #map - array, local by default
    
    # Read files between rawStart and rawEnd lines, skipping empty raws
    declare -A nRepVars #number of repetiotions of argument
    local firstCol
    local restCol
    
    while read -r firstCol restCol #because there might be spaces in names
    do
      if [[ -n $(RmSp "$firstCol") ]]; then
          nRepVars["$firstCol"]=$((nRepVars["$firstCol"] + 1))
          #((nRepVars["$firstCol"]++)) #- does not work
          varsList["$firstCol"]="$(sed -e "s#[\"$]#\\\&#g" <<< "$restCol")"
      fi
    done <<< "$(awk -v rawStart=$rawStart -v rawEnd=$rawEnd\
              'NF > 0 && NR >= rawStart; NR == rawEnd {exit}'\
              "$argsFile")"

    # Assign variables
    local strTmp
    if [[ -n "$scrLab" ]]; then
        strTmp="Section $scrLab in $argsFile:\n"
    fi
    
    local i
    for i in ${posArgList[@]}; do
      # Checking
      if [[ ${nRepVars[$i]} -eq 0 ]]; then
          # Trying to read an argument which is not in args.file
          # WarnMsg "No mention of $i"
          continue
      fi

      if [[ ${nRepVars[$i]} -gt 1 ]]; then
          if [[ "$i" = "$reservArg" ]]; then
              ErrMsg "${strTmp}Argument $i is repeated ${nRepVars[$i]} times.
                      $i - reserved argument and cannot be duplicated."
          fi
          
          WarnMsg "${strTmp}Argument $i is repeated ${nRepVars[$i]} times.
                   Last value is recorded: $i = ${varsList[$i]} ."
      fi
      
      # If assigned value is empty, then do not assign anything
      if [[ -n $(RmSp "${varsList[$i]}") ]]; then
          eval $i='${varsList[$i]}' #define: parameter=value
          exFl=$?
          if [ $exFl -ne 0 ]; then
              ErrMsg "${strTmp}Cannot read the parameter: $i=${valsList[$ind]}"
          fi
      else
        local defValue
        eval defValue="\$$i"
        if [[ -n $(RmSp "$defValue") ]]; then
            WarnMsg "${strTmp}The value of argument $i is empty.
                     Default value is assigned: $i = $defValue ."
        else
          WarnMsg "${strTmp}The value of argument $i is empty."
        fi
      fi
    done
  done
  EchoLineSh
}

PrintArgs(){
  ## Print arguments for the "current" script
  ## Use: PrintArgs "$scriptName" "${posArgs[@]}"
  local curScrName=$1
  shift 

  local posArgs=("$@")
  local maxLenArg=() #detect maximum argument length

  for i in ${!posArgs[@]};  do
    maxLenArg=(${maxLenArg[@]} ${#posArgs[$i]})
  done
  maxLenArg=$(Max ${maxLenArg[@]})

  ## Print
  EchoLineSh
  if [[ -n $(RmSp "$curScrName") ]]; then
      echo "Arguments for $curScrName:"
  else
    echo "Arguments"
  fi
  EchoLineSh
  
  local i
  local argSize
  for i in ${posArgs[@]}
  do
    #eval argSize="\${#$i[@]}"
    #echo "$argSize"
    eval "printf \"%-$((maxLenArg + 3))s %s \n\"\
                 \"- $i\" \"$"$i"\" "
  done
  EchoLineSh
}

mk_dir(){ #Delete. 
  # Function is alias to real mkdir -p, but which proceeds an exit flag in a
  # right way.

  local dirName=$1
  if [[ -z $(RmSp "$dirName") ]]; then
      ErrMsg "Input is empty"
  fi

  mkdir -p "$dirName"
  exFl=$?
  if [ $exFl = 0 ]; then
      echo "$dirName is created"
  else
    ErrMsg "Error: $dirName not created"
  fi
}
