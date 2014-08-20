#!/bin/bash
# kate: replace-tabs on; indent-width 4;
# the next line restarts using wish \
exec wish8.5 "$0" "$@"
package require Iwidgets 4.0
package require Tclx

set SSHCMD "ssh -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -oPasswordAuthentication=no -oConnectTimeout=15"

# Theme settings
set FONT "helvetica 9"
ttk::style configure "." -font $FONT
ttk::style configure sunken.TFrame -relief sunken
ttk::style configure groove.TFrame -relief groove

ttk::style configure TButton -font "$FONT bold" -padding "2 -1"
ttk::style configure TCheckbutton -padding "2 -1"
ttk::style configure cmd.TButton -padding "2 -1" -width -5
ttk::style map ok.cmd.TButton -background [list !disabled green3  active green2]
ttk::style map failed.cmd.TButton -background [list !disabled red2  active red]
ttk::style map starting.cmd.TButton -background [list !disabled yellow2  active yellow]

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

proc parse_options {comp} {
    global env HOST COMPONENTS ARGS USEX TERMINAL WAIT_READY NOAUTO LOGGING GROUP DETACHTIME COMP_LEVEL EXPORTS TITLE CONT_CHECK CHECKNOWAIT_TIME
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
            default {
                set NEWARGS [lappend NEWARGS $arg]
            }
        }
    }
    set ARGS($comp) $NEWARGS
}


