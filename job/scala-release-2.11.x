#!/bin/bash -ex
# requirements:
# - ~/.sonatype-curl that consists of user = USER:PASS
# - ~/.m2/settings.xml with credentials for sonatype
    # <server>
    #   <id>private-repo</id>
    #   <username>jenkinside</username>
    #   <password></password>
    # </server>
# - ~/.ivy2/.credentials (for sonatype)
    # realm=Sonatype Nexus Repository Manager
    # host=oss.sonatype.org
    # user=lamp
    # password=
# - ~/.ivy2/.credentials-private-repo for private-repo.typesafe.com, as follows:
    # realm=Artifactory Realm
    # host=private-repo.typesafe.com
    # user=jenkinside
    # password=
# - ~/.sbt/0.13/plugins/gpg.sbt with:
#   addSbtPlugin("com.typesafe.sbt" % "sbt-pgp" % "0.8.1")

# defaults for jenkins params
   SCALA_VER_BASE=${SCALA_VER_BASE-"2.11.0"}
SCALA_VER_SUFFIX=${SCALA_VER_SUFFIX-"-M8"}
          XML_VER=${XML_VER-"1.0.0-RC7"}
      PARSERS_VER=${PARSERS_VER-"1.0.0-RC5"}
CONTINUATIONS_VER=${CONTINUATIONS_VER-"1.0.0-RC3"}
        SWING_VER=${SWING_VER-"1.0.0-RC2"}
      PARTEST_VER=${PARTEST_VER-"1.0.0-RC8"}
PARTEST_IFACE_VER=${PARTEST_IFACE_VER-"0.2"}
   SCALACHECK_VER=${SCALACHECK_VER-"1.11.2"}

            SCALA_REF=${SCALA_REF-"master"}
              XML_REF=${XML_REF-"v$XML_VER"}
          PARSERS_REF=${PARSERS_REF-"v$PARSERS_VER"}
    CONTINUATIONS_REF=${CONTINUATIONS_REF-"v$CONTINUATIONS_VER"}
            SWING_REF=${SWING_REF-"v$SWING_VER"}
          PARTEST_REF=${PARTEST_REF-"v$PARTEST_VER"}
    PARTEST_IFACE_REF=${PARTEST_IFACE_REF-"v$PARTEST_IFACE_VER"}
       SCALACHECK_REF=${SCALACHECK_REF-"$SCALACHECK_VER"}


baseDir=${baseDir-`pwd`}
sbtCmd=${sbtCmd-sbt}

scriptsDir="$( cd "$( dirname "$0" )/.." && pwd )"
. $scriptsDir/common
. $scriptsDir/pr-scala-common

# ARGH trying to get this to work on multiple versions of sbt-extras...
# the old version (on jenkins, and I don't want to upgrade for risk of breaking other builds) honors -sbt-dir
# the new version of sbt-extras ignores sbt-dir, so we pass it in as -Dsbt.global.base
# we must not change ivy home, as it has ~/.ivy2/.credentials,
# but we don't want cross-pollination from the local ivy repo, so we use our own repositories-scala-release repo config
sbtArgs="-no-colors -Dsbt.override.build.repos=true -Dsbt.repository.config=$scriptsDir/repositories-scala-release -Dsbt.global.base=$HOME/.sbt/0.13 -sbt-dir $HOME/.sbt/0.13"

#parse_properties versions.properties


# repo used to publish "locker" scala to (to start the bootstrap)
stagingCred="private-repo"
stagingRepo="http://private-repo.typesafe.com/typesafe/scala-release-temp/"

resolver='"scala-release-temp" at "'$stagingRepo'"'

#####

SCALA_VER="$SCALA_VER_BASE$SCALA_VER_SUFFIX"

stApi="https://oss.sonatype.org/service/local"

function st_curl(){
  curl -H "Content-Type: application/json" -H "accept: application/json,application/vnd.siesta-error-v1+json,application/vnd.siesta-validation-errors-v1+json"  -K ~/.sonatype-curl -s -o - $@
}

function st_stagingReposOpen() {
 st_curl "$stApi/staging/profile_repositories" | jq '.data[] | select(.profileName == "org.scala-lang") | select(.type == "open")'
}

function st_stagingRepoDrop() {
  repo=$1
  message=$2
  echo "{\"data\":{\"description\":\"$message\",\"stagedRepositoryIds\":[\"$repo\"]}}" | st_curl -X POST -d @- "$stApi/staging/bulk/drop"
}

function st_stagingRepoClose() {
  repo=$1
  message=$2
  echo "{\"data\":{\"description\":\"$message\",\"stagedRepositoryIds\":[\"$repo\"]}}" | st_curl -X POST -d @- "$stApi/staging/bulk/close"
}

