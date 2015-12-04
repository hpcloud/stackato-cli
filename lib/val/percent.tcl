# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

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
    namespace export percent
    namespace ensemble create
}

namespace eval ::stackato::validate::percent {
    namespace export default validate complete release
    namespace ensemble create
    namespace import ::cmdr::validate::common::fail
}

proc ::stackato::validate::percent::default  {p}   { return 0 }
proc ::stackato::validate::percent::release  {p x} { return }
proc ::stackato::validate::percent::complete {p x} { return {} }

proc ::stackato::validate::percent::validate {p x} {
    if {[string is double -strict $x] && ($x >= 0) && ($x <= 100)} { return $x }
    fail $p PERCENT "a percentage" $x
}

# # ## ### ##### ######## ############# #####################

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::percent 0
