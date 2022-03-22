#!/bin/sh

# Jenkins Swarm Client integration for NUT CI farm
# Copyright (C)
#   2021-2022 by Jim Klimov <jimklimov+nut@gmail.com>
# License: MIT

# Intended to be symlinked as
#   .../jenkins-`hostname`/jenkins-swarm-prestart.sh
# and to run from that directory as current

set -e

SCRIPTDIR="`dirname "$0"`"
SCRIPTDIR="`cd "$SCRIPTDIR" && pwd`"

cd "$SCRIPTDIR"

mkdir -p "${HOME}/.ccache"
mkdir -p "${HOME}/.gitcache-dynamatrix"
mkdir -p "${HOME}/.gitcache-dynamatrix@tmp"

[ -n "$TMPDIR" ] && [ -d "$TMPDIR" ] || TMPDIR=/dev/shm
[ -n "$TMPDIR" ] && [ -d "$TMPDIR" ] || TMPDIR=/tmp
if [ -d "$TMPDIR" ] ; then
    WSDIR="`mktemp -d "$TMPDIR/jenkins-nutci.XXXXXX"`"
    rm -rf workspace
    ln -srf "$WSDIR" ./workspace
fi

ln -srf "${HOME}/.gitcache-dynamatrix" ./workspace/.gitcache-dynamatrix
ln -srf "${HOME}/.gitcache-dynamatrix@tmp" "./workspace/.gitcache-dynamatrix@tmp"
