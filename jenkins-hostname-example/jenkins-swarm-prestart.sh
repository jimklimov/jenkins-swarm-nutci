#!/bin/sh

# Wrapper for an agent's customized pre-start logic and settings

echo "disableSslVerification: true" >> jenkins-swarm.yml

# For co-located workers sharing storage via NFS:
GITCACHE_DYNAMATRIX_PERSISTENT="${HOME}/.gitcache-dynamatrix-`hostname`"
export GITCACHE_DYNAMATRIX_PERSISTENT

../jenkins-swarm/jenkins-swarm-prestart.nutci.linux-tmpfs.sh
