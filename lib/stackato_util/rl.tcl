# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5

namespace eval ::stackato::readline {}

::apply {{dir} {
    if {$::tcl_platform(platform) eq "windows"} {
	source [file join $dir rl_win.tcl]
    } else {
	source [file join $dir rl_unix.tcl]
    }
}} [file dirname [file normalize [info script]]]

# # ## ### ##### ######## ############# #####################

proc ::stackato::readline::columns {} {
    variable cols
    if {$cols eq {}} {
	set cols [platform-columns]
	#puts ||||$cols
    }
    return $cols
}

namespace eval ::stackato::readline {
    variable cols {}

    namespace export gets gets* tty columns
    namespace ensemble create
}

# # ## ### ##### ######## ############# #####################

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::readline 0