update() {
  [[ -d $baseDir ]] || mkdir -p $baseDir
  cd $baseDir
  getOrUpdate $baseDir/$2 "https://github.com/$1/$2.git" $3
  cd $2
}

# build/test/publish scala core modules to sonatype
buildModules() {
  # test and publish to sonatype, assuming you have ~/.sbt/0.13/sonatype.sbt and ~/.sbt/0.13/plugin/gpg.sbt
  update scala scala-xml "$XML_REF"
  $sbtCmd $sbtArgs 'set version := "'$XML_VER'"' \
      'set scalaVersion := "'$SCALA_VER'"' \
      'set credentials += Credentials(Path.userHome / ".ivy2" / ".credentials")'\
      "set pgpPassphrase := Some(Array.empty)" $@

  update scala scala-parser-combinators "$PARSERS_REF"
  $sbtCmd $sbtArgs 'set version := "'$PARSERS_VER'"' \
      'set scalaVersion := "'$SCALA_VER'"' \
      'set credentials += Credentials(Path.userHome / ".ivy2" / ".credentials")'\
      "set pgpPassphrase := Some(Array.empty)" $@

  update scala scala-partest "$PARTEST_REF"
  $sbtCmd $sbtArgs 'set version :="'$PARTEST_VER'"' \
      'set scalaVersion := "'$SCALA_VER'"' \
      'set VersionKeys.scalaXmlVersion := "'$XML_VER'"' \
      'set VersionKeys.scalaCheckVersion := "'$SCALACHECK_VER'"' \
      'set credentials += Credentials(Path.userHome / ".ivy2" / ".credentials")'\
      "set pgpPassphrase := Some(Array.empty)" $@

  update scala scala-partest-interface "$PARTEST_IFACE_REF"
  $sbtCmd $sbtArgs 'set version :="'$PARTEST_IFACE_VER'"' \
      'set scalaVersion := "'$SCALA_VER'"' \
      'set credentials += Credentials(Path.userHome / ".ivy2" / ".credentials")'\
      "set pgpPassphrase := Some(Array.empty)" $@

  update scala scala-continuations $CONTINUATIONS_REF
  $sbtCmd $sbtArgs 'set every version := "'$CONTINUATIONS_VER'"' \
      'set every scalaVersion := "'$SCALA_VER'"' \
      'set credentials += Credentials(Path.userHome / ".ivy2" / ".credentials")'\
      "set pgpPassphrase := Some(Array.empty)" $@

  update scala scala-swing "$SWING_REF"
  $sbtCmd $sbtArgs 'set version := "'$SWING_VER'"' \
      'set scalaVersion := "'$SCALA_VER'"' \
      'set credentials += Credentials(Path.userHome / ".ivy2" / ".credentials")'\
      "set pgpPassphrase := Some(Array.empty)" $@
}


# test and publish to $stagingRepo
# Duplicated because I cannot for the life of me figure out how to pass in these quoted sbt commands as args to a bash function
publishModulesPrivate() {
  update scala scala-xml "$XML_REF"
  $sbtCmd $sbtArgs 'set version := "'$XML_VER'"' \
      'set scalaVersion := "'$SCALA_VER'"' \
      "set publishTo := Some($resolver)"\
      'set credentials += Credentials(Path.userHome / ".ivy2" / ".credentials-private-repo")'\
      clean test publish

  update scala scala-parser-combinators "$PARSERS_REF"
  $sbtCmd $sbtArgs 'set version := "'$PARSERS_VER'"' \
      'set scalaVersion := "'$SCALA_VER'"' \
      "set publishTo := Some($resolver)"\
      'set credentials += Credentials(Path.userHome / ".ivy2" / ".credentials-private-repo")'\
      clean test publish

  update rickynils scalacheck $SCALACHECK_REF
  $sbtCmd $sbtArgs 'set version := "'$SCALACHECK_VER'"' \
      'set scalaVersion := "'$SCALA_VER'"' \
      'set every scalaBinaryVersion := "'$SCALA_VER'"' \
      'set VersionKeys.scalaParserCombinatorsVersion := "'$PARSERS_VER'"' \
      "set publishTo := Some($resolver)"\
      'set credentials += Credentials(Path.userHome / ".ivy2" / ".credentials-private-repo")'\
      clean publish # test times out

  update scala scala-partest "$PARTEST_REF"
  $sbtCmd $sbtArgs 'set version :="'$PARTEST_VER'"' \
      'set scalaVersion := "'$SCALA_VER'"' \
      'set VersionKeys.scalaXmlVersion := "'$XML_VER'"' \
      'set VersionKeys.scalaCheckVersion := "'$SCALACHECK_VER'"' \
      "set publishTo := Some($resolver)"\
      'set credentials += Credentials(Path.userHome / ".ivy2" / ".credentials-private-repo")'\
      clean test publish

  update scala scala-partest-interface "$PARTEST_IFACE_REF"
  $sbtCmd $sbtArgs 'set version :="'$PARTEST_IFACE_VER'"' \
      'set scalaVersion := "'$SCALA_VER'"' \
      "set publishTo := Some($resolver)"\
      'set credentials += Credentials(Path.userHome / ".ivy2" / ".credentials-private-repo")'\
      clean test publish

  update scala scala-continuations $CONTINUATIONS_REF
  $sbtCmd $sbtArgs 'set every version := "'$CONTINUATIONS_VER'"' \
      'set every scalaVersion := "'$SCALA_VER'"' \
        "set resolvers in ThisBuild += $resolver"\
        "set every publishTo := Some($resolver)"\
        'set credentials in ThisBuild += Credentials(Path.userHome / ".ivy2" / ".credentials-private-repo")'\
      clean test publish


  update scala scala-swing "$SWING_REF"
  $sbtCmd $sbtArgs 'set version := "'$SWING_VER'"' \
      'set scalaVersion := "'$SCALA_VER'"' \
      "set publishTo := Some($resolver)"\
      'set credentials += Credentials(Path.userHome / ".ivy2" / ".credentials-private-repo")'\
      clean test publish

}


