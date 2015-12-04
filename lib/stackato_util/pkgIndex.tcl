# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

#checker -scope global exclude warnUndefinedVar
# var in question is 'dir'.
if {![package vsatisfies [package provide Tcl] 8.5]} {
    # PRAGMA: returnok
    return
}

package ifneeded stackato::form     0 [list source [file join $dir form.tcl]]
package ifneeded stackato::form2    0 [list source [file join $dir form2.tcl]]
package ifneeded stackato::jmap     0 [list source [file join $dir jmap.tcl]]
package ifneeded stackato::yaml     0 [list source [file join $dir yaml.tcl]]
package ifneeded stackato::log      0 [list source [file join $dir log.tcl]]
package ifneeded stackato::misc     0 [list source [file join $dir misc.tcl]]
package ifneeded stackato::string   0 [list source [file join $dir string.tcl]]
