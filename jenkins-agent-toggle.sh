#!/bin/sh

# Toggle Jenkins agent(s) running on local system on and off
# (e.g. free up CPU when needed for something else temporarily).
#
# (C) 2026 Jim Klimov <jimklimov+nut@gmail.com>
#
# Posted at https://gist.github.com/jimklimov/e8841ff5bbcf6a23a8ece7fe7cb53eb9
# Inspired by discussion at
# https://stackoverflow.com/questions/61389821/get-running-build-status-on-a-given-jenkins-worker-node
#
# Requires common shell tools, `curl`, `jq`

for T in jq curl ; do
    command -v $T > /dev/null || exit
done

# May be specified by caller, prefer that
# Use internal-scoped variable when we need to guess though
_AGENT_NAME="${AGENT_NAME}"
[ -n "${_AGENT_NAME-}" ] || _AGENT_NAME="`hostname | sed 's,\..*$,,'`"

# Run-time process owner on current system
# If not empty nor "-", used to modify CPU affinity and process priority
# for already running processes owned by that user (e.g. free up the
# processor for something else).
# May be configured below, or kept as is for typical nut-swarm use case:
[ -n "${JRT_USER}" ] || JRT_USER="abuild"

# Pick out matching "displayName" hits from current list of agents
# every time we run a query. Example: REGEX_DN='.*-rpiv'
[ -n "${REGEX_DN-}" ] || REGEX_DN="OPTIONALLY_CONFIGURE_THIS_REGEX_OR_IT_WILL_BE_DEFAULTED"

##########################################
# Stuff to configure in the config file
# (see tried locations below)

# Your Jenkins instance
[ -n "${JENKINS_URL-}" ] || JENKINS_URL="https://CONFIGURE_THIS_URL"

# Your user (to run admin commands as); the swarm account should suffice here
[ -n "${J_USER-}" ] || J_USER="CONFIGURE_THIS_jadmin"
# Generate a User Token from Jenkins account properties, put it here
[ -n "${J_PASS-}" ] || J_PASS="CONFIGURE_THIS_123hex"

##########################################
# Stuff for possible deployment-specific call wrappers to set (e.g. not a NUT CI farm)

# This may refer to a .in file in SCRIPTDIR or a file in AGENT_DIR:
[ -n "${JSN_YML_TEMPLATE_BASENAME-}" ] || JSN_YML_TEMPLATE_BASENAME="jenkins-swarm-nutci.yml"
#[ -n "${JSN_YML_TOKEN_BASENAME-}" ] || JSN_YML_TOKEN_BASENAME="jenkins-swarm-nutci.token"

# Optional private CA collection
# * For Java:
[ -n "${CACERTS_JKS_BASENAME}" ] || CACERTS_JKS_BASENAME="jenkins-swarm.cacerts.jks"
# * For Curl:
[ -n "${CACERTS_PEM_BASENAME}" ] || CACERTS_PEM_BASENAME="jenkins-swarm.cacerts.pem"
##########################################

LANG=C
LC_ALL=C
TZ=UTC
export LANG LC_ALL TZ

WSPACE="`printf '[\t ]'`"

die() {
    echo "[FATAL] $*" >&2
    exit 1
}

SCRIPTDIR="`dirname "$0"`"
if [ -n "${SCRIPTDIR}" ] ; then
    D="`cd \"${SCRIPTDIR}\" && pwd`" && [ -n "$D" ] && SCRIPTDIR="$D"
fi

# May be specified by caller, prefer that
# Use internal-scoped variable when we need to guess though
_AGENT_DIR="${AGENT_DIR}"
[ -n "${_AGENT_DIR-}" ] || _AGENT_DIR="${SCRIPTDIR}/../jenkins-${_AGENT_NAME}/"

getval_JSNyml() {
    grep -E '^ *'"$1"': ' | sed -e 's,^ *'"$1"': *,,' -e 's/^"\(.*\)"$/\1/' -e 's/^'"'"'\(.*\)'"'"'$/\1/'
}

