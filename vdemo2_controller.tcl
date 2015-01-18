#!/bin/bash
# kate: replace-tabs on; indent-width 4;
# the next line restarts using wish \
exec wish "$0" "$@"

# required for scrollable frame
package require Iwidgets 4.0
# required for signal handling
package require Tclx

set SSHOPTS "-oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -oConnectTimeout=15"

# Theme settings
proc define_theme_color {style defaultBgnd mapping} {
    ttk::style configure $style -background $defaultBgnd
    ttk::style map $style -background $mapping
}

set FONT "helvetica 9"
ttk::style configure "." -font $FONT
ttk::style configure sunken.TFrame -relief sunken
ttk::style configure groove.TFrame -relief groove

ttk::style configure TButton -font "$FONT bold" -padding "2 -1"
ttk::style configure TCheckbutton -padding "2 -1"
ttk::style configure cmd.TButton -padding "2 -1" -width -5

define_theme_color ok.cmd.TButton green3 [list active green2]
define_theme_color noscreen.ok.cmd.TButton orange2 [list active orange]
define_theme_color failed.cmd.TButton red2 [list active red]
define_theme_color check.failed.cmd.TButton pink [list active pink2]
define_theme_color starting.cmd.TButton yellow2 [list active yellow]

ttk::style configure clock.TButton -font "$FONT"
ttk::style configure exit.TButton

ttk::style configure TLabel -padding "2 -1"
ttk::style configure level.TLabel -foreground darkblue -width 5
ttk::style configure label.TLabel -width 15 -anchor e
ttk::style configure group.TLabel -foreground darkblue -width 10 -anchor e
ttk::style configure host.TEntry  -width 5

ttk::style configure alert.TLabel -foreground blue -background yellow
ttk::style configure info.TLabel -foreground blue -background yellow
ttk::style configure log.TLabel -justify left -anchor e -relief sunken -foreground gray30

# debugging puts
set DEBUG_LEVEL 0
proc dputs {args {level 1}} {
    global DEBUG_LEVEL
    if [expr $level <= $DEBUG_LEVEL] {
        puts stderr "-- $args"
    }
}

proc parse_options {comp} {
    global env COMPONENTS ARGS USEX TERMINAL WAIT_READY NOAUTO LOGGING GROUP DETACHTIME COMP_LEVEL EXPORTS TITLE CONT_CHECK CHECKNOWAIT_TIME TERMINATE_ON_EXIT
    set NEWARGS [list]
    set USEX($comp) 0
    set WAIT_READY($comp) 0
    set CHECKNOWAIT_TIME($comp) 1
    set CONT_CHECK($comp) 0
    set GROUP($comp) ""
    set DETACHTIME($comp) 10
    set NOAUTO($comp) 0
    set TERMINAL($comp) "screen"
    set LOGGING($comp) 0
    set COMP_LEVEL($comp) ""
    set EXPORTS($comp) ""
    set TERMINATE_ON_EXIT($comp) 0

    for {set i 0} \$i<[llength $ARGS($comp)] {incr i} {
        set arg [lindex $ARGS($comp) $i]; set val [lindex $ARGS($comp) [expr $i+1]]
        switch -glob -- $arg {
            -w {
                set WAIT_READY($comp) "$val"
                incr i
            }
            -W {
                set CHECKNOWAIT_TIME($comp) "$val"
                incr i
            }
            -c {
                set CONT_CHECK($comp) 1
            }
            -d {
                set DETACHTIME($comp) "$val"
                incr i
            }
            -g {
                set GROUP($comp) [string tolower "$val"]
                incr i
            }
            -v {
                set EXPORTS($comp) "$EXPORTS($comp) $val"
                incr i
            }
            -t {
                set TITLE($comp) "$val"
                incr i
            }
            -x {
                set USEX($comp) 1
            }
            -n {
                set NOAUTO($comp) 1
            }
            -l {
                set LOGGING($comp) 1
            }
            -L {
                set COMP_LEVEL($comp) "$val"
                incr i
            }
            -Q {
                set TERMINATE_ON_EXIT($comp) 1
            }
            default {
                set NEWARGS [lappend NEWARGS $arg]
            }
        }
    }
    set ARGS($comp) $NEWARGS
}


proc parse_env_var {} {
    global env HOST HOSTS COMPONENTS ARGS USEX WATCHFILE COMMAND TITLE VDEMOID DEBUG_LEVEL
    set VDEMOID [file tail [file rootname $env(VDEMO_demoConfig)]]
    set components_list "$env(VDEMO_components)"
    set comp [split "$components_list" ":"]
    set nCompos [llength "$comp"]
    set COMPONENTS {}
    set WATCHFILE ""
    set HOSTS ""
    catch {set DEBUG_LEVEL $env(VDEMO_DEBUG_LEVEL)}
    catch {set WATCHFILE $env(VDEMO_watchfile)}
    dputs "VDEMO_watchfile = $WATCHFILE"
    dputs "COMPONENTS: "
    for {set i 0} { $i < $nCompos } {incr i} {
        set thisComp [split [string trim [lindex "$comp" $i]] ","]
        if {[llength "$thisComp"] == 3} {
            set component_name [lindex "$thisComp" 0]
            set component_name [string map "{ } {}" $component_name]
            set thisCommand "$component_name"
            set host [lindex "$thisComp" 1]
            set component_name "${i}_${component_name}"
            set COMMAND($component_name) "$thisCommand"
            set TITLE($component_name) "$thisCommand"
            set COMPONENTS "$COMPONENTS $component_name"

            if {"$host" != ""} {lappend HOSTS $host}
            set HOST($component_name) $host
            set ARGS($component_name) [lindex $thisComp 2]
            # do not simply tokenize at spaces, but allow quoted strings ("" or '')
            set ARGS($component_name) [regexp -all -inline -- "\\S+|\[^ =\]+=(?:\\S+|\"\[^\"]+\"|'\[^'\]+')" $ARGS($component_name)]
            dputs [format "%-20s HOST: %-13s ARGS: %s" $component_name $HOST($component_name) $ARGS($component_name)]
            # parse options known by the script and remove them from them the list
            parse_options "$component_name"
        } elseif {[string length [string trim [lindex "$comp" $i]]] != 0} {
            error "component $i: exepected three comma separated groups in '[string trim [lindex "$comp" $i]]'"
        }
    }
    set HOSTS [lsort -unique $HOSTS]
}

