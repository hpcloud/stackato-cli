
# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP @date@

# Tcl package index file, version 1.1

if {![package vsatisfies [package provide Tcl] 8.4]} {return}
package ifneeded s-http 2.7.13 [list source [file join $dir http.tcl]]
