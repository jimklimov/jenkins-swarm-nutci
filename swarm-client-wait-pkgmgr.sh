#!/bin/sh

# Block while any known package manager is active, then require a quiet
# period, so bursts of package-triggered restarts collapse into one start.
#
# Copyright (C)
#   2026 by Jim Klimov <jimklimov+nut@gmail.com>
# License: MIT
#
# Details worth knowing:
#  - You may have to run this script as root in the service definition,
#    because it accesses paths intimate to the OS/package manager.
#  - Java restart is usually triggered not only by Java package updates,
#    but also its dependencies like libc, libz, crypto, etc.
#  - Debian/Ubuntu: `needrestart` runs after each dpkg batch of an unattended
#    upgrade, so can cause multiple restarts of swarm-client service.
#  - RPM distros (RHEL, Fedora, SUSE): packages only restart their own services
#    through %systemd_postun_with_restart, so this unit is not normally restarted.
#    `dnf needs-restarting` only reports. You will see bursts only if something
#    like tracer or a custom hook restarts services. The script is harmless there.
#  - Arch: pacman does not restart services by default. The same applies unless
#    you have a hook such as `needrestart-pacman` or `checkservices`.
#  - Hard-coded paths: the fuser and pidfile paths are the current defaults.
#    Verify them on each distro.
#    For example, .rpm.lock appears with rpm 4.16 and later.
#    The /lib/apk/db/lock entry is included for Alpine, but Alpine uses OpenRC,
#    so the unit would not apply.
#  - fuser: it comes from psmisc. If it is missing, the script silently skips
#    that check and relies on the units and pidfiles.
#  - More platforms (not only Linux?) - TBD... PRs welcome!

SETTLE="${SETTLE:-20}"

busy_unit() {  # any of the usual package-update units active?
    systemctl is-active --quiet \
        apt-daily.service apt-daily-upgrade.service \
        dnf-automatic.service dnf-automatic-install.service \
        dnf5-automatic.service packagekit-offline-update.service \
        2>/dev/null
}

busy_pidfile() {  # dnf/yum/zypper keep a pidfile; stale ones don't count
    for f in /run/dnf.pid /var/run/yum.pid /run/zypp.pid; do
        [ -s "$f" ] && kill -0 "`cat "$f"`" 2>/dev/null && return 0
    done
    return 1
}

busy_lockfile() {  # pacman: db.lck exists only while it runs
    [ -e /var/lib/pacman/db.lck ] || [ -e /lib/apk/db/lock ] && return 0
    return 1
}

busy_flock() {  # held-lock files: dpkg/apt, rpm
    command -v fuser >/dev/null 2>&1 || return 1
    for f in /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock \
             /var/lib/rpm/.rpm.lock ; do
        [ -e "$f" ] && fuser -s "$f" 2>/dev/null && return 0
    done
    return 1
}

busy() { busy_unit || busy_pidfile || busy_lockfile || busy_flock; }

START="`LANG=C LC_ALL=C TZ=UTC date`" || START=1
while busy; do sleep 5; done
FINISH="`LANG=C LC_ALL=C TZ=UTC date`" || FINISH=2

# NOTE: This might sometimes delay because the second flipped,
#  while there was nothing to do - oh well...
if [ x"$START" = x"$FINISH" ] ; then
    echo "Package management activities not detected, not delaying" >&2
else
    echo "Package management activities no longer detected, sleeping $SETTLE sec to settle" >&2
    sleep "$SETTLE"
fi
