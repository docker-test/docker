#!/usr/bin/env bash
set +x
set -e

ENV_PATH="/data/docker/deployment"
export DEPLOYMENT=${1-development}
export VERSION=$(cat VERSION)

DOCKER=docker
source "$ENV_PATH/docker-ci-${DEPLOYMENT}.sh"
nocache=''
[ -n "$NO_CACHE" ] && nocache='-no-cache'
source /data/virtualenv/docker-ci/bin/activate

vpn () {
    TOGGLE=${1-off}
    if [ "$TOGGLE" == "on" ]; then
        pgrep openvpn >/dev/null && sudo kill $(pgrep openvpn)
        sleep 3
        sudo openvpn /etc/openvpn/docker.ovpn >/dev/null &
        sleep 7
    else
        pgrep openvpn >/dev/null && sudo kill $(pgrep openvpn) >/dev/null
    fi }

run () {
    CMD=$@
    SERVER=${DOCKER_SERVER-localhost}
    ssh -q -o UserKnownHostsFile=/dev/null -p 2222 sysadmin@$SERVER $CMD
}

echo "Launching VPN"
if [ "$DEPLOYMENT" == "staging" ] || [ "$DEPLOYMENT" == "production" ]; then
    vpn on
fi

echo "VPN activated"
if [ -n "$NEW_DEPLOYMENT" ]; then
    $DOCKER -H $DOCKER_DAEMON run -v /home:/data ubuntu:12.04 mkdir -p /data/docker-ci/coverage/docker-index
    $DOCKER -H $DOCKER_DAEMON run -v /home:/data ubuntu:12.04 mkdir -p /data/docker-ci/coverage/docker-io
    $DOCKER -H $DOCKER_DAEMON run -v /home:/data ubuntu:12.04 chown -R 1000.1000 /data/docker-ci
fi

if [ -n "$BUILD_IMAGES" ]; then
# Build containers and feed docker-ci-data credential if needed
    # Signal development deployment to docker build (needed for nginx.conf)
    [ "$DEPLOYMENT" == "development" ] && touch development
    $DOCKER -H $DOCKER_DAEMON build $nocache -rm -t docker-ci/docker-ci .
    rm -f development
    (cd testbuilder; $DOCKER -H $DOCKER_DAEMON build $nocache -rm -t docker-ci/testbuilder .)
fi

echo "Deployment starts"
if [ "$DEPLOYMENT" == "development" ]; then
    fig up &
    sleep 10
else

    # Prepare dcr deployment environment
    dcr docker-ci.yml unregister_all $DOCKER_CI_DOMAIN || true

    VERSION_PREV=$(git show HEAD~:VERSION)
    if [ "$DEPLOYMENT" == "production" ] && [ "$VERSION" != "$VERSION_PREV" ]; then
        export RELEASE_NAME=${RELEASE_NAME%-*}-$VERSION_PREV
        dcr docker-ci.yml stop
        sleep 10
        export RELEASE_NAME=${RELEASE_NAME%-*}-$VERSION
    fi

    dcr docker-ci.yml stop
    dcr docker-ci.yml remove
    dcr docker-ci.yml start
    sleep 2
    dcr docker-ci.yml register $DOCKER_CI_DOMAIN
fi

if [ -n "$RESTORE_BACKUP" ]; then
    run sudo supervisorctl stop buildmaster
    run sudo supervisorctl stop buildworker
    run 'echo -e "[default]\naccess_key = '$BACKUP_AWS_ID'\nsecret_key = '$BACKUP_AWS_SECRET'" > ~/.s3cfg'
    run s3cmd get s3://$BACKUP_BUCKET/docker-ci.tgz
    run /bin/tar zxf docker-ci.tgz
    run cp /data/buildbot/master/master.cfg buildbot/master
    run rm -rf /data/buildbot/master
    run mv buildbot/master /data/buildbot/master
    run sudo rm -rf /data/docker-ci/coverage
    run sudo mv docker-ci/coverage /data/docker-ci
    run sudo supervisorctl start buildmaster
    run sudo supervisorctl start buildworker
fi

# Drop vpn
vpn off
