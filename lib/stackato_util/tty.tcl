## -*- tcl -*-
# # ## ### ##### ######## #############

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tclx

# # ## ### ##### ######## #############

namespace eval tty {
    namespace export *
    namespace ensemble create
}

if {$::tcl_platform(platform) eq "windows"} {
    proc ::tty::stdout {} { return 0 }
} else {
    proc ::tty::stdout {} { fstat stdout tty }
}

# # ## ### ##### ######## #############
package provide tty 0
