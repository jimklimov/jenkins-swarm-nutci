#!/bin/sh

sed -e 's,^pidFile:.*$,,' -i.bak jenkins-swarm.yml
cat >> jenkins-swarm.yml << EOF
keepDisconnectedClients: false
webSocket: false
EOF

# Need GNU ln for script below
PATH="/usr/gnu/bin:$PATH"
export PATH

[ -n "$TMPDIR" ] && [ -d "$TMPDIR" ] || TMPDIR="${SHMDIR}"
[ -n "$TMPDIR" ] && [ -d "$TMPDIR" ] || TMPDIR=/tmp/jenkins-swarm
mkdir -p "$TMPDIR" || exit
export TMPDIR

#./jenkins-swarm-prestart.nutci.linux-tmpfs.sh
. ../jenkins-swarm/jenkins-swarm-prestart.nutci.linux-tmpfs.sh

