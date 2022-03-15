#!/bin/sh

sed -e 's,^pidFile:.*$,,' -i jenkins-swarm.yml

# Need GNU ln for script below
PATH="/usr/gnu/bin:$PATH"
export PATH

TMPDIR=/tmp/jenkins-swarm
mkdir -p "$TMPDIR" || exit
export TMPDIR

if [ -z "$USER" ] ; then
    USER="`id -u`" && [ -n "$USER" ] || USER=abuild
fi

if [ -z "$HOME" ] ; then
    HOME="`getent passwd "$USER" | awk -F: '{print $6}'`" \
    && [ -n "$HOME" ] && [ -d "$HOME" ] \
    || HOME=/export/home/abuild
    export HOME
fi

#./jenkins-swarm-prestart.nutci.linux-tmpfs.sh
. ../jenkins-swarm/jenkins-swarm-prestart.nutci.linux-tmpfs.sh

