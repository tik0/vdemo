# kate: replace-tabs on; indent-width 4;

# required for signal handling
package require Tclx

set VDEMO_CONNECTION_TIMEOUT 5
catch {set VDEMO_CONNECTION_TIMEOUT $::env(VDEMO_CONNECTION_TIMEOUT)}
append SSHOPTS "-q -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -oConnectTimeout=" ${VDEMO_CONNECTION_TIMEOUT}
append SSHOPTSSLAVE $SSHOPTS " -oPasswordAuthentication=no -oPubkeyAuthentication=no -oGSSAPIAuthentication=no"
set ::VDEMO_CONNCHECK_TIMEOUT [expr {$VDEMO_CONNECTION_TIMEOUT * 1000}]
set ::TERMINATED 0

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
define_theme_color failed.noauto gray60 [list active red]
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

set current_group ""
set current_group_stopped ""
set current_group_started ""
set global_outfilename ""

# debugging puts()
set DEBUG_LEVEL 0
catch {set DEBUG_LEVEL $::env(VDEMO_DEBUG_LEVEL)}
proc dputs {args {level 1}} {
    if {$level <= $::DEBUG_LEVEL} {
        if {$level < 0} {
            set ts [clock format [clock seconds] -format {[%Y-%m-%dT%H:%M:%S] }]
            puts stdout "-- $ts$args"
        } else {
            puts stderr "-- $args"
        }
    }
}
proc assert condition {
    if {![uplevel 1 expr $condition]} {
        return -code error "assertion failed: $condition"
    }
}
proc backtrace {} {
    set bt {}
    set startLevel [expr {[info level] - 2}]
    for {set level 1} {$level <= $startLevel} {incr level} {
        lappend bt [lindex [info level $level] 0]
    }
    return [join $bt { => }]
}
proc bgerror {msg} {
    if {[string length $msg]} {
        dputs "background error report begin" 0
        puts stderr $::errorInfo
        dputs "background error report end" 0
    }
}

# tooltips
proc tooltip { w txt } {
    bind $w <Any-Enter> "after 1000 [list tooltip:show %W $txt]"
    bind $w <Any-Leave> "destroy %W.tooltip"
}

proc tooltip:show {w arg} {
    if {[eval winfo containing  [winfo pointerxy .]]!=$w} {return}
    set top $w.tooltip
    catch {destroy $top}
    toplevel $top -bd 1 -bg black
    wm overrideredirect $top 1
    if {[string equal [tk windowingsystem] aqua]}  {
        ::tk::unsupported::MacWindowStyle style $top help none
    }
    pack [message $top.txt -aspect 10000 -bg lightyellow -text $arg]
    set wmx [winfo rootx $w]
    set wmy [expr {[winfo rooty $w]+[winfo height $w]}]
    wm geometry $top [winfo reqwidth $top.txt]x[winfo reqheight $top.txt]+$wmx+$wmy
    raise $top
}