proc bind_wheel_sf {comp} {
    set can [$comp component canvas]
    set vsb [$comp component vertsb]
    set wid [$comp childsite]
    foreach w_ [list $can $vsb $wid] {
        bind $w_ <4> [list $can yview scroll -1 units]
        bind $w_ <5> [list $can yview scroll +1 units]
    }
}

proc set_group_noauto {grp} {
    global COMPONENTS GROUP NOAUTO GNOAUTO
    foreach {comp} "$COMPONENTS" {
        if {$GROUP($comp) == $grp} {
            set NOAUTO($comp) $GNOAUTO($grp)
        }
    }
}

proc gui_tcl {} {
    global HOST HOSTS COMPONENTS ARGS TERMINAL USEX LOGTEXT env NOAUTO LOGGING  GROUP SCREENED  COMP_LEVEL COMPWIDGET WATCHFILE COMMAND LEVELS TITLE TIMERDETACH TERMINATE_ON_EXIT
    set root "."
    set base ""
    set LOGTEXT "demo configured from '$env(VDEMO_demoConfig)'"
    wm title . "vdemo_controller: $env(VDEMO_demoConfig)"
    wm geometry . "960x600"

    set groups ""
    set LEVELS ""

    ttk::frame $base.components
    ttk::frame $base.components.singles
    iwidgets::scrolledframe $base.components.singles.comp -vscrollmode dynamic -hscrollmode dynamic
    bind_wheel_sf $base.components.singles.comp
    set COMPWIDGET [$base.components.singles.comp childsite]
    pack $base.components.singles -side top -fill both -expand yes
    pack $base.components.singles.comp -side left -fill both -expand yes

    foreach {c} "$COMPONENTS" {
        set groups "$groups $GROUP($c)"
        set LEVELS "$LEVELS $COMP_LEVEL($c)"
        set TIMERDETACH($c) 0

        ttk::frame $COMPWIDGET.$c -style groove.TFrame
        pack $COMPWIDGET.$c -side top -fill both -expand yes
        ttk::label $COMPWIDGET.$c.level -style level.TLabel -text "$COMP_LEVEL($c)"
        ttk::label $COMPWIDGET.$c.label -width 25 -style label.TLabel -text "$TITLE($c)@"
        ttk::entry $COMPWIDGET.$c.host  -width 10 -textvariable HOST($c)
        ttk::label $COMPWIDGET.$c.group -style group.TLabel -text "$GROUP($c)"

        ttk::button $COMPWIDGET.$c.start -style cmd.TButton -text "start" -command "component_cmd $c start"
        ttk::button $COMPWIDGET.$c.stop  -style cmd.TButton -text "stop" -command "component_cmd $c stop"
        ttk::button $COMPWIDGET.$c.check -style cmd.TButton -text "check" -command "component_cmd $c check"
        ttk::checkbutton $COMPWIDGET.$c.noauto -text "no auto" -variable NOAUTO($c)
        ttk::checkbutton $COMPWIDGET.$c.terminate -text "exit" -variable TERMINATE_ON_EXIT($c)
        ttk::checkbutton $COMPWIDGET.$c.ownx   -text "own X" -variable USEX($c)
        ttk::checkbutton $COMPWIDGET.$c.logging -text "logging" -variable LOGGING($c)
        ttk::button $COMPWIDGET.$c.viewlog -style cmd.TButton -text "view log" -command "component_cmd $c showlog"
        frame $COMPWIDGET.$c.terminal

        set SCREENED($c) 0
        ttk::checkbutton $COMPWIDGET.$c.terminal.screen -text "show term" -command "component_cmd $c screen" -variable SCREENED($c) -onvalue 1 -offvalue 0
        ttk::button $COMPWIDGET.$c.inspect -style cmd.TButton -text "inspect" -command "component_cmd $c inspect"

        pack $COMPWIDGET.$c.level -side left
        pack $COMPWIDGET.$c.label -side left -fill x
        pack $COMPWIDGET.$c.host -side left
        pack $COMPWIDGET.$c.group -side left -fill x

        pack $COMPWIDGET.$c.ownx -side right -padx 3
        pack $COMPWIDGET.$c.terminate -side right
        pack $COMPWIDGET.$c.inspect -side right
        pack $COMPWIDGET.$c.viewlog -side right
        pack $COMPWIDGET.$c.logging -side right
        pack $COMPWIDGET.$c.terminal -side right
        pack $COMPWIDGET.$c.terminal.screen -side right
        pack $COMPWIDGET.$c.noauto -side right -padx 2
        pack $COMPWIDGET.$c.check -side right
        pack $COMPWIDGET.$c.stop -side right
        pack $COMPWIDGET.$c.start -side right
        set_status $c unknown
    }

    # buttons to control ALL components
    ttk::frame $base.components.all -style groove.TFrame
    pack $base.components.all -side top -fill x
    ttk::label $base.components.all.label -style TLabel -text "ALL COMPONENTS"
    ttk::button $base.components.all.start -style cmd.TButton -text "start" -command "allcomponents_cmd start"
    ttk::button $base.components.all.stop  -style cmd.TButton -text "stop"  -command "allcomponents_cmd stop"
    ttk::button $base.components.all.check -style cmd.TButton -text "check" -command "allcomponents_cmd check"
    pack $base.components.all.label -side left
    pack $base.components.all.start -side left
    pack $base.components.all.stop  -side left
    pack $base.components.all.check -side left

    # clear logger button
    ttk::button $base.components.all.clearLogger -text "clear logger" -command "clearLogger"
    pack $base.components.all.clearLogger -side right -ipadx 15

    ttk::frame $base.components.group
    pack $base.components.group -side top -fill x
    # button for level control:
    set LEVELS [lsort -unique "$LEVELS"]
    ttk::frame $base.components.group.level
    pack $base.components.group.level -side left -fill both
    foreach {g} "$LEVELS" {
        ttk::frame $base.components.group.level.$g -style groove.TFrame
        pack $base.components.group.level.$g -side top -fill x

        ttk::label $base.components.group.level.$g.label  -text "$g"
        ttk::button $base.components.group.level.$g.start -style cmd.TButton -text "start" -command "level_cmd start $g"
        ttk::button $base.components.group.level.$g.stop  -style cmd.TButton -text "stop"  -command "level_cmd stop $g"
        ttk::button $base.components.group.level.$g.check -style cmd.TButton -text "check" -command "level_cmd check $g"
        pack $base.components.group.level.$g.label -side left -padx 5 -fill x
        pack $base.components.group.level.$g.start -side left
        pack $base.components.group.level.$g.stop  -side left
        pack $base.components.group.level.$g.check -side left
    }
    # button for group control:
    set groups [lsort -unique "$groups"]
    ttk::frame $base.components.group.named
    pack $base.components.group.named -side left -fill both
    foreach {g} "$groups" {
        ttk::frame $base.components.group.named.$g -style groove.TFrame
        pack $base.components.group.named.$g -side top -fill x
        ttk::label $base.components.group.named.$g.label  -style group.TLabel -text "$g" -width 10 -anchor e
        ttk::button $base.components.group.named.$g.start -style cmd.TButton -text "start" -command "group_cmd start $g"
        ttk::button $base.components.group.named.$g.stop  -style cmd.TButton -text "stop"  -command "group_cmd stop $g"
        ttk::button $base.components.group.named.$g.check -style cmd.TButton -text "check" -command "group_cmd check $g"
        ttk::checkbutton $base.components.group.named.$g.noauto -text "no auto" -command "set_group_noauto $g" -variable GNOAUTO($g) -onvalue 1 -offvalue 0

        pack $base.components.group.named.$g.label -side left -padx 2
        pack $base.components.group.named.$g.start -side left
        pack $base.components.group.named.$g.stop -side left
        pack $base.components.group.named.$g.check -side left
        pack $base.components.group.named.$g.noauto -side left
    }

    # LOGGER area (WATCHFILE)
    ttk::frame $base.components.group.log
    text $base.components.group.log.text -yscrollcommand "$base.components.group.log.sb set" -height 8

    ttk::scrollbar $base.components.group.log.sb -command "$base.components.group.log.text yview"
    pack $base.components.group.log -side left -fill both -expand 1
    pack $base.components.group.log.text -side left -fill both -expand 1
    pack $base.components.group.log.sb -side right -fill y
    if {"$WATCHFILE" != ""} {
        init_logger "$WATCHFILE"
    }

    pack $base.components -side top -fill both -expand yes

    # logarea
    ttk::label $base.logarea -textvariable LOGTEXT -style log.TLabel
    pack $base.logarea -side top -fill both

    ttk::frame $base.ssh
    pack $base.ssh -side left -fill x
    ttk::label $base.ssh.label -text "ssh to"
    pack $base.ssh.label -side left
    foreach {h} $HOSTS {
        add_host $h
    }

    ttk::button $base.exit -style exit.TButton -text "exit" -command {gui_exit}
    pack $base.exit -side right

    if {[info exists ::env(VDEMO_alert_string)]} {
        ttk::label $base.orlabel -style alert.TLabel -text "$env(VDEMO_alert_string)"
        pack $base.orlabel -fill x
    } elseif {[info exists ::env(VDEMO_info_string)]} {
        ttk::label $base.orlabel -style info.TLabel -text "no robot config loaded"
        pack $base.orlabel -fill x
    }
}

