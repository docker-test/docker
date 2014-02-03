#!/bin/bash

export PATH='/go/bin':$PATH
export DOCKER_PATH='/go/src/github.com/dotcloud/docker'

# Signal coverage report name, parsed by docker-ci
set -x
COVERAGE_PATH=$(date +"docker-%Y%m%d%H%M%S")
set +x

REPORTS="/data/$COVERAGE_PATH"
INDEX="$REPORTS/index.html"

# Test docker
cd $DOCKER_PATH
./hack/make.sh test; exit_status=$?
PROFILE_PATH="$(ls -d $DOCKER_PATH/bundles/* | sed -n '$ p')/test/coverprofiles"

if [ "$exit_status" -eq "0" ]; then
    # Download coverage dependencies
    go get github.com/axw/gocov/gocov
    go get -u github.com/matm/gocov-html

    # Create coverage report
    mkdir -p $REPORTS
    cd $PROFILE_PATH
    echo "<HTML><TABLE BORDER=1><TR><TD colspan="2"><B>Docker Coverage Report</B></TD></TR>" >> $INDEX
    for profile in *; do
        gocov convert $profile | gocov-html >$REPORTS/$profile.html
        echo "<TR><TD><A HREF=\"${profile}.html\">$profile</A></TD><TD>" >> $INDEX
        go tool cover -func=$profile | sed -En '$ s/.+\t(.+)/\1/p' >> $INDEX
        echo "</TD></TR>" >> $INDEX
    done
    echo "</TABLE></HTML>" >> $INDEX
fi

# Signal test and coverage result, parsed by docker-ci
set -x
exit $exit_status