read_configs_JSNyml_template() {
    [ -s "${SCRIPTDIR}/${JSN_YML_TEMPLATE_BASENAME}.in" ] || return
    ### [ -s "${SCRIPTDIR}/${JSN_YML_TOKEN_BASENAME}" ] || return

    FILE="${SCRIPTDIR}/${JSN_YML_TEMPLATE_BASENAME}.in"

    RES=0

    case "${J_PASS}" in
        *CONFIGURE_THIS*)
            VAL="`getval_JSNyml 'passwordFile' < \"$FILE\"`" && [ -n "$VAL" ] && {
                if [ -s "$VAL" ] ; then
                    J_PASS="`cat \"$VAL\"`" || RES=1
                else
                    VAL="`echo \"$VAL\" | sed 's,@SCRIPTDIR@,'\"${SCRIPTDIR}\",`"
                    if [ -s "$VAL" ] ; then
                        J_PASS="`cat \"$VAL\"`" || RES=1
                    else
                        echo "WARNING: Referenced token file '${VAL}' does not exist" >&2
                        RES=1
                    fi
                fi
            }
        ;;
    esac

    case "${J_USER}" in
        *CONFIGURE_THIS*)
            VAL="`getval_JSNyml 'username' < \"$FILE\"`" && [ -n "$VAL" ] && J_USER="$VAL" || RES=1
        ;;
    esac

    case "${JENKINS_URL}" in
        *CONFIGURE_THIS*)
            VAL="`getval_JSNyml 'url' < \"$FILE\"`" && [ -n "$VAL" ] && JENKINS_URL="$VAL" || RES=1
        ;;
    esac

    case "${REGEX_DN}" in
        *CONFIGURE_THIS*)
            # This one is not likely in the template:
            VAL="`getval_JSNyml 'name' < \"$FILE\" | tr '+' '.' | tr '|' '.' | tr '^' '.' | tr '$' '.'`" \
            && [ -n "$VAL" ] && REGEX_DN="^$VAL"'$' \
            || {
                # Consider AGENT_NAME envvar that may be set for the swarm agent configs or exported otherwise
                [ -n "${AGENT_NAME-}" ] && REGEX_DN="^${AGENT_NAME}"'$'
            }
        ;;
    esac

    echo "Applied configuration from $FILE" >&2
    return $RES
}

read_configs_JSNyml_per_agent() {
    [ -s "`pwd`/${JSN_YML_TEMPLATE_BASENAME}" ] && FILE="`pwd`/${JSN_YML_TEMPLATE_BASENAME}" \
    || {
        [ -s "${_AGENT_DIR}/${JSN_YML_TEMPLATE_BASENAME}" ] \
        && FILE="${_AGENT_DIR}/${JSN_YML_TEMPLATE_BASENAME}" \
        || {
            [ -s "${SCRIPTDIR}/../jenkins-${_AGENT_NAME}/${JSN_YML_TEMPLATE_BASENAME}" ] \
            && FILE="${SCRIPTDIR}/../jenkins-${_AGENT_NAME}/${JSN_YML_TEMPLATE_BASENAME}" \
            || return
        }
    }

    RES=0
    case "${J_PASS}" in
        *CONFIGURE_THIS*)
            VAL="`getval_JSNyml 'passwordFile' < \"$FILE\"`" && [ -n "$VAL" ] \
            && {
                if [ -s "$VAL" ] ; then
                    J_PASS="`cat \"$VAL\"`" || RES=1
                else
                    echo "WARNING: Referenced token file '${VAL}' does not exist" >&2
                    RES=1
                fi
            }
        ;;
    esac

    case "${J_USER}" in
        *CONFIGURE_THIS*)
            VAL="`getval_JSNyml 'username' < \"$FILE\"`" && [ -n "$VAL" ] && J_USER="$VAL" || RES=1
        ;;
    esac

    case "${JENKINS_URL}" in
        *CONFIGURE_THIS*)
            VAL="`getval_JSNyml 'url' < \"$FILE\"`" && [ -n "$VAL" ] && JENKINS_URL="$VAL" || RES=1
        ;;
    esac

    case "${REGEX_DN}" in
        *CONFIGURE_THIS*)
            VAL="`getval_JSNyml 'name' < \"$FILE\" | tr '+' '.' | tr '|' '.' | tr '^' '.' | tr '$' '.'`" && [ -n "$VAL" ] && REGEX_DN="^$VAL"'$' || RES=1
        ;;
    esac

    echo "Applied configuration from $FILE" >&2
    return $RES
}