proc add_host {host} {
    global HOST SCREENED_SSH
    set base ""
    set lh [string tolower "$host"]
    set SCREENED_SSH($host) 0

    ttk::frame  $base.ssh.$lh
    ttk::button $base.ssh.$lh.xterm -style cmd.TButton -text "$host" -command "remote_xterm $host"
    ttk::button $base.ssh.$lh.clock -style cmd.TButton -text "⌚" -command "remote_clock $host" -width -2
    ttk::checkbutton $base.ssh.$lh.screen -text "" -command "screen_ssh_master $host" -variable SCREENED_SSH($host) -onvalue 1 -offvalue 0
    pack $base.ssh.$lh -side left -fill x -padx 3
    pack $base.ssh.$lh.xterm  -side left -fill x
    pack $base.ssh.$lh.clock  -side left -fill x
    pack $base.ssh.$lh.screen -side left -fill x
}

proc clearLogger {} {
    global WATCHFILE
    .components.group.log.text delete 1.0 end
    exec echo -n "" >> "$WATCHFILE"
}

proc init_logger {filename} {
    global mypid
     exec mkdir -p [file dirname $filename]
     exec touch $filename
    if { [catch {open "|tail -n 5 --pid=$mypid -F $filename"} infile] } {
        puts  "Could not open $filename for reading."
    } else {
        fconfigure $infile -blocking no -buffering line
        fileevent $infile readable [list insertLog $infile]
    }
}

