function start_Xserver {
	echo -n "Trying to find an unlocked X session ..." >&2
	# prefer $USER's own x sessions over other
	_user_sessions=$(who | egrep "$USER :[0-9]+" | cut -f2 -d " ")
	_other_sessions=$(who | egrep ".* :[0-9]+" | grep -v $USER | cut -f2 -d " ")
	# above expressions fail on Ubuntu 12.04 (Precise), list all sessions as fallback:
	_all_sessions=$(for x in /tmp/.X*-lock; do x=${x#/tmp/.X}; echo ":${x%-lock}"; done)
	for d in $_user_sessions $_other_sessions $_all_sessions; do
		echo -n " $d" >&2
		if xwininfo -display $d -root > /dev/null 2>&1; then
			_owner=$(who | egrep ".* $d" | cut -f1 -d " ")
			echo " ($_owner) works." >&2
			echo "$d"
			return 0
		fi
	done
	echo >&2
	echo "Couldn't find an unlocked X session. Consider using xhost+." >&2
	exit 2
}

function vdemo_pidFromScreen {
	# we append underscore to distinguish between components with same prefix
	local VDEMO_title="$1_"
	screen -ls | grep "${VDEMO_title}\s" | cut -f1 -d. | tr -d "\t "
}

# check for a running component
# $1:   title of the component
function vdemo_check_component {
	local VDEMO_title="$1"
	local VDEMO_pid=$(vdemo_pidFromScreen ${VDEMO_title})
	if [ "$VDEMO_pid" ]; then
		if ps -p "${VDEMO_pid}" > /dev/null; then
			echo "running" >&2
			return 0
		else
			echo "not running" >&2
			return 2
		fi
	else
		echo "no screen registered" >&2
		return 1
	fi
}

# reattach to a running "screened" component
# $1:   title of the component
function vdemo_reattach_screen {
	local VDEMO_pid=$(vdemo_pidFromScreen $1)
	if [ -n "$VDEMO_pid" ] ; then
		screen -d -r "$VDEMO_pid"
		failure=$?
	else
		echo "no screen for $1:"
		screen -ls
		failure=1
	fi

	if [ $failure == 1 ] ; then
		# change title and color of xterm
		echo -ne "\033]0;log of ${1}@${HOSTNAME}\007"
		echo -ne "\033]11;darkblue\007"
		local file="$VDEMO_logfile_prefix${1}.log"
		if [ -f $file ] ; then
			less $file
		else
			sleep 2
		fi
	fi
	return $failure
}

# detach a  "screened" component
# $1:   title of the component
function vdemo_detach_screen {
	local VDEMO_pid=$(vdemo_pidFromScreen $1)
	test -n "$VDEMO_pid" && screen -d "$VDEMO_pid"
}

# show log output of a component
# $1:   title of the component
function vdemo_showlog {
	xterm -fg white -bg darkblue -title "log of ${1}@${HOSTNAME}" -e \
		less -R "$VDEMO_logfile_prefix${1}.log" &
}

function vdemo_inspect {
	xterm -fg white -bg black -title "inspect ${1}@${HOSTNAME}" -e \
		vdemo_inspect_cmd &
}

# start a component. This function has the following options:
#   -d    use X11 DISPLAY to display the component
#   -l    enable logging
#   -D    start detached
# remaining arguments are treated as command line of the component to start
function vdemo_start_component {
	local VDEMO_title=$1; shift
	local VDEMO_componentDisplay="${DISPLAY}"
	local VDEMO_startDetached="no"
	local COLOR="white"
	local VDEMO_logfile="${VDEMO_logfile_prefix}${VDEMO_title}.log"
	while [ $# -gt 0 ]; do
		case $1 in
			"-D"|"--detached")
				VDEMO_startDetached="yes"
				;;
			"-d"|"--display")
				shift
				VDEMO_componentDisplay="$1"
				;;
			"-l"|"--logging")
				local logfiledir="${VDEMO_logfile%/*}"
				if [ ! -d "$logfiledir" ]; then mkdir -p "$logfiledir"; fi
				if [ "$LOG_ROTATION" == "ON" ]; then
					echo "logrotation is enabled." >&2
					export -f launch_logrotation
					export -f vdemo_pidFromScreen
					log_rotation_command="(launch_logrotation $VDEMO_logfile ${VDEMO_title})& "
				fi
				echo "logging to ${VDEMO_logfile}" >&2
				# exec allows to redirect output of current shell
				local VDEMO_logging="set -x; exec 1> >(tee -a \"${VDEMO_logfile}\") 2>&1;"
				;;
			--)
				break
				;;
			-*)
				echo "illegal option $1" >&2
				echo "$USAGE" >&2
				exit 1
				;;
			*)
				break
				;;
		esac
		shift
	done

	export -f component

	# remove old log file if we do not want to rotate/append
	if [ ! "$LOG_ROTATION" == "ON" ]; then
		rm -f "${VDEMO_logfile}" # remove any old log file
	else
		cat >> ${VDEMO_logfile} <<- EOX


			#################################
			new VDEMO component start
			component name: ${VDEMO_title}
			`date`
			#################################


		EOX
	fi

	# Logging has missing lines at the end (or is completely empty) when finishing fast.
	# Adding a small sleep seems to fix this issue.
	local cmd="${VDEMO_logging} ${log_rotation_command} LD_LIBRARY_PATH=${LD_LIBRARY_PATH} DISPLAY=${VDEMO_componentDisplay} component; sleep 0.01"

    # bash needs to be started in in interactive mode to have job control available
    # --norc is used to prevent inclusion of the use configuration in the execution.
	if [ "x$VDEMO_startDetached" == "xno" ]; then
		xterm -fg $COLOR -bg black -title "starting $VDEMO_title" -e \
			screen -t "$VDEMO_title" -S "${VDEMO_title}_" \
			stdbuf -oL bash --norc -i -c "$cmd" &
	else
		screen -t "$VDEMO_title" -S "${VDEMO_title}_" -d -m \
			stdbuf -oL bash --norc -i -c "$cmd"
	fi
}