proc check:tooltip {comp} {
    switch -- "$::COMPSTATUS($comp)" {
        starting {return "starting"}
        ok_screen {return "screen process is alive and component check succeeded"}
        ok_noscreen {return "component check succeeded, but not started from vdemo"}
        failed_noscreen {return "component not running"}
        failed_check {return "component is running, but component check failed"}
        default  {return "status unknown"}
    }
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
    global COMPONENTS ARGS USEX TERMINAL WAIT_READY NOAUTO NOAUTOCONFIG LOGGING GROUP DETACHTIME COMP_LEVEL EXPORTS TITLE CHECKNOWAIT_TIME RESTART

    set USEX($comp) 0
    # time to wait for a process to startup
    set WAIT_READY($comp) 5000
    # time until process is checked after start (when not waiting)
    set CHECKNOWAIT_TIME($comp) 500
    set GROUP($comp) ""
    # detach a component after this time
    set DETACHTIME($comp) [expr {1000 * $::env(VDEMO_DETACH_TIME)}]
    set NOAUTO($comp) 0
    set TERMINAL($comp) "screen"
    set LOGGING($comp) $::env(VDEMO_LOGGING)
    set COMP_LEVEL($comp) ""
    set EXPORTS($comp) ""
    set RESTART($comp) 0

    # do not simply tokenize at spaces, but allow quoted strings ("" or '')
    set TOKENS [regexp -all -inline -- "\\S+|\[^ =\]+=(?:\\S+|\"\[^\"]+\"|'\[^'\]+')" $ARGS($comp)]

    for {set i 0} { $i < [llength $TOKENS] } {incr i} {
        set arg [lindex $TOKENS $i]
        set val [lindex $TOKENS [expr {$i+1}]]
        if { "$arg" == "--" } { break }

        if { [catch {switch -glob -- $arg {
            -w {
                set WAIT_READY($comp) [expr {1000 * [number $val double]}]
                incr i
            }
            -W {
                set CHECKNOWAIT_TIME($comp) [expr {1000 * [number $val double]}]
                incr i
            }
            -c {
                dputs "$comp: arg '-c' is obsolete" 0
                if [string is double -strict $val] {incr i}
            }
            -r {
                set RESTART($comp) 1
            }
            -R {
                set RESTART($comp) 2
            }
            -d {
                set DETACHTIME($comp) [expr {1000 * [number $val double]}]
                incr i
            }
            -g {
                lappend GROUP($comp) [string tolower "$val"]
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
                dputs "$comp: unknown component option $arg" 0
                exit
            }
        } } err ] } {
            dputs "$comp: error processing option '$arg $val': $err"
            exit
        }
    }
    # re-assign remaining arguments:
    set ARGS($comp) [lrange $TOKENS [expr {$i+1}] end]
    array set NOAUTOCONFIG [array get NOAUTO]
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
    global HOST COMPONENTS ARGS USEX COMMAND TITLE TABS TAB COMPONENTS_ON_TAB
    set components_list "$::env(VDEMO_components)"
    set comp [psplit "$components_list" ":"]
    set nCompos [llength "$comp"]
    set COMPONENTS {}
    set ::HOSTS ""
    set tab "default"
    set TABS [list $tab]
    set COMPONENTS_ON_TAB($tab) [list]
    set components_on_tab_list COMPONENTS_ON_TAB($tab)

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
            lappend COMPONENTS $component_name
            set TAB($component_name) $tab
            lappend $components_on_tab_list $component_name
            if {"$host" != ""} {lappend ::HOSTS $host}
            set HOST($component_name) $host
            set ARGS($component_name) [lindex $thisComp 2]
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

proc find_component {src what} {
    global _SEARCH
    set what "*[string trim $what]*"
    if {$what == "**"} {
        $src configure -style TEntry
        hilite_component ""
        return
    }
    if {![info exists _SEARCH(string)] || $_SEARCH(string) != $what} {
        set _SEARCH(string) $what
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
    }
    while 1 {
        set _SEARCH(found) [list]
        foreach {c} $::COMPONENTS_ON_TAB($_SEARCH(cur_tab)) {
            if {[string match $_SEARCH(string) $::TITLE($c)]} {
                lappend _SEARCH(found) $c
            }
        }
        set _SEARCH(index) [expr {$_SEARCH(index) + 1}]
        if {$_SEARCH(index) < [llength $_SEARCH(found)]} {
            # found on current tab
            set comp [lindex $_SEARCH(found) $_SEARCH(index)]
            show_component $comp
            hilite_component $comp
            $src configure -style TEntry
            break
        }
        # if not found, try on next tab
        set _SEARCH(cur_idx) [expr {($_SEARCH(cur_idx) + 1) % $_SEARCH(end_idx)}]
        catch { set _SEARCH(cur_tab) [$::COMPONENTS_WIDGET tab $_SEARCH(cur_idx) -text] }
        set _SEARCH(index) -1
        # reached initial tab again? -> indicate failure
        if {$_SEARCH(cur_idx) == $_SEARCH(start_idx)} {
            hilite_component ""
            $src configure -style failed.TEntry
            break
        }
    }
}

proc show_component {comp} {
    set tab [string tolower $::COMPONENTS_WIDGET.$::TAB($comp)]
    catch {
        # show tab widget containing the component
        $::COMPONENTS_WIDGET select $tab
    }
    set pos [lsearch -exact $::COMPONENTS_ON_TAB($::TAB($comp)) $comp]
    sframe ymoveto $tab [expr {double($pos)/[llength $::COMPONENTS_ON_TAB($::TAB($comp))]}]
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
    set state [.main.allcmd.$grp.noauto instate selected]
    foreach {comp} "$::COMPONENTS" {
        if {[lsearch -exact $::GROUP($comp) $grp] >= 0} {
            if {$state == 1} {
                set ::NOAUTO($comp) 1
            } else {
                set ::NOAUTO($comp) $::NOAUTOCONFIG($comp)
            }
        }
    }
}

proc set_group_logging {grp} {
    global COMPONENTS GROUP LOGGING
    set state [.main.allcmd.$grp.logging instate selected]
    foreach {comp} "$COMPONENTS" {
        if {[lsearch -exact $GROUP($comp) $grp] >= 0} {
            set LOGGING($comp) $state
        }
    }
}

proc get_tab {name} {
    set name [string tolower $name]
    if {[winfo exists $name] == 0} {
        sframe new $name -toplevel false -anchor nw
        pack $name -side top -fill both -expand yes
    }
    return [sframe content $name]
}

proc wheelEvent {x y delta} {
    set widget [winfo containing $x $y]
    if {$widget == ""} return
    foreach {tab} $::TABS {
        set tab [string tolower $::COMPONENTS_WIDGET.$tab]
        if {[string match "$tab*" $widget]} {
            sframe scroll $tab yview $delta
        }
    }
}

proc gui_tcl {} {
    global HOST COMPONENTS TERMINAL USEX LOGTEXT NOAUTO LOGGING  GROUP SCREENED  COMP_LEVEL COMMAND LEVELS TITLE TIMERDETACH TAB WIDGET COMPONENTS_WIDGET
    set LOGTEXT "demo configured from '$::env(VDEMO_demoConfig)'"
    wm title . "vdemo_controller: $::env(VDEMO_demoConfig)"

    set groups ""
    set LEVELS ""

    # determine max number of components in tabs
    set ::MAX_NUM 1
    foreach tab $::TABS {
        set ::MAX_NUM [ expr {max($::MAX_NUM, [llength $::COMPONENTS_ON_TAB($tab)])} ]
    }

    # main gui frame
    ttk::frame .main
    set COMPONENTS_WIDGET .main.components
    
    if {[llength $::TABS] > 1} {
        ttk::notebook $COMPONENTS_WIDGET -height 200
    } else {
        ttk::frame $COMPONENTS_WIDGET -height 200
    }
    pack $COMPONENTS_WIDGET -side top -fill both -expand yes

    foreach {c} "$COMPONENTS" {
        lappend groups {*}$GROUP($c)
        set LEVELS "$LEVELS $COMP_LEVEL($c)"
        set TIMERDETACH($c) 0
        set ::COMP_START_TIME($c) 0
        set ::COMP_STATUS_INTENT($c) unknown

        # get the frame widget where this component should go to
        set w [get_tab $COMPONENTS_WIDGET.$TAB($c)]

        ttk::frame $w.$c -style groove.TFrame
        grid $w.$c -column 0 -sticky we
        set WIDGET($c) $w.$c

        ttk::label $w.$c.level -style level.TLabel -text "$COMP_LEVEL($c)"
        ttk::label $w.$c.label -width -10 -style label.TLabel -text "$TITLE($c)@"
        ttk::entry $w.$c.host  -width 14 -textvariable HOST($c)
        # disable host field for spreaddaemon: cannot add/change hosts in spread config
        if {"$COMMAND($c)" == "spreaddaemon"} { $w.$c.host state disabled }

        ttk::label $w.$c.group -style group.TLabel -width 12 -text "$GROUP($c)"
        tooltip $w.$c.group [concat {[list } $GROUP($c) {]} ]

        ttk::button $w.$c.start -style cmd.TButton -text "start" -command "component_cmd $c start"
        ttk::button $w.$c.stop  -style cmd.TButton -text "stop" -command "component_cmd $c stop"
        ttk::button $w.$c.check -style cmd.TButton -text "check" -command "component_cmd $c check"
        ttk::checkbutton $w.$c.noauto -text "no auto" -variable NOAUTO($c)
        ttk::checkbutton $w.$c.ownx   -text "own X" -variable USEX($c)
        ttk::checkbutton $w.$c.logging -text "logging" -variable LOGGING($c)
        ttk::button $w.$c.viewlog -style cmd.TButton -text "view log" -command "component_cmd $c showlog"

        tooltip $w.$c.check [concat {[eval check:tooltip } $c {]} ]

        set SCREENED($c) 0
        ttk::checkbutton $w.$c.screen -text "show term" -command "component_cmd $c screen" -variable SCREENED($c) -onvalue 1 -offvalue 0
        ttk::button $w.$c.inspect -style cmd.TButton -text "inspect" -command "component_cmd $c inspect"

        pack $w.$c.level -side left -padx {2 0}
        pack $w.$c.label -side left -fill x -expand yes
        pack $w.$c.host -side left
        pack $w.$c.group -side left -fill x

        pack $w.$c.ownx -side right -padx 3
        pack $w.$c.inspect -side right
        pack $w.$c.viewlog -side right
        pack $w.$c.logging -side right
        pack $w.$c.screen -side right
        pack $w.$c.noauto -side right -padx 2
        pack $w.$c.check -side right -pady 2
        pack $w.$c.stop -side right -pady 2
        pack $w.$c.start -side right -pady 2
        set_status $c unknown
        sframe resize [string tolower $COMPONENTS_WIDGET.$TAB($c)] 1
    }
    set LEVELS [lsort -integer -unique "$LEVELS"]

    if {[llength $::TABS] > 1} {
        set tabs [list]
        foreach {tab} $::TABS {
            if { [llength $::COMPONENTS_ON_TAB($tab)] > 0 } {
                $COMPONENTS_WIDGET add [string tolower $COMPONENTS_WIDGET.$tab] -text $tab
                lappend tabs $tab
            }
        }
        set ::TABS $tabs
    }
    pack .main -side top -fill both -expand yes
    
    set allcmd .main.allcmd
    ttk::frame $allcmd
    pack $allcmd -side left -fill y
    # buttons to control ALL components
    all_cmd_reset all
    ttk::frame $allcmd.all -style groove.TFrame
    grid $allcmd.all -column 0 -row 0 -sticky w -columnspan 100 -pady 4
    ttk::label $allcmd.all.label -style TLabel -text "ALL COMPONENTS"
    ttk::button $allcmd.all.start -style cmd.TButton -text "start" -command "all_cmd start"
    ttk::button $allcmd.all.stop  -style cmd.TButton -text "stop"  -command "all_cmd stop"
    ttk::button $allcmd.all.check -style cmd.TButton -text "check" -command "all_cmd check"
    pack $allcmd.all.label -side left -padx {2 10} -pady 2
    pack $allcmd.all.start $allcmd.all.stop $allcmd.all.check -side left -pady 2
    # search widgets
    set ::SEARCH_STRING ""
    ttk::button $allcmd.all.searchBtn -style cmd.TButton -text "search" -command {
        find_component .main.allcmd.all.searchText $::SEARCH_STRING}
    ttk::entry  $allcmd.all.searchText -textvariable SEARCH_STRING -width 40
    bind $allcmd.all.searchText <Return> {find_component .main.allcmd.all.searchText $::SEARCH_STRING}
    pack $allcmd.all.searchText -side left -pady 2
    pack $allcmd.all.searchBtn -side right -ipadx 15 -padx 2 -pady 2

    # buttons for group control:
    set ::GROUPS [lsort -unique $groups]
    set idx 0
    foreach {g} $::GROUPS {
        all_cmd_reset $g
        ttk::frame $allcmd.$g -style groove.TFrame
        ttk::label $allcmd.$g.label  -style group.TLabel -text $g -anchor w
        ttk::button $allcmd.$g.start -style cmd.TButton -text "start" -command "all_cmd start $g"
        ttk::button $allcmd.$g.stop  -style cmd.TButton -text "stop"  -command "all_cmd stop  $g"
        ttk::button $allcmd.$g.check -style cmd.TButton -text "check" -command "all_cmd check $g"
        ttk::checkbutton $allcmd.$g.noauto -text "no auto" -command "set_group_noauto $g"
        ttk::checkbutton $allcmd.$g.logging -text "logging" -command "set_group_logging $g"

        grid $allcmd.$g.label -row 0 -column 0 -columnspan 3 -sticky we -padx {4 0} -pady {2 0}
        grid $allcmd.$g.start -row 1 -column 0 -padx {3 0} -pady {0 2}
        grid $allcmd.$g.stop -row 1 -column 1 -padx {0 3} -pady {0 2}
        grid $allcmd.$g.check -row 1 -column 2 -padx {0 3} -pady {0 2}
        grid $allcmd.$g.noauto -row 0 -column 3 -padx {0 3} -pady {2 0}
        grid $allcmd.$g.logging -row 1 -column 3 -padx {0 3} -pady {0 2}
        # estimate the width of a group item
        if { ! $idx } {
            update
            set winwidth [expr {[winfo width .]}]
            set numcols [expr {max($winwidth / ([winfo reqwidth $allcmd.$g]+10),1)}]
            set maxrows [expr {([llength $::GROUPS] + $numcols - 1) / $numcols} ]
        }
        set col [expr {$idx / $maxrows}]
        set row [expr {$idx % $maxrows + 1}]
        grid $allcmd.$g -column $col -row $row -padx {0 10} -pady 2 -sticky w
        incr idx
    }
    #replaces logger area to keep some compatibility
    if {[info exists ::env(VDEMO_watchfile)]} {
        ttk::frame .terminal -height 150 -style groove.TFrame
        pack .terminal -side top -fill x -anchor s
        bind .terminal <Map> {
            bind %W <Map> {}
            exec xterm -bg white -fg black -geometry 500x500 -into [winfo id %W] -e "trap : INT; l=100; while true; do \
                printf \033c; tail --pid=[pid] -n \$l -F $::env(VDEMO_watchfile); l=0; done" >>& /dev/null &
        }
        
    }
    ttk::frame .ssh
    pack .ssh -side left -fill x -expand 1 -padx 1 -pady 2
    ttk::label .ssh.label -text "ssh to"
    grid .ssh.label -column 0 -row 0
    foreach {h} $::HOSTS {
        gui_add_host $h
    }

    ttk::frame .exit
    pack .exit -side right -fill y -padx 5 -pady 5
    ttk::button .exit.btn -style exit.TButton -text "exit" -command {gui_exit}
    pack .exit.btn -anchor se -side bottom

    if {[info exists ::env(VDEMO_alert_string)]} {
        ttk::label .exit.orlabel -style alert.TLabel -text $::env(VDEMO_alert_string)
        pack .exit.orlabel -fill x
    } elseif {[info exists ::env(VDEMO_info_string)]} {
        ttk::label .exit.orlabel -style info.TLabel -text $::env(VDEMO_info_string)
        pack .exit.orlabel -fill x
    }
    # mouse wheel handler
    bind all <4> "+wheelEvent %X %Y -5"
    bind all <5> "+wheelEvent %X %Y  5"
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
        set idx [lsearch $::HOSTS $host]
        # create buttons
        ttk::frame  .ssh.$lh
        ttk::button .ssh.$lh.xterm -style $style -text "$host" -command "remote_xterm $host"
        ttk::button .ssh.$lh.clock -style cmd.TButton -text "⌚" -command "remote_clock $host" -width -2
        ttk::checkbutton .ssh.$lh.screen -text "" -command "screen_ssh_master $host" -variable ::SCREENED_SSH($host) -onvalue 1 -offvalue 0
        pack .ssh.$lh.xterm -side left
        pack .ssh.$lh.clock -side left
        pack .ssh.$lh.screen -side left
        update
        set winwidth [expr {[winfo width .]}]
        set numcols [expr {max(($winwidth-120) / [winfo reqwidth .ssh.$lh], 1)}]
        set col [expr {$idx % $numcols}]
        set row [expr {$idx / $numcols}]
        grid .ssh.$lh -column [expr {$col+1}] -row $row -sticky w
    }
}

