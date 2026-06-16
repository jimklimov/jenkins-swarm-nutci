#!/bin/sh

# Jenkins Swarm Client integration for NUT CI farm
# Copyright (C)
#   2021-2026 by Jim Klimov <jimklimov+nut@gmail.com>
# License: MIT

# Settings below can be overridden by optional "swarm-client-download.conf":
# Fetches newest swarm client build, e.g.:
#LASTVER=1273.v578674cc1b_ca_.jar
### OLDER:
#LASTVER=3.25
#LASTVER=PR493-1

BASEURL="https://repo.jenkins-ci.org/releases/org/jenkins-ci/plugins/swarm-client/"

# Optional private CA collection
# * For Java:
[ -n "${CACERTS_JKS_BASENAME}" ] || CACERTS_JKS_BASENAME="jenkins-swarm.cacerts.jks"
# * For Curl:
[ -n "${CACERTS_PEM_BASENAME}" ] || CACERTS_PEM_BASENAME="jenkins-swarm.cacerts.pem"

[ -n "${AGENT_NAME-}" ] || AGENT_NAME="`hostname | sed 's,\..*$,,'`"

CURL_OPTS="-sL"
WGET_OPTS=""
getLastVer_Incrementals() {
	( curl $CURL_OPTS "${BASEURL}" || wget $WGET_OPTS -O - "${BASEURL}" ) \
	| grep -E '<a href="[0-9]+\.v[0-9a-f_]+/">' \
	| sed 's,^.*a href="\([0-9][0-9]*\.v[0-9a-f_]*\)/*".*$,\1,' \
	| grep -vE '^\d\.' \
	| sort -t. -k1,1n -k2,2n \
	| tail -1
}

getLastVer_Old() {
	( curl $CURL_OPTS "${BASEURL}" || wget $WGET_OPTS -O - "${BASEURL}" ) \
	| grep -E '<a href="[0-9]+\.[0-9]+/">' \
	| sed 's,^.*a href="\([0-9][0-9]*\.[0-9][0-9]*\)/*".*$,\1,' \
	| sort -t. -k1,1n -k2,2n \
	| tail -1
}

getLastVer() {
	getLastVer_Incrementals
}

SCRIPTDIR="`dirname \"$0\"`"
SCRIPTDIR="`cd \"${SCRIPTDIR}\" && pwd`"
cd "${SCRIPTDIR}"

[ -n "${AGENT_DIR-}" ] || AGENT_DIR="${SCRIPTDIR}/../jenkins-${AGENT_NAME}/"

if [ -s "./swarm-client-download.conf" ]; then
	ls -la "`pwd`/swarm-client-download.conf"
	. "./swarm-client-download.conf" || exit
fi

if [ -n "${CACERTS_PEM_BASENAME}" ] ; then
	CACERTS_PEM="${SCRIPTDIR}/${CACERTS_PEM_BASENAME}"

	if [ -n "${AGENT_DIR}" ] && [ -s "${AGENT_DIR}/${CACERTS_PEM_BASENAME}" ] ; then
		CACERTS_PEM="${AGENT_DIR}/${CACERTS_PEM_BASENAME}"
	fi

	if [ -s "${CACERTS_PEM_BASENAME}" ] ; then
		CURL_OPTS="${CURL_OPTS} --cacert '${CACERTS_PEM}'"
		WGET_OPTS="${WGET_OPTS} --ca-certificate='${CACERTS_PEM}'"
	fi
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
(  ( curl $CURL_OPTS "${JARURL}" > "${JARTMP}" && [ -s "${JARTMP}" ] ) \
|| ( wget $WGET_OPTS -O "${JARTMP}" "${JARURL}" && [ -s "${JARTMP}" ] ) ) \
&& mv -f "${JARTMP}" "swarm-client-${LASTVER}.jar"
