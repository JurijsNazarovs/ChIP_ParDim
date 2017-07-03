#!/bin/bash
#===============================================================================
# This script creates a right version of a dag file of AQUAS pipeline,
# base on files in input directory (inpPath)
#
# The script supports a range of stages (first stage - last stage),
# according to which AQUAS pipeline should be executed and
# corresponding dag file should be constructed.

# This script can stop on any of a supported last stages, but 
# it CANNOT start with some first stage, if the script was not run
# until this first stage before.
# In other words, first stage works like a check point for current pipeline.
#
# Supported stages in an order:
#	- toTag. Not in this script, but in the whole pipeline
#	- pseudo
#	- xcor
#	- pool
#	- stgMacs2
#	- peaks
#	- idroverlap 
# Input:
#	- argsFile	 file with all arguments for this shell
#
# Possible arguments are described in a section: ## Default values		
#==============================================================================

## Libraries and options
shopt -s nullglob #allows create an empty array
homePath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" 
source "$homePath"/funcList.sh

curScrName=${0##*/} #delete last backSlash

MapStage(){
  # Function maps input to numbers for comparison purpose
  # Input is the stage
  case "$1" in
    "")             echo 0;;
    "pseudo")       echo 1;;
    "xcor")         echo 2;;
    "pool")         echo 3;;
    "stgMacs2")     echo 4;;
    "peaks")        echo 5;;
    "idroverlap")   echo 6;; #becasue search for a computer is about 3-5mins,
    #which is the time of idr
    *)              echo -1
  esac
}


## Input and default values
argsFile=${1:-"args.listDev"} 
dagFile=${2:-"aquas.dag"} #create this
jobsDir=${3:-"aquasTmp"} #working directory, provided with one of analysed dirs
resPath=${4:-"/tmp/aquas"} #return here on submit server. Read from file if empty
inpDataInfo=${5} #text file with input data
resDir=${6:-"resultedDir"} #directory where to save resutls
transOut=${7:-"aquas"}

outPath="$resPath/$resDir" #used as input for stages after job was done


## Default values, which can be read from the $argsFile
posArgs=("inpExt" "isInpNested" "firstStage" "lastStage" "trueRep"
         "coresPeaks" "coresStg"
         "exePath" "funcList" "postScript"
         "specName" "specList" "chrmSz" "blackList")

#rewrite stages!
inpExt="nodup.tagAlign.gz" #extension of original input data
isInpNested="true"	#if all files in one dir or in subdirs: rep$i, ctl$i
firstStage="download"	#starting stage of the pipeline 
lastStage="peaks"	#ending stage of the pipeline
trueRep="false"		#whether to use true replicates or not
coresPeaks="4"          #number of cores for spp peaks caller
coresStg="1"            #number of cores for signal track generation (Macs2) 
exePath="$homePath/exeAquas.sh"
funcList="$homePath/funcList.sh"
postScript="$homePath/postScript.sh"

specName="hg19"		#names of species: hg38, hg19, mm10, mm9 
specList="spec.list"	#list with all species
chrmSz="" #for stg and peaks
blackList="" #for peaks
softTar="pipeInstallFiles.new.tar.gz"
softSize=9

if [[ -z $(RmSp "$resPath") ]]; then
    posArgs=("${posArgs[@]}" "resPath")
fi

ReadArgs "$argsFile" "1" "${curScrName%.*}" "${#posArgs[@]}" "${posArgs[@]}"\
         > /dev/null
PrintArgs "$curScrName" "${posArgs[@]}" "jobsDir"

for i in exePath postScript funcList resPath; do
  eval "strTmp=\"\$$i\""
  if [[ "${strTmp:0:1}" != "/" ]]; then
    ErrMsg "The full path for $i has to be provided:
           Current value is: $strTmp"
  fi
done

firstStage=$(MapStage "$firstStage")
lastStage=$(MapStage "$lastStage")

ChkValArg "isInpNested" "" "true" "false"
ChkValArg "trueRep" "" "true" "false"

if [[ "$trueRep" = "false" ]]; then
    prNum=2 
else
  prNum=0
fi


## Stages
ChkStages "$firstStage" "$lastStage"

# Define names of stage
pseudoName="pseudo"
xcorName="xcor"
poolName="pool"
stgName="stgMacs2"
peakName="peaks"
idrName="idr"
overlapName="overlap"

# Map stageNames
pseudoStage=$(MapStage "$pseudoName")
xcorStage=$(MapStage "$xcorName")
poolStage=$(MapStage "$poolName")
stgStage=$(MapStage "$stgName")
peakStage=$(MapStage "$peakName")
idrOverlapStage=$(MapStage "$idrName$overlapName")


## Detect reps and ctls
if [[ "$lastStage" -gt "$poolStage" ]]; then
    isDetectPool=true
