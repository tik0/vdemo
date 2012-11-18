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
		if ps --no-headers -fp "${VDEMO_pid}"; then
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
		sleep 2
		failure=1
	fi
	return $failure
}

# detach a  "screened" component
# $1:   title of the component
function vdemo_detach_screen {
	VDEMO_pid=$(vdemo_pidFromScreen $1)
	screen -d "$VDEMO_pid"
}

# show log output of a component
# $1:   title of the component
function vdemo_showlog {
	 xterm -fg white -bg darkblue -title "log of ${1}@${HOSTNAME}" -e \
		  less "$VDEMO_logfile_prefix${1}.log" &
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
		VDEMO_logging=" | tee ${VDEMO_logfile}"
		;;
	    --)
		break
		;;
	    "--noiconic")
      ICONIC=""
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

    if [ $# -lt 1 ]; then
	echo "obligatory arguments missing." >&2 
	return 1
    fi
    cmd="LD_LIBRARY_PATH=${LD_LIBRARY_PATH} DISPLAY=${VDEMO_componentDisplay} $1 2>&1 ${VDEMO_logging}"
    echo "starting $VDEMO_title as '$cmd' " >&2
    xterm -fg green -bg black $ICONIC -title "starting $VDEMO_title" -e \
	screen -t "$VDEMO_title" -S "${VDEMO_title}_" \
	bash -i -c "$cmd" "$VDEMO_title" &
}

# get all direct and indirect children of a process
function all_children {
    PIDS="$*"
    CHILDREN=""
    for P in $PIDS; do
	echo -n " $P"
	curr_children=$(ps --ppid $P -o pid --no-headers)
	if [ "$curr_children" ]; then
	    all_children "$curr_children"
	fi
    done
}

# stop a component
# $1: titl of the component
function vdemo_stop_component {
    VDEMO_title="$1"
    VDEMO_pid=$(vdemo_pidFromScreen ${VDEMO_title})

    if [ "$VDEMO_pid" ]; then
	PIDS=$(all_children "$VDEMO_pid")
	echo "stopping $VDEMO_title (PIDs $PIDS)" >&2
	kill $VDEMO_pid $PIDS > /dev/null 2>&1
	for i in {1..20}; do
		kill -0 $VDEMO_pid $PIDS > /dev/null 2>&1 || break
		sleep 0.1
	done
	kill -9 $VDEMO_pid $PIDS > /dev/null 2>&1
    fi
}
