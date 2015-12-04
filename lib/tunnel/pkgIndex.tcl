# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

#checker -scope global exclude warnUndefinedVar
# var in question is 'dir'.
if {![package vsatisfies [package provide Tcl] 8.5]} {
    # PRAGMA: returnok
    return
}

# tunneling support.
package ifneeded tunnel       0 [list source [file join $dir tunnel.tcl]]
package ifneeded tunnel::http 0 [list source [file join $dir http.tcl]]