proc insertLog {infile} {
    if { [gets $infile line] >= 0 } {
        .components.group.log.text insert end "$line\n"  ;# Add a newline too
        .components.group.log.text yview moveto 1

    } else {
        # Close the pipe - otherwise we will loop endlessly
        close $infile
    }
}


proc allcomponents_cmd {cmd} {
    global HOST COMPONENTS ARGS TERMINAL USEX WAIT_READY WAIT_BREAK NOAUTO LEVELS
    if {"$cmd" == "stop"} {
        set WAIT_BREAK 1
        foreach {level} "[lreverse [lsort $LEVELS]]" {
            level_cmd $cmd $level
        }
    } else {
        set WAIT_BREAK 0
        foreach {level} "$LEVELS" {
            if {$WAIT_BREAK} {
                # if WAIT_BREAK was set to 1 somewhere, we stop the loop
                break
            }
            level_cmd $cmd $level
        }
    }
}

proc group_cmd {cmd grp} {
    global HOST COMPONENTS ARGS GROUP TERMINAL USEX WAIT_READY NOAUTO WAIT_BREAK
    if {"$cmd" == "stop"} {
        set WAIT_BREAK 1
        foreach {comp} "[lreverse $COMPONENTS]" {
            if {$GROUP($comp) == $grp} {
                component_cmd $comp $cmd
            }
        }
    } elseif {"$cmd" == "check"} {
        foreach {comp} "$COMPONENTS" {
            if {$GROUP($comp) == $grp} {
                component_cmd $comp $cmd
            }
        }
    } else {
        set WAIT_BREAK 0
        foreach {comp} "$COMPONENTS" {
            if {$GROUP($comp) == $grp} {
                if {$WAIT_BREAK} {
                    break
                }
                if {! $NOAUTO($comp)} {
                    component_cmd $comp $cmd
                }
            }
        }
    }
}

proc level_cmd {cmd level} {
    global HOST COMPONENTS ARGS GROUP TERMINAL USEX WAIT_READY NOAUTO WAIT_BREAK COMP_LEVEL
    if {"$cmd" == "stop"} {
        set WAIT_BREAK 1
        foreach {comp} "[lreverse $COMPONENTS]" {
            if {$COMP_LEVEL($comp) == $level} {
                component_cmd $comp $cmd
            }
        }
    } elseif {"$cmd" == "check"} {
        foreach {comp} "$COMPONENTS" {
            if {$COMP_LEVEL($comp) == $level} {
                component_cmd $comp $cmd
            }
        }
    } else {
        set WAIT_BREAK 0
        foreach {comp} "$COMPONENTS" {
            if {$COMP_LEVEL($comp) == $level} {
                if {$WAIT_BREAK} {
                    break
                }
                if {! $NOAUTO($comp)} {
                    component_cmd $comp $cmd
                }
            }
        }
    }
}

proc wait_ready {comp} {
    global WAIT_READY WAIT_BREAK COMPSTATUS CONT_CHECK WAIT_BREAK TITLE CHECKNOWAIT_TIME COMPWIDGET
    set WAIT_BREAK 0
    if {[string is digit $WAIT_READY($comp)] && $WAIT_READY($comp) > 0} {
        puts "$TITLE($comp): waiting for the process to get ready"
        set endtime [expr [clock milliseconds] + $WAIT_READY($comp) * 1000]
        set checktime [expr [clock milliseconds] + 1000]
        while {$endtime > [clock milliseconds]} {
            sleep 100
            # check every 1000ms
            if {$CONT_CHECK($comp) && $checktime < [clock milliseconds]} {
                component_cmd $comp check
                set checktime [expr [clock milliseconds] + 1000]
            }
            if {[string match "ok_*" $COMPSTATUS($comp)] || $WAIT_BREAK} {
                break
            }
        }
        dputs "$TITLE($comp): finished waiting"

        # first re-enable start button
        $COMPWIDGET.$comp.start state !disabled
        # and then check component a last time to reflect final state
        component_cmd $comp check
    } else {
        dputs "$TITLE($comp): not waiting for the process to get ready"
        # re-enable start button
        $COMPWIDGET.$comp.start state !disabled
        after [expr $CHECKNOWAIT_TIME($comp) * 1000] component_cmd $comp check
    }
}

proc remote_xterm {host} {
    global env
    set cmd_line "xterm -fg white -bg black -title $host -e \"LD_LIBRARY_PATH=$env(LD_LIBRARY_PATH) bash\" &"
    ssh_command "$cmd_line" $host
}

proc remote_clock {host} {
    global env
    set cmd_line "xclock -fg white -bg black -geometry 250x30 -title $host -digital -update 1 &"
    ssh_command "$cmd_line" "$host"
}

proc cancel_detach_timer {comp} {
    global TIMERDETACH
    if {$TIMERDETACH($comp) != 0} {
        after cancel $TIMERDETACH($comp)
        set TIMERDETACH($comp) 0
    }
}

