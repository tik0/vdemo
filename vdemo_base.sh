function start_Xserver {
    XPIDFILE=/tmp/VDEMO_xserver_${VDEMO_title}_${USER}.pid
    i=0;
    echo "trying to find an X display" >&2
    while [ $i -lt 10 ]; do
        if [ -e "/tmp/.X${i}-lock" ]; then
            echo "X running on :${i}, try to use it" >&2
            if xwininfo -display :${i} -root 1>&2; then
                echo "found accessible X :${i}, reusing it" >&2
                echo ":${i}"
                return 0
            fi
        fi
        echo  "X on :${i} locked, try next..." >&2
        i=$(expr $i + 1)
    done
    echo "couldn't find a free display for the xserver. exiting" >&2
    exit 2
}

function vdemo_pidFromScreen {
    # we append underscore to distinguish between components with same prefix
    VDEMO_title="$1_"
    screen -ls | grep ${VDEMO_title} | cut -f1 -d. | tr -d "\t "
}

# check for a running component
# $1:   title of the component
function vdemo_check_component {
    VDEMO_title="$1"
    VDEMO_pid=$(vdemo_pidFromScreen ${VDEMO_title})
    if [ "$VDEMO_pid" ]; then
        echo "checking $VDEMO_title" >&2
        if ps -o user,pid,stime,cmd --no-headers -p "${VDEMO_pid}"; then
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
		# change title of xterm
		echo -ne "\033]0;${1}@${HOSTNAME}\007"
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
#           needs not to be the program name)
#   -d    use X11 DISPLAY to display the component
# remaining arguments are treated as command line of the component to start
function vdemo_start_component {
    # give the component 8 seconds to startup and set up the X11 connection
    VDEMO_wait=20
    VDEMO_title=""
    VDEMO_componentDisplay="${DISPLAY}"
    VDEMO_logging=""
    ICONIC="-iconic"
    COLOR="green"
    while [ $# -gt 0 ]; do
    case $1 in
        "-n"|"--name")
        shift
        VDEMO_title="$1"
        ;;
        "-d"|"--display")
        shift
        VDEMO_componentDisplay="$1"
        ;;
        "-l"|"--logging")
        VDEMO_logfile="${VDEMO_logfile_prefix}${VDEMO_title}.log"
        logfiledir="${VDEMO_logfile%/*}"
        if [ ! -d "$logfiledir" ]; then mkdir -p "$logfiledir"; fi
        echo "logging to ${VDEMO_logfile}" >&2
        VDEMO_logging="exec > >(tee \"${VDEMO_logfile}\"); exec 2>&1; "
        ;;
        --)
        break
        ;;
        "--noiconic")
        ICONIC=""
        COLOR=white
        ;;
        -*)
        echo "illegal option $1" >& 2
        echo "$USAGE" >& 2
        exit 1
        ;;
        *)
        break
        ;;
    esac
    shift
    done

	export -f component
	rm -f ${VDEMO_logfile} # remove any old log file
	cmd="${VDEMO_logging} LD_LIBRARY_PATH=${LD_LIBRARY_PATH} DISPLAY=${VDEMO_componentDisplay} component"
	echo "starting $VDEMO_title with component function:"$'\n'"$(declare -f component)" >&2
	xterm -fg $COLOR -bg black $ICONIC -title "starting $VDEMO_title" -e \
		screen -t "$VDEMO_title" -S "${VDEMO_title}_" \
		stdbuf -oL bash -i -c "$cmd" "$VDEMO_title" &
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
        if [ "$(ps -p $pid -o comm=)" != "tee" ]; then
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
		local PIDS=$(all_children $VDEMO_pid)
		# call stop_component if that function exists
		if declare -F stop_component > /dev/null; then
			echo "calling stop_component"
			stop_component $1
		else
			# by default we first kill children processes with SIGINT (2s timeout)
			vdemo_stop_signal_children $1
		fi
		# kill the screen and all its children (if there are still processes)
		local REMAIN_PIDS=$(ps --no-headers -o pid,comm -p $PIDS)
		test -n "$REMAIN_PIDS" && \
			(echo "killing remaining processes"; echo "$REMAIN_PIDS")
		kill -9 $PIDS > /dev/null 2>&1
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
		echo "sending signal $SIGNAL to child process $pid: $(ps -p $pid -o comm=)"
		kill -$SIGNAL $pid > /dev/null 2>&1
		# wait for process to be finished
		for i in {1..$TIMEOUT}; do
			sleep 0.1
			kill -0 $pid > /dev/null 2>&1 || break
		done
	done
}
