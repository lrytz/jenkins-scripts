#!/bin/bash -ex

ant -Dmaven.version.suffix=$mavenVersionSuffix nightly publish-signed
