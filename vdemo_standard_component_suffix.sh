#!/bin/bash
# /// @author	Marc Hanheide (mhanheid@TechFak.Uni-Bielefeld.de)
# /// @date	started at 2005/03/01
# /// @version	$Id: vdemo_standard_component_suffix.sh,v 1.4 2007/08/17 15:28:47 mhanheid Exp $
#
# THIS SCRIPT EXPECT THE FOLLOWING VARIABLES TO BE SET:
#   component="$VDEMO_root/bin/memory_server $VDEMO_CASA_dbxml/vam.dbxml $VDEMO_perceptVamName"
#   title=MemoryServer
#   SCRIPTNAME=`basename $0`
# and the following function
#   clean_component


HELP="\
usage: $SCRIPTNAME [options] start|stop|check

start $title

 options:
  -h  --help               this help text
  -x  --xserver            start own xserver

 author: Marc Hanheide ($RCS_ID)
"

# option checks
vdemo_start_XSERVER=""
vdemo_start_LOGGING=""
vdemo_start_ICONIC=""

while [ $# -gt 0 ]; do
    case $1 in
	"-h"|"--help")
	    echo "$HELP" >& 2
	    exit 0
	    ;;
	"-l"|"--logging")
	    vdemo_start_LOGGING="-l"
	    ;;
	"-x"|"--xserver")
	    vdemo_start_XSERVER="YES"
	    ;;
	"--noiconic")
	    vdemo_start_ICONIC="--noiconic"
	    ;;
	-*)
	    echo "illegal option '$1'" >& 2
	    echo "$HELP" >& 2
	    exit 1
	    ;;
	*)	    
	    break
	    ;;
    esac
    shift
done

# obligatory arguments check
if [ $# -lt 1 ]; then
    echo "obligatory argument(s) missing. $HELP" >&2 
    exit 1
fi

# This MUST be the absolut path to the used vdemo scripts (this script)
if [ -z "$VDEMO_root" ]; then
    echo '$VDEMO_root ist not set. Set it to absolut path of the used vdemo installation' >&2
    exit 1
fi

if [ -z "$title" ]; then
	echo '$title is not set. A good default is the name of the process' >&2
	exit 1
fi

# run the 
test -f "$VDEMO_sysConfig" && source "$VDEMO_sysConfig" $VDEMO_sysConfigOptions
source "$VDEMO_root/vdemo_base.sh"

# Calls a function if it exists, else return true.
# $1: function name
# $2, $3, ...: arguments passed to function
# returns: If function exists: Return value of function.
#          If function does not exist: True.
function call_if_exists {
  func=$1; shift
  if declare -f $func >/dev/null; then
    $func $@
  else
    true
  fi
}

case "$1" in
    start)
	if vdemo_check_component $title; then
 	    echo "$title already running, stopping first">&2
 	    vdemo_stop_component $title
	    sleep 1
	fi

	call_if_exists clean_component
	call_if_exists on_start

	if [ "${vdemo_start_XSERVER}" ]; then
	    comp_display=`start_Xserver`
	    echo "DISPLAY: $comp_display" >&2 
	    vdemo_start_component -d $comp_display -n $title $vdemo_start_ICONIC $vdemo_start_LOGGING \
		$component
	else
	    vdemo_start_component -n $title $vdemo_start_LOGGING $vdemo_start_ICONIC \
		$component
	fi
	;;
    stop)
	vdemo_stop_component $title
	if [ "${vdemo_start_XSERVER}" ]; then
	    stop_Xserver
	fi
	call_if_exists on_stop
	;;
    check)
	call_if_exists on_check || true
	vdemo_check_component $title
	exit $?
	;;
    screen)
	vdemo_reattach_screen $title
	exit $?
	;;
    detach)
	vdemo_detach_screen $title
	exit $?
	;;
    showlog)
	vdemo_showlog $title
	exit $?
	;;
    clean)
	if vdemo_check_component; then
	    echo "$title is running, stopping before cleaning">&2
	    vdemo_stop_component $title
	fi
	call_if_exists clean_component
	;;
    single)
	if [ "$2" ]; then
	    echo "configuration from $2" >&2
	    VDEMO_demoConfig="$2"
	    export VDEMO_demoConfig
	    source "$2"
	fi
	call_if_exists clean_component
	call_if_exists on_start
	bash -c "$component"
	call_if_exists on_stop
	;;
    *)
	echo "wrong argument. $HELP" >&2 
	exit 1
	;;
esac



# ******************************** EOF vdemo_component_memoryserver.sh *********************************