proc component_cmd {comp cmd} {
    global env HOST COMPONENTS ARGS TERMINAL USEX WAIT_READY LOGGING WAIT_BREAK SCREENED DETACHTIME COMPWIDGET COMMAND EXPORTS TITLE COMPSTATUS TIMERDETACH
    set cpath "$env(VDEMO_componentPath)"
    set component_script "$cpath/component_$COMMAND($comp)"
    set component_options "-t $TITLE($comp)"
    if {$USEX($comp)} {
        set component_options "$component_options -x"
    }
    if {$LOGGING($comp)} {
        set component_options "$component_options -l"
    }
    set VARS "$EXPORTS($comp) "

    switch $cmd {
        start {
            if { [$COMPWIDGET.$comp.start instate disabled] } {
                puts "$TITLE($comp): not ready, still waiting for the process"
                return
            }
            $COMPWIDGET.$comp.start state disabled
            update

            set res [ssh_command "screen -wipe | fgrep -q .$COMMAND($comp).$TITLE($comp)_" "$HOST($comp)"]
            if {$res == -1} {
                puts "no connection to $HOST($comp)"
                return
            } elseif {$res == 0} {
                puts "$TITLE($comp): already running, stopping first..."
                component_cmd $comp stop
            }

            set WAIT_BREAK 0
            set_status $comp starting
            cancel_detach_timer $comp

            if {$DETACHTIME($comp) < 0} {
                set component_options "$component_options --noiconic"
            }
            set cmd_line "$VARS $component_script $component_options start"
            set res [ssh_command "$cmd_line" "$HOST($comp)"]

            if {$res == 2} {
                puts "*** X connection failed: consider xhost + on $HOST($comp)"
                set_status $comp failed_noscreen
                $COMPWIDGET.$comp.start state !disabled
                return
            }

            set SCREENED($comp) 1
            if {$DETACHTIME($comp) >= 0} {
                set detach_after [expr $DETACHTIME($comp) * 1000]
                set TIMERDETACH($comp) [after $detach_after component_cmd $comp detach]
            }
            wait_ready $comp
        }
        stop {
            if { [$COMPWIDGET.$comp.stop instate disabled] } {
                dputs "$TITLE($comp): already stopping"
                return
            }
            $COMPWIDGET.$comp.stop state disabled
            set_status $comp unknown
            cancel_detach_timer $comp

            set cmd_line "$VARS $component_script $component_options stop"
            set WAIT_BREAK 1

            ssh_command "$cmd_line" "$HOST($comp)"
            set SCREENED($comp) 0

            after idle $COMPWIDGET.$comp.stop state !disabled
            after idle component_cmd $comp check
        }
        screen {
            cancel_detach_timer $comp
            if {$SCREENED($comp)} {
                set cmd_line "$VARS xterm -fg white -bg black -title \"$comp@$HOST($comp) - detach by \[C-a d\]\" -e $component_script $component_options screen &"
                ssh_command "$cmd_line" "$HOST($comp)"
                after idle component_cmd $comp check
            } else {
                set cmd_line "$VARS $component_script $component_options detach"
                ssh_command "$cmd_line" "$HOST($comp)"
            }
        }
        detach {
            cancel_detach_timer $comp
            set cmd_line "$VARS $component_script $component_options detach"
            ssh_command "$cmd_line" "$HOST($comp)"
            set SCREENED($comp) 0
        }
        showlog {
            set cmd_line "$VARS $component_script $component_options showlog"
            ssh_command "$cmd_line" "$HOST($comp)"
        }
        check {
            if { [$COMPWIDGET.$comp.check instate disabled] } {
                dputs "$TITLE($comp): already checking"
                return
            }
            $COMPWIDGET.$comp.check state disabled
            set_status $comp unknown

            set cmd_line "$VARS $component_script $component_options check"
            set res [ssh_command "$cmd_line" "$HOST($comp)"]
            dputs "ssh result: $res" 2
            after idle $COMPWIDGET.$comp.check state !disabled

            if { ! [string is integer -strict $res]} {
                puts "internal error: ssh result is not an integer: '$res'"
                return
            }

            if {$res == -1} {puts "no ssh connection"; return}
            if {$res == 124} {puts "ssh command timed out"; return}

            set noscreen 0
            # res = 10*callResult + processResult
            # callResult is the result from the on_check function (0 on success)
            # processResult: 0: success, 1: no screen, 2: PID not there
            if {[expr $res / 10] == 0} { # on_check was successful
                if {[expr $res % 10] == 0} {
                    set_status $comp ok_screen
                } else {
                    set_status $comp ok_noscreen
                    set noscreen 1
                }
            } elseif { [$COMPWIDGET.$comp.start instate disabled] } {
                set_status $comp starting
            } else { # on_check failed
                if {[expr $res % 10] != 0} {
                    set_status $comp failed_noscreen
                    set noscreen 1
                } else {
                    set_status $comp failed_check
                }
            }
            if {$noscreen} {
                dputs "$comp not running: cancel detach timer"
                cancel_detach_timer $comp
                set SCREENED($comp) 0
            }
        }
        inspect {
            set cmd_line "$VARS $component_script $component_options inspect"
            ssh_command "$cmd_line" "$HOST($comp)"
        }
    }
    update
}

proc wheelEvent { x y delta } {
    .components.singles.comp yview scroll $delta units
}
bind all <4> "+wheelEvent %X %Y -5"
bind all <5> "+wheelEvent %X %Y  5"