else
  isDetectPool=false
fi

DetectInput "$inpDataInfo" "2" "rep" "ctl" "$inpExt"\
            "$isInpNested" "true" "$isDetectPool"

if [[ "$repNum" -eq 0 ]]; then
    ErrMsg "Number of replicates has to be more than 0"
fi

if !([[ "$ctlNum" -eq 0 || "$ctlNum" -eq 1 || "$ctlNum" -eq "$repNum" ]]); then
    ErrMsg "Confusing number of ctl files.
            Number of ctl: $ctlNum
            Number of rep: $repNum"
fi


## Variables for future refences in stages after tag

# Ctl
if [[ "$inpExt" = nodup.tagAlign.gz ]]; then
    ctlTag=("${ctlName[@]}")
else
  ctlTag=()
  for ((i=0; i<$ctlNum; i++)); do
    resPathTmp="$outPath/align/ctl$((i+1))"
    ctlTag=("${ctlTag[@]}"
            "$resPathTmp/$(basename ${ctlName[$i]%.$inpExt}).nodup.tagAlign.gz")
  done
fi

# Copy values for an easy use if we have one ctl and several reps
if [[ "$ctlNum" -eq 1 && "$repNum" -ge 2 ]]; then
    for ((i=1; i<$repNum; i++)); do #yes, exactly from i=1
      ctlTag[$i]="${ctlTag[0]}"
      ctlSize[$i]="${ctlSize[0]}"
    done
fi

# Ctl pooled
if [[ "$ctlNum" -eq 1 ]]; then
    ctlTagPool="${ctlTag[0]}"
else
  ctlTagPool="$outPath/align/pooled_ctl/\
$(basename ${ctlName[0]%.$inpExt}).nodup_pooled.tagAlign.gz"
fi

# Reps and pseudo reps
declare -A repTag #matrix, rows: rep, pr1, pr2, ...; cols: 1,..,repNum
rowNum="$((1+prNum))" #real + number of pseudo
colNum="$repNum"

for ((i=0; i<$rowNum; i++)); do
  for ((j=1; j<=$colNum; j++)); do
    if [[ "$i" -eq 0 ]]; then #real replicates
        if [[ "$inpExt" = nodup.tagAlign.gz ]]; then
            inpTmp=("${repName[$((j-1))]}")
        else
	  inpTmp="$outPath/align/rep$j/\
$(basename ${repName[$((j-1))]%.$inpExt}).nodup.tagAlign.gz"
        fi
    else
      inpTmp="$outPath/align/pseudo_reps/rep$j/pr$i/\
$(basename ${repName[$((j-1))]%.$inpExt}).nodup.pr$i.tagAlign.gz"
    fi
    
    repTag[$i,$((j-1))]="$inpTmp"
  done
done


## Condor
# Arguments for condor job
jobArgsFile="" #file  w/ argumetns corresponds to var argsFile, e.g. xcor1.args
argsCon=("\$(script)" "\$(argsFile)" "$resDir" "\$(transOut)" "$softTar" "false")
argsCon="$(JoinToStr "\' \'" "${argsCon[@]}")"

# Output directory for condor log files
conOut="$jobsDir/conOut"
mkdir -p "$conOut"

# Transfered files
transFiles=("$jobsDir/\$(argsFile)"
	    "http://proxy.chtc.wisc.edu/SQUID/nazarovs/$softTar"
            "\$(transFiles)"
            "$funcList")
transFiles="$(JoinToStr ", " "${transFiles[@]}")"

# Main condor file
conFile="$jobsDir/${curScrName%.*}.condor"
bash "$homePath"/makeCon.sh "$conFile" "$conOut" "$exePath"\
     "$argsCon" "$transFiles"\
     "\$(nCores)" "\$(ram)" "\$(hd)" "\$(transOut)" "\$(transMap)"\
     "\$(conName)" "true"
 

## Start the "$dagFile"
PrintfLine > "$dagFile" 
printf "# [Start] Description of $dagFile\n" >> "$dagFile"
PrintfLine >> "$dagFile"