read_configs_JATconf() {
    for FILE in \
        "${SCRIPTDIR}/jenkins-agent-toggle.conf" \
        "${HOME}/.jenkins-agent-toggle.conf" \
        "${HOME}/.config/jenkins-agent-toggle.conf" \
    ; do
        if [ -s "$FILE" ] ; then
            . "$FILE" || die "Could not source config from $FILE"
            echo "Applied configuration from $FILE" >&2
            return 0
        fi
    done

    echo "WARNING: Could not source a jenkins-agent-toggle.conf from any tried location" >&2
    return 1
}

do_read_configs() {
    # NOTE: We start with jenkins-agent-toggle.conf files
    #  because they can point to a different user account
    #  (higher privileged) than what swarm agents use.
    #  Account for swarm agents suffices to create/destroy
    #  them only, and a separate admin account may manage
    #  *other* agent states and metadata.
    for METHOD in read_configs_JATconf read_configs_JSNyml_per_agent read_configs_JSNyml_template ; do
        case "${JENKINS_URL}${J_USER}${J_PASS}${REGEX_DN}" in
            *CONFIGURE_THIS*) ${METHOD} ;;
            *) echo "We have all the required configuration, not looking at other sources" >&2; return 0 ;;
        esac
    done
}

read_configs() {
    do_read_configs

    case "${JENKINS_URL}${J_USER}${J_PASS}" in
        *CONFIGURE_THIS*) die "Some critical parameters remain not set" ;;
    esac

    JENKINS_URL="`echo \"${JENKINS_URL}\" | sed 's,/*$,,'`"

    case "${REGEX_DN}" in
        *CONFIGURE_THIS*)
            REGEX_DN="^${_AGENT_NAME}"
        ;;
    esac

    return 0
}

read_configs

toggle_off_on() {
    echo "=== `date -u`: Toggling off for now..."
    "$0" off
    echo "=== `date -u`: Querying resulting status"
    "$0" status
    echo "=== `date -u`: Sleeping $1 seconds to toggle back on..."
    sleep $1
    echo "=== `date -u`: Toggling back on"
    "$0" on
    echo "=== `date -u`: Querying resulting status"
    "$0" status
    echo "=== `date -u`: done"
    exit
}

toggle_on_status() {
    echo "=== `date -u`: Toggling back on"
    "$0" on
    echo "=== `date -u`: Sleeping $1 seconds to query status..."
    sleep $1
    echo "=== `date -u`: Querying resulting status"
    "$0" status
    echo "=== `date -u`: done"
    exit
}

toggle_off_status() {
    echo "=== `date -u`: Toggling off"
    "$0" off
    echo "=== `date -u`: Sleeping $1 seconds to query status..."
    sleep $1
    echo "=== `date -u`: Querying resulting status"
    "$0" status
    echo "=== `date -u`: done"
    exit
}

case "$1" in
    on|off|status|stop-graceful) ACTION="$1" ;;
    list) ACTION="$1" ; REGEX_DN='.*' ;;
    status-all) ACTION="status" ; REGEX_DN='.*' ;;
    on-status) toggle_on_status 5 ;;
    off-status) toggle_off_status 5 ;;
    off-3h)  toggle_off_on 10800 ;;
    off-10h) toggle_off_on 24000 ;;
    off-1m|"test")  toggle_off_on 60 ;;
    -h|--help|help) cat << EOF
$0 (on | off | off-1m [test] | off-3h | off-10h)
    NOTE: 'off' means administrative offlining (any running jobs finish when
          they do, new ones are not scheduled); agent JAR remains connected.

$0 list
$0 status
$0 status-all

$0 stop-graceful
    Initiate administrative offlining and wait for REGEX_DN agent(s) to be
    idle; only then exit this script (agent JAR remains connected - kill it
    separately, see swarm-client-nutci-stop.sh for example).