# update button status to reflect state of master ssh connection
proc gui_update_host {host status {forceCreate 0}} {
    set lh [string tolower "$host"]
    dputs "gui_update_host: status:$status  forceCreate:$forceCreate" 3
    if {$status == 0} {set style "ok.cmd.TButton"} {set style "failed.cmd.TButton"}
    catch {.ssh.$lh.xterm configure -style $style}
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
# We achieve that behavior, by monitoring a list of started components (in ::ALLCMD(list_$group))
# and storing the start/stop mode (in ::ALLCMD(mode_$group)).
# If a running command should be cancelled, we use ::ALLCMD(intr_$group):
# -1: process failed -> stop further launching at next level
# -2: manual interrupt request -> immediately stop launching
#  0: all_cmd() finished / nothing pending
#  1: all_cmd() is pending
# This list of pending levels are stored in ::ALLCMD(pending_levels_$group).
# If a job finishes, fails, or a queue is cancelled, all_cmd_signal($group) is called.
# This one checks the open queues and triggers the next level for execution.

# list of groups for which user triggered an (exclusive) all_cmd
set ::ALLCMD(running_groups) [list]
proc all_cmd_reset {group} {
    set ::ALLCMD(list_$group) [list]
    set ::ALLCMD(mode_$group) ""
    set ::ALLCMD(intr_$group) 0
    set ::ALLCMD(pending_levels_$group) [list]
    # remove $group from list of running groups
    set ::ALLCMD(running_groups) [lsearch -inline -all -not -exact $::ALLCMD(running_groups) $group]
    if { [llength $::ALLCMD(running_groups)] == 0 } {
        set ::ALLCMD(ignore_hosts) [list]
    }
}

# a process from group succeeded, failed, or group's all_cmd was interrupted -> proceed with next jobs
proc all_cmd_signal {group} {
    # Are there pending jobs for this group?
    if { [llength $::ALLCMD(list_$group)] > 0 } return

    # Got we interrupted?
    if {$::ALLCMD(intr_$group) < 0} {
        # Should we cancel active all_cmds of other groups too?
        # I decided for no: If the user started groups independently,
        # they should be able to finish independently.
        # finish the current all_cmd for this group
        all_cmd_finish [ lindex $::ALLCMD(mode_$group) 0 ] $group 1
        return
    }

    # Is this group idle?  Test only here, because all_cmd_finish might have changed the variable
    if { $::ALLCMD(mode_$group) == "" } return

    # extract original all_cmd args and currently active execution level
    lassign $::ALLCMD(mode_$group) cmd lazy
    set current_level $::ALLCMD(current_level_${cmd})
    
    # are there pending execution levels for this job, which can be started right away?
    if { [llength $::ALLCMD(pending_levels_$group)] > 0 } {
        # peek next execution level
        set next [lindex $::ALLCMD(pending_levels_$group) 0]
        # can we execute next level right away?
        if { ($cmd == "start" && $current_level != "" && $next <= $current_level) ||
             ($cmd == "stop"  && $current_level != "" && $next >= $current_level) } {
            # eventually decrease/increase current level to $next
            set ::ALLCMD(current_level_${cmd}) $next
            # pop first item from pending_levels list
            set ::ALLCMD(pending_levels_$group) [lreplace $::ALLCMD(pending_levels_$group) 0 0]
            # run jobs at this level
            level_cmd $cmd $next $group $lazy
            return
        }
        # if we get here, the current_level doesn't allow for our execution level yet
    } else {
        # if there are no more pending execution levels, we are done with this all_cmd
        all_cmd_finish $cmd $group 1
    }
    all_cmd_continue $cmd
}

# continue with minimum execution level of all running all_cmds
proc all_cmd_continue {cmd} {
    set levels [list]
    foreach {group} $::ALLCMD(running_groups) {
        # Is this $group running a different cmd?
        if { [lindex $::ALLCMD(mode_$group) 0 ] != $cmd } { continue }
        # Are there pending jobs for this group?
        if { [llength $::ALLCMD(list_$group)] > 0 } return
        set levels [concat $levels $::ALLCMD(pending_levels_$group)]
    }
    set levels [lsort -unique $levels]
    if {"$cmd" == "stop"} {set levels [lreverse $levels]}

    # Are we finally done?
    if { [llength $levels] == 0 } {
        set ::ALLCMD(current_level_${cmd}) ""
        return
    }
    # If there are levels left, continue with next one
    set ::ALLCMD(current_level_${cmd}) [lindex $levels 0]
    set level $::ALLCMD(current_level_${cmd})
    # and trigger all running groups
    foreach {group} $::ALLCMD(running_groups) {
        set next [lindex $::ALLCMD(pending_levels_$group) 0]
        if { ($cmd == "start" && $next <= $level) ||
             ($cmd == "stop"  && $next >= $level) } {
            after idle all_cmd_signal $group
        }
    }
}

# signal interruption for active all_cmds of given groups
proc all_cmd_interrupt {groups} {
    # interrupt all groups?
    if {$groups == "all"} {set groups "$::GROUPS"}

    set ret 0
    # set manual interrupt flag: -2
    foreach group "all $groups" {
        if {$::ALLCMD(intr_$group) != 0} {
            set ::ALLCMD(intr_$group) -2
            after idle all_cmd_signal $group
            set ret 1
        }
    }
    return $ret
}
proc all_cmd_busy {} {
    lappend ::ALLCMD(current_level_start)
    lappend ::ALLCMD(current_level_stop)
    if {$::ALLCMD(current_level_stop) != "" || $::ALLCMD(current_level_stop) != ""} {return 1}
    foreach group "all $::GROUPS" {
        if {$::ALLCMD(intr_$group) != 0} {return 1}
    }
    foreach {comp} $::COMPONENTS {
        if {[$::WIDGET($comp).stop instate disabled] || [$::WIDGET($comp).start instate disabled]} {return 1}
    }
    return 0
}


proc all_cmd_update_gui {cmd group status style} {
    if {$group == "all"} { # also disable group buttons
        foreach g "$::GROUPS" {
            .main.allcmd.$g.$cmd state $status
            # reset style of all start buttons
            .main.allcmd.$g.start configure -style "cmd.TButton"
        }
    }
    .main.allcmd.$group.start configure -style "cmd.TButton"
    .main.allcmd.$group.$cmd state $status
}

set ::ALLCMD(pending_cmds) [list]
proc all_cmd_next_pending {} {
    # is there a pending command?
    if {[llength $::ALLCMD(pending_cmds)] == 0} {return ""}
    # peek next command
    set next [lindex $::ALLCMD(pending_cmds) 0]
    set group [lindex [split $next] 2]

    # check whether next command will conflict with active ones
    if {[all_cmd_interrupt $group]} {return ""}

    # no active + conflicting all_cmd() call: pop first element and return next
    set ::ALLCMD(pending_cmds) [lreplace $::ALLCMD(pending_cmds) 0 0]
    return $next
}

proc all_cmd {cmd {group "all"} {lazy 1}} {
    # initially define ::ALLCMD(current_level_${cmd}) if not yet done
    lappend ::ALLCMD(current_level_${cmd})

    # disable gui buttons
    all_cmd_update_gui $cmd $group "disabled" "starting.cmd.TButton"

    # get list of levels to process (in correct order)
    set levels $::LEVELS
    if {"$cmd" == "stop"} {set levels [lreverse $levels]}

    # ensure that other all_cmds from same $group are interrupted
    set sync [expr {[lsearch -exact [list "start" "stop"] $cmd] >= 0}]
    if {$sync} {
        if {[all_cmd_interrupt $group]} {
            # there is an active, conflicting all_cmd() call, postpone this new one
            lappend ::ALLCMD(pending_cmds) "all_cmd $cmd $group $lazy"
            return
        }
        # cmd accepted
        set ::ALLCMD(intr_$group) 1
        set ::ALLCMD(mode_$group) "$cmd $lazy"
        lappend ::ALLCMD(running_groups) "$group"

        # schedule all levels for execution
        set ::ALLCMD(pending_levels_$group) $levels
        all_cmd_signal $group
    } else {
        # trigger execution for all levels
        foreach {level} "$levels" {
            level_cmd $cmd $level $group $lazy
        }
        # finish
        all_cmd_finish $cmd $group $sync
    }
}

# finish execution of an all_cmd for $group
proc all_cmd_finish {cmd group synced} {
    # enable gui buttons
    set stylePrefix [expr {$::ALLCMD(intr_$group) == -1 ? "failed." : ""}]
    all_cmd_update_gui $cmd $group "!disabled" "${stylePrefix}cmd.TButton"

    if {$synced} {
        all_cmd_reset $group
        all_cmd_continue $cmd
        # if there is a pending all_cmd, now we can schedule it for execution
        if {[set next [all_cmd_next_pending]] != ""} {after idle $next}
    }
}

proc all_cmd_add_comp {group comp} {
    lappend ::ALLCMD(list_$group) $comp
}

# from status decide whether the component is correctly started or not
proc all_cmd_comp_started {status} { return [string match "ok_*" $status] }
# from status decide whether the component is correctly stopped or not
proc all_cmd_comp_stopped {status} { return [string match "*_noscreen" $status] }

# called when component's status changed
proc all_cmd_comp_set_status {group comp status} {
    if {$group == ""} return

    set started [all_cmd_comp_started $status]
    set stopped [all_cmd_comp_stopped $status]
    set ignored [expr {[lsearch -exact $::ALLCMD(ignore_hosts) $::HOST($comp)] >= 0}]

    switch -exact -- [lindex $::ALLCMD(mode_$group) 0] {
        start {
            if {!$started} {
                # if component is not starting anymore, it failed -> cancel
                if {"$status" != "starting"} {
                    if { !$ignored } { #  only cancel if host connection is not ignored
                        all_cmd_cancel $group $comp
                        return
                    }
                } else { # otherwise, component isn't ready yet, be more patient...
                    return
                }
            }
        }
        stop  {
            # if component isn't stopped yet, simply be patient...
            if {!$stopped && !$ignored} { return }
        }
        check {return}
    }
    set ::ALLCMD(list_$group) [lsearch -inline -all -not -exact $::ALLCMD(list_$group) $comp]
    all_cmd_signal $group
}

# set ALLCMD_INTR to -1 to indicate cancelling
proc all_cmd_cancel {group comp} {
    if {$group == "" || $::ALLCMD(mode_$group) == ""} return
    # remove comp from list ...
    set ::ALLCMD(list_$group) [lsearch -inline -all -not -exact $::ALLCMD(list_$group) $comp]
    # ... and indicate interrupt
    if {$::ALLCMD(intr_$group) > -1} {
        set ::ALLCMD(intr_$group) -1
    }
    blink_start $::WIDGET($comp).check
    all_cmd_signal $group
}
proc level_cmd { cmd level group {lazy 0} } {
    set synced [expr {[lsearch -exact [list "start" "stop"] $cmd] >= 0}]

    set components $::COMPONENTS
    if {"$cmd" == "stop"} {set components [lreverse $::COMPONENTS]}
    foreach {comp} "$components" {
        set ignore [expr {[lsearch -exact $::ALLCMD(ignore_hosts) $::HOST($comp)] >= 0}]
        if {$::COMP_LEVEL($comp) == $level && \
                ($group == "all" || [lsearch -exact $::GROUP($comp) $group] >= 0) && !$ignore} {
            switch -exact -- $cmd {
                check {set doIt 1}
                stop  {set doIt [expr  {!$lazy || ![all_cmd_comp_stopped $::COMPSTATUS($comp)]}]}
                start {set doIt [expr {(!$lazy || ![all_cmd_comp_started $::COMPSTATUS($comp)]) && !$::NOAUTO($comp)}]}
                default {error "invalid cmd: $cmd"}
            }
            if {$doIt} {
                if {$synced} {all_cmd_add_comp $group $comp}
                set res [component_cmd $comp $cmd $group]
                set ignore [expr {[lsearch -exact $::ALLCMD(ignore_hosts) $::HOST($comp)] >= 0}]
                if {$synced && $res != 0 && !$ignore} { # component_cmd failed
                    all_cmd_cancel $group $comp
                }
            } else {
                blink_stop $::WIDGET($comp).check
            }
            # break from loop, when manually requested (ALLCMD_INTR == -2)
            if {$synced && $::ALLCMD(intr_$group) == -2} {break}
        }
    }
    # in case of empty component list, we need to retrigger all_cmd_signal
    after idle all_cmd_signal $group
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
    set component_script "bash $cpath/component_$COMMAND($comp)"
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
                dputs "$TITLE($comp): not ready, still waiting for the process"
                return 1
            }
            $WIDGET($comp).start state disabled

            set res [ssh_command "screen -wipe | fgrep -q .$COMMAND($comp).$TITLE($comp)_" "$HOST($comp)"]
            if {$res == -1} {
                dputs "no master connection to $HOST($comp)"
                $WIDGET($comp).start state !disabled
                all_cmd_comp_set_status $allcmd_group $comp unknown
                return 1
            } elseif {$res == 0} {
                dputs "$TITLE($comp): already running, stopping first..."
                component_cmd $comp stopwait
                $WIDGET($comp).start state disabled
            }

            set_status $comp starting
            cancel_detach_timer $comp

            # don't detach when detach time == 0
            if {$DETACHTIME($comp) == 0} { set component_options "$component_options -D" }
            set cmd_line "$VARS $component_script $component_options start $ARGS($comp)"
            set res [ssh_command "$cmd_line" "$HOST($comp)"]

            # handle some typical errors:
            switch -exact -- $res {
                  0 { set msg "" }
                  2 { set msg "syntax error in component script" }
                  3 { set msg "invalid vdemo configuration. \nCheck VDEMO_root, component args, etc." }
                 10 { set msg "component already running" }
                 11 { set msg "function 'component' not declared in component script" }
                 12 { set msg "X connection failed on $HOST($comp).\nConsider using xhost+" }
                126 { set msg "component_$COMMAND($comp) start: permission denied" }
                127 { set msg "command not found" }
                default { set msg "component_$COMMAND($comp) start: unknown error $res" }
            }
            if {$msg != ""} {
                if [expr {$::DEBUG_LEVEL >= 0}] {
                    tk_messageBox -message $msg -icon warning -type ok
                } else {
                    dputs $msg 0
                }
                set_status $comp failed_noscreen
                $WIDGET($comp).start state !disabled
                return 1
            }

            set SCREENED($comp) 1
            if {$DETACHTIME($comp) > 0} {
                set TIMERDETACH($comp) [after $DETACHTIME($comp) component_cmd $comp detach]
            } elseif {$DETACHTIME($comp) == 0} {
                set SCREENED($comp) 0
            }
            set ::COMP_START_TIME($comp) [clock milliseconds]
            set ::COMP_STATUS_INTENT($comp) start
            after $::CHECKNOWAIT_TIME($comp) component_cmd $comp check $allcmd_group
        }
        stopwait -
        stop {
            if { [$WIDGET($comp).stop instate disabled] } {
                dputs "$TITLE($comp): already stopping"
                return 1
            }
            # We shouldn't enable start for stopwait (called from start)
            if {$cmd != "stopwait"} {
                $WIDGET($comp).stop state disabled
                $WIDGET($comp).start state !disabled
            }
            set old_status $::COMPSTATUS($comp)
            set_status $comp unknown
            cancel_detach_timer $comp
            set ::COMP_STATUS_INTENT($comp) stop

            set cmd_line "$VARS $component_script $component_options $cmd"
            set res [ssh_command "$cmd_line" "$HOST($comp)"]
            set SCREENED($comp) 0

            if {$res == -1} { # an error occurred when issuing the ssh_command
                $WIDGET($comp).stop state !disabled
                # restore old status
                set_status $comp $old_status
                if {[running $comp]} { # if component was running, indicate an error
                    return 1
                } else { # otherwise, pretend everything is fine
                    # pretend that component stopped, such that all_cmd loop can proceed
                    all_cmd_comp_set_status $allcmd_group $comp failed_noscreen
                    return 0
                }
            } elseif {$cmd != "stopwait"} {
                # Asynchronously wait for component to stop (triggering check every 100ms)
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
                return 1
            }
            $WIDGET($comp).check state disabled
            set_status $comp unknown

            set cmd_line "$VARS $component_script $component_options check"
            set res [ssh_command "$cmd_line" "$HOST($comp)"]
            after idle $WIDGET($comp).check state !disabled

            if { ! [string is integer -strict $res] } {
                dputs "internal error: result is not an integer: '$res'" 0
                $WIDGET($comp).start state !disabled
                if {$allcmd_group != ""} {after 100 component_cmd $comp check $allcmd_group}
                return 1
            }

            if {$res == -1} {
                dputs "no master connection to $HOST($comp)"
                $WIDGET($comp).start state !disabled
                all_cmd_comp_set_status $allcmd_group $comp unknown
                return 1
            }

            set noscreen 0
            # res = (onCheckResult << 2) | (screenResult & 3)
            # onCheckResult is the result from the on_check function (0 on success)
            # screenResult: 0: success, 1/2: no screen, finished without(1) / with(2) error
            dputs "check result: $res = ([expr $res >> 2] << 2) | [expr $res & 3]" 2
            set onCheckResult [expr {$res >> 2}]
            set screenResult  [expr {$res & 3}]
            set s unknown
            set status 0
            if {$onCheckResult == 0} { # on_check was successful
                if {$screenResult == 0} { set s ok_screen } { set s ok_noscreen }
                set status 0
            } else { # on_check failed
                if {$screenResult == 0} { set s failed_check } { set s failed_noscreen }
                set status 1
            }

            # handle started component
            if { [$::WIDGET($comp).start instate disabled] } {
                set endtime [expr {$::COMP_START_TIME($comp) + $WAIT_READY($comp)}]
                if {$onCheckResult != 0 && $screenResult == 0} {
                    if {$endtime < [clock milliseconds]} {
                        dputs "$TITLE($comp) failed: timeout" 0
                        set status 1
                    } else {
                        # stay in starting state and retrigger check
                        set s starting
                        after 1000 component_cmd $comp check $allcmd_group
                        set status 1
                    }
                }
            }

            # handle stopped component
            if {$screenResult != 0} {
                $WIDGET($comp).stop state !disabled
            } elseif { [$WIDGET($comp).stop instate disabled] } {
                # comp not yet stopped, retrigger check
                set s unknown
                after 1000 component_cmd $comp check $allcmd_group
                set status 0
            }

            set_status $comp $s
            # re-enable start button?
            if {"$s" != "starting"} {
                $WIDGET($comp).start state !disabled
            }

            if {$screenResult != 0} {
                dputs "$comp not running: cancel detach timer" 2
                cancel_detach_timer $comp
                set SCREENED($comp) 0
                set status 1
            }
            # indicate component status to all_cmd monitor
            all_cmd_comp_set_status $allcmd_group $comp $s

            return $status
        }
        inspect {
            set cmd_line "$VARS $component_script $component_options inspect"
            ssh_command "$cmd_line" "$HOST($comp)"
        }
        default {
            error "invalid component command: $cmd"
        }
    }
    update
    return 0
}