update scala scala $SCALA_REF

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


# build, test and publish modules with this core
# publish to our internal repo (so we can resolve the modules in the scala build below)
publishModulesPrivate


# # TODO: close all open staging repos so that we can be reaonably sure the only open one we see after publishing below is ours
# # the ant call will create a new one
# 
# Rebuild Scala with these modules so that all binary versions are consistent.
# Update versions.properties to new modules.
# Sanity check: make sure the Scala test suite passes / docs can be generated with these modules.
# don't skip locker (-Dlocker.skip=1\), or stability will fail
# stage to sonatype, along with all modules
cd $baseDir/scala
git clean -fxd
ant -Dstarr.version=$SCALA_VER\
    -Dextra.repo.url=$stagingRepo\
    -Dmaven.version.suffix=$SCALA_VER_SUFFIX\
    -Dscala.binary.version=$SCALA_VER\
    -Dpartest.version.number=$PARTEST_VER\
    -Dscala-xml.version.number=$XML_VER\
    -Dscala-parser-combinators.version.number=$PARSERS_VER\
    -Dscala-continuations-plugin.version.number=$CONTINUATIONS_VER\
    -Dscala-continuations-library.version.number=$CONTINUATIONS_VER\
    -Dscala-swing.version.number=$SWING_VER\
    -Dscalacheck.version.number=$SCALACHECK_VER\
    -Dupdate.versions=1\
    -Dscalac.args.optimise=-optimise\
    nightly publish-signed

open=$(st_stagingReposOpen)
lastOpenId=$(echo $open | jq  '.repositoryId' | tr -d \" | tail -n1)
lastOpenUrl=$(echo $open | jq  '.repositoryURI' | tr -d \" | tail -n1)
allOpen=$(echo $open | jq  '.repositoryId' | tr -d \")

echo "Most recent staging repo url: $lastOpenUrl"
echo "All open: $allOpen"

# publish to sonatype
buildModules clean test publish-signed

# was hoping we could make everything go to the same staging repo, but it's not timing that causes two staging repos to be opened
# -- maybe user-agent or something? WHY IS EVERYTHING SO HARD
# cd $baseDir/scala
# should not rebuild (already did nightly above), so -Dscalac.args.optimise should be irrelevant
# all versions have also been serialized to versions.properties
# skip locker since we're building with starr M8
# ant -Dextra.repo.url=$stagingRepo\
#     -Dmaven.version.suffix=$SCALA_VER_SUFFIX\
#     -Dscalac.args.optimise=-optimise\
#     -Dlocker.skip=1\
#     publish-signed
# buildModules publish

open=$(st_stagingReposOpen)
allOpenUrls=$(echo $open | jq  '.repositoryURI' | tr -d \")
allOpen=$(echo $open | jq  '.repositoryId' | tr -d \")

echo "Closing open repos: $allOpen"

for repo in $allOpen; do st_stagingRepoClose $repo; done

echo "Closed sonatype staging repos: $allOpenUrls."
echo "Update versions.properties, tag as v$SCALA_VER, publish 3rd-party modules (scalacheck, scalatest, akka-actor) against scala in the staging repo, and run scala-release-2.11.x."

# git commit versions.properties -m"Bump versions.properties for $SCALA_VER."
# TODO: push to github

# tag "v$SCALA_VER" "Scala v$SCALA_VER"

# used when testing scalacheck integration with partest, while it's in staging repo before releasing it
#     'set resolvers += "scalacheck staging" at "http://oss.sonatype.org/content/repositories/orgscalacheck-1010/"' \
# in ant: ()
#     -Dextra.repo.url=http://oss.sonatype.org/content/repositories/orgscalacheck-1010/\
