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
	VDEMO_title="$1_"
	screen -ls | grep "${VDEMO_title}\s" | cut -f1 -d. | tr -d "\t "
}

# check for a running component
# $1:   title of the component
function vdemo_check_component {
	VDEMO_title="$1"
	VDEMO_pid=$(vdemo_pidFromScreen ${VDEMO_title})
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
	VDEMO_pid=$(vdemo_pidFromScreen $1)
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
		file="$VDEMO_logfile_prefix${1}.log"
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
	VDEMO_pid=$(vdemo_pidFromScreen $1)
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
#   -n    title of the component (name to identify it by other functions,
#         needs not to be the program name)
#   -d    use X11 DISPLAY to display the component
#   -l    enable logging
#   -D    start detached
# remaining arguments are treated as command line of the component to start
function vdemo_start_component {
	VDEMO_componentDisplay="${DISPLAY}"
	VDEMO_startDetached="no"
	COLOR="white"

	while [ $# -gt 0 ]; do
		case $1 in
			"-n"|"--name")
				shift
				VDEMO_title="$1"
				;;
			"-D"|"--detached")
				VDEMO_startDetached="yes"
				;;
			"-d"|"--display")
				shift
				VDEMO_componentDisplay="$1"
				;;
			"-l"|"--logging")
				VDEMO_logfile="${VDEMO_logfile_prefix}${VDEMO_title}.log"
				logfiledir="${VDEMO_logfile%/*}"
				if [ ! -d "$logfiledir" ]; then mkdir -p "$logfiledir"; fi
				if [ "$LOG_ROTATION" == "ON" ]; then
					component_logrotate_configfile=${VDEMO_logfile_prefix}${VDEMO_title}.rotation.conf
					component_logrotate_statefile=${VDEMO_logfile_prefix}${VDEMO_title}.rotation.state

					echo "${VDEMO_logfile} {
	size ${LOG_ROTATION_SIZE-50M}
	rotate ${LOG_ROTATION_COUNT-8}
	missingok
	notifempty
	copytruncate
	${LOG_ROTATION_OPTIONS-compress}
}" > ${component_logrotate_configfile}
					log_rotation_command="(while true; do /usr/sbin/logrotate ${component_logrotate_configfile} -s ${component_logrotate_statefile}; sleep ${LOG_ROTATION_INTERVALL-300}; done)& "
				fi
				echo "logging to ${VDEMO_logfile}" >&2
				# exec allows to redirect output of current shell
				VDEMO_logging="exec 1> >(tee -a \"${VDEMO_logfile}\") 2>&1;"
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
	rm -f ${VDEMO_logfile} # remove any previous log file

	test -n "${VDEMO_logging}" && \
	echo "starting $VDEMO_title with component function:"$'\n'"$(declare -f component)" \
		>> ${VDEMO_logfile}

	# Hm. For some reason the last line of the output doesn't enter the log.
	# Adding a small sleep seems to fix this issue.
	cmd="${VDEMO_logging} ${log_rotation_command} LD_LIBRARY_PATH=${LD_LIBRARY_PATH} DISPLAY=${VDEMO_componentDisplay} component; sleep 0.01"

	if [ "x$VDEMO_startDetached" == "xno" ]; then
		xterm -fg $COLOR -bg black -title "starting $VDEMO_title" -e \
			screen -t "$VDEMO_title" -S "${VDEMO_title}_" \
			stdbuf -oL bash -c "$cmd" &
	else
		screen -t "$VDEMO_title" -S "${VDEMO_title}_" -d -m \
			stdbuf -oL bash -c "$cmd"
	fi
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

function vdemo_pidsFromComponent {
	# pid of bash process inside screen
	local ppid=$(ps --ppid $1 -o pid --no-headers)
	local children=$(ps --ppid $ppid -o pid --no-headers --sort -start_time,-pid)

	# exclude the logging process (tee)
	for pid in $children; do
		if [[ ! "$(ps -p $pid -o cmd=)" =~ \
			"bash -c exec 1> >(tee -a \"/tmp/vdemo-" ]]; then
			echo -n " $pid"
		fi
	done
}

# stop a component
# $1: title of the component
function vdemo_stop_component {
	VDEMO_title="$1"
	VDEMO_pid=$(vdemo_pidFromScreen ${VDEMO_title})
	if [ "$VDEMO_pid" ]; then
		echo "stopping $VDEMO_title: screen pid: ${VDEMO_pid}" >&2
		local PIDS=$(vdemo_pidsFromComponent $VDEMO_pid)
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
		# to be really sure, also kill the screen process
		kill -9 $VDEMO_pid > /dev/null 2>&1
	fi
}

# stop screen children of component by signal
# $1 - title of component
# $2 - signal to use (default: SIGINT)
# $3 - timeout, waiting for a single component (default: 2s)
function vdemo_stop_signal_children {
	VDEMO_title="$1"
	VDEMO_pid=$(vdemo_pidFromScreen ${VDEMO_title})
	VDEMO_compo_pids=$(vdemo_pidsFromComponent $VDEMO_pid)
	local SIGNAL=${2:-SIGINT}
	local TIMEOUT=$((10*${3:-2}))
	for pid in $VDEMO_compo_pids; do
		echo -n "${SIGNAL}ing $pid: $(ps -p $pid -o comm=) "
		kill -$SIGNAL $pid > /dev/null 2>&1
		# wait for process to be finished
		for i in $(seq $TIMEOUT); do
			sleep 0.1
			test $((i % 10)) -eq 0 && echo -n "."
			kill -0 $pid > /dev/null 2>&1 || break
		done
		echo
	done
}
