## -*- tcl -*-
# # ## ### ##### ######## #############

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
