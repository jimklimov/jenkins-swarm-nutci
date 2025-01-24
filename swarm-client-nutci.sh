#!/bin/sh

# Jenkins Swarm Client integration for NUT CI farm
# Copyright (C)
#   2021-2024 by Jim Klimov <jimklimov+nut@gmail.com>
# License: MIT

# Launcher for Jenkins swarm agent (can do with shared homedir)
# Expected structure:
#   SCRIPTDIR/swarm-client-nutci.sh
#   SCRIPTDIR/swarm-client-X.YZ.jar
#   SCRIPTDIR/jenkins-swarm-nutci.yml.in
#   SCRIPTDIR/jenkins-swarm-nutci.token (github token generated for the nut-swarm account)
#
# Per worker:
#   SCRIPTDIR/../jenkins-`hostname`/
#   SCRIPTDIR/../jenkins-`hostname`/jenkins-swarm.labels
#   SCRIPTDIR/../jenkins-`hostname`/jenkins-swarm.yml.envlist (optional, `ENVVAR: "value"` per line)
#   SCRIPTDIR/../jenkins-`hostname`/jenkins-swarm.yml.extra (optional, appended in the end)
#   SCRIPTDIR/../jenkins-`hostname`/jenkins-swarm-prestart.include-early (optional, export whatever local envvars needed for this script)
#   SCRIPTDIR/../jenkins-`hostname`/jenkins-swarm-prestart.include (optional, export whatever local envvars needed just before java launch)
#   SCRIPTDIR/../jenkins-`hostname`/jenkins-swarm-prestart.sh (optional, do whatever local logic needed)
#   e.g. symlink to SCRIPTDIR/jenkins-swarm-prestart.nutci.linux-tmpfs.sh
#
# Systemd integration:
#   SCRIPTDIR/swarm-client-nutci.service (e.g. SCRIPTDIR=/home/abuild/jenkins-swarm/)
#     ln -rs /home/abuild/jenkins-swarm/swarm-client-nutci.service /etc/systemd/system/
#     systemctl daemon-reload
#     systemctl enable swarm-client-nutci.service
#     systemctl start swarm-client-nutci.service

SCRIPTDIR="`dirname "$0"`"
SCRIPTDIR="`cd "$SCRIPTDIR" && pwd`"

# NOTE: At this point we may not know the AGENT_NAME from a config file
# but may have it from service unit configuration etc. Normally we get
# (or reset) it with jenkins-swarm-prestart.include-early file.
[ -n "${AGENT_NAME-}" ] || AGENT_NAME="`hostname | sed 's,\..*$,,'`"
cd "$SCRIPTDIR/../jenkins-${AGENT_NAME}/" || exit

if [ -s ./jenkins-swarm-prestart.include-early ] ; then
	# e.g. source some custom AGENT_NAME, custom PATH to GNU toolkit, etc.
	echo "SOURCING `pwd`/jenkins-swarm-prestart.include-early"
	. ./jenkins-swarm-prestart.include-early || exit
else
	echo "NOT SOURCING `pwd`/jenkins-swarm-prestart.include-early (absent or empty)"
fi

if [ -z "$USER" ] ; then
	USER="`id -u`" && [ -n "$USER" ] || USER=abuild
	export USER
	echo "DETERMINED missing USER: $USER" >&2
fi

if [ -z "$HOME" ] ; then
	HOME="`getent passwd "$USER" | awk -F: '{print $6}'`" \
	&& [ -n "$HOME" ] && [ -d "$HOME" ] \
	|| HOME=/export/home/abuild
	export HOME
	echo "DETERMINED missing HOME: $HOME" >&2
fi

sed \
	-e 's,[@]SCRIPTDIR[@],'"${SCRIPTDIR}"',g' \
	-e 's,[@]HOMEDIR[@],'"${HOME}"',g' \
	-e 's,[@]HOME[@],'"${HOME}"',g' \
	< "$SCRIPTDIR/jenkins-swarm-nutci.yml.in" > "jenkins-swarm.yml"

cat >> "jenkins-swarm.yml" << EOF
name: "${AGENT_NAME-}"
description: "NUT CI swarm worker from ${AGENT_NAME-} launched `date -u`"
EOF

RE_TABSPACE="`printf '[\t ]'`"
if [ -s ./jenkins-swarm.yml.envlist ] ; then
	grep -E "^environmentVariables:" "jenkins-swarm.yml" > /dev/null \
	|| { echo "environmentVariables:" >> "jenkins-swarm.yml"; }

	# Indent with two spaces in a way that works on non-GNU userlands
	ENVLIST="`sed -e 's,^'"${RE_TABSPACE}"'*\(.*\)'"${RE_TABSPACE}"'*$,  \1,' -e 's,\",\\\\\\\\\",g' < ./jenkins-swarm.yml.envlist | grep -vE '^  $' | while IFS='' read LINE ; do printf '%sn%s' '\' "$LINE" ; done`"
	#printf 'ENVLIST: %s\n' "$ENVLIST"
	awk '{ if (/^environmentVariables:'"${RE_TABSPACE}"'*$/) {print $0"'"${ENVLIST}"'";} else { print $0 } }' \
	< "jenkins-swarm.yml" > "jenkins-swarm.yml.tmp" \
	&& mv -f "jenkins-swarm.yml.tmp" "jenkins-swarm.yml" \
	|| exit
fi

if [ -s ./jenkins-swarm.executors ] ; then
	grep "executors:" "jenkins-swarm.yml" > /dev/null \
	|| { echo "executors: 1" >> "jenkins-swarm.yml"; }

	EXECUTORS="`head -1 "./jenkins-swarm.executors"`"
	if [ "$EXECUTORS" -gt 0 ]; then
		sed -e 's~\(executors:\)'"${RE_TABSPACE}"'*[0-9]*$~\1 '"${EXECUTORS}"'~' \
			-i.bak "jenkins-swarm.yml"
	fi
fi

if [ -s ./jenkins-swarm.yml.extra ] ; then
	cat jenkins-swarm.yml.extra >> "jenkins-swarm.yml" || exit
fi

if [ -s ./jenkins-swarm-prestart.include ] ; then
	# e.g. source some PATH to JAVA_HOME
	echo "SOURCING `pwd`/jenkins-swarm-prestart.include"
	. ./jenkins-swarm-prestart.include || exit
else
	echo "NOT SOURCING `pwd`/jenkins-swarm-prestart.include (absent or empty)"
fi

if [ -x ./jenkins-swarm-prestart.sh ] ; then
	# e.g. local handler to instantiate "workspace" dir in tmpfs
	echo "RUNNING `pwd`/jenkins-swarm-prestart.sh"
	./jenkins-swarm-prestart.sh || exit
else
	echo "NOT RUNNING `pwd`/jenkins-swarm-prestart.sh (absent or not executable)"
fi

echo "=== Debug: jenkins-swarm.yml:"
cat "jenkins-swarm.yml"

echo "=== Debug: jenkins-swarm.labels:"
cat "jenkins-swarm.labels" || true

# Note: This may be not the "LASTVER" downloaded by swarm-client-download.sh
# e.g. if you "game the system" temporarily to try custom builds named like
#   swarm-client-99999-growingNumbers.jar
[ -n "${PREFERJAR-}" ] || PREFERJAR="`ls -1 "$SCRIPTDIR"/swarm-client-*.jar | sort -n | tail -1`"

echo "=== Launching Java for $PREFERJAR:"
set -x
exec java -jar "$PREFERJAR" \
	-config "jenkins-swarm.yml"