proc update_group_stats {} {
    if {![info exists ::GROUPS]} {return}
    foreach {grp} $::GROUPS {
        incr groupstats($grp,count) 0
        incr groupstats($grp,running) 0
    }
    foreach {comp} $::COMPONENTS {
        if {![info exists ::COMPSTATUS($comp)]} {return}
        if {$::NOAUTO($comp)} {continue}
        set state $::COMPSTATUS($comp)
        foreach {grp} $::GROUP($comp) {
            incr groupstats($grp,count)
            if {$state == "ok_screen"} {
                incr groupstats($grp,running)
            }
        }
    }
    foreach {grp} $::GROUPS {
        .main.allcmd.$grp.label configure -text "$grp  \[$groupstats($grp,running)/$groupstats($grp,count)\]"
        if {$groupstats($grp,running) == $groupstats($grp,count)} {
            .main.allcmd.$grp.check configure -style "ok.cmd.TButton"
        } else {
            .main.allcmd.$grp.check configure -style "failed.cmd.TButton"
        }
        if {$groupstats($grp,count) == 0} {
            .main.allcmd.$grp.check configure -style "cmd.TButton"
        }
    }
}

proc set_status {comp status} {
    global WIDGET COMPSTATUS
    set COMPSTATUS($comp) $status
    switch -exact -- $status {
        starting {set style "starting.cmd.TButton"}
        ok_screen {set style "ok.cmd.TButton"}
        ok_noscreen {set style "noscreen.ok.cmd.TButton"}
        failed_noscreen {
            set style "failed.cmd.TButton"
            if {$::NOAUTO($comp)} {set style "failed.noauto.cmd.TButton"}
        }
        failed_check {set style "check.failed.cmd.TButton"}
        default  {set style "cmd.TButton"}
    }
    dputs "change status of $comp to $status: $style" 2
    blink_stop $WIDGET($comp).check
    $WIDGET($comp).check configure -style $style
    update_group_stats
    update
}

