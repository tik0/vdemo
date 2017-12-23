#!/bin/bash
# /// @author    Marc Hanheide (mhanheid@TechFak.Uni-Bielefeld.de)
# /// @author    Robert Haschke (rhaschke@TechFak.Uni-Bielefeld.de)
#
# THIS SCRIPT EXPECTS A FUNCTION NAMED "component" to be defined.
# This function can start any processes required for the component.

vdemo_component_scriptname="${BASH_SOURCE[${#BASH_SOURCE[@]}-1]##*/}"

HELP="\
usage: $vdemo_component_scriptname [options] command [component options]

 available commands: start,stop,check,screen,detach,showlog,clean,single
 options:
  -h  --help               this help text
  -x  --xserver            start own xserver
  -t  --title <title>      define component title
  -l  --logging            enable logging
  -D  --detached           start detached
"

# option checks
title="${vdemo_component_scriptname#component_}"
export VDEMO_component_title="$title"

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
        "-t"|"--title")
            shift
            title="$title.$1"
            export VDEMO_component_title="$title"
            ;;
        "-D"|"--detached")
            vdemo_start_DETACHED="-D"
            ;;
        -*)
            echo "illegal option '$1'" >& 2
            echo "$HELP" >& 2
            exit 3
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
   exit 3
fi
cmd=$1; shift

# This MUST be the absolut path to the used vdemo scripts (this script)
if [ -z "$VDEMO_root" ]; then
   echo '$VDEMO_root is not set. Set it to absolut path of the used vdemo installation' >&2
   exit 3
fi

if [ -z "$VDEMO_logfile_prefix" ]; then
   echo '$VDEMO_logfile_prefix is not set.' >&2
   exit 3
fi

if ! declare -F "component" >/dev/null; then
   echo 'function "component" is not declared or declared as variable'
   exit 11
fi

source "$VDEMO_root/vdemo_base.sh"

# Calls a function if it exists, else return true.
# $1: function name
# $2, $3, ...: arguments passed to function
# returns: If function exists: Return value of function.
#          If function does not exist: True.
function call_if_exists {
    local func=$1; shift
    if declare -F $func >/dev/null; then
       $func $@
    else
       true
    fi
}

case "$cmd" in
    start)
        if vdemo_check_component $title; then
           echo "$title already running">&2
           exit 10
        fi

        call_if_exists clean_component
        call_if_exists on_start

        if [ "${vdemo_start_XSERVER}" ]; then
           comp_display=$(vdemo_find_xdisplay)
           if [ $? == 2 ]; then exit 12; fi
           echo "DISPLAY: $comp_display" >&2
           display_arg="-d $comp_display"
        fi
        vdemo_start_component $title $vdemo_start_LOGGING $vdemo_start_DETACHED $display_arg -- "$*"
        ;;
    stop)
        vdemo_stop_component $title &
        ;;
    stopwait)
        echo "stopping and waiting" >&2
        vdemo_stop_component $title
        ;;
    check)
        vdemo_check_component $title;
        processResult=$?
        re="^on_check[^{]*\{[[:space:]]*true[[:space:]]*\}$"
        func=$(declare -f on_check)
        if [[ -n $func && ! $func =~ $re ]] ; then
           # only call on_check if it is defined and non-trivial
           on_check; callResult=$?
        else
           callResult=$processResult
        fi
        # combine both results, return value is limited to range [0..255]
        # - 6 highest bits for callResult
        # - 2 lowest bits for processResult (2#11 = binary 11 = 3)
        exit $(( ((callResult << 2) | (processResult & 2#11)) & 255 ))
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
    inspect)
        vdemo_inspect $title
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
           export VDEMO_demoConfig="$2"
           source "$2"
        fi
        call_if_exists clean_component
        call_if_exists on_start
        export -f component
        bash -c "component"
        call_if_exists on_stop
        ;;
    *)
        echo "wrong command argument: $cmd.
$HELP" >&2
        exit 3
        ;;
esac