proc set_status {comp status} {
    global COMPWIDGET COMPSTATUS
    set COMPSTATUS($comp) $status
    switch -- $status {
        starting {set style "starting.cmd.TButton"}
        ok_screen {set style "ok.cmd.TButton"}
        ok_noscreen {set style "noscreen.ok.cmd.TButton"}
        failed_noscreen {set style "failed.cmd.TButton"}
        failed_check {set style "check.failed.cmd.TButton"}
        default  {set style "cmd.TButton"}
    }
    dputs "change status of $comp to $status: $style" 2
    $COMPWIDGET.$comp.check configure -style $style
    update
}


# {{{ ssh and command procs

proc screen_ssh_master {h} {
    global SCREENED_SSH
    set screenid [get_master_screen_name $h]
    if {$SCREENED_SSH($h) == 1} {
        if { [catch {exec bash -c "screen -wipe | fgrep -q .$screenid"} ] } {
            set f [get_fifo_name $h]
            connect_host $f $h 0
        }
        exec  xterm -title "MASTER SSH CONNECTION TO $h." -e screen -r -S $screenid &
    } else {
        catch {exec  screen -d -S $screenid}
    }
}

proc ssh_check_connection {hostname} {
    global WAIT_BREAK
    set f [get_fifo_name $hostname]
    set screenid [get_master_screen_name $hostname]
    
    if { [catch {exec bash -c "screen -wipe | fgrep -q .$screenid"} ] } {
        # need to establish connection in first place?
        if {[file exists "$f.in"] == 0} {
            if { [tk_messageBox -message "Establish connection to $hostname?" \
                -type yesno -icon question] == yes} {
                connect_host $f $hostname
                add_host $hostname
            } else {
                set WAIT_BREAK 1
                return -1
            }
        } else {
            if { [tk_messageBox -message "Lost connection to $hostname. Reestablish?" \
                -type yesno -icon question] == yes} {
                connect_host $f $hostname 0
            } else {
                set WAIT_BREAK 1
                return -1
            }
        }
    }

    # Issue a dummy command to check whether connection is broken. In this case we get a timeout.
    # Without checking, reading $f.out will last forever when ssh connection is broken.
    # The error code of the timeout is 124. Tcl creates an exception on timeout.
    # Instead of timing out on the real ssh_command, we timeout here on a dummy, because here we
    # know, that the command shouldn't last long. However, the real ssh_command could last rather
    # long, e.g. stopping a difficult component. This would generate a spurious timeout.
    catch { set res 124; set res [exec bash -c "echo 'echo 0' > $f.in; timeout 1 cat $f.out"] }
    dputs "connection check result: $res"

    # cat might also fetch the result of a previous, delayed ssh command. Hence, if we didn't 
    # timed out, set the result always to zero.
    if {$res != 124} {set res 0}
    return $res
}

proc ssh_command {cmd hostname {check 1} {verbose 1}} {
    set f [get_fifo_name $hostname]

    # check if master connection is in place
    if $check {
        set res [ssh_check_connection $hostname]
        # return on error
        if $res { return $res; }
    }

    # actually issue the command
    set cmd [string trim "$cmd"]
    if {$verbose > 0} {
        puts "run '$cmd' on host '$hostname'"
        set verbose "echo \"****************************************\" 1>&2; date 1>&2; echo \"*** RUN $cmd\" 1>&2;"
    } else {set verbose ""}

    set res [exec bash -c "echo '$verbose $cmd 1>&2; echo \$?' > $f.in; cat $f.out"]
    dputs "ssh result: $res" 2
    return $res
}

proc get_master_screen_name { hostname } {
    global VDEMOID
    return "vdemo-$VDEMOID-$hostname"
}

proc get_fifo_name {hostname} {
    global COMPONENTS HOST TEMPDIR VDEMOID env
    return "$TEMPDIR/vdemo-$VDEMOID-ssh-$env(USER)-$hostname"
}

proc connect_host {fifo host {doMonitor 1}} {
    global env SSHOPTS DEBUG_LEVEL
    exec rm -f "$fifo.in"
    exec rm -f "$fifo.out"
    exec mkfifo "$fifo.in"
    exec mkfifo "$fifo.out"

    # Here we establish the master connection. Commands pushed into $fifo.in get piped into
    # the remote bash (over ssh) and the result is read again and piped into $fifo.out.
    # This way, the remote stdout goes into $fifo.out, while remote stderr is displayed here.
    set screenid [get_master_screen_name $host]   
    exec screen -dmS $screenid bash -c "tail -s 0.1 -n 10000 -f $fifo.in | ssh $SSHOPTS -Y $host bash | while read s; do echo \$s > $fifo.out; done"

    # Wait until connection is established. 
    # Issue a echo command on remote host that only returns if a connection was established. 
    puts -nonewline "connecting to $host: "; flush stdout
    exec bash -c "echo 'echo connected' > $fifo.in"
    # timeout: 30s (should be enough to enter ssh password if necessary)
    set endtime [expr [clock seconds] + 30]
    set xterm_shown 0
    while {$endtime > [clock seconds]} {
        set res [exec bash -c "timeout 1 cat $fifo.out; echo $?"]
        set noScreen [catch {exec bash -c "screen -wipe | fgrep -q .$screenid"} ]
        # continue waiting on timeout (124), otherwise break from loop
        if {$res == 124} { puts -nonewline "."; flush stdout } { break }
        # break from loop, when screen session was stopped
        if {$noScreen} {set res "aborted"; break}

        # show screen session in xterm after 1s (allow entering password, etc.)
        if { ! $xterm_shown } {
            exec xterm -title "establish ssh connection to $host" -n "$host" -e screen -rS $screenid &
            set xterm_shown 1
        }
    }
    if {[string match "connected*" $res]} {
        puts " OK"
    } else { # some failure
        if {$res == 124} {puts " timeout"} {puts " error: $res"}
        # quit screen session
        catch {exec screen -XS $screenid quit}
        exec rm -f "$fifo.in"
        exec rm -f "$fifo.out"
        return $res 
    }

    dputs "issuing remote initialization commands" 2
    if {[info exists env(VDEMO_exports)]} {
        foreach {var} "$env(VDEMO_exports)" {
            if {[info exists env($var)]} {
                ssh_command "export $var=$env($var)" $host 0 $DEBUG_LEVEL
            }
        }
    }
    ssh_command "source $env(VDEMO_demoConfig)" $host 0 $DEBUG_LEVEL

    # detach screen / close xterm
    catch { exec screen -dS $screenid }

    if $doMonitor {connect_screenmonitoring $host}

    if {$::AUTO_SPREAD_CONF == 1} {
        set content [exec cat $::env(SPREAD_CONFIG)]
        exec bash -c "echo 'echo \"$content\" > $::env(SPREAD_CONFIG)' > $fifo.in"
    }
    return 0
}

