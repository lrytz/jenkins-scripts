#!/bin/bash -ex
# needs SONA_USER_TOKEN and ~/.m2/settings.xml with credentials for sonatype

scriptsDir="$( cd "$( dirname "$0" )/.." && pwd )"
. $scriptsDir/common
. $scriptsDir/pr-scala-common

#parse_properties versions.properties

     SCALA_GITREF="master"
    SCALA_BASEVER="2.11.0"
     MAVEN_SUFFIX="-M8"
          XML_VER="1.0.0-RC7"
      PARSERS_VER="1.0.0-RC5"
   SCALACHECK_VER="1.11.1"
      PARTEST_VER="1.0.0-RC8"
PARTEST_IFACE_VER="0.2"

# repo used to publish "locker" scala to (to start the bootstrap)
# TODO: change to dedicated repo
stagingCred="pr-scala"
stagingRepo="http://private-repo.typesafe.com/typesafe/scala-pr-validation-snapshots/"
publishTask=publish-signed #publish-local

#####

SCALA_VER="$SCALA_BASEVER$MAVEN_SUFFIX"

baseDir=`pwd`


# TODO: clean local repo, or publish to a fresh one

# stApi="https://oss.sonatype.org/service/local/"
# 
# function st_curl(){
#   curl -H "accept: application/json" --user $SONA_USER_TOKEN -s -o - $@
# }
# 
# function st_stagingRepo() {
#  st_curl "$stApi/staging/profile_repositories" | jq '.data[] | select(.profileName == "org.scala-lang") | .repositoryURI'
# }


update() {
  cd $baseDir
  getOrUpdate $baseDir/$2 "https://github.com/$1/$2.git" $3
  cd $2
}

publishModules() {
  publishTask=$1
  sonaStaging=$2

  # test and publish to sonatype, assuming you have ~/.sbt/0.13/sonatype.sbt and ~/.sbt/0.13/plugin/gpg.sbt
  update scala scala-xml "v$XML_VER"
  sbt 'set version := "'$XML_VER'"' \
      'set resolvers += "staging" at "'$stagingRepo'"'\
      'set scalaVersion := "'$SCALA_VER'"' \
      clean test $publishTask

  update scala scala-parser-combinators "v$PARSERS_VER"
  sbt 'set version := "'$PARSERS_VER'"' \
      'set resolvers += "'$stagingRepo'"'\
      'set scalaVersion := "'$SCALA_VER'"' \
      clean test $publishTask

  update rickynils scalacheck $SCALACHECK_VER
  sbt 'set version := "'$SCALACHECK_VER'"' \
      'set resolvers += "'$stagingRepo'"'\
      'set scalaVersion := "'$SCALA_VER'"' \
      'set every scalaBinaryVersion := "'$SCALA_VER'"' \
      'set VersionKeys.scalaParserCombinatorsVersion := "'$PARSERS_VER'"' \
      clean test publish-local

  update scala scala-partest "v$PARTEST_VER"
  sbt 'set version :="'$PARTEST_VER'"' \
      'set resolvers += "'$stagingRepo'"'\
      'set scalaVersion := "'$SCALA_VER'"' \
      'set VersionKeys.scalaXmlVersion := "'$XML_VER'"' \
      'set VersionKeys.scalaCheckVersion := "'$SCALACHECK_VER'"' \
      clean $publishTask

  update scala scala-partest-interface "v$PARTEST_IFACE_VER"
  sbt 'set version :="'$PARTEST_IFACE_VER'"' \
      'set resolvers += "'$stagingRepo'"'\
      'set scalaVersion := "'$SCALA_VER'"' \
      clean $publishTask
}

update scala scala $SCALA_GITREF

# publish core so that we can build modules with this version of Scala and publish them locally
# must publish under $SCALA_VER so that the modules will depend on this (binary) version of Scala
# publish more than just core: partest needs scalap
ant -Dmaven.version.number=$SCALA_VER\
    -Dremote.snapshot.repository=NOPE\
    -Drepository.credentials.id=$stagingCred\
    -Dremote.release.repository=$stagingRepo\
    -Dscalac.args.optimise=-optimise\
    -Ddocs.skip=1\
    -Dlocker.skip=1\
    publish

echo "Scala core published to $stagingRepo"

# build, test and publish modules with this core
# resolve scala from $stagingRepo, publish to sonatype
publishModules publish $stagingRepo

# Rebuild Scala with these modules so that all binary versions are consistent.
# Update versions.properties to new modules.
# Sanity check: make sure the Scala test suite passes / docs can be generated with these modules.
# don't skip locker (-Dlocker.skip=1\), or stability will fail
cd $baseDir/scala
ant -Dstarr.version=$SCALA_VER\
    -Dextra.repo.url=$stagingRepo\
    -Dmaven.version.suffix=$MAVEN_SUFFIX\
    -Dscala.binary.version=$SCALA_VER\
    -Dpartest.version.number=$PARTEST_VER\
    -Dscala-xml.version.number=$XML_VER\
    -Dscala-parser-combinators.version.number=$PARSERS_VER\
    -Dscalacheck.version.number=$SCALACHECK_VER\
    -Dupdate.versions=1\
    -Dscalac.args.optimise=-optimise\
    nightly $publishTask

git commit versions.properties -m"Bump versions.properties for $SCALA_VER."

# TODO: tag and submit PR
# tag "v$SCALA_VER" "Scala v$SCALA_VER"

# rebuild modules for good measure
publishModules test


# used when testing scalacheck integration with partest, while it's in staging repo before releasing it
#     'set resolvers += "scalacheck staging" at "http://oss.sonatype.org/content/repositories/orgscalacheck-1010/"' \
# in ant: ()
#     -Dextra.repo.url=http://oss.sonatype.org/content/repositories/orgscalacheck-1010/\