proc blink_start {widget {interval 500}} {
  set ::blink_data($widget.styles) [list [$widget cget -style] "cmd.TButton"]
  set ::blink_data($widget.active) 1
  set ::blink_data($widget.interval) $interval
  set ::blink_data($widget.current) 0
  after $interval blink_cycle $widget
}

proc blink_cycle {widget} {
  if {$::blink_data($widget.active) == 0} {
    return
  }
  set style [lindex $::blink_data($widget.styles) $::blink_data($widget.current)]
  $widget configure -style $style
  set ::blink_data($widget.current) [expr {($::blink_data($widget.current) + 1) % [llength $::blink_data($widget.styles)]}]
  after $::blink_data($widget.interval) blink_cycle $widget
}

proc blink_stop {widget} {
  set ::blink_data($widget.active) 0
}

# {{{ ssh and command procs

proc pid_exists {procid} {
    set pidok 0
    catch {set pidok [expr {[llength [wait -nohang $procid]] eq 0}]}
    return $pidok
}

proc screen_ssh_master {h} {
    set screenid [get_master_screen_name $h]
    if {$::SCREENED_SSH($h) == 1} {
        if { [pid_exists $::screenMasterPID($h)] == 0 } {
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
    gui_update_host $host $res
    update
    if { $::DEBUG_LEVEL < 0 || $::DEBUG_LEVEL >= 0 && \
         [tk_messageBox -message $msg -type yesno -icon question] == yes } {
        # try to connect to host
        set fifo [get_fifo_name $host]
        set res [connect_host $fifo $host]
    } elseif { [llength $::ALLCMD(running_groups)] > 0 } {
        lappend ::ALLCMD(ignore_hosts) $host
    }
    gui_update_host $host $res
    return $res
}

# read_chan ignores data after \0 in the same read cycle.
proc read_chan {chan {timeout 0}} {
    set result ""
    if {[expr {$timeout != 0}]} {set endtime [expr {[clock milliseconds] + $timeout}]}
    while {$timeout == 0 || $endtime > [clock milliseconds]} {
        set data [split [read -nonewline $chan] \0]
        append result [lindex $data 0]
        if { [llength $data] == 2 } {
            break
        }
        after 1
    }
    return $result
}

proc communicate_ssh {host cmd {timeout 0}} {
    puts $::SSH_DATA_INCHAN($host) $cmd
    return [read_chan $::SSH_DATA_OUTCHAN($host) $timeout]
}

proc ssh_check_connection {hostname {connect 1}} {
    if {[string length $hostname] == 0} {return -1}
    set fifo [get_fifo_name $hostname]
    # error code to indicate missing master connection
    set res -1
    set msg ""
    if { [pid_exists $::screenMasterPID($hostname)] == 0 } {
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
        # The same applies to writing to $fifo.in thus it is opened as a filedescriptor in bash in read/write mode
        # which makes it non-blocking. The error code of the bash read timeout is 142.
        # Instead of timing out on the real ssh_command, we timeout here on a dummy, because here we
        # know, that the command shouldn't last long. However, the real ssh_command could last rather
        # long, e.g. stopping a difficult component. This would generate a spurious timeout.
        set res [communicate_ssh $hostname "echo -ne 0\\\\0" $::VDEMO_CONNCHECK_TIMEOUT]
        dputs "connection check result: $res" 2

        # we might also fetch the result of a previous, delayed ssh command. Really?
        if {$res != 0} {set msg "Timeout on connection to $hostname. Reconnect?"; set res 0}
    }

    # actually try to reconnect
    if { $msg != "" && ($::TERMINATED || !$connect || [reconnect_host $hostname $msg] != 0) } {
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
    set cmd [string trim $cmd]
    if {$verbose > 0} {
        dputs "run '$cmd' on host '$hostname'"
        set verbose "echo 1>&2; date +'*** %X %a, %x ***********************' 1>&2; echo '*** RUN $cmd' 1>&2;"
    } else {set verbose ""}
    # The 0 byte is a delimiter here. it enables collecting multiline output if necessary
    set res [communicate_ssh $hostname "$verbose $cmd 1>&2; echo -ne \$?\\\\0"]
    dputs "ssh result: '$res'" 3
    return $res
}

proc get_master_screen_name { hostname } {
    return "$::VDEMOID-$hostname"
}

proc get_fifo_name {hostname} {
    return "$::TEMPDIR/$hostname"
}

set MONITOR_IGNORE_HOSTS [list]
proc disable_monitoring {host} {
    lappend ::MONITOR_IGNORE_HOSTS $host
}
proc enable_monitoring {host} {
    set ::MONITOR_IGNORE_HOSTS [lsearch -inline -all -not -exact $::MONITOR_IGNORE_HOSTS $host]
}
proc monitoring_disabled {host} {
    return [expr {[lsearch -exact $::MONITOR_IGNORE_HOSTS $host] >= 0}]
}

proc init_connect_host {fifo host} {
    file delete "$fifo.in"
    file delete "$fifo.out"
    file delete "$fifo.ctrl"
    exec mkfifo "$fifo.in"
    exec mkfifo "$fifo.out"
    # open fifos in rw mode, so they do not receive an eof
    if {[info exists ::SSH_DATA_INCHAN($host)]} { close $::SSH_DATA_INCHAN($host) }
    if {[info exists ::SSH_DATA_OUTCHAN($host)]} { close $::SSH_DATA_OUTCHAN($host) }
    set outchan [open "$fifo.out" r+]
    fconfigure $outchan -buffering none -blocking 0 -translation binary
    set inchan [open "$fifo.in" r+]
    fconfigure $inchan -buffering none -blocking 0 -translation binary
    set ::SSH_DATA_INCHAN($host) $inchan
    set ::SSH_DATA_OUTCHAN($host) $outchan
    
    # temporarily ignore failed connections on this host
    disable_monitoring $host

    # Here we establish the master connection. Commands pushed into $fifo.in get piped into
    # the remote bash (over ssh) and the result is read again and piped into $fifo.out.
    # This way, the remote stdout goes into $fifo.out, while remote stderr is displayed here.
    # ssh will not see an eof because each fifo is openend in read/write mode.
    # here screen remains a child process of vdemo (-D), so we can save the pid.
    set screenid [get_master_screen_name $host]
    set ::screenMasterPID($host) [exec screen -DmS $screenid bash -c "exec 5<>$fifo.in; exec 6<>$fifo.out; ssh $::SSHOPTS -Y -M -S $fifo.ctrl $host bash <&5 >&6" &]

    # Wait until connection is established.
    # Issue a echo command on remote host that only returns if a connection was established.
    puts $::SSH_DATA_INCHAN($host) "echo -ne connected\\\\0"
}

proc process_connect_host {fifo host} {
    # Loop will wait for at most 30 seconds to allow entering a password if necessary.
    # This will break earlier if ssh connection returns, e.g. due to timeout.
    set endtime [expr {[clock seconds] + 30}]
    set xterm_shown 0
    set screenid [get_master_screen_name $host]
    puts -nonewline "connecting to $host: "; flush stdout
    while {$endtime > [clock seconds]} {
        set res [read_chan $::SSH_DATA_OUTCHAN($host) 1000]
        # continue waiting on timeout (""), otherwise break from loop
        if {$res == ""} { puts -nonewline "."; flush stdout } { break }
        # break from loop, when screen session was stopped
        if { [pid_exists $::screenMasterPID($host)] == 0} {set res -2; break}

        # show screen session in xterm after 1s (allow entering password, etc.)
        if { ! $xterm_shown } {
            exec xterm -title "establish ssh connection to $host" -n "$host" -e screen -rS $screenid &
            set xterm_shown 1
        }
    }

    # re-enable monitoring of master connection on this host
    after [expr $::SCREEN_FAILURE_DELAY] enable_monitoring $host

    # handle connection errors
    if {[string match "connected*" $res]} {
        puts " OK"
    } else { # some failure
        switch -exact -- $res {
            142 {puts " timeout"}
             -2 {puts " aborted"}
            default {puts "error: '$res'"; set res -2}
        }
        # quit screen session
        catch {exec screen -XS $screenid quit}
        file delete "$fifo.in"
        file delete "$fifo.out"
        return $res
    }

    dputs "issuing remote initialization commands" 2
    if {[info exists ::env(VDEMO_exports)]} {
        foreach {var} $::env(VDEMO_exports) {
            if {[info exists ::env($var)]} {
                ssh_command "export $var=$::env($var)" $host 0 $::DEBUG_LEVEL
            }
        }
    }
    set res [ssh_command "source $::env(VDEMO_demoConfig)" $host 0 $::DEBUG_LEVEL]
    if {$res} {dputs "on $host: failed to source $::env(VDEMO_demoConfig)" 0}

    # detach screen / close xterm
    catch { exec screen -dS $screenid }

    connect_screen_monitoring $host

    if {$::AUTO_SPREAD_CONF == 1} {
        dputs "sending spread config $::env(SPREAD_CONFIG) to $host"
        set content [read_file $::env(SPREAD_CONFIG)]
        communicate_ssh $host "echo '$content' > $::env(SPREAD_CONFIG); echo -ne \\\\0"
    }
    return 0
}

proc connect_host {fifo host} {
    init_connect_host $fifo $host
    return [process_connect_host $fifo $host]
}

proc connect_hosts {} {
    if {[info exists ::geometry]} {
        set geometry ${::geometry}
    } else {
        set geometry {}
    }
    wm geometry . ""
    update
    label .vdemoinit -text "init VDemo - be patient..." -foreground darkgreen -font "helvetica 30 bold"
    label .vdemoinit2 -text "" -foreground darkred -font "helvetica 20 bold"
    pack .vdemoinit
    pack .vdemoinit2
    update
    foreach {h} $::HOSTS {
        .vdemoinit2 configure -text "init connect to $h"
        update
        init_connect_host [get_fifo_name $h] $h
    }
    foreach {h} $::HOSTS {
        .vdemoinit2 configure -text "wait connect to $h"
        update
        process_connect_host [get_fifo_name $h] $h
    }
    # establish screen monitoring locally (for master connections)
    connect_screen_monitoring localhost
    if { ${geometry} != "" } { wm geometry . ${geometry} }
    destroy .vdemoinit
    destroy .vdemoinit2
}

proc disconnect_hosts {} {
    disconnect_screen_monitoring localhost
    foreach {h} $::HOSTS {
        dputs "disconnecting from $h"
        set screenid [get_master_screen_name $h]
        set fifo [get_fifo_name $h]
        if {$::AUTO_SPREAD_CONF == 1 && [info exists ::screenMasterPID($h)] && [pid_exists $::screenMasterPID($h)] && [file exists "$fifo.in"]} {
            # send ssh command, but do not wait for result
            ssh_command "rm -f $::env(SPREAD_CONFIG)" $h
        }
        disconnect_screen_monitoring $h
        catch {exec screen -S $screenid -X quit}
        file delete "$fifo.in"
        file delete "$fifo.out"
    }
}

proc finish { {hard 0} } {
    lappend ::ALLCMD(current_level_stop)
    if { !$hard && [all_cmd_busy] } {
        after 10 finish
        return
    }
    set ::TERMINATED 1
    disconnect_hosts
    catch {file delete "$::TEMPDIR"}
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
    # this file will be copied to all connected hosts
    return "/tmp/$::VDEMOID-spread.conf"
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
        if {"$ip" == ""} {dputs "failed to lookup host $h" 0; continue}
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
            set num [expr {$num + 1}]
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

set SCREEN_FAILURE_DELAY 2000
proc handle_screen_failure {chan host} {
    # eof case
    if {[gets $chan line] < 0} {
        fconfigure $chan -blocking 1
        try {
            close $chan
        } on error {results options} {
            # retrieving the exit code, 127: command not found
            set status [lindex [dict get $options -errorcode] 2]
            if {$status == 127} {
                dputs "component monitoring failed on $host: Is inotifywait installed?" 0
                set ::MONITOR_CHAN($host) "err: no inotify"
            }
        } finally {
            dputs "component monitoring failed on $host" 0
        }
        set ::MONITOR_CHAN($host) err:disconnected
        return
    }
    dputs "screen failure: $host $chan: $line" 3
    
    # check for a lost master connection
    set remoteHost ""
    regexp "^\[\[:digit:]]+\.$::VDEMOID-(.*)\$" $line matched remoteHost
    if {"$remoteHost" != ""} {
        set ::SCREENED_SSH($remoteHost) 0
        # only ask for reconnection when $host == localhost && monitoring is enabled
        if {$host != "localhost" || [monitoring_disabled $remoteHost]} return
        reconnect_host $remoteHost "Lost connection to $remoteHost. Reconnect?"
        return
    }
    # a component crashed
    foreach {comp} $::COMPONENTS {
        if {$::HOST($comp) == $host && \
            [string match "*.$::COMMAND($comp).$::TITLE($comp)_" "$line"]} {
            dputs "$comp closed its screen session on $host" 2
            if {$::COMP_STATUS_INTENT($comp) == "stop"} {
                # component was stopped or just started via gui -> ignore event
                component_cmd $comp check
            } else {
                # if this is not a user initiated stop, exit the system if requested
                if {[lsearch -exact $::VDEMO_QUIT_COMPONENTS $comp] >= 0 || \
                    [lsearch -exact $::VDEMO_QUIT_COMPONENTS $::TITLE($comp)] >= 0} {
                    dputs "$::TITLE($comp) finished on $host: quitting vdemo" -1
                    all_cmd stop all 0
                    finish
                } else {
                    dputs "$::TITLE($comp) died on $host." -1
                    if {!$::TERMINATED && ( \
                            $::RESTART($comp) == 2 || ($::RESTART($comp) == 1 && $::DEBUG_LEVEL < 0) || \
                        ($::RESTART($comp) == 1 && \
                        [tk_messageBox -message "$::TITLE($comp) stopped on $host.\nRestart?" \
                            -type yesno -icon warning] == "yes") \
                        )
                    } {
                        dputs "Restarting $::TITLE($comp)." -1
                        component_cmd $comp start
                    } else {
                        # trigger stopwait: component's on_stop() might do some cleanup
                        component_cmd $comp stopwait
                        component_cmd $comp check
                        blink_start $::WIDGET($comp).check
                        catch {after cancel $::SHOW_COMPONENT_TIMER}
                        set ::SHOW_COMPONENT_TIMER [after 100 show_component $comp]
                    }
                }
            }
            return
        }
    }
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
        set fifo [get_fifo_name $host]
        set cmd "ssh $::SSHOPTSSLAVE -tt -S $fifo.ctrl $host $cmd"
        # If there was never a screen executed on the remote machine,
        # the directory /var/run/screen/S-$USER doesn't yet exist
        # Hence, call screen at least once:
        ssh_command "screen -ls 2> /dev/null" $host 0 $::DEBUG_LEVEL
    }

    # pipe-open monitor connection: cmd may fail due to missing ssh or local inotifywait causing POSIX error
    # nonzero exit codes cannot be detected here but using close on eof in handle_screen_failure
    try {
        set chan [open "|$cmd" "r+"]
    } trap POSIX {chan options} {
        dputs "failed to monitor master connections on $host: Is inotifywait installed?" 0
        set ::MONITOR_CHAN($host) "err: no inotify"
        return
    }
    set ::MONITOR_CHAN($host) $chan
    fconfigure $chan -blocking 0 -buffering line -translation auto
    fileevent $chan readable [list handle_screen_failure $chan $host]
    dputs "connected screen monitoring channel $chan for host $host" 2
}

proc disconnect_screen_monitoring {host} {
    if {! [info exists ::MONITOR_CHAN($host)]} return
    set chan $::MONITOR_CHAN($host)
    if {[string match "err:*" $chan]} return
    dputs "disconnecting monitor channel $chan for host $host" 2
    kill HUP [lindex [pid $chan] 0]
    close $chan
    # indicate, that we are not monitoring anymore
    set ::MONITOR_CHAN($host) "err:disconnected"
}

proc running {comp} {
    set running_states [list starting ok_screen failed_check]
    return [expr {[lsearch -exact $running_states $::COMPSTATUS($comp)] >= 0}]
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
        if [expr {$::DEBUG_LEVEL >= 0}] {
            set ans [tk_messageBox -message \
                "There are still running components.\nStop them before quitting?" \
                -type yesnocancel -default yes -icon question]
        } else {
            dputs "Stopping remaining components before quitting." 0
            set ans yes
        }
        switch -- $ans {
            yes {
                all_cmd stop all 0
            }
            cancel {return}
        }
    }
    finish
}

wm protocol . WM_DELETE_WINDOW {
    gui_exit
}

proc setup_temp_dir { } {
    global TEMPDIR VDEMOID

    # VDEMOID is composed of demoConfig's basename and unique id
    set name [file tail [file rootname $::env(VDEMO_demoConfig)]]
    set TEMPDIR [exec mktemp -d /tmp/vdemo-$name-XXXXXXXXXX]
    set VDEMOID [ file tail $TEMPDIR ]
}

proc handle_remote_request { request args } {
    dputs "got remote request: $request $args" 1
    switch $request {
        "list" {
            dputs "remote cmd: ${request}ing components" 2
            set result {"component\tlevel\ttitle\thost\tgroup\tstatus"}
            foreach {comp} $::COMPONENTS {
                 lappend result "$comp\t$::COMP_LEVEL($comp)\t$::TITLE($comp)\t$::HOST($comp)\t$::GROUP($comp)\t$::COMPSTATUS($comp)"
            }
            return [join $result "\n"]
        }
        "grouplist" {
            return [join $::GROUPS "\n"]
        }
        "all" {
            if { [llength $args] > 1 } {
                set grp [lindex $args 1]
                if { [lsearch -exact $::GROUPS $grp] == -1 && $grp != "all" } {
                    error "group $grp not found"
                }
            }
            all_cmd {*}$args
            return "OK"
        }
        "terminate" {
            all_cmd stop all 0
            finish
            return "OK"
        }
        "component" {
            set method [lindex $args 0]
            set compstr [lindex $args 1]
            switch $method {
                id { 
                    set complist [lsearch -exact -inline -all $::COMPONENTS $compstr]
                }
                match {
                    set complist [list]
                    foreach {c} $::COMPONENTS {
                        if {[string match $compstr "$::TITLE($c)@$::HOST($c)"]} {
                            lappend complist $c
                        }
                    }
                }
                default {error "unknown access method $method"}
            }
            dputs "remote cmd: selected components: $complist" 2
            set cmd [lindex $args 2]
            set lines [lindex $args 3]
            switch $cmd {
                log {
                    if {[llength $complist] != 1} {
                        error "$cmd requires a single component but [llength $complist] match."
                    }
                    set comp $complist
                    set host $::HOST($comp)
                    set logname "$::env(VDEMO_logfile_prefix)$::COMMAND($comp).$::TITLE($comp).log"
                    set fifo [get_fifo_name $host]
                    return [exec ssh {*}$::SSHOPTSSLAVE -S $fifo.ctrl $host tail -n $lines $logname]
                }
                default {
                    if {[llength $complist] < 1} {
                        error "$cmd requires at least one component but no match found."
                    }
                    foreach {c} $complist {
                        after idle component_cmd $c $cmd
                    }
                }
            }
            return "OK"
        }
        "busy" {
            return [all_cmd_busy]
        }
        default {
            error "no handler for $request"
        }
    }
}

# sframe.tcl
# Paul Walton
# Create a ttk-compatible, scrollable frame widget.
#   Usage:
#       sframe new <path> ?-toplevel true?  ?-anchor nsew?
#       -> <path>
#
#       sframe content <path>
#       -> <path of child frame where the content should go>

namespace eval ::sframe {
    namespace ensemble create
    namespace export *

    # Create a scrollable frame or window.
    proc new {path args} {
        # Create the main frame or toplevel.
        if { [dict exists $args -toplevel]  &&  [dict get $args -toplevel] } {
            toplevel $path
        } else {
            ttk::frame $path -relief sunken -borderwidth 1
        }

        # Create a scrollable canvas with scrollbars which will always be the same size as the main frame.
        set canvas [canvas $path.canvas -bd 0 -highlightthickness 0 -yscrollcommand [list $path.scrolly set] -xscrollcommand [list $path.scrollx set]]
        ttk::scrollbar $path.scrolly -orient vertical   -command [list $canvas yview]
        ttk::scrollbar $path.scrollx -orient horizontal -command [list $canvas xview]

        # Create a container frame which will always be the same size as the canvas or content, whichever is greater.
        # This allows the child content frame to be properly packed and also is a surefire way to use the proper ttk background.
        set container [ttk::frame $canvas.container]
        pack propagate $container 0

        # Create the content frame. Its size will be determined by its contents. This is useful for determining if the
        # scrollbars need to be shown.
        set content [ttk::frame $container.content]

        # Pack the content frame and place the container as a canvas item.
        set anchor "n"
        if { [dict exists $args -anchor] } {
            set anchor [dict get $args -anchor]
        }
        pack $content -anchor $anchor
        $canvas create window 0 0 -window $container -anchor nw

        # Grid the scrollable canvas sans scrollbars within the main frame.
        grid $canvas   -row 0 -column 0 -sticky nsew -padx 1 -pady 1
        grid rowconfigure    $path 0 -weight 1
        grid columnconfigure $path 0 -weight 1

        # Make adjustments when the sframe is resized or the contents change size.
        bind $path.canvas <Configure> [list [namespace current]::resize $path]
        return $path
    }


    # Given the toplevel path of an sframe widget, return the path of the child frame suitable for content.
    proc content {path} {
        return $path.canvas.container.content
    }

    proc ymoveto {path pos} {
        $path.canvas yview moveto $pos
    }

    # Make adjustments when the the sframe is resized or the contents change size.
    proc resize {path {autowidth 0} } {
        set canvas    $path.canvas
        set container $canvas.container
        set content   $container.content

        # Set the size of the container. At a minimum use the same width & height as the canvas.
        set width  [winfo width $canvas]
        set height [winfo height $canvas]

        # If the requested width or height of the content frame is greater then use that width or height.
        if { [winfo reqwidth $content] > $width } {
            set width [winfo reqwidth $content]
        }
        if { [winfo reqheight $content] > $height } {
            set height [winfo reqheight $content]
        }
        $container configure  -width $width  -height $height

        # Configure the canvas's scroll region to match the height and width of the container.
        $canvas configure -scrollregion [list 0 0 $width $height]
        #automatic width adjustment
        
        if {$autowidth} {
            $canvas configure -width $width
        }

        # Show or hide the scrollbars as necessary.
        # Horizontal scrolling.
        if { [winfo reqwidth $content] > [winfo width $canvas] } {
            grid $path.scrollx  -row 1 -column 0 -sticky ew
        } else {
            grid forget $path.scrollx
        }
        # Vertical scrolling.
        if { [winfo reqheight $content] > [winfo height $canvas] } {
            grid $path.scrolly  -row 0 -column 1 -sticky ns
        } else {
            grid forget $path.scrolly
        }
        return
    }

    # Handle mousewheel scrolling.
    proc scroll {path view D} {
        if { [winfo exists $path.canvas] } {
            $path.canvas $view scroll [expr {$D}] units
        }
        return
    }
}

signal trap SIGINT [list finish 1]
signal trap SIGHUP [list finish 1]
catch {set geometry $::env(GEOMETRY)}

setup_temp_dir
dputs "my process id: [pid], vdemo-id: $::VDEMOID" -1

parse_env_var
if {$::VDEMO_QUIT_COMPONENTS != ""} {dputs "quitting on exit of: $::VDEMO_QUIT_COMPONENTS" 0}
remove_duplicates
create_spread_conf

# cleanup dangling connections first
disconnect_hosts
connect_hosts
update
gui_tcl
if {![info exists ::geometry]} {wm geometry . ""}
update

# autocheck
if {[info exists ::env(VDEMO_autocheck)] && $::env(VDEMO_autocheck) == "true"} {
    dputs "Checking all components due to autocheck request" -1
    all_cmd check all
}

# autostart
if {[info exists ::env(VDEMO_autostart)] && $::env(VDEMO_autostart) == "true"} {
    dputs "Starting all components due to autostart request" -1
    all_cmd start all
}

# Local Variables:
# mode: tcl
# End:
