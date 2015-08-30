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
proc define_theme_color {stylePrefix defaultBgnd mapping} {
    ttk::style configure $stylePrefix.cmd.TButton -background $defaultBgnd
    ttk::style map $stylePrefix.cmd.TButton -background $mapping
}

set FONT "helvetica 9"
ttk::style configure "." -font $FONT
ttk::style configure sunken.TFrame -relief sunken
ttk::style configure groove.TFrame -relief groove

ttk::style configure TButton -font "$FONT bold" -padding "2 -1"
ttk::style configure TCheckbutton -padding "2 -1"
ttk::style configure cmd.TButton -padding "2 -1" -width -5

define_theme_color ok green3 [list active green2]
define_theme_color noscreen.ok orange2 [list active orange]
define_theme_color failed red2 [list active red]
define_theme_color check.failed pink [list active pink2]
define_theme_color starting yellow2 [list active yellow]

ttk::style configure clock.TButton -font "$FONT"
ttk::style configure exit.TButton

ttk::style configure TLabel -padding "2 -1"
ttk::style configure level.TLabel -foreground darkblue -width 5
ttk::style configure label.TLabel -width 15 -anchor e
ttk::style configure group.TLabel -foreground darkblue -width 10 -anchor e

# for search
ttk::style configure hilite.label.TLabel -background yellow
ttk::style configure failed.TEntry -fieldbackground pink

ttk::style configure alert.TLabel -foreground blue -background yellow
ttk::style configure info.TLabel -foreground blue -background yellow
ttk::style configure log.TLabel -justify left -anchor e -relief sunken -foreground gray30

# debugging puts()
set DEBUG_LEVEL 0
catch {set DEBUG_LEVEL $::env(VDEMO_DEBUG_LEVEL)}
proc dputs {args {level 1}} {
    if [expr $level <= $::DEBUG_LEVEL] {
        puts stderr "-- $args"
    }
}
proc assert condition {
    if {![uplevel 1 expr $condition]} {
        return -code error "assertion failed: $condition"
    }
}
proc printBackTrace {} {
    set backTrace {}
    set startLevel [expr {[info level] - 2}]
    for {set level 1} {$level <= $startLevel} {incr level} {
        lappend backTrace [lindex [info level $level] 0]
    }
    puts stderr "   backtrace: [join $backTrace { => }]"
}

# set some default values from environment variables
if { ! [info exists ::env(VDEMO_LOGGING)] || \
     ! [string is integer -strict $::env(VDEMO_LOGGING)] } \
    {set ::env(VDEMO_LOGGING) 0}
dputs "default logging: $::env(VDEMO_LOGGING)" 3

if { ! [info exists ::env(VDEMO_DETACH_TIME)] || \
     ! [string is double -strict $::env(VDEMO_DETACH_TIME)] } \
    {set ::env(VDEMO_DETACH_TIME) 0}
dputs "default detach time: $::env(VDEMO_DETACH_TIME)" 3

set VDEMO_QUIT_COMPONENTS [list]
catch {set VDEMO_QUIT_COMPONENTS [split $::env(VDEMO_QUIT_COMPONENTS)]}

proc number {val type} {
    if {[string is $type -strict $val]} {
        return $val
    } else {
        throw {ARITH DOMAIN {no number}} "$val is not $type"
    }
}

proc parse_options {comp} {
    global COMPONENTS ARGS USEX TERMINAL WAIT_READY NOAUTO LOGGING GROUP DETACHTIME COMP_LEVEL EXPORTS TITLE CHECKNOWAIT_TIME RESTART

    set NEWARGS [list]
    set USEX($comp) 0
    # time to wait for a process to startup
    set WAIT_READY($comp) 0
    # time until process is checked after start (when not waiting)
    set CHECKNOWAIT_TIME($comp) 1000
    set GROUP($comp) ""
    # detach a component after this time
    set DETACHTIME($comp) [expr 1000 * $::env(VDEMO_DETACH_TIME)]
    set NOAUTO($comp) 0
    set TERMINAL($comp) "screen"
    set LOGGING($comp) $::env(VDEMO_LOGGING)
    set COMP_LEVEL($comp) ""
    set EXPORTS($comp) ""
    set RESTART($comp) 0

    for {set i 0} \$i<[llength $ARGS($comp)] {incr i} {
        set arg [lindex $ARGS($comp) $i]; set val [lindex $ARGS($comp) [expr $i+1]]
        if { [catch {switch -glob -- $arg {
            -w {
                set WAIT_READY($comp) [expr 1000 * [number $val double]]
                incr i
            }
            -W {
                set CHECKNOWAIT_TIME($comp) [expr 1000 * [number $val double]]
                incr i
            }
            -c {
                puts "$comp: arg '-c' is obsolete"
                if [string is double -strict $val] {incr i}
            }
            -r {
                set RESTART($comp) 1
            }
            -R {
                set RESTART($comp) 2
            }
            -d {
                set DETACHTIME($comp) [expr 1000 * [number $val double]]
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
                set COMP_LEVEL($comp) [number $val integer]
                incr i
            }
            -Q {
                lappend ::VDEMO_QUIT_COMPONENTS $comp
            }
            default {
                set NEWARGS [lappend NEWARGS $arg]
            }
        } } err ] } {
            puts "$comp: error processing '$arg $val': $err"
            exit
        }
    }
    set ARGS($comp) $NEWARGS
}

# split $str on $sep, but don't split when $sep is preceeded by $protector
proc psplit { str sep {protector "\\"}} {
    set result [list]
    # accumulate next item (from oversegmented substrings)
    foreach s [split $str $sep] {
        append cur $s
        if { [string range $s end end] == $protector } {
            set cur [string range $cur 0 end-1]
            append cur $sep
        } else {
            lappend result $cur
            set cur ""
        }
    }
    return $result
}

