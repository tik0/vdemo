function start_Xserver {
	echo -n "Trying to find an accessible X session ..." >&2
	# prefer $USER's own x sessions over other
	_user_sessions=$(who | grep -oP "$USER.*\(\K:[0-9.]+(?=\))")
	_other_sessions=$(who | grep -oP '^(?!'"$USER"' ).*\(\K:[0-9.]+(?=\))')
	# above expressions fail on Ubuntu 12.04 (Precise), list all sessions as fallback:
	_all_sessions=$(for x in /tmp/.X*-lock; do x=${x#/tmp/.X}; echo ":${x%-lock}"; done)
	for d in $_user_sessions $_other_sessions $_all_sessions; do
		echo -n " $d" >&2
		if xwininfo -display $d -root > /dev/null 2>&1; then
			echo " works." >&2
			echo "$d"
			return 0
		fi
	done
	echo >&2
	echo "Couldn't find an accessible X session. Consider copying the sessions X authority file (xauth info) to ~/.Xauthority" >&2
	exit 2
}

function vdemo_pidFromScreen {
	# we append underscore to distinguish between components with same prefix
	local VDEMO_title="$1_"
	local screendir="/var/run/screen/S-$USER"
	local screensocks=("$screendir"/*."$VDEMO_title")
	[[ "${screensocks[0]}" =~ $screendir/([0-9]+)\.$VDEMO_title ]] && echo -n "${BASH_REMATCH[1]}"
}
export -f vdemo_pidFromScreen

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
	local VDEMO_pid=$(vdemo_pidFromScreen "$1")
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
	local VDEMO_pid=$(vdemo_pidFromScreen "$1")
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
		bash -c vdemo_inspect_cmd "$@" &
}

function vdemo_logging {
	function vdemo_screendump {
		set +x
		if [ ! -e "${VDEMO_logfile}" ]; then
			screen -S "$STY" -X -p0 hardcopy -h "${VDEMO_logfile}"
			sed -i -e '1i#VDEMO note: screen hardcopy' -e '/./,$!d' "${VDEMO_logfile}"
		fi
	}
	# always run screendump on exit. E.g. it will catch if rotatelogs is missing.
	trap vdemo_screendump EXIT
	case $1 in
		"onexit")
			;;
		"rotatelogs")
			exec &> >(VDEMO_logfile="${VDEMO_logfile}" exec rotatelogs -p "${VDEMO_root}"/vdemo_remove_logfiles \
			-L "${VDEMO_logfile}" -f -e "${VDEMO_logfile}" 10M)
			;;
		"tee")
			exec &> >(exec tee -i -a "${VDEMO_logfile}")
			;;
		esac
	read -d '' startmsg <<- EOF
	#########################################
	vdemo component start: ${VDEMO_component_title}
	$(date -Ins)
	#########################################
	EOF
	echo "$startmsg"
	set -o functrace
	set -x
}

# start a component. This function has the following options:
#   -d    use X11 DISPLAY to display the component
#   -l    enable logging
#   -D    start detached
# remaining arguments are treated as command line of the component to start
function vdemo_start_component {
	local VDEMO_title="$1"; shift
	local VDEMO_componentDisplay="${DISPLAY}"
	local VDEMO_startDetached="no"
	local COLOR="white"
	export VDEMO_logfile="${VDEMO_logfile_prefix}${VDEMO_title}.log"
	local logfiledir="${VDEMO_logfile%/*}"
	if [ ! -d "$logfiledir" ]; then mkdir -p "$logfiledir"; fi
	local VDEMO_logging="onexit"
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
				echo "logging to ${VDEMO_logfile}" >&2
				# exec allows to redirect output of current shell
				if [[ "$VDEMO_LOG_ROTATION" =~ ^[0-9]+$ ]] ; then
					echo "logrotation is enabled." >&2
					VDEMO_logging="rotatelogs"
				else
					VDEMO_logging="tee"
				fi
				;;
			--)
				shift
				break
				;;
			*)
				echo "illegal argument $1" >&2
				echo "$USAGE" >&2
				exit 1
				;;
		esac
		shift
	done

	# Logging has missing lines at the end (or is completely empty) when finishing fast.
	# Adding a small sleep seems to fix this issue.
	eval "function vdemo_component { vdemo_logging $VDEMO_logging; LD_LIBRARY_PATH=${LD_LIBRARY_PATH} DISPLAY=${VDEMO_componentDisplay} component $*; sleep 0.01; }"

	export -f vdemo_logging
	export -f component
	export -f vdemo_component
	rm -f "${VDEMO_logfile}" # remove any old log file

    # bash needs to be started in in interactive mode to have job control available
    # --norc is used to prevent inclusion of the use configuration in the execution.
	if [ "$VDEMO_startDetached" == "no" ]; then
		xterm -fg $COLOR -bg black -title "starting $VDEMO_title" -e \
			screen -t "$VDEMO_title" -S "${VDEMO_title}_" \
			stdbuf -oL bash --norc -i -c "vdemo_component" &
	else
		screen -t "$VDEMO_title" -S "${VDEMO_title}_" -d -m \
			stdbuf -oL bash --norc -i -c "vdemo_component"
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
			stop_component "$1"
		else
			# by default we first kill children processes with SIGINT (2s timeout)
			vdemo_stop_signal_children "$1" SIGINT 2
		fi
		# kill remaining children processes
		local REMAIN_PIDS=$(ps --no-headers -o pid,comm -p $PIDS)
		if [ -n "$REMAIN_PIDS" ]; then
			echo $'killing remaining processes\n'"$REMAIN_PIDS"
			kill -9 $PIDS > /dev/null 2>&1
		fi
		# call on_stop function
		if declare -F on_stop > /dev/null; then
			on_stop "$1"
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
