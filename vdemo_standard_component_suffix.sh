#!/bin/bash
# /// @author    Marc Hanheide (mhanheid@TechFak.Uni-Bielefeld.de)
# /// @date      started at 2005/03/01
# /// @version   $Id: vdemo_standard_component_suffix.sh,v 1.4 2007/08/17 15:28:47 mhanheid Exp $
#
# THIS SCRIPT EXPECTS THE FOLLOWING VARIABLES TO BE SET:
#   component="$prefix/bin/some_binary args"
#   title=MemoryServer # only if not sourced from another bash script

vdemo_component_scriptname="${BASH_SOURCE[${#BASH_SOURCE[@]}-1]##*/}"

HELP="\
usage: $vdemo_component_scriptname [options] start|stop|check

 options:
  -h  --help               this help text
  -x  --xserver            start own xserver
  -t  --title <title>      define component title
  -l  --logging            enable logging
  -D  --detached           start detached
 author: Marc Hanheide ($RCS_ID)
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
            if [ -z "$title" ]; then
               title="$1"
            else
               title="$title.$1"
               export VDEMO_component_title="$1"
            fi
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

# This MUST be the absolut path to the used vdemo scripts (this script)
if [ -z "$VDEMO_root" ]; then
   echo '$VDEMO_root is not set. Set it to absolut path of the used vdemo installation' >&2
   exit 3
fi

if [ -z "$VDEMO_logfile_prefix" ]; then
   export VDEMO_logfile_prefix="/tmp/vdemo-$USER/component_"
fi

if ! declare -F "component" >/dev/null; then
   echo 'function "component" is not declared or declared as variable'
   exit 11
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
    if declare -F $func >/dev/null; then
       $func $@
    else
       true
    fi
}

case "$1" in
    start)
        if vdemo_check_component $title; then
           echo "$title already running">&2
           exit 10
        fi

        call_if_exists clean_component
        call_if_exists on_start

        if [ "${vdemo_start_XSERVER}" ]; then
           comp_display=$(start_Xserver)
           if [ $? == 2 ]; then exit 12; fi
           echo "DISPLAY: $comp_display" >&2
           display_arg="-d $comp_display"
        fi
        vdemo_start_component $title $vdemo_start_LOGGING $vdemo_start_DETACHED $display_arg
        ;;
    stop)
        vdemo_stop_component $title &
        ;;
    stopwait)
        echo "stopping and waiting" >&2
        vdemo_stop_component $title
        ;;
    check)
        vdemo_check_component $title; processResult=$?
        re="^on_check[^{]*\{[[:space:]]*true[[:space:]]*\}$"
        func=$(declare -f on_check)
        if [[ -n $func && ! $func =~ $re ]] ; then
           # only call on_check if it is defined and non-trivial
           on_check; callResult=$?
           # combined result is limited to 8bit!
           if (( $callResult > 25 || $callResult < 0 )); then callResult=25; fi
        else
           callResult=$processResult
        fi
        exit $((10*callResult + processResult)) # combine both results
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
           VDEMO_demoConfig="$2"
           export VDEMO_demoConfig
           source "$2"
        fi
        call_if_exists clean_component
        call_if_exists on_start
        export -f component
        bash -c "component"
        call_if_exists on_stop
        ;;
    *)
        echo "wrong argument. $HELP" >&2
        exit 3
        ;;
esac