proc connect_hosts {} {
    global HOSTS

    label .vdemoinit -text "init VDemo - be patient..." -foreground darkgreen -font "helvetica 30 bold"
    label .vdemoinit2 -text "" -foreground darkred -font "helvetica 20 bold"
    pack .vdemoinit
    pack .vdemoinit2
    update

    foreach {h} $HOSTS {
        .vdemoinit2 configure -text "connect to $h"
        update
        set fifo [get_fifo_name $h]
        connect_host $fifo $h
    }
    destroy .vdemoinit
    destroy .vdemoinit2
}

proc disconnect_hosts {} {
    global env HOSTS

    foreach {h} $HOSTS {
        dputs "disconnecting from $h"
        set screenid [get_master_screen_name $h]
        set fifo [get_fifo_name $h]
        set screenPID [exec bash -c "screen -list $screenid | grep vdemo | cut -d. -f1"]
        if {$::AUTO_SPREAD_CONF == 1 && "$screenPID" != "" && [file exists "$fifo.in"]} {
            # send ssh command, but do not wait for result
            set cmd "rm -f $env(SPREAD_CONFIG)"
            exec bash -c "echo 'echo \"*** RUN $cmd\" 1>&2; $cmd 1>&2; echo \$?' > $fifo.in"
        }
        catch {exec bash -c "screen -list $screenid | grep vdemo | cut -d. -f1 | xargs kill 2>&1"}
        exec rm -f "$fifo.in"
        exec rm -f "$fifo.out"
    }
}

proc finish {} {
    global MONITORCHAN_HOST TEMPDIR
    foreach ch [chan names] {
        if { [info exists MONITORCHAN_HOST($ch)] } {
            exec kill -HUP [lindex [pid $ch] 0]
        }
    }
    disconnect_hosts
    catch {exec rmdir "$TEMPDIR"}
    exit
}

proc remove_duplicates {} {
    global COMPONENTS TITLE HOST

    set _COMPONENTS {}
    foreach {c} "$COMPONENTS" {
        set cmdhost "$TITLE($c):$HOST($c)"
        if { ![info exists _HAVE($cmdhost)] } {
            set _HAVE($cmdhost) "$cmdhost"
            set _COMPONENTS "$_COMPONENTS $c"
        } else {
            dputs "duplicate component title: $TITLE($c):$HOST($c)"
        }
    }
    set COMPONENTS $_COMPONENTS
}

proc compute_spread_segment {ip num} {
    global env
    set octets [split $ip .]
    # use IP octets 1-4
    set seg [join [lrange $octets 1 3] .]
    return "225.$seg:$env(SPREAD_PORT)"
}

proc get_autospread_filename {} {
    global VDEMOID env
    return "/tmp/vdemo-spread-$VDEMOID-$env(USER).conf"
}