EOF
        exit
        ;;
    *) die "Unsupported option: '$1'" ;;
esac

adjust_runtime_impact_linux() {
    # NOTE: Typically only root may modify CPU affinity and niceness,
    #  especially toward the less restrictive values (when onlining):
    if [ -n "${JRT_USER}" ] && [ x"${JRT_USER}" != x- ] && command -v sudo && command -v taskset ; then
        # TODO: `ps -ef` is GNU, `taskset` is Linux.
        # * Expand this to more platforms?
        # * Detect/configure CPU numbers (cores 0-15 below)
        #   and the way to post them for a particular tool?
        JRT_PIDS="$(ps -ef | awk '($1 == "'"${JRT_USER}"'") {print $2}')"

        if [ -n "${JRT_PIDS}" ] ; then
            for P in $JRT_PIDS ; do
                case "$ACTION" in
                    on)  sudo taskset -pc 0-15 $P ;;
                    off) sudo taskset -pc 0 $P ;;
                esac
            done
        fi
    fi
}

adjust_runtime_impact() {
    # For processes owned by the expected run-time user ($JRT_USER),
    # reduce (if ACTION=off) or increase (on) the priority and/or
    # CPU affinity.
    # Requires OS-specific tools and usually the `sudo` ability or
    # running as `root` in the first place (especially to let some
    # process use more resources again).
    if [ x"${JRT_USER-}" = x ] || [ x"${ACTION-}" != xon -a x"${ACTION-}" != xoff ]; then
        return 0
    fi

    case "`uname -o | tr 'A-Z' 'a-z'`" in
        *linux*) adjust_runtime_impact_linux ;;
        *) echo "SKIP: Can not adjust_runtime_impact() on platform '`uname -o` yet" >&2 ;;
    esac
}

adjust_runtime_impact

EXIT_FLAG=false
cookie="`mktemp`" && [ -n "$cookie" ] || cookie="/tmp/cookie.$$"
trap "rm $cookie ; EXIT_FLAG=true" 0 1 2 3 15

### Set default curl options, to be used for every call:
# -f	Return failed exit code upon HTTP-400 and higher codes
CURL_ARGS_DEFAULT="-f"

case x"${DEBUG}" in
    xtrue)  CURL_ARGS_DEFAULT="${CURL_ARGS_DEFAULT} -v" ;;
    xlow)   ;;	# Default to middle verbosity = transfer stats
    x""|xfalse) CURL_ARGS_DEFAULT="${CURL_ARGS_DEFAULT} -s" ;;	# Actual default is quiet
esac


if [ -n "${CACERTS_PEM_BASENAME}" ] ; then
    CACERTS_PEM="${SCRIPTDIR}/${CACERTS_PEM_BASENAME}"
    if [ -n "${_AGENT_DIR}" ] && [ -s "${_AGENT_DIR}/${CACERTS_PEM_BASENAME}" ] ; then
        CACERTS_PEM="${_AGENT_DIR}/${CACERTS_PEM_BASENAME}"
    fi

    if [ -s "${CACERTS_PEM}" ] ; then
        CURL_ARGS_DEFAULT="${CURL_ARGS_DEFAULT} --cacert '${CACERTS_PEM}'"
    fi
fi

do_curlcmd() {
    CURL_ARGS="${CURL_ARGS_DEFAULT}"

    # -L	Follow location redirections (not for POST queries)
    case x"$*" in
        *XPOST*|*"X POST"*) ;;
        *)  CURL_ARGS="${CURL_ARGS} -L" ;;
    esac

    CURL_RES=0
    if [ x"${DEBUG}" = xtrue ] ; then
        { echo "=== COOKIE JAR: $cookie" ; cat "$cookie" ; } >&2 || true
        ( set -x ; curl $CURL_ARGS -b "$cookie" -c "$cookie" -u "${J_USER}:${J_PASS}" "$@" ) || CURL_RES=$?
    else
        curl $CURL_ARGS -b "$cookie" -c "$cookie" -u "${J_USER}:${J_PASS}" "$@" || CURL_RES=$?
    fi

    if [ x"${CURL_RES}" != x0 ] ; then
        echo "WARNING: curl call FAILED ($CURL_RES). If it is about 'HTTP-403 No valid crumb was included in the request' - check that your '${J_USER}' account has the needed permissions on Jenkins controller!" >&2
    fi

    return $CURL_RES
}

