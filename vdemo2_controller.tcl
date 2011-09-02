#!/bin/bash
# the next line restarts using wish \
exec wish8.5 "$0" "$@"
package require Iwidgets 4.0

# if {[catch {package require Scrolledframe}]} \
#     {
# 	source [file join [file dirname [info script]] scrollframe2.tcl]
# 	package require Scrolledframe
#     }
# namespace import ::scrolledframe::scrolledframe

proc parse_options {comp} {
    global env HOST COMPONENTS ARGS USEX TERMINAL WAIT_READY NOAUTO LOGGING WAIT_SERVER WAIT_PUBLISHER GROUP DETACHTIME XC_COMPNAME COMP_LEVEL EXPORTS TITLE
    set NEWARGS [list]
    set USEX($comp) 0
    set WAIT_READY($comp) 0
    set WAIT_SERVER($comp) ""
    set WAIT_PUBLISHER($comp) ""
    set GROUP($comp) ""
    set DETACHTIME($comp) 10
    set NOAUTO($comp) 0
    set TERMINAL($comp) "screen"
    set LOGGING($comp) 0
    set COMP_LEVEL($comp) ""
    set XC_COMPNAME($comp) ""
    set EXPORTS($comp) ""

    for {set i 0} \$i<[llength $ARGS($comp)] {incr i} {
        set arg [lindex $ARGS($comp) $i]; set val [lindex $ARGS($comp) [expr $i+1]]
        switch -glob -- $arg {
	    -w {
		set WAIT_READY($comp) "$val"
		incr i
	    }
	    -s {
		set WAIT_SERVER($comp) "$val"
		incr i
	    }
	    -c {
		set XC_COMPNAME($comp) "$val"
		incr i
	    }
	    -d {
		set DETACHTIME($comp) "$val"
		incr i
	    }
	    -p {
		set WAIT_PUBLISHER($comp) "$val"
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
	    -t {
                set TERMINAL($comp) "$val"
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
    global env HOST COMPONENTS ARGS USEX WATCHFILE COMMAND TITLE
    set components_list "$env(VDEMO_components)"
    set comp [split "$components_list" ":"]
    set nCompos [llength "$comp"]
    set COMPONENTS {}
    set WATCHFILE ""
    catch {set WATCHFILE $env(VDEMO_watchfile)}
    puts "VDEMO_watchfile = $WATCHFILE"
	 puts "COMPONENTS: "
    for {set i 0} { $i < $nCompos } {incr i} {
	set thisComp [split [lindex "$comp" $i] ","]
	if {[llength "$thisComp"] == 3} {
	    set component_name [string tolower [lindex "$thisComp" 0]]
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
	    set ARGS($component_name) [regexp -all -inline {\S+|[^ =]+=(?:\S+|"[^"]+"|'[^']+')} $ARGS($component_name)]
       # '"
	    puts "$component_name\tHOST: $HOST($component_name)\tARGS: $ARGS($component_name)"
	    # parse options known by the script and remove them from them the list
	    parse_options "$component_name"
	}
    }
	puts ""
    
}

proc isXCFComp {c} {
    global WAIT_PUBLISHER WAIT_SERVER
    if {[string length $WAIT_SERVER($c)] > 0 || [string length $WAIT_PUBLISHER($c)] > 0} {
	return 1
    } else {
	return 0
    }

}

proc gui_tcl {} {
    global HOST SCREENED_SSH COMPONENTS ARGS TERMINAL USEX LOGTEXT env NOAUTO LOGGING WAIT_PUBLISHER WAIT_SERVER GROUP SCREENED XC_COMPNAME COMP_LEVEL COMPWIDGET WATCHFILE COMMAND LEVELS TITLE
    set BOLDFONT "-*-helvetica-bold-r-*-*-10-*-*-*-*-*-*-*"
    set FONT "-*-helvetica-medium-r-*-*-10-*-*-*-*-*-*-*"
    set root "."
    set base ""
    set LOGTEXT "demo configured from '$env(VDEMO_demoConfig)'"
    wm title . "vdemo_controller: $env(VDEMO_demoConfig)"

    set hosts ""
    set groups ""
    set LEVELS ""

    frame $base.components 
    frame $base.components.singles 
    iwidgets::scrolledframe $base.components.singles.comp 	-vscrollmode dynamic -hscrollmode dynamic 

    set COMPWIDGET [$base.components.singles.comp childsite]

    pack $base.components.singles -side top -fill both -expand yes 
    pack $base.components.singles.comp -side left -expand yes -fill both 

    foreach {c} "$COMPONENTS" {
	set hosts "$hosts $HOST($c)"
	set groups "$groups $GROUP($c)"
	set LEVELS "$LEVELS $COMP_LEVEL($c)"
	#reliefs: flat, groove, raised, ridge, solid, or sunken
	frame $COMPWIDGET.$c -relief groove -borderwidth 1
	pack $COMPWIDGET.$c -side top -fill both 
	label $COMPWIDGET.$c.level -foreground blue -width 1 -text "$COMP_LEVEL($c)" -activebackground white -pady -3 -padx -7 -borderwidth 1 -font "$BOLDFONT" 
	pack $COMPWIDGET.$c.level -side left

	label $COMPWIDGET.$c.group -anchor e -foreground blue -font "$FONT" -width 10 -text "$GROUP($c)" 
	label $COMPWIDGET.$c.label -font "$BOLDFONT" -width 15 -anchor e -text "$TITLE($c)@" 
	entry $COMPWIDGET.$c.host -borderwidth 1 -font "$FONT" -width 10 -textvariable HOST($c)
	pack $COMPWIDGET.$c.label -side left -fill x
	pack $COMPWIDGET.$c.host -side left
	pack $COMPWIDGET.$c.group -side left -fill x
	button $COMPWIDGET.$c.start -activebackground white -pady -3 -padx -7 -borderwidth 1 -font "$BOLDFONT" -text "start" -command "component_cmd $c start"
	button $COMPWIDGET.$c.stop -activebackground white -pady -3 -padx -7 -borderwidth 1 -font "$BOLDFONT" -text "stop" -command "component_cmd $c stop"
	button $COMPWIDGET.$c.check -pady -3 -padx -7 -borderwidth 1 -font "$BOLDFONT" -text "check" -command "component_cmd $c check"
	checkbutton $COMPWIDGET.$c.noauto -font "$BOLDFONT" -borderwidth 1 -text "no auto" -variable NOAUTO($c) -foreground blue
	checkbutton $COMPWIDGET.$c.ownx -font "$BOLDFONT" -borderwidth 1 -text "own X" -variable USEX($c)
	checkbutton $COMPWIDGET.$c.logging -font "$BOLDFONT" -borderwidth 1 -text "logging" -variable LOGGING($c)
	button $COMPWIDGET.$c.logoutput -font "$BOLDFONT" -pady -3 -padx -7 -borderwidth 1 -text "view log" -command "component_cmd $c showlog"
	frame $COMPWIDGET.$c.terminal
	set SCREENED($c) 0
	checkbutton $COMPWIDGET.$c.terminal.screen -pady -3 -padx -7 -font "$BOLDFONT" -borderwidth 1 -text "show term" -command "component_cmd $c screen" -variable SCREENED($c) -onvalue 1 -offvalue 0
	if {[isXCFComp $c]} {
	    if {[string length $WAIT_SERVER($c)] > 0} {
		set button_text "SERV. $WAIT_SERVER($c)"
	    }
	    if {[string length $WAIT_PUBLISHER($c)] > 0} {
		set button_text "PUBL. $WAIT_PUBLISHER($c)"
	    }
	    set intercept_disabled "normal"
	} else {
	    set intercept_disabled "disabled"
	    set button_text "not interceptable"
	}	
	button $COMPWIDGET.$c.intercept -pady -3 -padx -7 -font "$BOLDFONT" -activebackground white -borderwidth 1 -state $intercept_disabled -text "$button_text" -width 20 -command "intercept_component $c"
	
	pack $COMPWIDGET.$c.ownx -side right 
	pack $COMPWIDGET.$c.logoutput -side right 
	pack $COMPWIDGET.$c.logging -side right 
	pack $COMPWIDGET.$c.intercept -side right
	pack $COMPWIDGET.$c.terminal -side right 
	pack $COMPWIDGET.$c.terminal.screen -side right

	pack $COMPWIDGET.$c.start -side left
	pack $COMPWIDGET.$c.stop -side left 
	pack $COMPWIDGET.$c.check -side left 
	pack $COMPWIDGET.$c.noauto -side left
	if {[string length "$XC_COMPNAME($c)"] > 0} {
	    button $COMPWIDGET.$c.xcf_start -activebackground white -pady -3 -padx -5 -borderwidth 1 -font "$BOLDFONT" -foreground darkgreen -text ">" -command "xcfctrl_cmd $XC_COMPNAME($c) start"
	    button $COMPWIDGET.$c.xcf_pause -activebackground white -pady -3 -padx -5 -borderwidth 1 -font "$BOLDFONT" -foreground darkred -text "=" -command "xcfctrl_cmd $XC_COMPNAME($c) pause"
	    button $COMPWIDGET.$c.xcf_info -activebackground white -pady -3 -padx -5 -borderwidth 1 -font "$BOLDFONT" -foreground darkblue -text "?" -command "xcfctrl_cmd $XC_COMPNAME($c) info"
	    pack $COMPWIDGET.$c.xcf_start -side left
	    pack $COMPWIDGET.$c.xcf_pause -side left
	    pack $COMPWIDGET.$c.xcf_info -side left
	}
	set_status $c unknown
	
    }

    # button to control ALL components
    frame $base.components.all -relief groove -borderwidth 1
    pack $base.components.all -side top -fill both
    label $base.components.all.label -anchor e -font "$BOLDFONT" -text "ALL COMPONENTS" -foreground blue
    pack $base.components.all.label -side left -fill x
    button $base.components.all.start -font "$BOLDFONT" -pady -3 -padx -7 -borderwidth 1 -text "start" -foreground blue -command "allcomponents_cmd start"
    button $base.components.all.stop -font "$BOLDFONT" -pady -3 -padx -7 -borderwidth 1 -text "stop" -foreground blue -command "allcomponents_cmd stop"
    button $base.components.all.check -font "$BOLDFONT" -pady -3 -padx -7 -borderwidth 1 -text "check" -foreground blue -command "allcomponents_cmd check"
    pack $base.components.all.start -side left
    pack $base.components.all.stop -side left 
    pack $base.components.all.check -side left 

    # clear logger button
    button $base.components.all.clearLogger -font "$BOLDFONT" -pady -3 -padx -7 -borderwidth 1 -text "clear logger" \
	-command "clearLogger"
    pack $base.components.all.clearLogger -side right

    frame $base.components.group 
    pack $base.components.group -side top -fill x
    # button for level control:
    set LEVELS [lsort -unique "$LEVELS"]
    frame $base.components.group.level -borderwidth 0
    pack $base.components.group.level -side left -fill both
    foreach {g} "$LEVELS" {
	frame $base.components.group.level.$g -relief groove -borderwidth 1
	pack $base.components.group.level.$g -side top -fill x
	label $base.components.group.level.$g.label -anchor w -font "$BOLDFONT" -text "$g" -foreground blue
	button $base.components.group.level.$g.start -font "$BOLDFONT" -pady -3 -padx -3 -borderwidth 1 -text "start" -foreground blue -command "level_cmd start $g"
	button $base.components.group.level.$g.stop -font "$BOLDFONT" -pady -3 -padx -3 -borderwidth 1 -text "stop" -foreground blue -command "level_cmd stop $g"
	button $base.components.group.level.$g.check -font "$BOLDFONT" -pady -3 -padx -3 -borderwidth 1 -text "check" -foreground blue -command "level_cmd check $g"
	pack $base.components.group.level.$g.check -side right 
	pack $base.components.group.level.$g.stop -side right
	pack $base.components.group.level.$g.start -side right
	pack $base.components.group.level.$g.label -side right -fill x
    }
    # button for group control:
    set groups [lsort -unique "$groups"]
    frame $base.components.group.named -borderwidth 0
    pack $base.components.group.named -side left -fill both
    foreach {g} "$groups" {
	frame $base.components.group.named.$g -relief groove -borderwidth 1
	pack $base.components.group.named.$g -side top -fill x
	label $base.components.group.named.$g.label -width 10 -anchor e -font "$BOLDFONT" -text "$g" -foreground blue
	pack $base.components.group.named.$g.label -side left -fill x
	button $base.components.group.named.$g.start -font "$BOLDFONT" -pady -3 -padx -3 -borderwidth 1 -text "start" -foreground blue -command "group_cmd start $g"
	button $base.components.group.named.$g.stop -font "$BOLDFONT" -pady -3 -padx -3 -borderwidth 1 -text "stop" -foreground blue -command "group_cmd stop $g"
	button $base.components.group.named.$g.check -font "$BOLDFONT" -pady -3 -padx -3 -borderwidth 1 -text "check" -foreground blue -command "group_cmd check $g"
	pack $base.components.group.named.$g.start -side left
	pack $base.components.group.named.$g.stop -side left 
	pack $base.components.group.named.$g.check -side left 
    }
    
    # LOGGER area (WATCHFILE)


    frame $base.components.group.log -borderwidth 0
    text $base.components.group.log.text -yscrollcommand "$base.components.group.log.sb set" \
	-height 12 -font "$FONT" -background white 

    scrollbar $base.components.group.log.sb -command "$base.components.group.log.text yview" 
    pack $base.components.group.log -side left -fill both -expand 1
    pack $base.components.group.log.text -side left -fill both -expand 1
    pack $base.components.group.log.sb -side right -fill y
    if {"$WATCHFILE" != ""} {
	init_logger "$WATCHFILE"
    }

    pack $base.components -side top -fill both -expand yes 

    # logarea
    label $base.logarea -font "$FONT" -textvariable LOGTEXT -width 50 -anchor nw -height 4 -justify left -relief sunken -background white -foreground darkgreen
    pack $base.logarea -side top -fill both

    set hosts [lsort -unique [string tolower "$hosts"]]
    frame $base.ssh 
    frame $base.clocks
    pack $base.ssh -side top -fill x
    label $base.ssh.label -font "$BOLDFONT"    -text "ssh to"
    pack $base.ssh.label -side left
    foreach {h} "$hosts" {
	button $base.ssh.$h -pady -3 -padx -7 -borderwidth 1 -text "$h" -font "$BOLDFONT" -command "remote_xterm $h"
	button $base.ssh.clocks_$h -pady -3 -padx -7 -borderwidth 1 -text "C" -font "$FONT" -command "remote_clock $h"
	set SCREENED_SSH($h) 0
	checkbutton  $base.ssh.screen_$h -pady -3 -padx -7 -borderwidth 1 -text "" -font "$FONT" -command "screen_ssh_master $h" -variable SCREENED_SSH($h) -onvalue 1 -offvalue 0
	#	button $base.ssh.$h -text "$h" -command "$h" -command "exec ssh -X $h xterm &"
	pack $base.ssh.$h -side left -fill x
	pack $base.ssh.clocks_$h -side left -fill x
	pack $base.ssh.screen_$h -side left -fill x
    }




    button $base.exit -pady -3 -padx -7 -borderwidth 1 -text "exit" -font "$BOLDFONT" -command {finish}
    pack $base.exit -side bottom -fill x

}

proc clearLogger {} {
    global WATCHFILE
    .components.group.log.text delete 1.0 end
    exec echo -n "" > "$WATCHFILE"
}

proc init_logger {filename} {
    global mypid
    if { [catch {open "|tail -n 5 --pid=$mypid -F $filename"} infile] } {
	puts  "Could not open $filename for reading, quit."
	exit 1
    }
    
    fconfigure $infile -blocking no -buffering line 
    fileevent $infile readable [list insertLog $infile]
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

proc xcfctrl_cmd {component cmd} {
    global LOGTEXT
    set LOGTEXT [exec bash -c "echo 'xcfctrl: '; xcfcctrl -c $component -m $cmd 2>&1 || echo failed"]
}

proc intercept_component {comp} {
    global WAIT_PUBLISHER WAIT_SERVER
    if {[string length $WAIT_SERVER($comp)] > 0} {
    	exec xterm -title "XCF intercepts for $comp (Server: $WAIT_SERVER($comp))" -e bash -c "xcflogger -i -s $WAIT_SERVER($comp)" &
	}
    if {[string length $WAIT_PUBLISHER($comp)] > 0} {
    	exec xterm -title "XCF intercepts for $comp (Publisher: $WAIT_PUBLISHER($comp))" -e bash -c "xcflogger -i -p $WAIT_PUBLISHER($comp)" &
	}
}

proc allcomponents_cmd {cmd} {
    global HOST COMPONENTS ARGS TERMINAL USEX LOGTEXT  WAIT_READY WAIT_BREAK NOAUTO LEVELS
    if {"$cmd" == "stop"} {
	set WAIT_BREAK 1
	foreach {level} "[lsort $LEVELS]" {
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
    global HOST COMPONENTS ARGS GROUP TERMINAL USEX LOGTEXT  WAIT_READY NOAUTO WAIT_BREAK
    if {"$cmd" == "stop"} {
	set WAIT_BREAK 1
	foreach {comp} "$COMPONENTS" {
	    if {$GROUP($comp) == $grp} {
		if {! $NOAUTO($comp)} {
		    after idle "component_cmd $comp $cmd"
		}
	    }
	}
    } elseif {"$cmd" == "check"} {
	foreach {comp} "$COMPONENTS" {
	    if {$GROUP($comp) == $grp} {
		if {! $NOAUTO($comp)} {
		    after idle "component_cmd $comp check"
		}
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
    global HOST COMPONENTS ARGS GROUP TERMINAL USEX LOGTEXT  WAIT_READY NOAUTO WAIT_BREAK COMP_LEVEL
    if {"$cmd" == "stop"} {
	set WAIT_BREAK 1
	foreach {comp} "$COMPONENTS" {
	    if {$COMP_LEVEL($comp) == $level} {
		if {! $NOAUTO($comp)} {
		    after idle "component_cmd $comp $cmd"
		}
	    }
	}
    } elseif {"$cmd" == "check"} {
	foreach {comp} "$COMPONENTS" {
	    if {$COMP_LEVEL($comp) == $level} {
		if {! $NOAUTO($comp)} {
		    after idle "component_cmd $comp check"
		}
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

proc checkXCFcomp {comp} {
    global WAIT_PUBLISHER WAIT_SERVER XC_COMPNAME
    if {[string length $WAIT_SERVER($comp)] > 0} {
	puts "check XCF server $WAIT_SERVER($comp)"
	if {[catch {exec bash -c "/vol/xcf/bin/xcfinfo -c -s $WAIT_SERVER($comp) | grep -q Running 2>&1" } {XCFOUTPUT}]} {
	    return 0
	} else {
	    return 1
	}
    }
    if {[string length $XC_COMPNAME($comp)] > 0} {
	puts "check XCF server $XC_COMPNAME($comp)"
	if {[catch {exec bash -c "/vol/xcf/bin/xcfinfo -c -s $XC_COMPNAME($comp) | grep -q Running 2>&1" } {XCFOUTPUT}]} {
	    puts $XCFOUTPUT
	    return 0
	} else {
	    return 1
	}
    }
    if {[string length $WAIT_PUBLISHER($comp)] > 0} {
	puts "check XCF publisher $WAIT_PUBLISHER($comp)"
	if {[catch {exec bash -c "/vol/xcf/bin/xcfinfo -c -p $WAIT_PUBLISHER($comp) | grep -q Running 2>&1" } {XCFOUTPUT}]} {
	    return 0
	} else {
	    return 1
	}
    }
    return 1
}

proc wait_ready {comp} {
    global WAIT_READY WAIT_PUBLISHER WAIT_SERVER WAIT_BREAK XC_COMPNAME COMPWIDGET
    puts "waiting for process to be ready"
    update
    # wait a minimum of 4 seconds to check for the process ID
    #exec sleep 4
    set WAIT_BREAK 0
    if {([string length $WAIT_SERVER($comp)] > 0) || ([string length $WAIT_PUBLISHER($comp)] > 0)|| ([string length $XC_COMPNAME($comp)] > 0)} {
	puts "WAIT FOR XCF COMPONENT"
	while {![checkXCFcomp $comp]} {
	    set LOGTEXT "still waiting for the component to register"
	    update
	    $COMPWIDGET.$comp.intercept flash
	    after 1000
	    puts -nonewline "."
	    flush stdout
	    if {$WAIT_BREAK} {
		break
	    }
	}
    }
    
    if {[string is digit $WAIT_READY($comp)]} {
	for {set x 0} {$x<$WAIT_READY($comp)} {incr x} {
	    update
	    exec sleep 1
	}
    } 
}
   
proc remote_xterm {host} {
    global LOGTEXT env
    set cmd_line "xterm -fg white -bg black -title $host &"
    ssh_command "$cmd_line" $host
}

proc remote_clock {host} {
    global LOGTEXT env
    set cmd_line "xclock -fg white -bg black -geometry 250x30 -title $host -digital -update 1 &"
    ssh_command "$cmd_line" "$host"
}

proc component_cmd {comp cmd} {
    global env HOST COMPONENTS ARGS TERMINAL USEX LOGTEXT WAIT_READY LOGGING WAIT_BREAK SCREENED DETACHTIME COMPWIDGET COMMAND EXPORTS
    set cpath "$env(VDEMO_componentPath)"
    set component_script "$cpath/component_$COMMAND($comp)"
    set component_options ""
    if {$USEX($comp)} {
				set component_options "$component_options -x"
    }
    if {$LOGGING($comp)} {
				set component_options "$component_options -l"
    }
	 set VARS "$EXPORTS($comp) "

    set success 1
    switch $cmd {
	start {
       if {$DETACHTIME($comp) < 0} {
           set component_options "$component_options --noiconic"
       }
	    set cmd_line "$VARS $component_script $component_options start"
	    $COMPWIDGET.$comp.start flash
	    set WAIT_BREAK 0
	    set_status $comp unknown

	    ssh_command "$cmd_line" "$HOST($comp)"

# 	    if [catch {exec bash -c "$cmd_line 2>&1" &} LOGTEXT ] {
# 		puts $LOGTEXT
# 		set success 0
# 	    } else {}
	    set SCREENED($comp) 1
	    wait_ready $comp
	    # wait longer period of time when using X
	    if {$USEX($comp)} {
		after 20000 "component_cmd $comp check"
	    } else {
		after 7000 "component_cmd $comp check"
	    }
	    if {$DETACHTIME($comp) >= 0} {
		set detach_after [expr $DETACHTIME($comp) * 1000]
		after $detach_after "component_cmd $comp detach"
	    }
	}
	stop {
	    set cmd_line "$VARS $component_script $component_options stop"
	    $COMPWIDGET.$comp.stop flash
	    set WAIT_BREAK 1
	    set_status $comp unknown

	    ssh_command "$cmd_line" "$HOST($comp)"

	    set_status $comp 0
	    set SCREENED($comp) 0
	    after idle "component_cmd $comp check"
	}
	screen {
	    if {$SCREENED($comp)} {
		set cmd_line "$VARS xterm -fg white -bg black -title \"$comp - detach by \[C-a d\], DO NOT HIT CLOSE BUTTON!\" -e $component_script $component_options screen &"
		ssh_command "$cmd_line" "$HOST($comp)"
	    } else {
		set cmd_line "$VARS $component_script $component_options detach"
		ssh_command "$cmd_line" "$HOST($comp)"
	    }
	}
	detach {
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

	    set success 1
	    if {$res == 1} {
		set SCREENED($comp) 0
		set_status $comp 0
	    } else {
		if {[isXCFComp $comp]} {
		    set_status $comp [checkXCFcomp $comp]
		} else {
		    set_status $comp 1
		}
	    }
	}
    }
    if $success {
	.logarea configure -background white
    } else {
	.logarea configure -background red
    }
    update
} 

proc set_status {comp status} {
    global COMPWIDGET
    if {$status == 1} {
	$COMPWIDGET.$comp.check configure -background darkgreen -activebackground green
    } elseif {$status == 0} {
	$COMPWIDGET.$comp.check configure -background darkred -activebackground red
    } else {
	$COMPWIDGET.$comp.check configure -background grey -activebackground grey
    }    
    update
}


# proc start_component {comp} {
#     puts "start $comp"
# }

# proc stop_component {comp} {
#     puts "stop $comp"
# }

# proc screen_component {comp} {
#     puts "screen $comp"
# }

# proc check_component {comp} {
#     global COMPWIDGET
#     puts "check $comp"
    
#     $COMPWIDGET.$comp.check configure -background red
# }



# {{{ ssh and command procs

proc screen_ssh_master {h} {
    global SCREENED_SSH
    if {$SCREENED_SSH($h) == 1} {
	exec  xterm -title "MASTER SSH CONNECTION TO $h. Do not close this window!" -e screen -d -r -S "vdemo-$h" &
    } else {
	exec  screen -d -S "vdemo-$h" 
    }
}

proc ssh_command {cmd hostname} {
    set f [get_fifo_name $hostname]
    puts "run '$cmd' on host '$hostname'"

    set res [exec bash -c "echo 'echo \"****************************************\" 1>&2; date 1>&2; echo \"*** RUN $cmd\" 1>&2; $cmd 1>&2; echo \$?' > $f.in; cat $f.out"]
    return $res
}

proc get_fifo_name {hostname} {
    global COMPONENTS HOST env
    return "/tmp/vdemo-ssh-$env(USER)-$hostname"
}

proc connect_hosts {} {
    global COMPONENTS env HOST
    set fifos ""

    label .vdemoinit -text "init VDemo - be patient..." -foreground darkgreen -font "-*-helvetica-bold-r-*-*-30-*-*-*-*-*-*-*"
    label .vdemoinit2 -text "" -foreground darkred -font "-*-helvetica-bold-r-*-*-20-*-*-*-*-*-*-*"
    pack .vdemoinit 
    pack .vdemoinit2 
    update

    foreach {c} "$COMPONENTS" {
	set fifo "[get_fifo_name $HOST($c)]"
	set fifos "$fifos $fifo"
	set fifo_host($fifo) "$HOST($c)"
    }
    set fifos [lsort -unique "$fifos"]

    foreach {f} "$fifos" {
	.vdemoinit2 configure -text "connect to $fifo_host($f)"
	update
	exec rm -f "$f.in"
	exec rm -f "$f.out"
	exec mkfifo "$f.in"
	exec mkfifo "$f.out"

	exec xterm -title "establish ssh connection to $f" -n "$f" -e screen -mS "vdemo-$fifo_host($f)" bash -c "tail -s 0.1 -n 10000 -f $f.in | ssh -X  $fifo_host($f) bash --login --rcfile /etc/profile | while read s; do echo \$s > $f.out; done" &

	ssh_command "source $env(VDEMO_demoConfig)" $fifo_host($f)
	if {[info exists env(SPREAD_CONFIG)]} {
		ssh_command "export SPREAD_CONFIG=$env(SPREAD_CONFIG)" $fifo_host($f)
	}
	# transmit current LD_LIBRARY_PATH to remote session
#	if {[info exists env(LD_LIBRARY_PATH)]} {	
#		ssh_command "export LD_LIBRARY_PATH=$env(LD_LIBRARY_PATH)" $fifo_host($f)
#	}
	exec screen -dS "vdemo-$fifo_host($f)"
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
	puts "exit $fifo_host($f)"
	catch {exec bash -c "screen -list vdemo-$fifo_host($f) | grep vdemo | cut -d. -f1 | xargs kill 2>&1"}
	exec rm -f "$f.in"
	exec rm -f "$f.out"
    }
}

proc finish {} {
	 disconnect_hosts
	 if {$::AUTO_SPREAD_CONF == 1} {
		  puts "delete generated spread config"
		  file delete $::env(SPREAD_CONFIG)
	 }
    exit	 
}

proc create_spread_conf {} {
    global COMPONENTS COMMAND HOST env
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

	 set segments ""
	 foreach {h} "$spread_hosts" {
		  set ip [exec dig +search +short $h]
		  if {"$ip" == ""} {
			  set ip [exec ping -c1 $h | grep "bytes from" | cut -f2 -d "("  | cut -f1 -d ")"]
		  }
		  if {"$ip" == ""} {continue}

		  set seg [exec echo $ip | cut -f 1,2,3 -d "."]
		  set segments "$segments $seg"
		  set IP($h) $ip
		  if {![info exists hosts($seg)]} {
					 set hosts($seg) "$h"
		  } else {
					 set hosts($seg) "$hosts($seg) $h"
		  }
	 }
	 set segments [lsort -unique "$segments"]

	 set filename "$env(VDEMO_demoRoot)/spread-$env(USER)-$env(XCF_Initial_Host).conf"
	 set ::env(SPREAD_CONFIG) $filename
	 if {[catch {open $filename w 0664} fd]} {
      # something went wrong 
		error "Could not open $filename."
	 } 
    if {![info exists hosts($seg)]} {set ::env(SPREAD_PORT) 4803}

	 set num 1
	 foreach {seg} "$segments" {
		  if {$seg == "127.0.0"} {
					 set sp_seg "127.0.0.255:$env(SPREAD_PORT)"
		  } else {
					 set sp_seg "225.0.0.$num:$env(SPREAD_PORT)"
					 set num [expr $num + 1]
		  }
		  puts $fd "Spread_Segment $sp_seg {"
		  foreach {h} $hosts($seg) {
				puts $fd "\t $h \t $IP($h)"
		  }
		  puts $fd "}"
		  puts $fd ""
	 }

	 close $fd
}

# }}}


set mypid [pid]
puts "My process id is $mypid" 

parse_env_var
# auto-create spread config
set ::AUTO_SPREAD_CONF 0
if {![info exists ::env(SPREAD_CONFIG)]} {
		  create_spread_conf
}

# cleanup dangling connections first
disconnect_hosts
connect_hosts

update
gui_tcl
update
