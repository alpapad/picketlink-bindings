#!/bin/sh

RELEASE_LOG_FILE="pl-release.log"
RELEASE_VERSION=""

# simple function used to execute comands from the script
execute_cmd() {
    "$@" > $RELEASE_LOG_FILE
}

# check if a previous maven build was successful or not
check_build_result() {
    if tail -n 100 pl-release.log|grep -F "BUILD SUCCESS" 
    then
        return 0
    else
        return 1;
    fi
}

# check if the release version was specified
check_release_version() {
	if [ "$RELEASE_VERSION" == "" ]; then
	   echo "--version not specified. Please use: --version X"
	   exit 1
	fi
}

# clean the local repo and revert all local modifications
clean_local_repo() {
    git clean -f -d
    git reset --hard upstream/master
    rm -rf release.properties
    rm -rf $RELEASE_LOG_FILE
}

# rollback a previous release attempt and prepare the local repo for another one
rollback() {
	check_release_version
    echo "Aborting ..."
    clean_local_repo
    git checkout develop
    clean_local_repo
    git checkout master
    clean_local_repo
    git branch -D release/$RELEASE_VERSION
    git push origin :release/$RELEASE_VERSION
    git push upstream :release/$RELEASE_VERSION
    git tag -d v$RELEASE_VERSION
    git push origin :refs/tags/v$RELEASE_VERSION
    git push upstream :refs/tags/v$RELEASE_VERSION
    echo "Done."    
}

# perform the release
release() {
	if [ "$DEVELOPMENT_VERSION" == "" ]; then
	   echo "--snapshot not specified. Please use: --snapshot X"
	   exit 1
	fi

	check_release_version

	rm -rf $RELEASE_LOG_FILE

	echo "###################################################"
	echo "            PicketLink Release Script              "
	echo "###################################################"

	echo ""

	echo "Current version: $DEVELOPMENT_VERSION"
	echo "Release version: $RELEASE_VERSION"
	echo ""

	echo "Preparing local repository to release."
	execute_cmd git checkout master
	echo "    Fetching latest changes from upstream..."
	execute_cmd git fetch upstream
	echo "    Merging latest changes into master..."
	execute_cmd git merge upstream/master
	echo "    Swithing to develop branch..."
	execute_cmd git checkout develop
	echo "    Merging latest changes into develop branch..."
	execute_cmd git merge master
	echo "Done."
	echo ""

        read -p "Check all project dependencies before releasing ?[y/n] " FLAG_NO_DEPENDENCY_CHECK

	if [ "$FLAG_NO_DEPENDENCY_CHECK" == "y" ]; then
		echo "Checking dependencies."
		execute_cmd mvn -DskipTests=true clean install dependency:resolve -Dmaven.repo.local=/tmp/release_repo
		if check_build_result; then
			echo "Done."
		else
			echo "ERROR: Error checking dependencies. Check the logs."
			exit 1;
		fi
	else
		echo "WARNING: Depedencies were not checked. This can impact users when downloading the project's artifacts."
	fi
	echo ""

	echo "Preparing to release using git flow."
	echo "    Starting release $RELEASE_VERSION..."
	execute_cmd git flow release start $RELEASE_VERSION
	echo "Done."
	echo ""

	echo "Preparing to release."
	echo "    Executing maven-release-plugin in DryRun mode..."
	execute_cmd mvn -DpreparationGoals="-Drelease -Prelease -DskipTests=true clean install" release:prepare	--batch-mode -DdevelopmentVersion=$DEVELOPMENT_VERSION -DreleaseVersion=$RELEASE_VERSION -Dtag=vRELEASE_VERSION	-DdryRun -DignoreSnapshots=true -Prelease
	if check_build_result; then     
		 read -p "Project is ready to release. Do you want to proceed ?[y/n] " FLAG_PERFORM_RELEASE
	else
		 echo "ERROR: Project build failed. Can not proceed with the release. Check the logs."
		 exit 1;
	fi

        FLAG_PERFORM_RELEASE="n"

	if [ "$FLAG_PERFORM_RELEASE" == "y" ]; then
		echo "Releasing version $RELEASE_VERSION."
		execute_cmd mvn -DpreparationGoals="-Drelease -Prelease clean install" release:prepare --batch-mode -DdevelopmentVersion=$DEVELOPMENT_VERSION -DreleaseVersion=$RELEASE_VERSION -Dtag=v$RELEASE_VERSION -Dresume=false -DignoreSnapshots=true -Prelease
		if check_build_result; then
			echo "Done."
		else
			echo "ERROR: Release failed."
			exit 1
		fi
	else
		exit 1
	fi
	echo ""

	FLAG_PUBLISH_NEXUS="n"
	read -p "Do you want to publish artifacts to Nexus staging repository ?[y/n] " FLAG_PUBLISH_NEXUS

	if [ "$FLAG_PUBLISH_NEXUS" == "y" ]; then
		echo "Publishing artifacts to Nexus. "
		execute_cmd mvn release:perform nexus:staging-close -Prelease
		echo "Done. You can now go to Nexus and finish release the artifacts."
	fi
	echo ""

	echo "Finishing the release."
	git flow release finish $RELEASE_VERSION
        clean_local_repo
        git branch -D release/$RELEASE_VERSION
        git push origin :release/$RELEASE_VERSION
        git push upstream :release/$RELEASE_VERSION
        git reset --hard upstream/master
	echo "Done."
	exit 0
}

usage()
{
cat << EOF
usage: $0 options

Use this script to release PicketLink versions.

OPTIONS:
   --snapshot      Snapshot version number to update from.
   --version       New snapshot version number to update to, if undefined, defaults to the version number updated from.
   --rollback      Undo a previous release attempt and prepares the local repo for a new one.
EOF
}

DEVELOPMENT_VERSION=""
FLAG_NO_DEPENDENCY_CHECK="false"
ROLLBACK="false"

while true; do
  case "$1" in
	 --help)
		 usage
		 exit
		 ;;
	 --snapshot )	     
		 DEVELOPMENT_VERSION=$2
		 shift
		 shift
		 ;;
	 --version )
		 RELEASE_VERSION=$2
		 shift
		 shift
		 ;;
	 --rollback )
		 ROLLBACK="true"
		 shift
		 ;;
	 -- ) 
	     shift; 
	     break ;;
     * ) 
         break 
         ;;
  esac
done

if [ "$ROLLBACK" == "true" ]; then
	rollback
	exit 0
fi

release
