#!/bin/sh

. ../jenkins-swarm/jenkins-swarm-prestart.nutci.macos-homebrew.include

#sed -e 's,^pidFile:.*$,,' -i.bak jenkins-swarm.yml
#cat >> jenkins-swarm.yml << EOF
#keepDisconnectedClients: false
#webSocket: false
#EOF

[ -n "$TMPDIR" ] && [ -d "$TMPDIR" ] || TMPDIR="${SHMDIR}"
[ -n "$TMPDIR" ] && [ -d "$TMPDIR" ] || TMPDIR=/tmp/jenkins-swarm
mkdir -p "$TMPDIR" || exit
export TMPDIR

# Needs sudoers-abuild-macos set up properly
# Recommended to comment away inheriting TMPDIR from caller above
# and just hard-code e.g. /tmp/jenkins-swarm here and in sudoers
# (for better security)
if ( [ -x /sbin/mount_tmpfs ] && command -v sudo) >/dev/null 2>/dev/null ; then
    if [ -n "`/sbin/mount | grep "${TMPDIR}"`" ] ; then : ; else
        # Can this can be automated in /etc/fstab equivalent?
        # -e : case-sensitive; -s X : size (RAM)
        sudo /sbin/mount_tmpfs -s 2G -e -o nodev,noatime,nosuid "${TMPDIR}" \
        && sudo /bin/chmod 1777 "${TMPDIR}" \
        || echo "FAILED to prepare tmpfs at $TMPDIR" >&2
    fi
fi

. ../jenkins-swarm/jenkins-swarm-prestart.nutci.linux-tmpfs.sh
