#!/bin/sh

# Jenkins Swarm Client integration for NUT CI farm
# Copyright (C)
#   2021-2024 by Jim Klimov <jimklimov+nut@gmail.com>
# License: MIT

# Intended to be symlinked as
#   .../jenkins-`hostname`/jenkins-swarm-prestart.sh
# and to run from that directory as current

set -e

SCRIPTDIR="`dirname "$0"`"
SCRIPTDIR="`cd "$SCRIPTDIR" && pwd`"

cd "$SCRIPTDIR"

# NOTE: Some co-located deployments may want a `hostname` suffix etc. here.
# Can be done via export in their individual `jenkins-swarm-prestart.sh` files.
[ -n "${GITCACHE_DYNAMATRIX_PERSISTENT}" ] || GITCACHE_DYNAMATRIX_PERSISTENT="${HOME}/.gitcache-dynamatrix"
[ -n "${WSTMPDIR_NAME}" ] || WSTMPDIR_NAME="jenkins-nutci"

mkdir -p "${HOME}/.ccache"
mkdir -p "${GITCACHE_DYNAMATRIX_PERSISTENT}"
mkdir -p "${GITCACHE_DYNAMATRIX_PERSISTENT}@tmp"

[ -n "$TMPDIR" ] && [ -d "$TMPDIR" ] || TMPDIR="${SHMDIR}"
[ -n "$TMPDIR" ] && [ -d "$TMPDIR" ] || TMPDIR=/dev/shm
[ -n "$TMPDIR" ] && [ -d "$TMPDIR" ] || TMPDIR=/tmp
if [ -d "$TMPDIR" ] ; then
    #WSDIR="`mktemp -d "$TMPDIR/${WSTMPDIR_NAME}.XXXXXX"`"
    WSDIR="${TMPDIR}/${WSTMPDIR_NAME}"
    mkdir -p "$WSDIR"
    rm -rf workspace
    ln -srf "$WSDIR" ./workspace 2>/dev/null \
    || ln -sf "$WSDIR" ./workspace
fi

if [ -d ./workspace/.gitcache-dynamatrix ] || [ -L ./workspace/.gitcache-dynamatrix ] || [ -h ./workspace/.gitcache-dynamatrix ] ;
then :
else
    rm -f ./workspace/.gitcache-dynamatrix
    ln -srf "${GITCACHE_DYNAMATRIX_PERSISTENT}" ./workspace/.gitcache-dynamatrix 2>/dev/null \
    || ln -sf "${GITCACHE_DYNAMATRIX_PERSISTENT}" ./workspace/.gitcache-dynamatrix
fi

if [ -d "./workspace/.gitcache-dynamatrix@tmp" ] || [ -L "./workspace/.gitcache-dynamatrix@tmp" ] || [ -h "./workspace/.gitcache-dynamatrix@tmp" ] ;
then :
else
    rm -f "./workspace/.gitcache-dynamatrix@tmp"
    ln -srf "${GITCACHE_DYNAMATRIX_PERSISTENT}@tmp" "./workspace/.gitcache-dynamatrix@tmp" 2>/dev/null \
    || ln -sf "${GITCACHE_DYNAMATRIX_PERSISTENT}@tmp" "./workspace/.gitcache-dynamatrix@tmp"
fi
