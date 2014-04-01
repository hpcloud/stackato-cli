## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Integer values [0..100]

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::validate ;# Fail utility command.

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export percent-int
    namespace ensemble create
}

namespace eval ::stackato::validate::percent-int {
    namespace export default validate complete release
    namespace ensemble create
    namespace import ::cmdr::validate::common::fail
}

proc ::stackato::validate::percent-int::default  {p}   { return 0 }
proc ::stackato::validate::percent-int::release  {p x} { return }
proc ::stackato::validate::percent-int::complete {p x} { return {} }

proc ::stackato::validate::percent-int::validate {p x} {
    if {[string is integer -strict $x] && ($x >= 0) && ($x <= 100)} { return $x }
    fail $p PERCENT-INT "an integral percentage" $x
}

# # ## ### ##### ######## ############# #####################

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::percent-int 0