curlcmd() {
    OUT="`do_curlcmd \"$@\"`" || {
        sleep 15
        OUT="`do_curlcmd \"$@\"`"
    }
    echo "$OUT"
}

curlcmd_crumb() {
    curlcmd -H "${JENKINS_CRUMB_FIELD}:${JENKINS_CRUMB}" "$@"
}

curlcmd_crumb_POST() {
    curlcmd_crumb -X POST "$@"
}

JENKINS_CRUMB=""
JENKINS_CRUMB_FIELD="Jenkins-Crumb"
get_crumb() {
    echo "=== Getting Jenkins CSFR Token"
    OUT="$(curlcmd "${JENKINS_URL}/crumbIssuer/api/json")" && \
    JENKINS_CRUMB="$(echo "${OUT}" | jq -r '.crumb')"
    echo "===== CSFR Token: $JENKINS_CRUMB"
    [ -n "${JENKINS_CRUMB}" ] || die "Did not get JENKINS_CRUMB"

    VAL="$(echo "${OUT}" | jq -r '.crumbRequestField')" && [ -n "${VAL}" ] && JENKINS_CRUMB_FIELD="${VAL}"
}

RAW_NODE_LIST=""
FILTERED_NODE_LIST=""
get_node_list() {
    echo "... Getting Jenkins list of nodes which match regex '${REGEX_DN}'"

    [ -n "${JENKINS_CRUMB}" ] || get_crumb

    # This should have all detailed info about all nodes,
    # at least those visible to this account
    RAW_NODE_LIST="$(curlcmd_crumb "${JENKINS_URL}/computer/api/json?pretty=true")"
    #echo "${RAW_NODE_LIST}" > /tmp/raw-node-list
    [ -n "${RAW_NODE_LIST}" ] || die "Did not get RAW_NODE_LIST"

    # TODO: jq? Also query current node state to toggle on/off specifically?
    FILTERED_NODE_LIST="$(echo "${RAW_NODE_LIST}" | grep -E "\"displayName\"${WSPACE}*:${WSPACE}*\"[^ ]*\"," | awk '{print $NF}' | sed 's/["'"'"',]//g' | grep -Ev '^Nodes*$' | grep -E "${REGEX_DN}")"
    echo "=== FILTERED_NODE_LIST with regex '${REGEX_DN}':"
    echo "${FILTERED_NODE_LIST}"
    [ -n "${FILTERED_NODE_LIST}" ] || die "Did not get anything in FILTERED_NODE_LIST"
}

