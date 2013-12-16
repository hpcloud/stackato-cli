# Tcl package index file, version 1.1

if {![package vsatisfies [package provide Tcl] 8.4]} {return}
package ifneeded s-http 2.7.13 [list source [file join $dir http.tcl]]
