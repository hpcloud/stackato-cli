if {![package vsatisfies [package require Tcl] 8.5]} return
package ifneeded sdebug      1.0 [list source [file join $dir debug.tcl]]
package ifneeded debug::snit 0.1 [list source [file join $dir debug_snit.tcl]]
