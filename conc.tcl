#!/usr/bin/wish

set i 0

set ALLCMD(list_.a) [list]
set ALLCMD(list_.b) [list]
set ALLCMD_COUNT_.a 0
set ALLCMD_COUNT_.b 0

proc wait_add {group comp} {
    puts "$group: add $comp"
    lappend ::ALLCMD(list_$group) $comp
    incr ::ALLCMD_COUNT_$group 1
}
proc wait_del {group comp} {
    puts "$group: del $comp"
    set ::ALLCMD(list_$group) [lsearch -inline -all -not -exact $::ALLCMD(list_$group) $comp]
    incr ::ALLCMD_COUNT_$group -1
}

proc doIt {group} {
    $group state disabled
    set time 5000
    foreach n [list "foo" "bar" "abc" "def"] {
        wait_add $group $n
        after $time wait_del $group $n
        set time [expr $time - 1000]
    }

    while {[set ::ALLCMD_COUNT_$group] > 0} {
        puts "$group pending: $::ALLCMD(list_$group)"
        vwait ::ALLCMD_COUNT_$group
    }
    puts "$group: done"
    $group state !disabled
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
proc wait {time} {
    sleep [expr $time*1000]
    puts "timer for $time done"
}

pack [ttk::button .a -text "A" -command "doIt .a"]
pack [ttk::button .b -text "B" -command "doIt .b"]

pack [ttk::button .c -text "2s" -command "wait 2"]
pack [ttk::button .d -text "5s" -command "wait 5"]