## pseudo
if [[ $firstStage -le $pseudoStage && $lastStage -ge $pseudoStage &&\
          "$trueRep" = false ]]; then
    jobName="$pseudoName" 

    PrintfLine >> "$dagFile"
    printf "# $jobName\n" >> "$dagFile" 
    PrintfLine >> "$dagFile"
    
    # Dag file	
    for ((j=1; j<=$repNum; j++)); do
      jobId="${jobName}Rep$j"
      jobArgsFile=("$jobsDir/$jobId.args")

      hd="${repSize[$((j-1))]}" #size in bytes
      hd=$(echo $((prNum + 1))\*$hd/1024^3 + 1 | bc) #in GB
      ram=$((hd*2))
      hd=$((hd + softSize)) #for software

      PrintfLineSh >> "$dagFile"
      printf "# $jobId\n" >> "$dagFile"
      PrintfLineSh >> "$dagFile"

      printf "JOB $jobId $conFile\n" >> "$dagFile"
      printf "VARS $jobId script=\"$jobName.bds\"\n" >> "$dagFile"
      printf "VARS $jobId argsFile=\"${jobArgsFile##*/}\"\n" >> "$dagFile"
      
      printf "VARS $jobId nCores=\"1\"\n" >> "$dagFile"
      printf "VARS $jobId hd=\"$hd\"\n" >> "$dagFile"
      printf "VARS $jobId ram=\"$ram\"\n" >> "$dagFile"

      transOutTmp="$transOut.$jobId.tar.gz"
      transMapTmp="$resPath/$transOutTmp"
      printf "VARS $jobId transFiles=\"${repTag[0,$((j-1))]}\"\n" >> "$dagFile"
      printf "VARS $jobId transOut=\"$transOutTmp\"\n"\
             >> "$dagFile"
      printf "VARS $jobId transMap=\"\$(transOut)=$transMapTmp\"\n"\
             >> "$dagFile"
      printf "VARS $jobId conName=\"$jobId.\"\n"\
             >> "$dagFile"
      
      # args file
      printf -- "-nth\t\t1\n" > "$jobArgsFile"
      printf -- "-tag\t\t${repTag[0,$((j-1))]##*/}\n" >> "$jobArgsFile"
      printf -- "-rep\t\t$j\n" >> "$jobArgsFile"

      # Parent & Child dependency 
      # pool
      if [[ $lastStage -ge $poolStage && "$repNum" -ge "2" ]]; then
	  printf "PARENT $jobId CHILD " >> "$dagFile"
	  for ((k=1; k<=$prNum; k++)); do
	    printf "${poolName}Pr$k " >> "$dagFile"
	  done
	  printf "\n" >> "$dagFile"
      fi

      # peak
      if [[ $lastStage -ge $peakStage && $ctlNum -ge 1 ]]; then
	  printf "PARENT $jobId CHILD " >> "$dagFile"
	  for ((k=1; k<=$prNum; k++)); do #go throw pseudo
	    printf "${peakName}Rep${j}Pr$k " >> "$dagFile"
	  done
	  printf "\n" >> "$dagFile"
      fi

      # Post script to untar resulting files
      printf "\nSCRIPT POST $jobId $postScript untarfiles $transMapTmp\n"\
             >> "$dagFile"
    done
fi


## xcor
if [[ "$firstStage" -le "$xcorStage" && "$lastStage" -ge "$xcorStage" ]]; then
    jobName="$xcorName"

    PrintfLine >> "$dagFile"
    printf "# $jobName\n" >> "$dagFile" 
    PrintfLine >> "$dagFile"
    
    # Create the dag file
    for ((i=1; i<=$repNum; i++)); do				
      jobId="$jobName$i"
      jobArgsFile=("$jobsDir/$jobId.args")

      hd="${repSize[$((i-1))]}" #size in bytes
      hd=$(echo $hd/1024^3 + 1 | bc) #in GB
      ram=$((hd*2))
      hd=$((hd + softSize)) #for software

      PrintfLineSh >> "$dagFile"
      printf "# $jobId\n" >> "$dagFile"
      PrintfLineSh >> "$dagFile"

      printf "JOB $jobId $conFile\n" >> "$dagFile"
      printf "VARS $jobId script=\"$jobName.bds\"\n" >> "$dagFile"
      printf "VARS $jobId argsFile=\"${jobArgsFile##*/}\"\n" >> "$dagFile"
      
      printf "VARS $jobId nCores=\"1\"\n" >> "$dagFile"
      printf "VARS $jobId hd=\"$hd\"\n" >> "$dagFile"
      printf "VARS $jobId ram=\"$ram\"\n" >> "$dagFile"

      transOutTmp="$transOut.$jobId.tar.gz"
      transMapTmp="$resPath/$transOutTmp"
      printf "VARS $jobId transFiles=\"${repTag[0,$((i-1))]}\"\n" >> "$dagFile"
      printf "VARS $jobId transOut=\"$transOutTmp\"\n"\
             >> "$dagFile"
      printf "VARS $jobId transMap=\"\$(transOut)=$transMapTmp\"\n"\
             >> "$dagFile"
      printf "VARS $jobId conName=\"$jobId.\"\n"\
             >> "$dagFile"
      
      # args file
      printf -- "-nth\t\t1\n" > "$jobArgsFile"
      printf -- "-tag\t\t${repTag[0,$((i-1))]##*/}\n" >> "$jobArgsFile"
      printf -- "-rep\t\t$i\n" >> "$jobArgsFile"

      # Parent & Child dependency
      # peak
      if [[ "$lastStage" -ge "$peakStage" && $ctlNum -ge 1 ]]; then
	  printf "PARENT $jobId CHILD " >> "$dagFile"

	  if [[ "$repNum" -gt 1 ]]; then #pooled peak
	      for ((j=0; j<=$prNum; j++)); do #go throw pseudo				
		printf "${peakName}Rep0Pr$j " >> "$dagFile"
	      done
	  fi

	  for ((j=0; j<=$prNum; j++)); do #go throw pseudo #replicate peak	
	    printf "${peakName}Rep${i}Pr$j " >> "$dagFile"
	  done
	  printf "\n" >> "$dagFile"
      fi

      # stgMacs
      if [[ "$lastStage" -ge "$stgStage" && $ctlNum -ge 1 ]]; then
	  printf "PARENT $jobId CHILD " >> "$dagFile"

	  if [[ "$repNum" -gt 1 ]]; then #pooled peak				
	      printf "${stgName}Rep0 " >> "$dagFile"
	  fi
	  
	  printf "${stgName}Rep${i}" >> "$dagFile"
	  printf "\n" >> "$dagFile"
      fi

      # Post script to untar resulting files
      printf "\nSCRIPT POST $jobId $postScript untarfiles $transMapTmp\n"\
             >> "$dagFile"
    done
