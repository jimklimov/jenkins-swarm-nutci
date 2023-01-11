#!/bin/sh

# Jenkins Swarm Client integration for NUT CI farm
# Copyright (C)
#   2021-2023 by Jim Klimov <jimklimov+nut@gmail.com>
# License: MIT

# Fetches newest swarm client
#LASTVER=3.25
#LASTVER=PR493-1

BASEURL="https://repo.jenkins-ci.org/releases/org/jenkins-ci/plugins/swarm-client/"

getLastVer() {
	( curl -sL "${BASEURL}" || wget -O - "${BASEURL}" ) \
	| grep -E '<a href="[0-9]+\.[0-9]+/">' \
	| sed 's,^.*a href="\([0-9][0-9]*\.[0-9][0-9]*\)/*".*$,\1,' \
	| sort -t. -k1,1n -k2,2n \
	| tail -1
}

SCRIPTDIR="`dirname "$0"`"
SCRIPTDIR="`cd "$SCRIPTDIR" && pwd`"
cd "$SCRIPTDIR"

{ [ -n "${LASTVER-}" ] || LASTVER="`getLastVer`" ; } && [ -n "$LASTVER" ] || exit
if [ -s "swarm-client-${LASTVER}.jar" ] ; then
	echo "swarm-client-${LASTVER}.jar is the newest published version" >&2
	exit 0
fi

JARURL="${BASEURL}/${LASTVER}/swarm-client-${LASTVER}.jar"

echo "Fetching $JARURL" >&2
(  ( curl -sL "${JARURL}" > "swarm-client-${LASTVER}.jar.tmp" && [ -s "swarm-client-${LASTVER}.jar.tmp" ] ) \
|| ( wget -O "swarm-client-${LASTVER}.jar.tmp" "${JARURL}" && [ -s "swarm-client-${LASTVER}.jar.tmp" ] ) ) \
&& mv -f "swarm-client-${LASTVER}.jar.tmp" "swarm-client-${LASTVER}.jar"
