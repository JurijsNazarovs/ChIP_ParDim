#!/bin/bash
echo [Start] Installation
startTime=$SECONDS


## Change pathes in configuration files, because of wrong installation
cpStartTime=$SECONDS
varTmp=$(dirname "$homePath") #the part before dir_...
varTmp2=$(basename "$homePath") #exact dir_...

find miniconda3/*/ -type f\
     -exec sed -i -e "s,$varTmp/[Aa-Zz0-9_]\+,$varTmp/$varTmp2,g" {} \;

cpElapsedTime=$(($SECONDS - $cpStartTime))
echo $cpElapsedTime seconds to change pathes in all files


## Options
#export _JAVA_OPTIONS="-Xms256M -Xmx512M -XX:ParallelGCThreads=1" #not quite sure what this is


## End
elapsedTime=$(($SECONDS - $startTime))
echo [End] Installation: $elapsedTime seconds
