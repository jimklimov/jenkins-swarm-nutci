#!/usr/bin/env bash

# Check what Jenkins controller thinks about this agent - is it known? online?

SCRIPTDIR="`dirname "$0"`"
SCRIPTDIR="`cd "$SCRIPTDIR" && pwd`"

cd "$SCRIPTDIR/../jenkins-`hostname`/" || exit

( command -v curl || command -v wget ) >/dev/null 2>&1 || exit

JENKINS_URL="`grep -E '^url:' jenkins-swarm.yml | awk '{print $NF}' | sed -e 's,^"\(.*\)"$,\1,' -e 's,/*$,,'`"
NODENAME="`grep -E '^name:' jenkins-swarm.yml | awk '{print $NF}' | sed 's,^"\(.*\)"$,\1,'`"

TEMP="`mktemp -p "${TMPDIR:-/tmp}" -d swarm-client-healthCheck.XXXXXX`" || exit
trap 'rm -rf "$TEMP"' 0 1 2 3 15

API_URL="$JENKINS_URL/computer/$NODENAME/api/json"
if command -v curl >/dev/null 2>&1 ; then
    curl -vkL "$API_URL"
else
    wget -O - "$API_URL"
fi 1>"$TEMP/json-api.out" 2>"$TEMP/json-api.err"

if grep -E '^(< H|H)TTP.* 200' "$TEMP/json-api.err" >/dev/null ; then
    # Parse JSON
    if grep '"offline":true' "$TEMP/json-api.out" >/dev/null \
    || grep '"temporarilyOffline":false' "$TEMP/json-api.out" >/dev/null \
    ; then
        echo "VERDICT: Query for $API_URL returned HTTP/200 and JSON indicates the agent is known, offline, and not administratively downed (not temporarilyOffline)" >&2
        if grep 'OfflineCause$LaunchFailed' "$TEMP/json-api.out" >/dev/null ; then
            echo "VERDICT: Hit 'OfflineCause - LaunchFailed' " >&2
            exit 43
        fi
    fi
else
    if grep -E '^(< H|H)TTP.* 404' "$TEMP/json-api.err" >/dev/null ; then
        echo "VERDICT: Query for $API_URL returned HTTP/404 - assuming node is not recognized" >&2
        exit 44
    else
        echo "VERDICT: Query for $API_URL did not return HTTP/404 nor HTTP/200 - assuming query timeout etc." >&2
        exit 0
    fi
fi

# Should not get here
exit 0
