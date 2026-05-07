#!/bin/sh

# Toggle Jenkins agent(s) running on local system on and off
# (e.g. free up CPU when needed for something else temporarily).
#
# (C) 2026 Jim Klimov <jimklimov+nut@gmail.com>
#
# Posted at https://gist.github.com/jimklimov/e8841ff5bbcf6a23a8ece7fe7cb53eb9
# Inspired by discussion at
# https://stackoverflow.com/questions/61389821/get-running-build-status-on-a-given-jenkins-worker-node

# Run-time process owner on current system
# If not empty nor "-", used to modify CPU affinity and process priority
# for already running processes owned by that user (e.g. free up the
# processor for something else).
# May be configured below, or kept as is for typical nut-swarm use case:
[ -n "${JRT_USER}" ] || JRT_USER="abuild"

# Pick out matching "displayName" hits from current list of agents every time we run:
#REGEX_DN='.*-rpiv'
REGEX_DN="`hostname`"

##########################################
# Stuff to configure in the config file
# (see tried locations below)

# Your Jenkins instance
JENKINS_URL="https://CONFIGURE_THIS_URL"

# Your user (to run admin commands as)
J_USER="CONFIGURE_THIS_jadmin"
# Generate a User Token from Jenkins account properties, put it here
J_PASS="CONFIGURE_THIS_123hex"

##########################################

LANG=C
LC_ALL=C
TZ=UTC
export LANG LC_ALL TZ

WSPACE="`printf '[\t ]'`"

die() {
    echo "[FATAL] $*" >&2
    exit 1
}

SCRIPTDIR="`dirname "$0"`"
if [ -n "$SCRIPTDIR" ] ; then
    D="`cd \"$SCRIPTDIR\" && pwd`" && [ -n "$D" ] && SCRIPTDIR="$D"
fi

for F in \
    "${SCRIPTDIR}/jenkins-agent-toggle.conf" \
    "${HOME}/.jenkins-agent-toggle.conf" \
    "${HOME}/.config/jenkins-agent-toggle.conf" \
    die \
; do
    [ "$F" = die ] && die "Could not source config from any tried location"
    if [ -s "$F" ] ; then
        . "$F" || die "Could not source config from $F"
    fi
done

toggle_off_on() {
    echo "=== `date -u`: Toggling off for now..."
    "$0" off
    echo "=== `date -u`: Sleeping $1 seconds to toggle back on..."
    sleep $1
    echo "=== `date -u`: Toggling back on"
    "$0" on
    echo "=== `date -u`: done"
    exit
}

case "$1" in
    on) ACTION=on ;;
    off) ACTION=off ;;
    off-3h)  toggle_off_on 10800 ;;
    off-10h) toggle_off_on 24000 ;;
    off-1m|"test")  toggle_off_on 60 ;;
    -h|--help|help) cat << EOF
$0 (on | off | off-1m [test] | off-3h | off-10h)
EOF
        exit
        ;;
    *) die "Unsupported option: '$1'" ;;
esac

# NOTE: Typically only root may modify CPU affinity and niceness,
#  especially toward the less restrictive values (when onlining):
if [ -n "${JRT_USER}" ] && [ x"${JRT_USER}" != x- ] && command -v sudo && command -v taskset ; then
    # TODO: `ps -ef` is GNU, `taskset` is Linux.
    # * Expand this to more platforms?
    # * Detect/configure CPU numbers (cores 0-15 below)
    #   and the way to post them for a particular tool?
    JRT_PIDS="$(ps -ef | awk '($1 == "'"${JRT_USER}"'") {print $2}')"

    if [ -n "${JRT_PIDS}" ] ; then
        for P in $JRT_PIDS ; do
            case "$ACTION" in
                on)  sudo taskset -pc 0-15 $P ;;
                off) sudo taskset -pc 0 $P ;;
            esac
        done
    fi
fi

cookie="`mktemp`" && [ -n "$cookie" ] || cookie="/tmp/cookie.$$"
trap "rm $cookie" 0 1 2 3 15

do_curlcmd() {
    curl -s -c "$cookie" -u "${J_USER}:${J_PASS}" "$@"
}

curlcmd() {
    OUT="`do_curlcmd \"$@\"`" || {
        sleep 15
        OUT="`do_curlcmd \"$@\"`"
    }
    echo "$OUT"
}

curlcmd_crumb() {
    curlcmd -H "Jenkins-Crumb:${JENKINS_CRUMB}" "$@"
}

curlcmd_crumb_POST() {
    curlcmd_crumb -X POST "$@"
}

echo "Getting Jenkins CSFR Token"
JENKINS_CRUMB="$(curlcmd "${JENKINS_URL}/crumbIssuer/api/json" | jq -r '.crumb')"
echo "CSFR Token: $JENKINS_CRUMB"
[ -n "${JENKINS_CRUMB}" ] || die "Did not get JENKINS_CRUMB"

RAW_NODE_LIST="$(curlcmd_crumb "${JENKINS_URL}/computer/api/json?pretty=true")"
[ -n "${RAW_NODE_LIST}" ] || die "Did not get RAW_NODE_LIST"

# TODO: jq? Also query current node state to toggle on/off specifically?
FILTERED_NODE_LIST="$(echo "${RAW_NODE_LIST}" | grep -E "\"displayName\"${WSPACE}*:${WSPACE}*\"${REGEX_DN}\"," | awk '{print $NF}' | sed 's/["'"'"',]//g')"
echo "FILTERED_NODE_LIST: ${FILTERED_NODE_LIST}"
[ -n "${FILTERED_NODE_LIST}" ] || die "Did not get anything in FILTERED_NODE_LIST"

# NOTE: Above we toggle also CPU affinity (TBD: process priorities?)
for NODE_NAME in $FILTERED_NODE_LIST ; do
    echo "=== Researching node: $NODE_NAME"

    NODE_INFO="$(curlcmd_crumb "$JENKINS_URL/computer/$NODE_NAME/api/json")"
    NODE_IDLE="$(echo "${NODE_INFO}" | jq ".idle")"
    NODE_OFFLINE="$(echo "${NODE_INFO}" | jq ".offline")"
    echo "Node Idle State: $NODE_IDLE"
    echo "Node Offline State: $NODE_OFFLINE"

    if ( [ x"$NODE_OFFLINE" = xtrue ] && [ x"$ACTION" = xoff ] ) \
    || ( [ x"$NODE_OFFLINE" = xfalse ] && [ x"$ACTION" = xon ] ) \
    ; then
        echo "Node already in desired logical state ($ACTION)"
        continue
    fi

    echo "Toggling node: $NODE_NAME => $ACTION"
    curlcmd_crumb_POST "$JENKINS_URL/computer/$NODE_NAME/toggleOffline"
done
