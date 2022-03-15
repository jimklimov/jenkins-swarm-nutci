#!/bin/sh

# Jenkins Swarm Client integration for NUT CI farm
# Copyright (C)
#   2021-2022 by Jim Klimov <jimklimov+nut@gmail.com>
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

cd "$SCRIPTDIR/../jenkins-`hostname`/" || exit

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
name: "`hostname | sed 's,\..*$,,'`"
description: "NUT CI swarm worker from `hostname | sed 's,\..*$,,'` launched `date -u`"
EOF

RE_TABSPACE="`printf '[\t ]'`"
if [ -s ./jenkins-swarm.yml.envlist ] ; then
	grep -E "^environmentVariables:" "jenkins-swarm.yml" > /dev/null \
	|| { echo "environmentVariables:" >> "jenkins-swarm.yml"; }

	# Indent with two spaces
	ENVLIST="`sed 's,^'"${RE_TABSPACE}"'*\(.*\)'"${RE_TABSPACE}"'*$,  \1,' < ./jenkins-swarm.yml.envlist | grep -vE '^  $' | sed -e 's,\n,\\\\n,g'`"
	sed -e 's~^\(environmentVariables:\)'"${RE_TABSPACE}"'*$~\1\n'"${ENVLIST}"'~' \
		-i "jenkins-swarm.yml"
fi

if [ -s ./jenkins-swarm.executors ] ; then
	grep "executors:" "jenkins-swarm.yml" > /dev/null \
	|| { echo "executors: 1" >> "jenkins-swarm.yml"; }

	EXECUTORS="`head -1 "./jenkins-swarm.executors"`"
	if [ "$EXECUTORS" -gt 0 ]; then
		sed -e 's~\(executors:\)'"${RE_TABSPACE}"'*[0-9]*$~\1 '"${EXECUTORS}"'~' \
			-i "jenkins-swarm.yml"
	fi
fi

if [ -x ./jenkins-swarm-prestart.include ] ; then
	# e.g. source some PATH to JAVA_HOME
	. ./jenkins-swarm-prestart.include || exit
fi

if [ -x ./jenkins-swarm-prestart.sh ] ; then
	# e.g. local handler to instantiate "workspace" dir in tmpfs
	./jenkins-swarm-prestart.sh || exit
fi

exec java -jar "`ls -1 "$SCRIPTDIR"/swarm-client-*.jar | sort -n | tail -1`" \
	-config "jenkins-swarm.yml"