handle_action() {
    [ -n "${JENKINS_CRUMB}" ] || get_node_list

    if [ x"$ACTION" = xlist ] ; then
        # Reported for FILTERED_NODE_LIST above
        return
    fi

    # NOTE: Above we toggle also CPU affinity (TBD: process priorities?)
    for NODE_NAME in $FILTERED_NODE_LIST ; do
        if $EXIT_FLAG ; then
            echo "!!! Break received, aborting loop" >&2
            return
        fi

        echo ""
        echo "=== Researching node: $NODE_NAME"

        # FIXME: At least for the first round, it should suffice to parse
        #  the RAW_NODE_LIST with jq, instead of querying the server again
        NODE_INFO="$(curlcmd_crumb "$JENKINS_URL/computer/$NODE_NAME/api/json")"
        NODE_IDLE="$(echo "${NODE_INFO}" | jq ".idle")"
        NODE_OFFLINE="$(echo "${NODE_INFO}" | jq ".offline")"
        NODE_OFFLINE_TEMP="$(echo "${NODE_INFO}" | jq ".temporarilyOffline")"
        NODE_OFFLINE_CAUSE_CLASS="$(echo "${NODE_INFO}" | jq ".offlineCause._class")"
        NODE_OFFLINE_CAUSE_REASON="$(echo "${NODE_INFO}" | jq ".offlineCauseReason")"
        echo "Node Idle State: $NODE_IDLE"
        echo "Node Offline State: $NODE_OFFLINE"
        if [ x"$NODE_OFFLINE" = xtrue ] ; then
            STR=""
            if [ x"${NODE_OFFLINE_TEMP}" = xtrue ] ; then
                STR="Offlined temporarily."
            fi

            if [ x"${NODE_OFFLINE_CAUSE_CLASS}" != xnull ] \
            || [ x"${NODE_OFFLINE_CAUSE_REASON}" != xnull -a x"${NODE_OFFLINE_CAUSE_REASON}" != x'""' ] \
            ; then
                STR="${STR} Offline cause:"
                [ x"${NODE_OFFLINE_CAUSE_CLASS}" = xnull ] || STR="${STR} ${NODE_OFFLINE_CAUSE_CLASS}"
                [ x"${NODE_OFFLINE_CAUSE_REASON}" = xnull -o x"${NODE_OFFLINE_CAUSE_REASON}" = x'""' ] || STR="${STR} ${NODE_OFFLINE_CAUSE_REASON}"
            fi

            if [ -n "${STR}" ] ; then
                echo "* ${STR}"
            fi
        fi

        if [ x"$ACTION" = xstop-graceful ] ; then
            if [ x"$NODE_OFFLINE" = xfalse ] ; then
                echo "Toggling node: $NODE_NAME => off"
                curlcmd_crumb_POST "$JENKINS_URL/computer/$NODE_NAME/toggleOffline"
            else
                echo "Node already in desired logical state (off)"
            fi

            continue
        fi

        if [ x"$ACTION" != xoff ] && [ x"$ACTION" != xon ] ; then
            continue
        fi

        if ( [ x"$NODE_OFFLINE" = xtrue ] && [ x"$ACTION" = xoff ] ) \
        || ( [ x"$NODE_OFFLINE" = xfalse ] && [ x"$ACTION" = xon ] ) \
        ; then
            echo "Node already in desired logical state ($ACTION)"
            continue
        fi

        echo "Toggling node: $NODE_NAME => $ACTION"
        curlcmd_crumb_POST "$JENKINS_URL/computer/$NODE_NAME/toggleOffline"
    done

    if [ x"$ACTION" = xstop-graceful ] ; then
        echo "`date -u`: Waiting for nodes to be idle"

        while true ; do
            if $EXIT_FLAG ; then
                echo "!!! Break received, aborting loop" >&2
                return
            fi

            ALL_OFFLINE=true

            for NODE_NAME in $FILTERED_NODE_LIST ; do
                echo "=== Waiting for node to be idle: $NODE_NAME"

                # FIXME: Query for just the data points we parse?
                #  (Do it once for all names in FILTERED_NODE_LIST?)
                #  Less overheads all around...
                NODE_INFO="$(curlcmd_crumb "$JENKINS_URL/computer/$NODE_NAME/api/json")"
                NODE_IDLE="$(echo "${NODE_INFO}" | jq ".idle")"
                NODE_OFFLINE="$(echo "${NODE_INFO}" | jq ".offline")"
                echo "Node Idle State: $NODE_IDLE"
                echo "Node Offline State: $NODE_OFFLINE"

                if [ x"$NODE_OFFLINE" = xfalse ] ; then
                    echo "Toggling node: $NODE_NAME => off (again)"
                    curlcmd_crumb_POST "$JENKINS_URL/computer/$NODE_NAME/toggleOffline"
                fi

                if [ x"$NODE_OFFLINE" = xfalse ] || [ x"$NODE_IDLE" = xfalse ] ; then
                    ALL_OFFLINE=false
                fi
            done

            if $ALL_OFFLINE ; then
                echo "`date -u`: All nodes of interest are offline and idle"
                return
            else
                echo "`date -u`: Some nodes of interest are not yet offline and idle, waiting 10 sec"
                sleep 10
            fi
        done
    fi
}

handle_action