proc parse_env_var {} {
    global HOST COMPONENTS ARGS USEX WATCHFILE COMMAND TITLE VDEMOID TABS TAB COMPONENTS_ON_TAB
    set VDEMOID [file tail [file rootname $::env(VDEMO_demoConfig)]]
    set components_list "$::env(VDEMO_components)"
    set comp [psplit "$components_list" ":"]
    set nCompos [llength "$comp"]
    set COMPONENTS {}
    set WATCHFILE ""
    set ::HOSTS ""
    set tab "default"
    set TABS [list $tab]
    set COMPONENTS_ON_TAB($tab) [list]
    set components_on_tab_list COMPONENTS_ON_TAB($tab)

    catch {set ::WATCHFILE $::env(VDEMO_watchfile)}
    dputs "VDEMO_watchfile = $WATCHFILE"
    dputs "COMPONENTS: "
    for {set i 0} { $i < $nCompos } {incr i} {
        set component_def [string trim [lindex "$comp" $i]]
        set thisComp [split $component_def ","]
        if {[llength "$thisComp"] == 3} {
            set component_name [lindex "$thisComp" 0]
            set component_name [string map "{ } {}" $component_name]
            set thisCommand "$component_name"
            set host [string trim [lindex "$thisComp" 1]]
            set component_name "${i}_${component_name}"
            set COMMAND($component_name) "$thisCommand"
            set TITLE($component_name) "$thisCommand"
            set COMPONENTS "$COMPONENTS $component_name"
            set TAB($component_name) "$tab"
            lappend $components_on_tab_list $component_name
            if {"$host" != ""} {lappend ::HOSTS $host}
            set HOST($component_name) $host
            set ARGS($component_name) [lindex $thisComp 2]
            # do not simply tokenize at spaces, but allow quoted strings ("" or '')
            set ARGS($component_name) [regexp -all -inline -- "\\S+|\[^ =\]+=(?:\\S+|\"\[^\"]+\"|'\[^'\]+')" $ARGS($component_name)]
            dputs [format "%-20s HOST: %-13s ARGS: %s" $component_name $HOST($component_name) $ARGS($component_name)]
            # parse options known by the script and remove them from them the list
            parse_options "$component_name"
        } elseif {[llength "$thisComp"] == 1} { # this is a new tab definition
            set tab [lindex "$thisComp" 0]
            if {[lsearch -exact $TABS $tab] == -1} { # new tab
                lappend TABS $tab
                set COMPONENTS_ON_TAB($tab) [list]
            }
            set components_on_tab_list COMPONENTS_ON_TAB($tab)
        } elseif {[string length $component_def] != 0} {
            error "component $i: expected three comma separated groups in '$component_def'"
        }
    }
    set ::HOSTS [lsort -unique $::HOSTS]
}

proc bind_wheel_sf {widget} {
    bind all <4> [list $widget yview scroll -5 units]
    bind all <5> [list $widget yview scroll  5 units]
}

proc find_component {what} {
    global _SEARCH COMPONENTS_ON_TAB
    set what "*[string trim $what]*"
    if {$what == "**"} {return}

    if {![info exists _SEARCH(string)] || $_SEARCH(string) != $what} {
        set _SEARCH(string) "$what"
        # get name of currently selected tab: will fail if simple frame is used
        if { ! [ catch {set curTab [$::COMPONENTS_WIDGET select]} ] } {
            set _SEARCH(start_idx) [$::COMPONENTS_WIDGET index $curTab]
            set _SEARCH(end_idx) [$::COMPONENTS_WIDGET index end]
            set _SEARCH(cur_tab) [$::COMPONENTS_WIDGET tab $curTab -text]
        } else {
            set _SEARCH(start_idx) 0
            set _SEARCH(end_idx) 1
            set _SEARCH(cur_tab) "default"
        }
        set _SEARCH(cur_idx) $_SEARCH(start_idx)
        set _SEARCH(index) -1
        set _SEARCH(found) [lsearch -all $COMPONENTS_ON_TAB($_SEARCH(cur_tab)) $_SEARCH(string)]
    }
    while 1 {
        set _SEARCH(index) [expr $_SEARCH(index) + 1]
        if {$_SEARCH(index) < [llength $_SEARCH(found)]} {
            # found on current tab
            set index [lindex $_SEARCH(found) $_SEARCH(index)]
            set comp [lindex $COMPONENTS_ON_TAB($_SEARCH(cur_tab)) $index]
            show_component $comp
            hilite_component $comp
            .main.log.row.searchText configure -style TEntry
            break
        }
        # if not found, try on next tab
        set _SEARCH(cur_idx) [expr ($_SEARCH(cur_idx) + 1) % $_SEARCH(end_idx)]
        catch { set _SEARCH(cur_tab) [$::COMPONENTS_WIDGET tab $_SEARCH(cur_idx) -text] }
        # do the search
        set _SEARCH(index) -1
        set _SEARCH(found) [lsearch -all $COMPONENTS_ON_TAB($_SEARCH(cur_tab)) $_SEARCH(string)]
        # reached initial tab again? -> indicate failure
        if {$_SEARCH(cur_idx) == $_SEARCH(start_idx)} {
            hilite_component ""
            .main.log.row.searchText configure -style failed.TEntry
            break
        }
    }
}

proc show_component {comp} {
    catch {
        # show tab widget containing the component
        $::COMPONENTS_WIDGET select $::COMPONENTS_WIDGET.$::TAB($comp)
    }
    set pos [lsearch -exact $::COMPONENTS_ON_TAB($::TAB($comp)) $comp]
    .main.scrollable yview moveto [expr double($pos)/$::MAX_NUM]
}

