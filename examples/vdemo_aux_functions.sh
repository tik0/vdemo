function vdemo_gdbbacktrace {
    tracelog="${VDEMO_logfile_prefix}${0##*/}_trace.log"
    date +"++++ %Y-%m-%d %T ++++" >> "$tracelog"
    echo "$@" >> "$tracelog"
    gdb -q -n -return-child-result -ex "set confirm off" -ex "set logging file $tracelog" -ex "set logging on" -ex "set logging redirect on" -ex "handle SIGTERM noprint nostop" -ex "set pagination off" -ex run -ex "thread apply all bt" -ex "quit" --args "$@"
    date +$'---- %Y-%m-%d %T ----\n' >> "$tracelog"
}
export -f vdemo_gdbbacktrace

function vdemo_coredump {
    coredumpdir="$VDEMO_logdir/${0##*/}"
    mkdir -p "$coredumpdir" && cd "$coredumpdir" && ulimit -c unlimited && "$@"
}
export -f vdemo_coredump

function vdemo_inspect_cmd {
    echo pstree output:
    source "$VDEMO_root/vdemo_base.sh"
    pid=$(vdemo_pidFromScreen "${VDEMO_component_title}")
    if [ -z "$pid" ]; then
        echo "component not running"
    else
        pstree -p "$pid"
    fi
    echo press any key to continue
    read -N 1
    screen -r $pid -p0 -X hardcopy -h $(tty)
    read -N 1
}
export -f vdemo_inspect_cmd
