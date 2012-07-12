#!/bin/bash -ex

scriptsDir="$( cd "$( dirname "$0" )/.." && pwd )"
. $scriptsDir/common
. $scriptsDir/publish-nightly

publishNightly $publish "scala-nightly-main-2.10.x" $mainBuild "false"