proc parse_env_var {} {
    global env HOST COMPONENTS ARGS USEX WATCHFILE COMMAND TITLE VDEMOID
    set VDEMOID [file tail [file rootname $env(VDEMO_demoConfig)]]
    set components_list "$env(VDEMO_components)"
    set comp [split "$components_list" ":"]
    set nCompos [llength "$comp"]
    set COMPONENTS {}
    set WATCHFILE ""
    catch {set WATCHFILE $env(VDEMO_watchfile)}
    puts "VDEMO_watchfile = $WATCHFILE"
    puts "COMPONENTS: "
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
            
            set HOST($component_name) $host
            set ARGS($component_name) [lindex $thisComp 2]
            # do not simply tokenize at spaces, but allow quoted strings ("" or '')
            set ARGS($component_name) [regexp -all -inline -- "\\S+|\[^ =\]+=(?:\\S+|\"\[^\"]+\"|'\[^'\]+')" $ARGS($component_name)]
            puts "$component_name\tHOST: $HOST($component_name)\tARGS: $ARGS($component_name)"
            # parse options known by the script and remove them from them the list
            parse_options "$component_name"
        } elseif {[string length [string trim [lindex "$comp" $i]]] != 0} {
            error "component $i: exepected three comma separated groups in '[string trim [lindex "$comp" $i]]'"
        }
    }
    puts ""
    
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
    global HOST SCREENED_SSH COMPONENTS ARGS TERMINAL USEX LOGTEXT env NOAUTO LOGGING  GROUP SCREENED  COMP_LEVEL COMPWIDGET WATCHFILE COMMAND LEVELS TITLE TIMERDETACH
    set root "."
    set base ""
    set LOGTEXT "demo configured from '$env(VDEMO_demoConfig)'"
    wm title . "vdemo_controller: $env(VDEMO_demoConfig)"
    wm geometry . "850x600"
    
    set hosts ""
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
        set hosts "$hosts $HOST($c)"
        set groups "$groups $GROUP($c)"
        set LEVELS "$LEVELS $COMP_LEVEL($c)"
        set TIMERDETACH($c) 0

        ttk::frame $COMPWIDGET.$c -style groove.TFrame
        pack $COMPWIDGET.$c -side top -fill both -expand yes
        ttk::label $COMPWIDGET.$c.level -style level.TLabel -text "$COMP_LEVEL($c)"        
        ttk::label $COMPWIDGET.$c.label -style label.TLabel -text "$TITLE($c)@"
        ttk::entry $COMPWIDGET.$c.host  -width 10 -textvariable HOST($c)
        ttk::label $COMPWIDGET.$c.group -style group.TLabel -text "$GROUP($c)"

        ttk::button $COMPWIDGET.$c.start -style cmd.TButton -text "start" -command "component_cmd $c start"
        ttk::button $COMPWIDGET.$c.stop  -style cmd.TButton -text "stop" -command "component_cmd $c stop"
        ttk::button $COMPWIDGET.$c.check -style cmd.TButton -text "check" -command "component_cmd $c check"
        ttk::checkbutton $COMPWIDGET.$c.noauto -text "no auto" -variable NOAUTO($c)
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
        pack $COMPWIDGET.$c.inspect -side right
        pack $COMPWIDGET.$c.viewlog -side right
        pack $COMPWIDGET.$c.logging -side right
        pack $COMPWIDGET.$c.terminal -side right
        pack $COMPWIDGET.$c.terminal.screen -side right
        pack $COMPWIDGET.$c.noauto -side right -padx 3
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
    pack $base.components.group.named -side left -fill x
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
    
    set hosts [lsort -unique "$hosts"]
    ttk::frame $base.ssh
    pack $base.ssh -side left -fill x
    ttk::label $base.ssh.label -text "ssh to"
    pack $base.ssh.label -side left
    foreach {h} "$hosts" {
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
    global WAIT_READY WAIT_BREAK COMPSTATUS CONT_CHECK WAIT_BREAK TITLE CHECKNOWAIT_TIME
    set WAIT_BREAK 0
    if {[string is digit $WAIT_READY($comp)] && $WAIT_READY($comp) > 0} {
        puts "$TITLE($comp): waiting for the process to be ready"
        set endtime [expr [clock milliseconds] + $WAIT_READY($comp) * 1000]
        set checktime [expr [clock milliseconds] + 1000]
        while {$endtime > [clock milliseconds]} {
            sleep 100
            if {$CONT_CHECK($comp) && $checktime < [clock milliseconds]} {
                component_cmd $comp check
                set checktime [expr [clock milliseconds] + 1000]
            }
            if {$COMPSTATUS($comp) == 1 || $WAIT_BREAK} {
                break
            }
        }
        component_cmd $comp check
        puts "$TITLE($comp): finished waiting"
    } else {
        puts "$TITLE($comp): not waiting for the process to be ready"
        after [expr $CHECKNOWAIT_TIME($comp) * 1000] "component_cmd $comp check"
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
            try_eval {
                if { [$COMPWIDGET.$comp.start instate disabled] } {
                    puts "$TITLE($comp): not ready, still waiting for the process"
                    return
                }
                $COMPWIDGET.$comp.start state disabled
                update
                set res [ssh_command "screen -wipe | fgrep -q .$COMMAND($comp).$TITLE($comp)_" "$HOST($comp)"]
                if {$res == 10} {
					puts "no connection to $HOST($comp)"
					return
                } elseif {$res == 0} {
                    puts "$TITLE($comp): already running, stopping first..."
                    component_cmd $comp stop
                }
                
                set WAIT_BREAK 0
                set_status $comp 2
                cancel_detach_timer $comp
                
                if {$DETACHTIME($comp) < 0} {
                    set component_options "$component_options --noiconic"
                }
                set cmd_line "$VARS $component_script $component_options start"
                ssh_command "$cmd_line" "$HOST($comp)"
                
                set SCREENED($comp) 1
                if {$DETACHTIME($comp) >= 0} {
                    cancel_detach_timer $comp
                    set detach_after [expr $DETACHTIME($comp) * 1000]
                    set TIMERDETACH($comp) [after $detach_after "component_cmd $comp detach"]
                }
                wait_ready $comp
            } {} {
                #finally
                $COMPWIDGET.$comp.start state !disabled
                if {$COMPSTATUS($comp) == 2 && $WAIT_READY($comp) > 0} {
                    set_status $comp 0
                    set SCREENED($comp) 0
                }
            }
        }
        stop {
            set cmd_line "$VARS $component_script $component_options stop"
#            $COMPWIDGET.$comp.stop flash
            set WAIT_BREAK 1
            set_status $comp unknown
            
            ssh_command "$cmd_line" "$HOST($comp)"
            set SCREENED($comp) 0
            cancel_detach_timer $comp
            update
            if {$COMPSTATUS($comp) != 0} {
                after idle "component_cmd $comp check"
            }
        }
        screen {
            cancel_detach_timer $comp
            if {$SCREENED($comp)} {
                set cmd_line "$VARS xterm -fg white -bg black -title \"$comp - detach by \[C-a d\]\" -e $component_script $component_options screen &"
                ssh_command "$cmd_line" "$HOST($comp)"
                after idle "component_cmd $comp check"
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
            set cmd_line "$VARS $component_script $component_options check"
            
            set_status $comp unknown
            set res [ssh_command "$cmd_line" "$HOST($comp)"]
            
            if {$res == 0} {
                set_status $comp 1
            } elseif { [$COMPWIDGET.$comp.start instate disabled] } {
                set_status $comp 2
            } else {
                cancel_detach_timer $comp
                set SCREENED($comp) 0
                set_status $comp 0
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
    if {$status == 1} {
        $COMPWIDGET.$comp.check configure -style ok.cmd.TButton
    } elseif {$status == 0} {
        $COMPWIDGET.$comp.check configure -style failed.cmd.TButton
    } elseif {$status == 2} {
        $COMPWIDGET.$comp.check configure -style starting.cmd.TButton
    } else {
        $COMPWIDGET.$comp.check configure -style cmd.TButton
    }
    update
}


# {{{ ssh and command procs

proc screen_ssh_master {h} {
    global SCREENED_SSH
    set screenid [get_master_screen_name $h]
    if {$SCREENED_SSH($h) == 1} {
        exec  xterm -title "MASTER SSH CONNECTION TO $h." -e screen -d -r -S $screenid &
    } else {
        catch {exec  screen -d -S $screenid}
    }
}

proc ssh_command {cmd hostname} {
    set f [get_fifo_name $hostname]
    if {[file exists "$f.in"] == 0} {
		if { [tk_messageBox -message "Establish connection to $hostname?" -type yesno -icon question] == yes} {
			connect_host $f $hostname
			add_host $hostname
			update
		} else {
			return 10
		}
    }
    set cmd [string trim "$cmd"]
    puts "run '$cmd' on host '$hostname'"
    set res [exec bash -c "echo 'echo \"****************************************\" 1>&2; date 1>&2; echo \"*** RUN $cmd\" 1>&2; $cmd 1>&2; echo \$?' > $f.in; cat $f.out"]
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

proc connect_host {fifo host} {
	global env SSHCMD
	exec rm -f "$fifo.in"
	exec rm -f "$fifo.out"
	exec mkfifo "$fifo.in"
	exec mkfifo "$fifo.out"

	set screenid [get_master_screen_name $host]
	exec xterm -title "establish ssh connection to $fifo" -n "$fifo" -e screen -mS $screenid bash -c "tail -s 0.1 -n 10000 -f $fifo.in | $SSHCMD -Y $host bash | while read s; do echo \$s > $fifo.out; done" &

	if {[info exists env(VDEMO_exports)]} {
		foreach {var} "$env(VDEMO_exports)" {
			if {[info exists env($var)]} {
				ssh_command "export $var=$env($var)" $host
			}
		}
	}
	ssh_command "source $env(VDEMO_demoConfig)" $host
	exec screen -dS $screenid
}

proc connect_hosts {} {
    global COMPONENTS HOST
    
    label .vdemoinit -text "init VDemo - be patient..." -foreground darkgreen -font "helvetica 30 bold"
    label .vdemoinit2 -text "" -foreground darkred -font "helvetica 20 bold"
    pack .vdemoinit
    pack .vdemoinit2
    update
    
    set fifos ""
    foreach {c} "$COMPONENTS" {
        set fifo "[get_fifo_name $HOST($c)]"
        set fifos "$fifos $fifo"
        set fifo_host($fifo) "$HOST($c)"
    }
    set fifos [lsort -unique "$fifos"]
    
    foreach {f} "$fifos" {
        .vdemoinit2 configure -text "connect to $fifo_host($f)"
        update
		connect_host $f $fifo_host($f)
    }
    destroy .vdemoinit
    destroy .vdemoinit2
}

proc disconnect_hosts {} {
    global COMPONENTS env HOST
    set fifos ""
    foreach {c} "$COMPONENTS" {
        set fifo "[get_fifo_name $HOST($c)]"
        set fifos "$fifos $fifo"
        set fifo_host($fifo) "$HOST($c)"
    }
    set fifos [lsort -unique "$fifos"]
    
    foreach {f} "$fifos" {
        puts "terminating control channel session on $fifo_host($f)"
        set screenid [get_master_screen_name $fifo_host($f)]
        catch {exec bash -c "screen -list $screenid | grep vdemo | cut -d. -f1 | xargs kill 2>&1"}
        exec rm -f "$f.in"
        exec rm -f "$f.out"
    }
}

proc finish {} {
    global MONITORCHAN_HOST TEMPDIR
    disconnect_hosts
    if {$::AUTO_SPREAD_CONF == 1} {
        puts "deleting generated spread config"
        file delete $::env(SPREAD_CONFIG)
    }
    foreach ch [chan names] {
        if { [info exists MONITORCHAN_HOST($ch)] } {
            exec kill -HUP [lindex [pid $ch] 0]
        }
    }
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
            puts "duplicate component title: $TITLE($c):$HOST($c)"
        }
    }
    set COMPONENTS $_COMPONENTS
}

proc create_spread_conf {} {
    global COMPONENTS COMMAND HOST VDEMOID env
    set spread_hosts ""
    foreach {c} "$COMPONENTS" {
        if {"$COMMAND($c)" == "spreaddaemon"} {
            set spread_hosts "$spread_hosts $HOST($c)"
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
		if { [catch {set ip [exec ping -c1 $h | grep "bytes from" | egrep -o "$REGEXP_IP"]}] } {
			catch {set ip [exec dig +search +short $h | egrep -o $REGEXP_IP]}
		}
        # if address is localhost and we have a config with multiple hosts
        if {[string match "127.*" $ip] && [llength "$spread_hosts"] > 1} {
            # try to find alternatives the host resolves to
            set ips [exec getent ahostsv4 $h | grep "STREAM" | cut -d " " -f1 | sort | uniq]
            foreach {lip} "$ips" {
                if {[lsearch -exact $local_addr $lip] > -1} {
                    set ip $lip
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
    set filename "$env(VDEMO_demoRoot)/spread-$env(USER)-$VDEMOID.conf"
    if {[catch {open $filename w 0664} fd]} {
        # something went wrong
        # try local file again
        set filename "/tmp/spread-$env(USER)-$VDEMOID.conf"
        if {[catch {open $filename w 0664} fd]} {
            error "Could not open auto-generated spread configuration $filename"
        }
    }
    set ::env(SPREAD_CONFIG) $filename
    if {![info exists ::env(SPREAD_PORT)]} {set ::env(SPREAD_PORT) 4803}
    
    set num 1
    foreach {seg} "$segments" {
        if {[string match "127.*" $seg]} {
            set sp_seg "$seg.255:$env(SPREAD_PORT)"
        } else {
            set sp_seg "225.42.65.$num:$env(SPREAD_PORT)"
            set num [expr $num + 1]
        }
        puts $fd "Spread_Segment $sp_seg {"
            foreach {h} $hosts($seg) {
                puts $fd "\t $h \t $IP($h)"
            }
        puts $fd "}"
        puts $fd "SocketPortReuse = ON"
        puts $fd ""
    }
    
    close $fd
}

proc handle_screenmonitoring {chan} {
    global MONITORCHAN_HOST COMPONENTS HOST COMMAND TITLE COMPSTATUS WAIT_BREAK
    if {[gets $chan line] >= 0} {
        foreach {comp} "$COMPONENTS" {
            if {$HOST($comp) == $MONITORCHAN_HOST($chan) && [string match "*.$COMMAND($comp).$TITLE($comp)_" "$line"]} {
                puts "$TITLE($comp): screen closed on $MONITORCHAN_HOST($chan), checking..."
                component_cmd $comp check
                cancel_detach_timer $comp
                if { $COMPSTATUS($comp) != 1 } {
                    set WAIT_BREAK 1
                }
            }
        }
    }
    if {[eof $chan]} {
        puts "screen monitoring channel for host $MONITORCHAN_HOST($chan) received EOF"
        close $chan
    }
}

proc connect_screenmonitoring {} {
    global MONITORCHAN_HOST COMPONENTS HOST env SSHCMD
    set hosts ""
    foreach {c} "$COMPONENTS" {
        set hosts "$hosts $HOST($c)"
    }
    set hosts [lsort -unique "$hosts"]
    foreach {host} "$hosts" {
        set chan [open "|$SSHCMD -tt $host inotifywait -e delete -qm --format %f /var/run/screen/S-$env(USER)" "r+"]
        set MONITORCHAN_HOST($chan) $host
        fconfigure $chan -blocking 0 -buffering line -translation auto
        fileevent $chan readable [list handle_screenmonitoring $chan]
    }
}


proc gui_exit {} {
    global COMPONENTS COMPSTATUS
    set quickexit 1
    foreach {comp} "$COMPONENTS" {
        if { $COMPSTATUS($comp) == 1 || $COMPSTATUS($comp) == 2} {
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

# auto-create spread config
set ::AUTO_SPREAD_CONF 0
if {![info exists ::env(SPREAD_CONFIG)]} {
    create_spread_conf
}
if {![info exists ::env(LD_LIBRARY_PATH)]} {
    set ::env(LD_LIBRARY_PATH) ""
}

# cleanup dangling connections first
disconnect_hosts
connect_hosts
connect_screenmonitoring
update
gui_tcl
update
# autostart
if {[info exists env(VDEMO_autostart)] && $env(VDEMO_autostart) == "true"} {
    puts "Starting all components due to autostart request"
    allcomponents_cmd "start"
}
