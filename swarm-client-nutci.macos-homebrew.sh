#!/bin/ksh
#
# Jenkins Swarm Client integration for NUT CI farm
# Copyright (C)
#   2021-2026 by Jim Klimov <jimklimov+nut@gmail.com>
# License: MIT
#
# MacOS launcher wrapper for jenkins swarm client.
# Note that there is only a start method in plist(5)
# and service stop should be handled via SIGTERM,
# so this wrapper persists with a `trap` for that.

JRT_USER="abuild"
SCRIPTDIR="/Users/${JRT_USER}/jenkins-swarm"

"${SCRIPTDIR}"/swarm-client-download.sh || exit

CLEANUP_NEEDED=true
cleanup() {
    RES=$?
    if $CLEANUP_NEEDED ; then
        "${SCRIPTDIR}"/swarm-client-nutci-stop.sh stop
    else
        return $RES
    fi
}

trap cleanup TERM QUIT INT EXIT 0

# Start the Jenkins agent
"${SCRIPTDIR}"/swarm-client-nutci.sh &

APP_PID=$!

wait $APP_PID

# If we somehow get here (agent process exits), too late for graceful exit:
CLEANUP_NEEDED=false
