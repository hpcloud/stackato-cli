## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Command dispatcher framework.
## Knows about officers and privates.
## Encapsulates the creation of command hierachies.

# @@ Meta Begin
# Package cmdr 0
# Meta author   {Andreas Kupries}
# Meta location https://core.tcl.tk/akupries/cmdr
# Meta platform tcl
# Meta summary Main entry point to the commander framework.
# Meta description A framework for the specification and
# Meta description use of complex command line processing.
# Meta subject {command line} delegation dispatch options arguments
# Meta require TclOO
# Meta require cmdr::officer
# Meta require debug
# Meta require debug::caller
# Meta require {Tcl 8.5-}
# @@ Meta End

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require debug
package require debug::caller
package require TclOO
package require cmdr::officer

# # ## ### ##### ######## ############# #####################

debug define cmdr/main
debug level  cmdr/main
debug prefix cmdr/main {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::cmdr {
    namespace export new create interactive interactive?
    namespace ensemble create

    # Generally interaction is possible.
    variable interactive 1
}

# # ## ### ##### ######## #############

proc ::cmdr::new {name spec} {
    debug.cmdr/main {}
    return [cmdr::officer new {} $name $spec]
}

proc ::cmdr::create {obj name spec} {
    debug.cmdr/main {}
    # Uplevel to ensure proper namespace for the 'obj'.
    return [uplevel 1 [list cmdr::officer create $obj {} $name $spec]]
}

# # ## ### ##### ######## ############# #####################
## Global interactivity configuration.

proc ::cmdr::interactive {{enable 1}} {
    debug.cmdr/main {}
    variable interactive $enable
    return
}

proc ::cmdr::interactive? {} {
    variable interactive
    return  $interactive
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide cmdr 1.0