fi


## pool
if [[ "$firstStage" -le "$poolStage" && "$lastStage" -ge "$poolStage" &&\
          "$repNum" -ge "2" ]]; then
    jobName="$poolName"
    jobArgsFile=() #here we have several arguments files

    PrintfLine >> "$dagFile"
    printf "# $jobName\n" >> "$dagFile" 
    PrintfLine >> "$dagFile"

    # [Create args files]
    transFilesTmp=() #for every argList which files to transfer
    # Reps and PR: pr0-2
    for ((i=0; i<$rowNum; i++)); do
      jobArgsFile[$i]="$jobsDir/${jobName}Pr$i.args"
      printf -- "-nth\t\t1\n" > "${jobArgsFile[$i]}"

      hdTmp[$i]=0
      for ((j=1; j<=$colNum; j++)); do #number of reps
	printf -- "-tag$j\t\t${repTag[$i,$((j-1))]##*/}\n" >> "${jobArgsFile[$i]}"
        
        if [[ $j -eq 1 ]]; then
             transFilesTmp[$i]="${repTag[$i,$((j-1))]}"
        else
          transFilesTmp[$i]="${transFilesTmp[$i]}, ${repTag[$i,$((j-1))]}"
        fi

        hdTmp[$i]=$((hdTmp[i] + repSize[((j-1))]))
        # everytime is sum of real reps size, since pr size is not bigger
      done
      printf -- "-ctl\t\t0\n" >> "${jobArgsFile[$i]}"
      printf -- "-pr\t\t$i\n" >> "${jobArgsFile[$i]}"
    done

    # Ctls - has to be the last one	
    if [[ "$ctlNum" -gt 1 ]]; then
	# Create args file for ctl
        nTmp=${#jobArgsFile[@]}
	jobArgsFileTmp="$jobsDir/${jobName}Ctl.args"
	jobArgsFile[$nTmp]="$jobArgsFileTmp"
	printf -- "-nth\t\t1\n" > "$jobArgsFileTmp"

	# Fill these files
        hdTmp[$nTmp]=0
	for ((i=1; i<=$ctlNum; i++)); do
	  printf -- "-tag$i\t\t${ctlTag[$((i-1))]##*/}\n" >> "$jobArgsFileTmp"
          hdTmp[$nTmp]=$((hdTmp[nTmp] + ctlSize[((i-1))]))
	done
        transFilesTmp[$nTmp]="$(JoinToStr ", " "${ctlTag[@]}")"
	printf -- "-ctl\t\t1\n" >> "$jobArgsFileTmp"
    fi

    # [Fill job file] for reps, PR_i files, ctl
    for ((i=0; i<${#jobArgsFile[@]}; i++)); do #pr0, pr1, pr2, ..., ctl
      jobId="${jobArgsFile[$i]##*/}" #take the name from the argFile with format
      jobId="${jobId%.*}" #delete extension

      hd=$(echo ${hdTmp[$i]}/1024^3 + 1 | bc) #in GB
      ram=$((hd*2))
      hd=$((hd + softSize)) #for software
      
      PrintfLineSh >> "$dagFile"
      printf "# $jobId\n" >> "$dagFile"
      PrintfLineSh >> "$dagFile"

      printf "JOB $jobId $conFile\n" >> "$dagFile"
      printf "VARS $jobId script=\"$jobName.bds\"\n" >> "$dagFile"
      printf "VARS $jobId argsFile=\"${jobArgsFile[$i]##*/}\"\n" >> "$dagFile"
      
      printf "VARS $jobId nCores=\"1\"\n" >> "$dagFile"
      printf "VARS $jobId hd=\"$hd\"\n" >> "$dagFile"
      printf "VARS $jobId ram=\"$ram\"\n" >> "$dagFile"

      transOutTmp="$transOut.$jobId.tar.gz"
      transMapTmp="$resPath/$transOutTmp"
      printf "VARS $jobId transFiles=\"${transFilesTmp[$i]}\"\n" >> "$dagFile"
      printf "VARS $jobId transOut=\"$transOutTmp\"\n"\
             >> "$dagFile"
      printf "VARS $jobId transMap=\"\$(transOut)=$transMapTmp\"\n"\
             >> "$dagFile"
      printf "VARS $jobId conName=\"$jobId.\"\n"\
             >> "$dagFile"
      
      # Parent & Child dependency
      # peak
      if [[ "$lastStage" -ge "$peakStage" && $ctlNum -ge 1 ]]; then
	  printf "PARENT $jobId CHILD " >> "$dagFile"

	  if [[ "$i" -lt "$((${#jobArgsFile[@]} - 1))" ]]; then #pr part
	      printf "${peakName}Rep0Pr$i " >> "$dagFile"
	  else 
	    if [[ "$ctlNum" -ge 2 ]]; then #ctl part
		for ((j=0; j<=$prNum; j++)); do #go throw pooled pseudo peaks
	 	  printf "${peakName}Rep0Pr$j " >> "$dagFile"
		done
		
		# Peaks of reps, where ctl = pool
		for ((j=0; j<$ctlNum; j++)); do
		  if [[ "${useCtlPool[$j]}" = true ]]; then
		      for ((k=0; k<=$prNum; k++)); do #throw pooled pseudo peaks
		     	printf "${peakName}Rep$((j+1))Pr$k " >> "$dagFile"
		      done
		  fi
		done
	    else #last pr part
	      printf "${peakName}Rep0Pr$i " >> "$dagFile" 
	    fi
	  fi
	  printf "\n" >> "$dagFile"
      fi

      # stgMacs2
      if [[ "$lastStage" -ge "$stgStage" && $ctlNum -ge 1 ]]; then
	  if [[ "$i" -eq 0 ]]; then
	      printf "PARENT $jobId CHILD ${stgName}Rep0" >> "$dagFile"
	  fi

	  if [[ "$i" = $((${#jobArgsFile[@]} - 1)) && "$ctlNum" -ge 2 ]]; then
              # ctl part
	      printf "PARENT $jobId CHILD " >> "$dagFile"
	      printf "${stgName}Rep0 " >> "$dagFile"

	      # Peaks of reps, where ctl = pool
	      for ((j=0; j<$ctlNum; j++)); do
		if [[ "${useCtlPool[$j]}" = true ]]; then	
		    printf "${stgName}Rep$((j+1)) " >> "$dagFile"
		fi
	      done
	  fi
	  printf "\n" >> "$dagFile"
      fi

      # Post script to untar resulting files
      printf "\nSCRIPT POST $jobId $postScript untarfiles $transMapTmp\n"\
             >> "$dagFile"
    done
fi


## Add path of ctlPool in ctlTag
for ((i=0; i<$ctlNum; i++)); do
  if [[ "${useCtlPool[$i]}" = true ]]; then
      ctlTag[$i]="$ctlTagPool"
  fi
done

## Peaks and stgMacs2
# Code is almost the same for two parts => we use loop
# Difference is that stg does not need PR values
stIterTmp=("$stgName" "$peakName")
for stIter in "${stIterTmp[@]}"; do
  stTmp=$(MapStage "$stIter")

  if [[ -z $(RmSp "$specName") ]]; then
      ErrMsg "For $stIter chromosome size, species name and species list
              should be defined."
  fi

  for i in specList chrmSz; do
    eval "strTmp=\"\$$i\""
    if [[ "${strTmp:0:1}" != "/" ]]; then
        ErrMsg "The full path for $i has to be provided:
           Current value is: $strTmp"
    fi
  done

  if [[ -z $(RmSp "$blackList") ]]; then
      WarnMsg "For $stIter blackList is empty."
  else
    if [[ "${blackList:0:1}" != "/" ]]; then
        ErrMsg "The full path for blackList has to be provided:
                Current value is: $blackList"
    fi
  fi

  
  if [[ $firstStage -le $stTmp && $lastStage -ge $stTmp &&\
            $ctlNum -ge 1 ]]; then
      jobName="$stIter"

      if [[ "$stIter" = "$stgName" ]]; then
	  prNumTmp=0
      else
	prNumTmp=$prNum
      fi

      PrintfLine >> "$dagFile"
      printf "# $jobName\n" >> "$dagFile" 
      PrintfLine >> "$dagFile"

      # Go throw replicates: rep_pooled, rep1, rep2, ...
      for ((i=0; i<=$repNum; i++)); do #0-pooled	
	inpXcorTmp=() 
	jobId=()
	inpTmp=()
	
        # Create input for args files for both stg and peaks
	if [[ "$i" -eq 0 ]]; then #i.e. pooled peak or stg
	    if [[ "$repNum" -gt 1 ]]; then
                # Ctl
		inpCtlTmp="$ctlTagPool" #includes 1 or many ctl
                # Xcor
		for ((j=1; j<=repNum; j++)); do
		  inpXcorTmp[$((j-1))]="$outPath/qc/rep$j/\
$(basename ${repName[$((j-1))]%.$inpExt}).nodup.15M.cc.qc"
		done
                # Rep, PR
                strTmp="$(basename ${repName[0]%.$inpExt})"
		for ((j=0; j<=$prNumTmp; j++)); do #rep, repPr1, repPr2, ...
		  if [[ "$j" -eq 0 ]]; then
		      inpTmp[$j]="$outPath/align/pooled_rep/\
$strTmp.nodup_pooled.tagAlign.gz"
		  else	
		    inpTmp[$j]="$outPath/align/pooled_pseudo_reps/ppr$j/\
$strTmp.nodup.pr${j}_pooled.tagAlign.gz"
		  fi
		  
		  jobId[$j]="${jobName}Rep${i}"
		  if [[ "$stIter" != "$stgName" ]]; then
		      jobId[$j]="${jobId[$j]}Pr$j"
		  fi
		done

                hdTmp[$i]=0
                for ((j=1; j<=repNum; j++)); do
		  hdTmp[$i]=$((hd[i] + repSize[j] + ctlSize[j]))
		done
	    else
	      continue
	    fi
	else #separately for replicates
	  # Ctl
	  inpCtlTmp="${ctlTag[$((i-1))]}" #considering if ctlNum>1 or notxs
	  # Xcor
          inpXcorTmp=()
	  inpXcorTmp="$outPath/qc/rep$i/\
$(basename ${repName[$((i-1))]%.$inpExt}).nodup.15M.cc.qc"
	  # Rep, PR
          inpTmp=()
	  for ((j=0; j<=$prNumTmp; j++)); do #rep, repPr1, repPr2, ...
	    inpTmp[$j]="${repTag[$j,$((i-1))]}"
            
	    jobId[$j]="${jobName}Rep${i}"
	    if [[ "$stIter" != "$stgName" ]]; then
		jobId[$j]="${jobId[$j]}Pr$j"
	    fi
	  done

          hdTmp[$i]=$((repSize[i] + ctlSize[i])) #b/c PR is about same size as rep
	fi

	# Print jobs in the file based on replicates: pooled, rep1, rep2	
	PrintfLineSh >> "$dagFile"
	printf "# Rep$i\n" >> "$dagFile" 
	PrintfLineSh >> "$dagFile"

	for ((j=0; j<=$prNumTmp; j++)); do #rep, repPr1, repPr2, ...
	  jobIdTmp="${jobId[$j]}"
	  jobArgsFile=("$jobsDir/$jobIdTmp.args")

          hd=$(echo ${hdTmp[$i]}/1024^3 + 1 | bc) #in GB
          if [[ "$stIter" = "$stgName" ]]; then #string comparison
	      nCoresTmp=$coresStg
              ram=$((hd*2))
	  else
	    nCoresTmp=$coresPeaks
            ram=$((hd + 2*nCoresTmp))
	  fi

          hd=$((hd + softSize)) #for software
          transFilesTmp=("${inpTmp[$j]}" "${inpCtlTmp}" "${inpXcorTmp[@]}"
                         "$chrmSz" "$specList")
          if [[ -n $(RmSp "$blackList") ]]; then
              transFilesTmp=("${transFilesTmp[@]}" "$blackList")
          fi  

          transFilesTmp="$(JoinToStr ", " "${transFilesTmp[@]}")"

          if [[ $j -gt 0 ]]; then
              PrintfLineSh >> "$dagFile"
          fi

	  printf "JOB $jobIdTmp $conFile\n" >> "$dagFile"
          printf "VARS $jobIdTmp script=\"$jobName.bds\"\n" >> "$dagFile"
          printf "VARS $jobIdTmp argsFile=\"${jobArgsFile##*/}\"\n" >> "$dagFile"
          
          printf "VARS $jobIdTmp nCores=\"$nCoresTmp\"\n" >> "$dagFile"
          printf "VARS $jobIdTmp hd=\"$hd\"\n" >> "$dagFile"
          printf "VARS $jobIdTmp ram=\"$ram\"\n" >> "$dagFile"

          transOutTmp="$transOut.$jobIdTmp.tar.gz"
          transMapTmp="$resPath/$transOutTmp"
          printf "VARS $jobIdTmp transFiles=\"$transFilesTmp\"\n" >> "$dagFile"
          printf "VARS $jobIdTmp transOut=\"$transOutTmp\"\n"\
                 >> "$dagFile"
          printf "VARS $jobIdTmp transMap=\"\$(transOut)=$transMapTmp\"\n"\
                 >> "$dagFile"
          printf "VARS $jobIdTmp conName=\"$jobIdTmp.\"\n"\
                 >> "$dagFile"

	  # args file
          printf -- "-species\t\t$specName\n" > "$jobArgsFile"
          printf -- "-species_file\t\t${specList##*/}\n" >> "$jobArgsFile"
          
	  printf -- "-nth\t\t$nCoresTmp\n" >> "$jobArgsFile"
	  printf -- "-tag\t\t${inpTmp[$j]##*/}\n" >> "$jobArgsFile"
	  printf -- "-ctl_tag\t\t${inpCtlTmp##*/}\n" >> "$jobArgsFile"

	  if [[ "$stIter" != "$stgName" ]]; then
	      printf -- "-pr\t\t$j\n" >> "$jobArgsFile"
	  fi

	  if [[ "$i" -eq 0 ]]; then
	      for ((k=1; k<=$repNum; k++)); do			
		printf -- "-xcor_qc$k\t\t${inpXcorTmp[$((k-1))]##*/}\n"\
		       >> "$jobArgsFile"
	      done
	  else
	    printf -- "-rep\t\t$i\n" >> "$jobArgsFile"
	    printf -- "-xcor_qc\t\t${inpXcorTmp##*/}\n" >> "$jobArgsFile"
	  fi
          
	  # Parent & Child dependency
	  if [[ "$lastStage" -ge "$idrOverlapStage" &&\
                    "$stIter" != "$stgName" ]]; then
	      printf "PARENT $jobIdTmp CHILD $idrName $overlapName\n\n"\
		     >> "$dagFile"
	  fi

          # Post script to untar resulting files
          printf "\nSCRIPT POST $jobIdTmp $postScript untarfiles $transMapTmp\n"\
                 >> "$dagFile"
	done
      done
  fi
done


## idr and overlap
if [[ $firstStage -le $idrOverlapStage && $lastStage -ge $idrOverlapStage &&\
          $ctlNum -ge 1 ]]; then
    jobArgsFileTmp=("$jobsDir/tmp.args")

    if [[ -z $(RmSp "$specName") ]]; then #just for idr
        ErrMsg "For $stIter species name should be defined."
    fi

    for i in specList chrmSz; do  #just for idr
      eval "strTmp=\"\$$i\""
      if [[ "${strTmp:0:1}" != "/" ]]; then
          ErrMsg "The full path for $i has to be provided:
           Current value is: $strTmp"
      fi
    done

    for ((i=0; i<$ctlNum; i++)); do
      if [[ "${useCtlPool[$i]}" = true ]]; then
	  ctlNameTmp[$i]="${ctlTagPool##*/}"
      else 
	ctlNameTmp[$i]="${ctlTag[$i]##*/}"
      fi
      ctlNameTmp[$i]="${ctlNameTmp[$i]%.*}" #delete .gz
    done

    # Copy ctl1 name in case we have one ctl and several reps
    if [[ "$ctlNum" -eq 1 && "$repNum" -ge 2 ]]; then
	for ((i=1; i<$repNum; i++)); do #yes, exactly from i=1
	  ctlNameTmp[$i]="${ctlNameTmp[0]}"
	done
    fi
    
    # Create input for args files for both idr and overlap
    transFilesTmp=("$chrmSz" "$specList")
    printf -- "-species\t\t$specName\n" > "$jobArgsFileTmp"
    printf -- "-species_file\t\t${specList##*/}\n" >> "$jobArgsFileTmp"
    for ((i=0; i<=$repNum; i++)); do #0-pooled
      inpTmp=()
      if [[ "$i" -eq 0 ]]; then #i.e. pooled version
	  if [[ "$repNum" -gt 1 ]]; then
	      # Rep, PR
	      for ((j=0; j<=$prNum; j++)); do #rep, repPr1, repPr2, ...
                strTmp="$(basename ${repName[0]%.$inpExt})"
		# AQUAS takes repName[0] as a name for pooled replicates
		if [[ "$j" -eq "0" ]]; then
		    inpTmp[$j]="$outPath/peak/spp/pooled_rep/\
$strTmp.nodup_pooled.tagAlign_x_"
		else	
		  inpTmp[$j]="$outPath/peak/spp/pooled_pseudo_reps/ppr$j/\
$strTmp.nodup.pr${j}_pooled.tagAlign_x_"
		fi
		# In peaks it should be ctlTagPool anyway for pooled replicates
		strTmp="${ctlTagPool##*/}"
		strTmp="${strTmp%.*}" #delete .gz
		inpTmp[$j]="${inpTmp[$j]}$strTmp.regionPeak.gz"
	      done
	  else
	    continue
	  fi
      else #separately for replicates
        strTmp="$(basename ${repName[$((i-1))]%.$inpExt})"
	for ((j=0; j<=$prNum; j++)); do #rep, repPr1, repPr2, ...
	  if [[ "$j" -eq 0 ]]; then
	      inpTmp[$j]="$outPath/peak/spp/rep$i/\
$strTmp.nodup.tagAlign_x_"
	  else	
	    inpTmp[$j]="$outPath/peak/spp/pseudo_reps/rep$i/pr$j/\
$strTmp.nodup.pr$j.tagAlign_x_"
	  fi
	  inpTmp[$j]="${inpTmp[$j]}${ctlNameTmp[$((i-1))]}.regionPeak.gz"
	done
      fi

      # args file - same for both jobs
      for ((j=0; j<=$prNum; j++)); do #rep, repPr1, repPr2, ...
	if [[ "$i" -eq 0 ]]; then
	    if [[ "$j" -eq 0 ]]; then
		printf -- "-peak_pooled" >> "$jobArgsFileTmp"
	    else
	      printf -- "-peak_ppr$j" >> "$jobArgsFileTmp"
	    fi
	else
	  if [[ "$repNum" -eq 1 ]]; then
	      printf -- "-peak" >> "$jobArgsFileTmp"
	  else
	    printf -- "-peak$i" >> "$jobArgsFileTmp"
	  fi
	  if [[ "$j" -ne 0 ]]; then
	      printf -- "_pr$j" >> "$jobArgsFileTmp"
	  fi
	fi
	printf -- "\t\t${inpTmp[$j]##*/}\n" >> "$jobArgsFileTmp"
        transFilesTmp=("${transFilesTmp[@]}" "${inpTmp[$j]}")
      done
    done

    printf -- "-true_rep\t\t$trueRep\n" >> "$jobArgsFileTmp"
    printf -- "-nth\t\t1\n" >> "$jobArgsFileTmp"

    hd=$(echo ${#transFilesTmp[@]}/1024^3 + 1 | bc) #in GB
    ram=$((hd*2))
    hd=$((hd + softSize)) #for software
    transFilesTmp="$(JoinToStr ", " "${transFilesTmp[@]}")"

    # Fill job files
    jobNames=("$idrName" "$overlapName")
    for jobName in "${jobNames[@]}"; do
      PrintfLine >> "$dagFile"
      printf "# $jobName\n" >> "$dagFile" 
      PrintfLine >> "$dagFile"
      
      jobId="$jobName"
      jobArgsFile=("$jobsDir/$jobId.args")
      cp "$jobArgsFileTmp" "$jobArgsFile"
      
      printf "JOB $jobId $conFile\n" >> "$dagFile"
      printf "VARS $jobId script=\"$jobName.bds\"\n" >> "$dagFile"
      printf "VARS $jobId argsFile=\"${jobArgsFile##*/}\"\n" >> "$dagFile"

      printf "VARS $jobId nCores=\"1\"\n" >> "$dagFile"
      printf "VARS $jobId hd=\"$hd\"\n" >> "$dagFile"
      printf "VARS $jobId ram=\"$ram\"\n" >> "$dagFile"

      transOutTmp="$transOut.$jobId.tar.gz"
      transMapTmp="$resPath/$transOutTmp"
      printf "VARS $jobId transFiles=\"${transFilesTmp}\"\n" >> "$dagFile"
      printf "VARS $jobId transOut=\"$transOutTmp\"\n"\
             >> "$dagFile"
      printf "VARS $jobId transMap=\"\$(transOut)=$transMapTmp\"\n"\
             >> "$dagFile"
      printf "VARS $jobId conName=\"$jobId.\"\n"\
             >> "$dagFile"

      # Post script to untar resulting files
      printf "\nSCRIPT POST $jobId $postScript untarfiles $transMapTmp\n"\
             >> "$dagFile"
    done

    rm -rf "$jobArgsFileTmp"
fi


## End
PrintfLine >> "$dagFile"
printf "# [End] Description of $dagFile\n" >> "$dagFile"
PrintfLine >> "$dagFile"

exit 0 #everything is ok
