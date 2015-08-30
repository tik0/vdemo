#!/usr/bin/wish

set i 0

# event-handling sleep, see http://www2.tcl.tk/933
proc uniqkey { } {
    set key   [ expr { pow(2,31) + [ clock clicks ] } ]
    set key   [ string range $key end-8 end-3 ]
    set key   [ clock seconds ]$key
    puts $key
    return $key
}

proc sleep { ms } {
    set uniq [ uniqkey ]
    set ::__sleep__tmp__$uniq 0
    after $ms set ::__sleep__tmp__$uniq 1
    vwait ::__sleep__tmp__$uniq
    unset ::__sleep__tmp__$uniq
}

proc evt {d} {
    global i;
    set time [clock milliseconds]
    puts "entered [expr ($time / 1000) % 100]:[expr $time % 1000]"
    if { $d > 0 } {
        # time smaller 500 causes the next sleeps to finish simultaneously
        after 500 [list evt -2]
    }
    sleep 1000
    set time [clock milliseconds]
    incr i $d;
    puts "val: $d $i [expr ($time / 1000) % 100]:[expr $time % 1000]"
}

pack [button .a -text "Press Me" -command "evt 1"]
pack [button .b -text "Dont Press Me" -command "evt -1"]
