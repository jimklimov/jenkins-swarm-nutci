#!/bin/sh

# Jenkins Swarm Client integration for NUT CI farm
# Copyright (C)
#   2021-2023 by Jim Klimov <jimklimov+nut@gmail.com>
# License: MIT

# Settings below can be overridden by optional "swarm-client-download.conf":
# Fetches newest swarm client build, e.g.:
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

if [ -s "./swarm-client-download.conf" ]; then
	ls -la "`pwd`/swarm-client-download.conf"
	. "./swarm-client-download.conf" || exit
fi

{ [ -n "${LASTVER-}" ] || LASTVER="`getLastVer`" ; } && [ -n "$LASTVER" ] || exit
if [ -s "swarm-client-${LASTVER}.jar" ] ; then
	echo "swarm-client-${LASTVER}.jar is the newest published version" >&2
	exit 0
fi

JARURL="${BASEURL}/${LASTVER}/swarm-client-${LASTVER}.jar"

echo "Fetching $JARURL" >&2
# Let several runners coexist in same homedir... somehow
JARTMP="swarm-client-${LASTVER}.jar.$$.tmp"
(  ( curl -sL "${JARURL}" > "${JARTMP}" && [ -s "${JARTMP}" ] ) \
|| ( wget -O "${JARTMP}" "${JARURL}" && [ -s "${JARTMP}" ] ) ) \
&& mv -f "${JARTMP}" "swarm-client-${LASTVER}.jar"
