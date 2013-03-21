# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################
#checker -scope global exclude warnUndefinedVar
# var in question is 'dir'.
if {![package vsatisfies [package provide Tcl] 8.5]} {
    # PRAGMA: returnok
    return
}

package ifneeded stackato::color    0 [list source [file join $dir color.tcl]]
package ifneeded stackato::form     0 [list source [file join $dir form.tcl]]
package ifneeded stackato::jmap     0 [list source [file join $dir jmap.tcl]]
package ifneeded stackato::yaml     0 [list source [file join $dir yaml.tcl]]
package ifneeded stackato::log      0 [list source [file join $dir log.tcl]]
package ifneeded stackato::string   0 [list source [file join $dir string.tcl]]
package ifneeded stackato::term     0 [list source [file join $dir term.tcl]]

package ifneeded tty                0 [list source [file join $dir tty.tcl]]
