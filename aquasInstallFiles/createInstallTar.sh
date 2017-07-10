#!/bin/bash
#===============================================================================
# Script produces tar.gz file with all files necessary to run any part based on
# Aquas pipeline.
# This script is executed on executed server with an interactive job
# Interactive job has to transfer 1 tar file:
#   - javaTar=jdk-8u131-linux-x64.tar.gz
#===============================================================================

## Names for downloading software
javaTar=jdk-8u131-linux-x64.tar.gz
javaDir=jdk1.8.0_131
bdsTar=bds_Linux.tgz
minicondaSh=Miniconda3-latest-Linux-x86_64.sh
aquasDir=TF_chipseq_pipeline
finalTar="pipeSoftwareFiles.tar.gz"

export HOME="$PWD"


## Java
tar -xzf "$javaTar"
JAVA_HOME="$HOME/$javaDir"
export PATH="$JAVA_HOME/bin:$PATH"


## Miniconda3
wget "https://repo.continuum.io/miniconda/$minicondaSh"
bash "$minicondaSh" -b -p "$HOME/miniconda3"
export PATH="$HOME/miniconda3/bin:$PATH"
rm -rf "$minicondaSh"


## BDS
wget "https://github.com/leepc12/BigDataScript/blob/master/distro/$bdsTar?raw=true -O bds_Linux.tgz"
$ tar -xzf "$bdsTar" #creates .bds directory
$ export PATH="$HOME/.bds:$PATH"
$ rm -rf "$bdsTar"
#If Java memory occurs, add
#export _JAVA_OPTIONS="-Xms256M -Xmx728M -XX:ParallelGCThreads=1" too.


## Aquas
git clone https://github.com/kundajelab/$aquasDir
cd "$HOME/$aquasDir"
bash ./install_dependencies.sh
cd "$HOME"
cp "$HOME/miniconda3/pkgs/mysql-5.5.24-0/lib/libmysqlclient.so.18.0.0" "$HOME/miniconda3/envs/aquas_chipseq_py3/lib/libmysqlclient.so.18"
rm -rf "$HOME"/miniconda3/pkgs/*.tar.bz2 #make final tar lighter


## Tar all files together
tar -czf "$finalTar" .bds "$javaDir" miniconda3
