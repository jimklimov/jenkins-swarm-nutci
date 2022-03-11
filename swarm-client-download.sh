#!/bin/sh

# Jenkins Swarm Client integration for NUT CI farm
# Copyright (C)
#   2021-2022 by Jim Klimov <jimklimov+nut@gmail.com>
# License: MIT

# Fetches newest swarm client

BASEURL="https://repo.jenkins-ci.org/releases/org/jenkins-ci/plugins/swarm-client/"

getLastVer() {
	( curl -s "${BASEURL}" || wget -O - "${BASEURL}" ) \
	| grep -E '<a href="[0-9]+\.[0-9]+/">' \
	| sed 's,^.*a href="\([0-9][0-9]*\.[0-9][0-9]*\)/*".*$,\1,' \
	| sort -t. -k1,1n -k2,2n \
	| tail -1
}

SCRIPTDIR="`dirname "$0"`"
SCRIPTDIR="`cd "$SCRIPTDIR" && pwd`"
cd "$SCRIPTDIR"

LASTVER="`getLastVer`" && [ -n "$LASTVER" ] || exit
if [ -s "swarm-client-${LASTVER}.jar" ] ; then
	echo "swarm-client-${LASTVER}.jar is the newest published version" >&2
	exit 0
fi

JARURL="${BASEURL}/${LASTVER}/swarm-client-${LASTVER}.jar"

echo "Fetching $JARURL" >&2
( curl -s "${JARURL}" > "swarm-client-${LASTVER}.jar.tmp" ) \
|| ( wget -O "swarm-client-${LASTVER}.jar.tmp" "${JARURL}" ) \
&& mv -f "swarm-client-${LASTVER}.jar.tmp" "swarm-client-${LASTVER}.jar"