proc create_spread_conf {} {
    global COMPONENTS COMMAND HOST env
    set ::AUTO_SPREAD_CONF 0

    # If SPREAD_CONFIG was defined in environment, we are already done
    if {[info exists ::env(SPREAD_CONFIG)]} { return }

    set spread_hosts ""
    foreach {c} "$COMPONENTS" {
        if {"$COMMAND($c)" == "spreaddaemon"} {
            lappend spread_hosts $HOST($c)
        }
    }
    set spread_hosts [lsort -unique "$spread_hosts"]
    if {[llength $spread_hosts] > 0} {
        set ::AUTO_SPREAD_CONF 1
    } else {
        return
    }
    # list of adapter ips to find best local ip
    set local_addr [exec ip -o -4 addr | sed {s/.*inet \(\([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\}\).*/\1/g}]
    set segments ""
    set REGEXP_IP {([0-9]{1,3}\.){3}[0-9]{1,3}}
    foreach {h} "$spread_hosts" {
        set ip ""
        if { [catch {set ip [exec ping -c1 -W 1 $h | grep "bytes from" | egrep -o "$REGEXP_IP"]}] } {
            catch {set ip [exec dig +tries=1 +retry=0 +time=1 +search +short $h | egrep -o $REGEXP_IP]}
        }
        # if address is localhost and we have a config with multiple hosts
        if {[string match "127.*" $ip] && [llength "$spread_hosts"] > 1} {
            # try to find alternatives the host resolves to
            catch {
                set ips [exec getent ahostsv4 $h | grep "STREAM" | cut -d " " -f1 | sort | uniq]
                foreach {lip} "$ips" {
                    if {[lsearch -exact $local_addr $lip] > -1} {
                        set ip $lip
                    }
                }
            }
        }
        if {"$ip" == ""} {puts "failed to lookup host $h"; continue}
        set seg [join [lrange [split $ip .] 0 2] .]
        set segments "$segments $seg"
        set IP($h) $ip
        if {![info exists hosts($seg)]} {
            set hosts($seg) "$h"
        } else {
            set hosts($seg) "$hosts($seg) $h"
        }
    }
    set segments [lsort -unique "$segments"]
    set filename [get_autospread_filename]
    if {[catch {open $filename w 0664} fd]} {
        error "Could not open auto-generated spread configuration $filename"
    }
    set ::env(SPREAD_CONFIG) $filename
    if {![info exists ::env(SPREAD_PORT)]} {set ::env(SPREAD_PORT) 4803}

    set num 1
    foreach {seg} "$segments" {
        if {[string match "127.*" $seg]} {
            set sp_seg "$seg.255:$env(SPREAD_PORT)"
        } else {
            set sp_seg [compute_spread_segment $IP([lindex $hosts($seg) 0]) $num]
            set num [expr $num + 1]
        }
        puts $fd "Spread_Segment $sp_seg {"
            foreach {h} $hosts($seg) {
                puts $fd "\t $h \t $IP($h)"
            }
        puts $fd "}"
        puts $fd ""
    }
    puts $fd "SocketPortReuse = ON"

    close $fd
    puts "created spread config: $filename"
    exec cat $filename
}

proc handle_screen_failure {chan} {
    global MONITORCHAN_HOST SCREENED_SSH COMPONENTS HOST COMMAND TITLE COMPSTATUS WAIT_BREAK VDEMOID TERMINATE_ON_EXIT COMPWIDGET
    if {[gets $chan line] >= 0} {
        set host ""
        regexp "^\[\[:digit:]]+\.vdemo-$VDEMOID-(.*)\$" $line matched host
        if {"$host" != ""} {
            set SCREENED_SSH($host) 0
            if { [tk_messageBox -message "Lost connection to $host. Reestablish?" \
                -type yesno -icon question] == yes} {
                set f [get_fifo_name $host]
                connect_host $f $host 0
            }
        } else {
            set host $MONITORCHAN_HOST($chan)
            foreach {comp} "$COMPONENTS" {
                if {$HOST($comp) == $host && \
                    [string match "*.$COMMAND($comp).$TITLE($comp)_" "$line"]} {
                    puts "$TITLE($comp): screen closed on $MONITORCHAN_HOST($chan), calling stop..."
                    # store the previous state of the gui to determine whether
                    # we have been called as a consequence of a user initiated
                    # stop request (in that case the button is already disabled)
                    # or through inotify (button not disabled).
                    # We need to store this variable before calling stop here
                    # to preserve the original state before user interaction.
                    set already_disabled [$COMPWIDGET.$comp.stop instate disabled]
                    component_cmd $comp stop
                    # only if this is not a user initiated stop, exit the system
                    # if requested to
                    if {!$already_disabled && $TERMINATE_ON_EXIT($comp)} {
                        allcomponents_cmd "stop"
                        finish
                    }
                }
            }
        }
    }
    if {[eof $chan]} {
        puts "screen monitoring failed on $MONITORCHAN_HOST($chan) (received EOF): install inotifywait?"
        close $chan
    }
}

# setup inotifywait on remote hosts to monitor deletions in screen-directory
proc connect_screenmonitoring {host} {
    global MONITORCHAN_HOST COMPONENTS HOST env SSHOPTS
    set chan [open "|ssh $SSHOPTS -tt $host inotifywait -e delete -qm --format %f /var/run/screen/S-$env(USER)" "r+"]
    set MONITORCHAN_HOST($chan) $host
    fconfigure $chan -blocking 0 -buffering line -translation auto
    fileevent $chan readable [list handle_screen_failure $chan]
}

proc gui_exit {} {
    global COMPONENTS COMPSTATUS
    set quickexit 1
    foreach {comp} "$COMPONENTS" {
        if { [string match *_screen $COMPSTATUS($comp)] || \
             $COMPSTATUS($comp) == "starting"} {
            set quickexit 0
            break
        }
    }
    if {$quickexit || [tk_messageBox -message "Really quit?" -type yesno -icon question] == yes} {
        finish
    }
}

wm protocol . WM_DELETE_WINDOW {
    gui_exit
}

# event-handling sleep, see http://www2.tcl.tk/933
proc uniqkey { } {
    set key   [ expr { pow(2,31) + [ clock clicks ] } ]
    set key   [ string range $key end-8 end-3 ]
    set key   [ clock seconds ]$key
    return $key
}

proc sleep { ms } {
    set uniq [ uniqkey ]
    set ::__sleep__tmp__$uniq 0
    after $ms set ::__sleep__tmp__$uniq 1
    vwait ::__sleep__tmp__$uniq
    unset ::__sleep__tmp__$uniq
}

proc setup_temp_dir { } {
    global TEMPDIR
    set TEMPDIR [exec mktemp -d /tmp/vdemo.XXXXXXXXXX]
}

set mypid [pid]
puts "My process id is $mypid"

signal trap SIGINT finish
signal trap SIGHUP finish

setup_temp_dir
parse_env_var
remove_duplicates

if {![info exists ::env(LD_LIBRARY_PATH)]} {
    set ::env(LD_LIBRARY_PATH) ""
}
create_spread_conf

# cleanup dangling connections first
disconnect_hosts
connect_hosts
update
gui_tcl
update

# autostart
if {[info exists env(VDEMO_autostart)] && $env(VDEMO_autostart) == "true"} {
    puts "Starting all components due to autostart request"
    allcomponents_cmd "start"
}
