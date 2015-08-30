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

pack [ttk::button .a -text "A" -command "doIt .a"]
pack [ttk::button .b -text "B" -command "doIt .b"]
