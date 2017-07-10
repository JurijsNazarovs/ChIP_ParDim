#!/bin/bash
tarName="pipeInstallFiles.new.tar.gz"

tar -czf "$tarName" .bds jdk1.8.0_131 miniconda3 pipeInstall.sh pipePath.source\
    pipeScripts

mv "$tarName" /squid/nazarovs
# To update files on squid we have to mv them with one name and change it to
# the original name
mv /squid/nazarovs/"$tarName" /squid/nazarovs/"$tarName"Tmp
mv /squid/nazarovs/"$tarName"Tmp /squid/nazarovs/"$tarName"
