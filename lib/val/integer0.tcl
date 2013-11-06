## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Integer values >= 0

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::validate ;# Fail utility command.

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export integer0
    namespace ensemble create
}

namespace eval ::stackato::validate::integer0 {
    namespace export default validate complete release
    namespace ensemble create
    namespace import ::cmdr::validate::common::fail
}

proc ::stackato::validate::integer0::default  {p}   { return 0 }
proc ::stackato::validate::integer0::release  {p x} { return }
proc ::stackato::validate::integer0::complete {p x} { return {} }

proc ::stackato::validate::integer0::validate {p x} {
    if {[string is integer -strict $x] && ($x >= 0)} { return $x }
    fail $p INTEGER0 "an integer >= 0" $x
}

# # ## ### ##### ######## ############# #####################

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::integer0 0
