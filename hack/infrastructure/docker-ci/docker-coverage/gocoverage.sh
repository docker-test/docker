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
    echo '<!DOCTYPE html><head><meta charset="utf-8">' > $INDEX
    echo '<script type="text/javascript" src="//tablesorter.com/jquery-latest.js"></script>' >> $INDEX
    echo '<script type="text/javascript" src="//tablesorter.com/__jquery.tablesorter.min.js"></script>' >> $INDEX
    echo '<script type="text/javascript">$(document).ready(function() { ' >> $INDEX
    echo '$("table").tablesorter({ sortForce: [[1,0]] }); });</script>' >> $INDEX
    echo '<style>table,th,td{border:1px solid black;}</style>' >> $INDEX
    echo '<title>Docker Coverage Report</title>' >> $INDEX
    echo '</head><body>' >> $INDEX
    echo '<h1><strong>Docker Coverage Report</strong></h1>'
    echo '<table class="tablesorter">' >> $INDEX
    echo '<thead><tr><th>package</th><th>pct</th></tr></thead><tbody>' >> $INDEX
    for profile in *; do
        gocov convert $profile | gocov-html >$REPORTS/$profile.html
        echo "<tr><td><a href=\"${profile}.html\">$profile</a></td><td>" >> $INDEX
        go tool cover -func=$profile | sed -En '$ s/.+\t(.+)/\1/p' >> $INDEX
        echo "</td></tr>" >> $INDEX
    done
    echo "</tbody></table></body></html>" >> $INDEX
fi

# Signal test and coverage result, parsed by docker-ci
set -x
exit $exit_status