# creates a logrotation configuration file and enters a logrotate loop until
# the process dies
#
#
# $1 : logfile to rotate
# $2 : $VDEMO_title of process which is responsible (makes sure logrotation loop
#      is ended if process dies)
#
# Note: start this function in the background using &
function launch_logrotation {
	# disabled for now
	# echo "[VDEMO_LOGROTATE] initiating logrotation for component $2 - file to watch: $1" >&2

	# Create the configuration files
	component_logrotate_configfile=$1.rotation.conf
	component_logrotate_statefile=$1.rotation.state
	cat > ${component_logrotate_configfile} <<- EOX
		$1 {
		    size ${LOG_ROTATION_SIZE-50M}
		    rotate ${LOG_ROTATION_COUNT-8}
		    missingok
		    notifempty
		    copytruncate
		    ${LOG_ROTATION_OPTIONS-compress}
		}
	EOX

	# wait a bit until the process is up in a screen session (we have time here)
	sleep 10

	# obtain the pid of screen session
	local initial_VDEMO_pid=$(vdemo_pidFromScreen $2)

	# loop until process dies
	echo "[VDEMO_LOGROTATE] entering logrotation loop ($2 - $1)" >&2
	while true
	do

		# check if there was a component death/restart
		if ! ps -p ${initial_VDEMO_pid} > /dev/null; then
			echo "[VDEMO_LOGROTATE] vdemo log rotation stops for $2 - component seems to have died/restarted/crashed (pid $initial_VDEMO_pid is gone)" >&2
			break
		fi

		# rotate the logfile
		# echo "[VDEMO_LOGROTATE] logrotatting file '$1' now (component '$2')" >&2
		/usr/sbin/logrotate ${component_logrotate_configfile} -s ${component_logrotate_statefile}
		sleep ${LOG_ROTATION_INTERVALL-300}
	done
}

# get all direct and indirect children of a process (including process itself)
# --filter <filter> filters out processes whos cmdline contains given filter as argument
function all_children {
	if [ "$1" == "--filter" ]; then
		local FILTER=$2
		local FILTER_ARGS="--filter $FILTER"
		shift
		shift
	fi

	# ensure that all variables stay function-local
	local PIDS="$*"
	local P
	for P in $PIDS; do
		# depth-first search, children ordered by start_time and pid in reverse order
		local CHILDREN=$(ps --ppid $P -o pid --no-headers --sort -start_time,-pid)
		if [ "$CHILDREN" ]; then
			all_children $FILTER_ARGS $CHILDREN
		fi
		# filter out $FILTER (literally) and bash at beginning of command line
		if [[ -z "$FILTER" ]] || [[ ! $(ps -p $P -o comm=) =~ $FILTER ]]; then
			echo -n " $P"
		fi
	done
}

# stop a component
# $1: title of the component
function vdemo_stop_component {
	local VDEMO_title="$1"
	local VDEMO_pid=$(vdemo_pidFromScreen ${VDEMO_title})
	if [ "$VDEMO_pid" ]; then
		echo "stopping $VDEMO_title: screen pid: ${VDEMO_pid}" >&2
		local PIDS=$(all_children $VDEMO_pid)
		# call stop_component if that function exists
		if declare -F stop_component > /dev/null; then
			echo "calling stop_component"
			stop_component $1
		else
			# by default we first kill children processes with SIGINT (2s timeout)
			vdemo_stop_signal_children $1 SIGINT 2
		fi
		# kill remaining children processes
		local REMAIN_PIDS=$(ps --no-headers -o pid,comm -p $PIDS)
		test -n "$REMAIN_PIDS" && \
			(echo "killing remaining processes"; echo "$REMAIN_PIDS")
		kill -9 $PIDS > /dev/null 2>&1

		# call on_stop function
		if declare -F on_stop > /dev/null; then
			on_stop
		fi
	fi
}

# This is the default stopping function:
# Stop all children of component by a signal, starting at the leafs of the process tree
# $1 - title of component
# $2 - signal to use (default: SIGINT)
# $3 - timeout, waiting for a single component (default: 2s)
function vdemo_stop_signal_children {
	local VDEMO_title="$1"
	# get pids of screen and of all children
	local VDEMO_pid=$(vdemo_pidFromScreen ${VDEMO_title})
	local VDEMO_compo_pids=$(all_children $VDEMO_pid)
	local SIGNAL=${2:-SIGINT}
	local TIMEOUT=$((10*${3:-2}))
	for pid in $VDEMO_compo_pids; do
		# don't send a kill signal when process is already gone
		kill -0 $pid > /dev/null 2>&1 || continue
		echo -n "${SIGNAL}ing $pid: $(ps -p $pid -o comm=) "
		kill -$SIGNAL $pid > /dev/null 2>&1
		# wait for process to be finished
		for i in $(seq $TIMEOUT); do
			sleep 0.1
			test $((i % 10)) -eq 0 && echo -n "."
			kill -0 $pid > /dev/null 2>&1 || break
		done
		sleep 0.01 # give parent processes some time to quit themselves
		echo
	done
}