set _LAST_HILITED ""
proc hilite_component {comp} {
    if {$::_LAST_HILITED != ""} {
        $::WIDGET($::_LAST_HILITED).label configure -style label.TLabel
    }
    set ::_LAST_HILITED $comp
    if {$::_LAST_HILITED != ""} {
        $::WIDGET($::_LAST_HILITED).label configure -style hilite.label.TLabel
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

proc get_tab {name} {
    if {[winfo exists $name] == 0} {
        ttk::frame $name
        pack $name -side top -fill both -expand yes
    }
    return $name
}

proc gui_tcl {} {
    global HOST COMPONENTS ARGS TERMINAL USEX LOGTEXT NOAUTO LOGGING  GROUP SCREENED  COMP_LEVEL WATCHFILE COMMAND LEVELS TITLE TIMERDETACH TAB WIDGET COMPONENTS_WIDGET
    set LOGTEXT "demo configured from '$::env(VDEMO_demoConfig)'"
    wm title . "vdemo_controller: $::env(VDEMO_demoConfig)"
    wm geometry . "875x600"

    set groups ""
    set LEVELS ""

    # determine max number of components in tabs
    set ::MAX_NUM 1
    foreach tab $::TABS {
        set ::MAX_NUM [ expr max($::MAX_NUM, [llength $::COMPONENTS_ON_TAB($tab)]) ]
    }

    # main gui frame
    ttk::frame .main
    # scrollable frame
    iwidgets::scrolledframe .main.scrollable -vscrollmode dynamic -hscrollmode none
    bind_wheel_sf .main.scrollable
    pack .main.scrollable -side top -fill both -expand yes

    set COMPONENTS_WIDGET [.main.scrollable childsite].components

    if {[llength $::TABS] > 1} {
        ttk::notebook $COMPONENTS_WIDGET
    } else {
        ttk::frame $COMPONENTS_WIDGET
    }
    pack $COMPONENTS_WIDGET -side top -fill both -expand yes

    foreach {c} "$COMPONENTS" {
        set groups "$groups $GROUP($c)"
        set LEVELS "$LEVELS $COMP_LEVEL($c)"
        set TIMERDETACH($c) 0
        set ::LAST_GUI_INTERACTION($c) 0

        # get the frame widget where this component should go to
        set w [get_tab $COMPONENTS_WIDGET.$TAB($c)]

        ttk::frame $w.$c -style groove.TFrame
        pack $w.$c -side top -fill both
        set WIDGET($c) $w.$c

        ttk::label $w.$c.level -style level.TLabel -text "$COMP_LEVEL($c)"
        ttk::label $w.$c.label -width 20 -style label.TLabel -text "$TITLE($c)@"
        ttk::entry $w.$c.host  -width 10 -textvariable HOST($c)
        # disable host field for spreaddaemon: cannot add/change hosts in spread config
        if {"$COMMAND($c)" == "spreaddaemon"} { $w.$c.host state disabled }

        ttk::label $w.$c.group -style group.TLabel -text "$GROUP($c)"

        ttk::button $w.$c.start -style cmd.TButton -text "start" -command "component_cmd $c start"
        ttk::button $w.$c.stop  -style cmd.TButton -text "stop" -command "component_cmd $c stop"
        ttk::button $w.$c.check -style cmd.TButton -text "check" -command "component_cmd $c check"
        ttk::checkbutton $w.$c.noauto -text "no auto" -variable NOAUTO($c)
        ttk::checkbutton $w.$c.ownx   -text "own X" -variable USEX($c)
        ttk::checkbutton $w.$c.logging -text "logging" -variable LOGGING($c)
        ttk::button $w.$c.viewlog -style cmd.TButton -text "view log" -command "component_cmd $c showlog"

        set SCREENED($c) 0
        ttk::checkbutton $w.$c.screen -text "show term" -command "component_cmd $c screen" -variable SCREENED($c) -onvalue 1 -offvalue 0
        ttk::button $w.$c.inspect -style cmd.TButton -text "inspect" -command "component_cmd $c inspect"

        pack $w.$c.level -side left
        pack $w.$c.label -side left -fill x
        pack $w.$c.host -side left
        pack $w.$c.group -side left -fill x

        pack $w.$c.ownx -side right -padx 3
        pack $w.$c.inspect -side right
        pack $w.$c.viewlog -side right
        pack $w.$c.logging -side right
        pack $w.$c.screen -side right
        pack $w.$c.noauto -side right -padx 2
        pack $w.$c.check -side right
        pack $w.$c.stop -side right
        pack $w.$c.start -side right
        set_status $c unknown
    }
    set LEVELS [lsort -unique "$LEVELS"]

    if {[llength $::TABS] > 1} {
        set tabs [list]
        foreach {tab} $::TABS {
            if { [llength $::COMPONENTS_ON_TAB($tab)] > 0 } {
                $COMPONENTS_WIDGET add $COMPONENTS_WIDGET.$tab -text $tab
                lappend tabs $tab
            }
        }
        set ::TABS $tabs
    }

    set allcmd ".main.allcmd"
    ttk::frame $allcmd
    pack $allcmd -side left -fill y
    # buttons to control ALL components
    all_cmd_reset "all"
    ttk::frame $allcmd.all -style groove.TFrame
    pack $allcmd.all -side top -fill x
    ttk::label $allcmd.all.label -style TLabel -text "ALL COMPONENTS"
    ttk::button $allcmd.all.start -style cmd.TButton -text "start" -command "all_cmd start"
    ttk::button $allcmd.all.stop  -style cmd.TButton -text "stop"  -command "all_cmd stop"
    ttk::button $allcmd.all.check -style cmd.TButton -text "check" -command "all_cmd check"
    pack $allcmd.all.label -side left -fill x
    pack $allcmd.all.check $allcmd.all.stop $allcmd.all.start -side right

    # buttons for group control:
    set ::GROUPS [lsort -unique "$groups"]
    foreach {g} "$::GROUPS" {
        all_cmd_reset "$g"
        ttk::frame $allcmd.$g -style groove.TFrame
        pack $allcmd.$g -side top -fill x
        ttk::label $allcmd.$g.label  -style group.TLabel -text "$g" -width 10 -anchor e
        ttk::button $allcmd.$g.start -style cmd.TButton -text "start" -command "all_cmd start $g"
        ttk::button $allcmd.$g.stop  -style cmd.TButton -text "stop"  -command "all_cmd stop  $g"
        ttk::button $allcmd.$g.check -style cmd.TButton -text "check" -command "all_cmd check $g"
        ttk::checkbutton $allcmd.$g.noauto -text "no auto" -command "set_group_noauto $g" -variable GNOAUTO($g) -onvalue 1 -offvalue 0

        pack $allcmd.$g.label -side left -padx 2
        pack $allcmd.$g.start -side left
        pack $allcmd.$g.stop -side left
        pack $allcmd.$g.check -side left
        pack $allcmd.$g.noauto -side left
    }

    ttk::frame .main.log
    pack .main.log -side left
    ttk::frame .main.log.row
    pack .main.log.row -side top -fill x
    # search widgets
    ttk::button .main.log.row.searchBtn -style cmd.TButton -text "search" -command {find_component $SEARCH_STRING}
    ttk::entry  .main.log.row.searchText -textvariable SEARCH_STRING
    bind .main.log.row.searchText <Return> {find_component $SEARCH_STRING}

    # clear logger button
    ttk::button .main.log.row.clearLogger -text "clear logger" -command "clearLogger"
    pack .main.log.row.searchText -side left -fill x -expand 1
    pack .main.log.row.searchBtn -side left -ipadx 15
    pack .main.log.row.clearLogger -side left -ipadx 10

    # LOGGER area (WATCHFILE)
    text .main.log.text -yscrollcommand ".main.log.sb set" -height 8

    ttk::scrollbar .main.log.sb -command ".main.log.text yview"
    pack .main.log -side left -fill both -expand 1
    pack .main.log.text -side left -fill both -expand 1
    pack .main.log.sb -side right -fill y
    if {"$WATCHFILE" != ""} {
        init_logger "$WATCHFILE"
    }

    pack .main -side top -fill both -expand yes

    # logarea
    ttk::label .logarea -textvariable LOGTEXT -style log.TLabel
    pack .logarea -side top -fill both

    ttk::frame .ssh
    pack .ssh -side left -fill x
    ttk::label .ssh.label -text "ssh to"
    pack .ssh.label -side left
    foreach {h} $::HOSTS {
        gui_add_host $h
    }

    ttk::button .exit -style exit.TButton -text "exit" -command {gui_exit}
    pack .exit -side right

    if {[info exists ::env(VDEMO_alert_string)]} {
        ttk::label .orlabel -style alert.TLabel -text $::env(VDEMO_alert_string)
        pack .orlabel -fill x
    } elseif {[info exists ::env(VDEMO_info_string)]} {
        ttk::label .orlabel -style info.TLabel -text $::env(VDEMO_info_string)
        pack .orlabel -fill x
    }
}

proc gui_add_host {host} {
    set lh [string tolower "$host"]

    # check status of screen session, but do not attempt to reconnect (avoiding infinite recursion)
    set connection [ssh_check_connection $host 0]
    if {$connection == 0} {set style "ok.cmd.TButton"} {set style "failed.cmd.TButton"}

    # add $host to list of known $::HOSTS if necessary
    if {[lsearch -exact $::HOSTS $host] == -1} {lappend ::HOSTS $host}

    set ::SCREENED_SSH($host) 0

    if {[catch {.ssh.$lh.xterm configure -style $style}]} {
        # create buttons
        ttk::frame  .ssh.$lh
        ttk::button .ssh.$lh.xterm -style $style -text "$host" -command "remote_xterm $host"
        ttk::button .ssh.$lh.clock -style cmd.TButton -text "⌚" -command "remote_clock $host" -width -2
        ttk::checkbutton .ssh.$lh.screen -text "" -command "screen_ssh_master $host" -variable ::SCREENED_SSH($host) -onvalue 1 -offvalue 0
        pack .ssh.$lh -side left -fill x -padx 3
        pack .ssh.$lh.xterm  -side left -fill x
        pack .ssh.$lh.clock  -side left -fill x
        pack .ssh.$lh.screen -side left -fill x
    }
}

# update button status to reflect state of master ssh connection
proc gui_update_host {host status {forceCreate 0}} {
    set lh [string tolower "$host"]
    dputs "gui_update_host: status:$status  forceCreate:$forceCreate" 3
    if {$status == 0} {set style "ok.cmd.TButton"} {set style "failed.cmd.TButton"}
    catch {.ssh.$lh.xterm configure -style $style}
}

proc clearLogger {} {
    .main.log.text delete 1.0 end
    if {$::WATCHFILE != ""} {exec echo -n "" >> "$::WATCHFILE"}
}

proc init_logger {filename} {
    exec mkdir -p [file dirname $filename]
    exec touch $filename
    if { [catch {open "|tail -n 5 --pid=$::mypid -F $filename"} infile] } {
        puts  "Could not open $filename for reading."
    } else {
        fconfigure $infile -blocking no -buffering line
        fileevent $infile readable [list insertLog $infile]
    }
}

proc insertLog {infile} {
    if { [gets $infile line] >= 0 } {
        .main.log.text insert end "$line\n"  ;# Add a newline too
        .main.log.text yview moveto 1
    } else {
        # Close the pipe - otherwise we will loop endlessly
        close $infile
    }
}

# all_cmd() should start/stop all components in a specific group *level by level*.
# Components at the same level can be started/stopped in parallel.
# start/stop buttons of different groups can be run in parallel too.
# However, within a group (ALL serves as a group as well), either start or stop can run,
# and the components of *different level* should be started / stopped sequentially.
#
# We achieve that behavior, by counting the number of started components
# (in ::ALLCMD_COUNT_$group), and storing the start/stop mode (in ::ALLCMD(mode_$group))
# as well as a list of pending components (in ::ALLCMD(list_$group)).
# If a running command should be canceled, we use ::ALLCMD_INTR_$group:
# -1: process failed -> stop further launching at next level
# -2: manual interrupt request -> immediately stop launching
#  0: all_cmd() finished / nothing pending
#  1: all_cmd() is pending
proc all_cmd_reset {group} {
    set ::ALLCMD(list_$group) [list]
    set ::ALLCMD(mode_$group) ""
    set ::ALLCMD_COUNT_$group 0
    set ::ALLCMD_INTR_$group  0
}
proc all_cmd_interrupt {groups} {
    # interrupt all groups?
    if {$groups == "all"} {set groups "$::GROUPS"}

    set ret 0
    # set manual interrupt flag: -2
    foreach group "all $groups" {
        if {[set ::ALLCMD_INTR_$group] != 0} {
            set ::ALLCMD_INTR_$group -2
            set ret 1
        }
    }
    return $ret
}
proc all_cmd_set_gui {cmd group status} {
    set stylePrefix [expr {$status == "disabled" ? "starting." : ""}]
    .main.allcmd.$group.$cmd state $status
    .main.allcmd.$group.$cmd configure -style "${stylePrefix}cmd.TButton"
    if {$group == "all"} { # also disable group buttons
        foreach g "$::GROUPS" {
            .main.allcmd.$g.$cmd state $status
        }
    }
}

set ::ALLCMD(pending) [list]
proc all_cmd_next_pending {} {
    # is there a pending command?
    if {[llength $::ALLCMD(pending)] == 0} {return ""}
    # peek next command
    set next [lindex $::ALLCMD(pending) 0]
    set group [lindex [split $next] 2]

    # check whether next command will conflict with active ones
    if {[all_cmd_interrupt $group]} {return ""}

    # no active + conflicting all_cmd() call: pop first element and return next
    set ::ALLCMD(pending) [lreplace $::ALLCMD(pending) 0 0]
    return $next
}

proc all_cmd {cmd {group "all"} {lazy 1}} {
    ### preparation
    # disable gui buttons
    all_cmd_set_gui $cmd $group "disabled"
    # ensure that other all_cmds from same $group are interrupted
    set doWait [expr [lsearch -exact [list "start" "stop"] $cmd] >= 0]
    if {$doWait} {
        if {[all_cmd_interrupt $group]} {
            # there is a pending all_cmd() call, postpone this new one
            lappend ::ALLCMD(pending) "all_cmd $cmd $group $lazy"
            return
        }
        # cmd accepted, clean pending var
        set ::ALLCMD(pending) ""
        set ::ALLCMD_INTR_$group  1
        set ::ALLCMD(mode_$group) $cmd
    }

    ### run all components by level
    set levels $::LEVELS
    if {"$cmd" == "stop"} {set levels [lreverse $levels]}
    foreach {level} "$levels" {
        # if ALLCMD_INTR was set negative, we break the loop
        if {$doWait && [set ::ALLCMD_INTR_$group] < 0} {break}
        level_cmd $cmd $level $group $lazy
    }

    ### cleanup
    # enable gui buttons
    all_cmd_set_gui $cmd $group "!disabled"
    if {$doWait} {
        all_cmd_reset $group
        # if there is a pending all_cmd, now we can execute it
        if {[set next [all_cmd_next_pending]] != ""} {after idle $next}
    }
}

proc all_cmd_add_comp {group comp} {
    lappend ::ALLCMD(list_$group) $comp
    incr ::ALLCMD_COUNT_$group 1
}
# called when component's status changed
proc all_cmd_comp_status {group comp status} {
    if {$group == ""} return

    switch -glob -- $status {
        # this is accepted for stop:
        *_noscreen {set cmd "stop"}
        # this is accept for start:
        ok_* {set cmd "start"}
        default {set cmd "-"}
    }
    if {$cmd == $::ALLCMD(mode_$group)} {
        set ::ALLCMD(list_$group) [lsearch -inline -all -not -exact $::ALLCMD(list_$group) $comp]
        incr ::ALLCMD_COUNT_$group -1
    }
}
proc all_cmd_wait {group} {
    # TODO: only wait as long as INTR was not set?
    while {[set ::ALLCMD_COUNT_$group] > 0} {
        vwait ::ALLCMD_COUNT_$group
    }
}
# set ALLCMD_INTR to -1 to indicate cancelling
proc all_cmd_cancel {group} {
    if {$group == "" || $::ALLCMD(mode_$group) == ""} return
    set ::ALLCMD_INTR_$group -1
}
proc level_cmd { cmd level group {lazy 0} } {
    # a start / stop command should stop a currently running process
    set doWait [expr [lsearch -exact [list "start" "stop"] $cmd] >= 0]

    set components $::COMPONENTS
    if {"$cmd" == "stop"} {set components [lreverse $::COMPONENTS]}
    foreach {comp} "$components" {
        if {$::COMP_LEVEL($comp) == $level && \
                ($group == "all" || $::GROUP($comp) == $group)} {
            switch -exact -- $cmd {
                check {set doIt 1}
                stop  {set doIt [expr !$lazy || [running $comp]]}
                start {set doIt [expr !$::NOAUTO($comp) && (!$lazy || ![running $comp])]}
            }
            if {$doIt} {
                if {$doWait} {all_cmd_add_comp $group $comp}
                component_cmd $comp $cmd $group
            }
            # break from loop, when manually requested (ALLCMD_INTR <= -2)
            if {$doWait && [set ::ALLCMD_INTR_$group] < -1} {break}
        }
    }

    if {$doWait} {all_cmd_wait $group}
}

proc remote_xterm {host} {
    # source both, .bashrc and $VDEMO_demoConfig file
    # However, --rcfile loads a single file only, hence we open a temporary pipe
    # sourcing both files:
    set bash_init "test -r ~/.bashrc && . ~/.bashrc; . $::env(VDEMO_demoConfig)"
    set cmd_line "xterm -fg white -bg black -title $host -e \"bash --rcfile <(echo \\\"$bash_init\\\")\" &"
    ssh_command "$cmd_line" $host
}

proc remote_clock {host} {
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

proc component_cmd {comp cmd {allcmd_group ""}} {
    global HOST COMPONENTS ARGS TERMINAL USEX WAIT_READY LOGGING SCREENED DETACHTIME WIDGET COMMAND EXPORTS TITLE COMPSTATUS TIMERDETACH
    set cpath "$::env(VDEMO_componentPath)"
    set component_script "$cpath/component_$COMMAND($comp)"
    set component_options "-t $TITLE($comp)"
    if {$USEX($comp)} {
        set component_options "$component_options -x"
    }
    if {$LOGGING($comp)} {
        set component_options "$component_options -l"
    }
    set VARS "$EXPORTS($comp) "

    switch -exact -- $cmd {
        start {
            if { [$WIDGET($comp).start instate disabled] } {
                puts "$TITLE($comp): not ready, still waiting for the process"
                return
            }
            $WIDGET($comp).start state disabled

            set res [ssh_command "screen -wipe | fgrep -q .$COMMAND($comp).$TITLE($comp)_" "$HOST($comp)"]
            if {$res == -1} {
                puts "no master connection to $HOST($comp)"
                $WIDGET($comp).start state !disabled
                return
            } elseif {$res == 0} {
                dputs "$TITLE($comp): already running, stopping first..."
                component_cmd $comp stopwait
                $WIDGET($comp).start state disabled
            }

            set_status $comp starting
            cancel_detach_timer $comp

            # don't detach when detach time == 0
            if {$DETACHTIME($comp) == 0} { set component_options "$component_options -D" }
            set cmd_line "$VARS $component_script $component_options start"
            set res [ssh_command "$cmd_line" "$HOST($comp)"]

            # handle some typical errors:
            switch -exact -- $res {
                  0 { set msg "" }
                  1 { set msg "invalid vdemo configuration. \nCheck VDEMO_root, component args, etc." }

                  2 { set msg "X connection failed on $HOST($comp).\nConsider using xhost+" }
                  3 { set msg "function 'component' not declared in component script" }
                  4 { set msg "component already running" }
                126 { set msg "component_$COMMAND($comp) start: permission denied" }
                default { set msg "component_$COMMAND($comp) start: unknown error $res" }
            }
            if {$msg != ""} {
                if [expr $::DEBUG_LEVEL >= 0] {
                    tk_messageBox -message $msg -icon warning -type ok
                } else {
                    puts $msg
                }
                set_status $comp failed_noscreen
                $WIDGET($comp).start state !disabled
                return
            }

            set SCREENED($comp) 1
            if {$DETACHTIME($comp) > 0} {
                set TIMERDETACH($comp) [after $DETACHTIME($comp) component_cmd $comp detach]
            } elseif {$DETACHTIME($comp) == 0} {
                set SCREENED($comp) 0
            }
            set ::LAST_GUI_INTERACTION($comp) [clock milliseconds]
            set check_time 500
            if { $WAIT_READY($comp) <= 0 } {set check_time $::CHECKNOWAIT_TIME($comp)}
            after $check_time component_cmd $comp check $allcmd_group
        }
        stopwait -
        stop {
            if { [$WIDGET($comp).stop instate disabled] } {
                dputs "$TITLE($comp): already stopping"
                return
            }
            # Hm. For some reason, we shouldn't do this for stopwait (called from start)
            if {$cmd != "stopwait"} {
                $WIDGET($comp).stop state disabled
                $WIDGET($comp).start state !disabled
            }
            set_status $comp unknown
            cancel_detach_timer $comp

            set cmd_line "$VARS $component_script $component_options $cmd"
            set res [ssh_command "$cmd_line" "$HOST($comp)"]
            set SCREENED($comp) 0

            set ::LAST_GUI_INTERACTION($comp) [clock milliseconds]
            if {$res != -1 && $cmd != "stopwait"} {
                after 100 component_cmd $comp check $allcmd_group
            }
        }
        screen {
            cancel_detach_timer $comp
            if {$SCREENED($comp)} {
                set cmd_line "$component_script $component_options screen"
                set title "$::TITLE($comp)@$::HOST($comp) - detach by \[C-a d\]"
                set cmd_line "xterm -fg white -bg black -title \"$title\" -e $cmd_line &"
                ssh_command "$VARS $cmd_line" "$HOST($comp)"
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
            if { [$WIDGET($comp).check instate disabled] } {
                dputs "$TITLE($comp): already checking"
                if {$allcmd_group != ""} {after 100 component_cmd $comp check $allcmd_group}
                return
            }
            $WIDGET($comp).check state disabled
            set_status $comp unknown

            set cmd_line "$VARS $component_script $component_options check"
            set res [ssh_command "$cmd_line" "$HOST($comp)"]
            dputs "check result: $res" 2
            after idle $WIDGET($comp).check state !disabled

            if { ! [string is integer -strict $res] } {
                puts "internal error: result is not an integer: '$res'"
                $WIDGET($comp).start state !disabled
                if {$allcmd_group != ""} {after 100 component_cmd $comp check $allcmd_group}
                return
            }

            if {$res == -1} {
                dputs "no master connection to $HOST($comp)";
                all_cmd_cancel $allcmd_group
                $WIDGET($comp).start state !disabled
                return
            }

            set noscreen 0
            # res = 10*min(onCheckResult, 25) + screenResult
            # onCheckResult is the result from the on_check function (0 on success)
            # screenResult: 0: success, 1: no screen, 2: PID not there
            set onCheckResult [expr $res / 10]
            set screenResult  [expr $res % 10]
            set s unknown
            if {$onCheckResult == 0} { # on_check was successful
                if {$screenResult == 0} { set s ok_screen } { set s ok_noscreen }
            } else { # on_check failed
                if {$screenResult == 0} { set s failed_check } { set s failed_noscreen }
            }

            # handle started component
            if { [$::WIDGET($comp).start instate disabled] } {
                set endtime [expr $::LAST_GUI_INTERACTION($comp) + $WAIT_READY($comp)]
                if {$onCheckResult != 0 && $screenResult == 0} {
                    if {$endtime < [clock milliseconds]} {
                        puts "$TITLE($comp) failed: timeout"
                        all_cmd_cancel $allcmd_group
                    } else {
                        # stay in starting state and retrigger check
                        set s starting
                        after 1000 component_cmd $comp check $allcmd_group
                    }
                }
            }
            # indicate component status to all_cmd monitor
            all_cmd_comp_status $allcmd_group $comp $s

            # handle stopped component
            if {$screenResult != 0} {
                $WIDGET($comp).stop state !disabled
            } elseif { [$WIDGET($comp).stop instate disabled] } {
                # comp not yet stopped, retrigger check
                set s unknown
                after 1000 component_cmd $comp check $allcmd_group
            }

            set_status $comp $s
            # re-enable start button?
            if {"$s" != "starting"} {
                set ::LAST_GUI_INTERACTION($comp) [clock milliseconds]
                $WIDGET($comp).start state !disabled
            }

            if {$screenResult != 0} {
                dputs "$comp not running: cancel detach timer" 2
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

proc set_status {comp status} {
    global WIDGET COMPSTATUS
    set COMPSTATUS($comp) $status
    switch -exact -- $status {
        starting {set style "starting.cmd.TButton"}
        ok_screen {set style "ok.cmd.TButton"}
        ok_noscreen {set style "noscreen.ok.cmd.TButton"}
        failed_noscreen {set style "failed.cmd.TButton"}
        failed_check {set style "check.failed.cmd.TButton"}
        default  {set style "cmd.TButton"}
    }
    dputs "change status of $comp to $status: $style" 2
    blink_stop $WIDGET($comp).check
    $WIDGET($comp).check configure -style $style
    update
}

proc blink_start {widget {interval 500}} {
  global _blink_data
  set _blink_data($widget.styles) [list [$widget cget -style] "cmd.TButton"]
  set _blink_data($widget.active) 1
  set _blink_data($widget.interval) $interval
  set _blink_data($widget.current) 0
  after $interval blink_cycle $widget
}

proc blink_cycle {widget} {
  global _blink_data
  if {$_blink_data($widget.active) == 0} {
    return
  }
  set style [lindex $_blink_data($widget.styles) $_blink_data($widget.current)]
  $widget configure -style $style
  set _blink_data($widget.current) [expr "($_blink_data($widget.current) + 1) % [llength $_blink_data($widget.styles)]"]
  after $_blink_data($widget.interval) blink_cycle $widget
}

proc blink_stop {widget} {
  global _blink_data
  set _blink_data($widget.active) 0
}

# {{{ ssh and command procs

proc screen_ssh_master {h} {
    set screenid [get_master_screen_name $h]
    if {$::SCREENED_SSH($h) == 1} {
        if { [catch {exec bash -c "screen -wipe | fgrep -q .$screenid"} ] } {
            set f [get_fifo_name $h]
            set res [connect_host $f $h]
            gui_update_host $h $res
            if {$res} {set ::SCREENED_SSH($h) 0}
        }
        exec  xterm -title "MASTER SSH CONNECTION TO $h." -e screen -r -S $screenid &
    } else {
        catch {exec  screen -d -S $screenid}
    }
}

proc reconnect_host {host msg} {
    # error code to indicate that user cancelled reconnection
    set res -2
    if { $::DEBUG_LEVEL >= 0 && \
         [tk_messageBox -message $msg -type yesno -icon question] == yes } {
        # try to connect to host
        set fifo [get_fifo_name $host]
        set res [connect_host $fifo $host]
    }
    gui_update_host $host $res
    return $res
}

proc ssh_check_connection {hostname {connect 1}} {
    set fifo [get_fifo_name $hostname]
    set screenid [get_master_screen_name $hostname]
    # error code to indicate missing master connection
    set res -1
    set msg ""
    if { [catch {exec bash -c "screen -wipe | fgrep -q .$screenid"} ] } {
        if {[file exists "$fifo.in"] == 0} {
            # fifo not yet in place / connection never succeeded yet
            set msg "Establish connection to $hostname?"
        } else {
            # fifo in place, screen session terminated or crashed
            set msg "Lost connection to $hostname. Reconnect?"
        }
    } else {
        # Issue a dummy command to check whether connection is still alive. If not, we get a timeout after 1s.
        # Without checking, reading $fifo.out will last forever when ssh connection is broken.
        # The error code of the timeout is 124. Tcl creates an exception on timeout.
        # Instead of timing out on the real ssh_command, we timeout here on a dummy, because here we
        # know, that the command shouldn't last long. However, the real ssh_command could last rather
        # long, e.g. stopping a difficult component. This would generate a spurious timeout.
        catch { set res 124; set res [exec bash -c "echo 'echo 0' > $fifo.in; timeout 1 cat $fifo.out"] }
        dputs "connection check result: $res" 2

        # cat might also fetch the result of a previous, delayed ssh command. Hence, if we didn't
        # timed out, set the result always to zero.
        if {$res != 124} {set res 0} {set msg "Timeout on connection to $hostname. Reconnect?"}
    }

    # actually try to reconnect
    if { $msg != "" && (!$connect || [reconnect_host $hostname $msg] != 0) } {
        return $res
    } elseif { $msg != "" && $connect } {
        # successfully (re)established connection
        gui_add_host $hostname
    } else {
        # otherwise connection was OK anyway
        gui_update_host $hostname 0
    }
    return 0
}

proc ssh_command {cmd hostname {check 1} {verbose 1}} {
    set f [get_fifo_name $hostname]

    # check if master connection is in place
    if $check {
        set res [ssh_check_connection $hostname]
        # return on error
        if $res { return -1 }
    }

    # actually issue the command
    set cmd [string trim "$cmd"]
    if {$verbose > 0} {
        dputs "run '$cmd' on host '$hostname'"
        set verbose "echo 1>&2; date +\"*** %X %a, %x ***********************\" 1>&2; echo \"*** RUN $cmd\" 1>&2;"
    } else {set verbose ""}

    set res [exec bash -c "echo '$verbose $cmd 1>&2; echo \$?' > $f.in; cat $f.out"]
    dputs "ssh result: $res" 3
    return $res
}

proc get_master_screen_name { hostname } {
    global VDEMOID
    return "vdemo-$VDEMOID-$hostname"
}

proc get_fifo_name {hostname} {
    return "$::TEMPDIR/vdemo-$::VDEMOID-ssh-$::env(USER)-$hostname"
}

set MONITOR_IGNORE_HOSTS [list]
proc disable_monitoring {host} {
    lappend ::MONITOR_IGNORE_HOSTS $host
}
proc enable_monitoring {host} {
    set ::MONITOR_IGNORE_HOSTS [lsearch -inline -all -not -exact $::MONITOR_IGNORE_HOSTS $host]
}
proc monitoring_disabled {host} {
    return [expr [lsearch -exact $::MONITOR_IGNORE_HOSTS $host] >= 0]
}

proc connect_host {fifo host} {
    exec rm -f "$fifo.in"
    exec rm -f "$fifo.out"
    exec mkfifo "$fifo.in"
    exec mkfifo "$fifo.out"

    # temporarily ignore failed connections on this host
    disable_monitoring $host

    # Here we establish the master connection. Commands pushed into $fifo.in get piped into
    # the remote bash (over ssh) and the result is read again and piped into $fifo.out.
    # This way, the remote stdout goes into $fifo.out, while remote stderr is displayed here.
    set screenid [get_master_screen_name $host]
    exec screen -dmS $screenid bash -c "tail -s 0.1 -f $fifo.in | ssh $::SSHOPTS -Y $host bash | while read s; do echo \$s > $fifo.out; done"

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
        if {$noScreen} {set res -2; break}

        # show screen session in xterm after 1s (allow entering password, etc.)
        if { ! $xterm_shown } {
            exec xterm -title "establish ssh connection to $host" -n "$host" -e screen -rS $screenid &
            set xterm_shown 1
        }
    }

    # re-enable monitoring of master connection on this host
    after [expr $::SCREEN_FAILURE_DELAY * 1000] enable_monitoring $host

    # handle connection errors
    if {[string match "connected*" $res]} {
        puts " OK"
    } else { # some failure
        switch -exact -- $res {
            124 {puts " timeout"}
             -2 {puts " aborted"}
            default {puts "error: $res"; set res -2}
        }
        # quit screen session
        catch {exec screen -XS $screenid quit}
        exec rm -f "$fifo.in"
        exec rm -f "$fifo.out"
        return $res
    }

    dputs "issuing remote initialization commands" 2
    set res [ssh_command "source $::env(VDEMO_demoConfig)" $host 0 $::DEBUG_LEVEL]
    set res [ssh_command "ls \$VDEMO_root 2> /dev/null" $host 0 $::DEBUG_LEVEL]
    if {$res} {puts "on $host: failed to source $::env(VDEMO_demoConfig)"}

    if {[info exists ::env(VDEMO_exports)]} {
        foreach {var} "$::env(VDEMO_exports)" {
            if {[info exists ::env($var)]} {
                ssh_command "export $var=$::env($var)" $host 0 $::DEBUG_LEVEL
            }
        }
    }

    # detach screen / close xterm
    catch { exec screen -dS $screenid }

    connect_screen_monitoring $host

    if {$::AUTO_SPREAD_CONF == 1} {
        set content [exec cat $::env(SPREAD_CONFIG)]
        exec bash -c "echo 'echo \"$content\" > $::env(SPREAD_CONFIG)' > $fifo.in"
    }
    return 0
}

proc connect_hosts {} {
    label .vdemoinit -text "init VDemo - be patient..." -foreground darkgreen -font "helvetica 30 bold"
    label .vdemoinit2 -text "" -foreground darkred -font "helvetica 20 bold"
    pack .vdemoinit
    pack .vdemoinit2
    update

    foreach {h} $::HOSTS {
        .vdemoinit2 configure -text "connect to $h"
        update
        set fifo [get_fifo_name $h]
        connect_host $fifo $h
    }
    # establish screen monitoring locally (for master connections)
    connect_screen_monitoring localhost
    destroy .vdemoinit
    destroy .vdemoinit2
}

proc disconnect_hosts {} {
    disconnect_screen_monitoring localhost

    foreach {h} $::HOSTS {
        dputs "disconnecting from $h"
        set screenid [get_master_screen_name $h]
        set fifo [get_fifo_name $h]
        set screenPID [exec bash -c "screen -list $screenid | grep vdemo | cut -d. -f1"]
        if {$::AUTO_SPREAD_CONF == 1 && "$screenPID" != "" && [file exists "$fifo.in"]} {
            # send ssh command, but do not wait for result
            set cmd "rm -f $::env(SPREAD_CONFIG)"
            exec bash -c "echo 'echo \"*** RUN $cmd\" 1>&2; $cmd 1>&2; echo \$?' > $fifo.in"
        }
        catch {exec bash -c "screen -list $screenid | grep vdemo | cut -d. -f1 | xargs kill 2>&1"}
        exec rm -f "$fifo.in"
        exec rm -f "$fifo.out"

        disconnect_screen_monitoring $h
    }
}

proc finish {} {
    disconnect_hosts
    catch {exec rmdir "$::TEMPDIR"}
    exit
}

proc remove_duplicates {} {
    global COMPONENTS TITLE HOST COMPONENTS_ON_TAB TAB

    set _COMPONENTS {}
    foreach {c} "$COMPONENTS" {
        set cmdhost "$TITLE($c):$HOST($c)"
        if { ![info exists _HAVE($cmdhost)] } {
            set _HAVE($cmdhost) "$cmdhost"
            set _COMPONENTS "$_COMPONENTS $c"
        } else {
            dputs "duplicate component title: $TITLE($c):$HOST($c)"
            set COMPONENTS_ON_TAB($TAB($c)) [lsearch -all -inline -not -exact $COMPONENTS_ON_TAB($TAB($c)) $c]
        }
    }
    set COMPONENTS $_COMPONENTS
}

proc compute_spread_segment {ip num} {
    set octets [split $ip .]
    # use IP octets 1-4
    set seg [join [lrange $octets 1 3] .]
    return "225.$seg:$::env(SPREAD_PORT)"
}

proc get_autospread_filename {} {
    return "/tmp/vdemo-spread-$::VDEMOID-$::env(USER).conf"
}

proc create_spread_conf {} {
    global COMPONENTS COMMAND HOST
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
            set sp_seg "$seg.255:$::env(SPREAD_PORT)"
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

set SCREEN_FAILURE_DELAY 2
proc handle_screen_failure {chan host} {
    gets $chan line
    dputs "screen failure: $host $chan: $line" 3

    if {[eof $chan] && ! [string match "err:*" $::MONITOR_CHAN($host)]} {
        puts "component monitoring failed on $host: Is inotifywait installed?"
        close $chan
        set ::MONITOR_CHAN($host) "err: no inotify"
        return
    }

    # check for a lost master connection
    set remoteHost ""
    regexp "^\[\[:digit:]]+\.vdemo-$::VDEMOID-(.*)\$" $line matched remoteHost
    if {"$remoteHost" != ""} {
        set ::SCREENED_SSH($remoteHost) 0
        # only ask for reconnection when $host == localhost && monitoring is enabled
        if {$host != "localhost" || [monitoring_disabled $remoteHost]} return
        reconnect_host $remoteHost "Lost connection to $remoteHost. Reconnect?"
        return
    }

    # a component crashed
    foreach {comp} "$::COMPONENTS" {
        if {$::HOST($comp) == $host && \
            [string match "*.$::COMMAND($comp).$::TITLE($comp)_" "$line"]} {
            dputs "$comp closed its screen session on $host" 2
            if {[$::WIDGET($comp).stop  instate disabled] || \
                [$::WIDGET($comp).start instate disabled] ||
                [expr [clock seconds] - $::LAST_GUI_INTERACTION($comp) < $::SCREEN_FAILURE_DELAY]} {
                # component was stopped or just started via gui -> ignore event
                # trigger stop: component's on_stop() might do some cleanup
                # component_cmd $comp stop
                component_cmd $comp check
            } else {
                # if this is not a user initiated stop, exit the system if requested
                if {[lsearch -exact $::VDEMO_QUIT_COMPONENTS $comp] >= 0 || \
                    [lsearch -exact $::VDEMO_QUIT_COMPONENTS "$::TITLE($comp)"] >= 0} {
                    puts "$::TITLE($comp) finished on $host: quitting vdemo"
                    all_cmd "stop"
                    finish
                } else {
                    dputs "$::TITLE($comp) died on $host." 0
                    if {$::RESTART($comp) == 2 || \
                        ($::RESTART($comp) == 1 && [tk_messageBox -message \
                            "$::TITLE($comp) stopped on $host.\nRestart?" \
                            -type yesno -icon warning] == "yes")} {
                        dputs "Restarting $::TITLE($comp)." 0
                        component_cmd $comp start
                    } else {
                        # trigger stop: component's on_stop() might do some cleanup
                        # component_cmd $comp stop
                        component_cmd $comp check
                        blink_start $::WIDGET($comp).check
                        show_component $comp
                    }
                }
            }
            return
        }
    }
    dputs "on $host: $line"
}

# setup inotifywait on remote hosts to monitor deletions in screen-directory
proc connect_screen_monitoring {host} {
    if { [info exists ::MONITOR_CHAN($host)] } {
        # disconnect old monitoring channel first
        disconnect_screen_monitoring $host

        # do not attempt to call inotify again, if it was previously not found
        if {[string match "err: no inotify" $::MONITOR_CHAN($host)]} return
    }

    set cmd "inotifywait -e delete -qm --format %f /var/run/screen/S-$::env(USER)"
    # remote hosts require monitoring through ssh connection
    if {$host != "localhost"} {
        set cmd "ssh $::SSHOPTS -tt $host $cmd"
        # If there was never a screen executed on the remote machine,
        # the directory /var/run/screen/S-$USER doesn't yet exist
        # Hence, call screen at least once:
        ssh_command "screen -ls 2> /dev/null" $host 0 $::DEBUG_LEVEL
    }

    # pipe-open monitor connection: cmd may fail due to missing ssh or inotifywait
    if { [ catch {set chan [open "|$cmd" "r+"]} ] } {
        puts "failed to monitor master connections: Is inotifywait installed?"
        set ::MONITOR_CHAN($host) "err: no inotify"
        return
    }
    set ::MONITOR_CHAN($host) $chan
    fconfigure $chan -blocking 0 -buffering line -translation auto
    fileevent $chan readable [list handle_screen_failure $chan $host]
}

proc disconnect_screen_monitoring {host} {
    if {! [info exists ::MONITOR_CHAN($host)]} return
    set chan $::MONITOR_CHAN($host)
    if {[string match "err:*" $chan]} return

    dputs "disconnecting monitor channel $chan for host $host" 2
    exec kill -HUP [lindex [pid $chan] 0]
    close $chan

    # indicate, that we are not monitoring anymore
    set ::MONITOR_CHAN($host) "err:disconnected"
}

proc running {comp} {
    set running_states [list starting ok_screen failed_check]
    return [expr [lsearch -exact $running_states $::COMPSTATUS($comp)] >= 0]
}

proc gui_exit {} {
    set quickexit 1
    foreach {comp} "$::COMPONENTS" {
        if { [running $comp] } {
            set quickexit 0
            break
        }
    }
    if {!$quickexit} {
        if [expr $::DEBUG_LEVEL >= 0] {
            set ans [tk_messageBox -message \
                "There are still running components.\nStop them before quitting?" \
                -type yesnocancel -default yes -icon question]
        } else {
            puts "Stopping remaining components before quitting."
            set ans yes
        }
        switch -- $ans {
            yes {all_cmd stop "all" 1}
            cancel {return}
        }
    }
    finish
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

proc handle_ctrl_fifo { infile } {
    if { [gets $infile line] >= 0 } {
        set args [regexp -all -inline {\S+} $line]
        set cmd [lindex $args 0]
        set comp [lindex $args 1]
        if {[lsearch -exact [list "start" "stop" "check"] $cmd] == -1} {
            puts "unknown remote control command: $cmd"
            return
        }
        foreach {c} "$::COMPONENTS" {
            if {$c == $comp} {
                puts "remote cmd: ${cmd}ing component $comp"
                component_cmd $comp $cmd
                return
            } elseif {$::GROUP($c) == $comp} {
                puts "remote cmd: ${cmd}ing group $comp"
                all_cmd $cmd $comp
                return
            } elseif {$comp == "ALL"} {
                puts "remote cmd: ${cmd}ing all components"
                all_cmd $cmd
                return
            }
        }
        puts "unknown component or group: $comp"
    } else {
        close $infile
    }
}

proc setup_ctrl_fifo { { filename "" } } {
    if {$filename == ""} {
        # fetch default from environment variable
        if {[info exists ::env(VDEMO_CONTROL_FIFO)]} {
            set filename $::env(VDEMO_CONTROL_FIFO)
        }
    }
    if {$filename == ""} return

    exec mkdir -p [file dirname $filename]
    exec rm -f $filename
    exec mkfifo $filename

    if { [ catch { open "|tail -n 5 --pid=[pid] -F $filename"} infile] } {
        puts "failed creating control fifo $filename"
    } else {
        fconfigure $infile -blocking no -buffering line
        fileevent $infile readable [list handle_ctrl_fifo $infile]
        puts "connected to remote control fifo $filename"
    }
}

set mypid [pid]
puts "My process id is $mypid"

signal trap SIGINT finish
signal trap SIGHUP finish

setup_temp_dir
parse_env_var
if {"$::VDEMO_QUIT_COMPONENTS" != ""} {puts "quitting on exit of: $::VDEMO_QUIT_COMPONENTS"}
remove_duplicates
create_spread_conf

# cleanup dangling connections first
disconnect_hosts
connect_hosts
update
gui_tcl
update
setup_ctrl_fifo

# autostart
if {[info exists ::env(VDEMO_autostart)] && $::env(VDEMO_autostart) == "true"} {
    puts "Starting all components due to autostart request"
    all_cmd "start"
}

# Local Variables:
# mode: tcl
# End:
