#!/bin/sh
#
# chkconfig: - 70 40
# description: Init-script for jenkins swarm client for NUT CI farm
#
### BEGIN INIT INFO
# Provides: swarm_client_nutci
# Required-Start: $network $remote_fs $syslog
# Required-Stop:  $network $remote_fs $syslog
# Default-Start:  3 5
# Default-Stop:   0 1 2 6
# Short-Description: Start and stop swarm_client_nutci
# Description: Init-script for jenkins swarm client for NUT CI farm
### END INIT INFO
#
# Init-script for jenkins swarm client
# Symlink as /etc/init.d/swarm_client_nutci and then
#   chkconfig --add swarm_client_nutci
#
# May also work for systems with rc.d approach -
# Symlink as /etc/init.d/rc.swarm_client_nutci and hope it works :)

#exec >> /var/log/swarm_client_nutci.rcctl.log 2>&1
#echo "===== `date`: $0 $*"
#set -x

# These lines run as root, regardless of daemon_user
if [ -n "`/sbin/mount | grep /dev/shm`" ] ; then : ; else
    # This can be automated in /etc/fstab with such line:
    #   swap /dev/shm mfs rw,nodev,nosuid,-s=1536000 0 0
    mkdir /dev/shm
    mount -t tmpfs -o rw,nodev,nosuid,inode64 swap /dev/shm
fi
if [ -d /dev/shm ]; then chmod 1777 /dev/shm ; fi

daemon_user="abuild"
touch /var/log/swarm-client-nutci
chown ${daemon_user} /var/log/swarm-client-nutci

# allow larger resource limits (consider even "daemon" for unlimited?)
# see /etc/login.conf for standard definitions
#usermod -L pbuild ${daemon_user}

downloader="/home/abuild/jenkins-swarm/swarm-client-download.sh >> /var/log/swarm-client-nutci 2>&1"
daemon="/home/abuild/jenkins-swarm/swarm-client-nutci.sh"
#daemon="cd /dev/shm && nohup /home/abuild/jenkins-swarm/swarm-client-nutci.sh >> /var/log/swarm-client-nutci 2>&1 &"
#daemon="/bin/sh -c \\' cd /dev/shm && nohup /home/abuild/jenkins-swarm/swarm-client-nutci.sh >> /var/log/swarm-client-nutci 2>&1 \\' &"

# Allow to restart the service on command line (or via rcctl)
#INRC=1
#. /etc/rc.d/rc.subr

rc_start() {
	echo "`date`: Starting $0" >> /var/log/swarm-client-nutci
#	exec >> /var/log/swarm_client_nutci.rcctl.log 2>&1
#	set -x
#	set -v
	PATH="$PATH:/usr/local/sbin:/usr/local/bin" ${downloader}
	#cd /dev/shm || exit

	# Leading single-token no-op due to shell inlining peculiarities generally
	cd /dev/shm && nohup su - ${daemon_user} -c ' true; ulimit -a >&2; /home/abuild/jenkins-swarm/swarm-client-nutci.sh' >> /var/log/swarm-client-nutci 2>&1 &
}

rc_stop() {
	echo "`date`: Stopping $0" >> /var/log/swarm-client-nutci
	kill -15 `ps -xawwu | grep java | grep swarm-client | grep ${daemon_user} | awk '{print $2}'`
}

rc_check() {
	ps -xawwu | grep java | grep swarm-client | grep ${daemon_user} | awk '{print $2}'
}

#set -x
#rc_cmd $1

case "$1" in
	start) rc_start;;
	stop)  rc_stop;;
	restart) rc_stop; wait; sleep 3; rc_start ;;
	status|check) rc_check ;;
	*) echo "Unknown verb: $1" >&2; exit 1 ;;
esac
