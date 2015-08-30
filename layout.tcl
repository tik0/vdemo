#!/usr/bin/wish

frame .f1
label .f1.t -text "This widget is at the top"    -bg red
label .f1.b -text "This widget is at the bottom" -bg green
label .f1.l -text "Left\nHand\nSide"
label .f1.r -text "Right\nHand\nSide"
label .f1.mid -text "This layout is like Java's BorderLayout"

frame .f2
label .f2.a -text "foo" -bg yellow
label .f2.b -text "foo" -bg yellow
label .f2.c -text "foo" -bg yellow
label .f2.d -text "foo" -bg yellow

# Lay them out
pack .f1 -side left
pack .f1.l   -side left   -fill y
pack .f1.r   -side right  -fill y
pack .f1.t   -side top    -fill x
pack .f1.b   -side bottom -fill x
pack .f1.mid -expand 1    -fill both

pack .f2 -side top
pack .f2.a .f2.b .f2.c .f2.d -side top -fill x
