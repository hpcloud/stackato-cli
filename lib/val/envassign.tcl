## -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Host:Port information.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::validate ;# Fail utility command.

debug level  validate/envassign
debug prefix validate/envassign {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export envassign
    namespace ensemble create
}

namespace eval ::stackato::validate::envassign {
    namespace export default validate complete release
    namespace ensemble create
    namespace import ::cmdr::validate::common::fail
}

proc ::stackato::validate::envassign::default  {p}   { return 0 }
proc ::stackato::validate::envassign::release  {p x} { return }
proc ::stackato::validate::envassign::complete {p x} { return {} }

proc ::stackato::validate::envassign::validate {p x} {
    debug.validate/envassign {}
    # Must contain = separator.
    # varname must not be empty, vaue can be

    if {![string match *=* $x]}               { Fail $p $x {missing assignment} }
    if {![regexp {^([^=]*)=(.*)$} $x -> k v]} { Fail $p $x internal }
    if {$k eq {}}                             { Fail $p $x {empty varname} }

    debug.validate/envassign {= OK}
    # FUTURE: cmdr conversion to k/v list, not pairs as now.
    return [list $k $v]
}

proc ::stackato::validate::envassign::Fail {p x msg} {
    debug.validate/envassign {= FAIL, $msg}
    fail $p ENVASSIGN "an assignment" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::envassign 0
