## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Host:Port information.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::validate ;# Fail utility command.

debug level  validate/hostport
debug prefix validate/hostport {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export hostport
    namespace ensemble create
}

namespace eval ::stackato::validate::hostport {
    namespace export default validate complete release
    namespace ensemble create
    namespace import ::cmdr::validate::common::fail
}

proc ::stackato::validate::hostport::default  {p}   { return {} }
proc ::stackato::validate::hostport::release  {p x} { return }
proc ::stackato::validate::hostport::complete {p x} { return {} }

proc ::stackato::validate::hostport::validate {p x} {
    debug.validate/hostport {}

    # Must contain colon separator.
    # Must contain colon separator only once (2 list elements).
    # 2nd element must be proper integer > 0 (not empty implied).
    # 1st element must not be empty.

    if {![string match *:* $x]}          { Fail $p $x {missing colon} }

    set hp [split $x :]
    if {[llength $hp] != 2}              { Fail $p $x {not 2 elements} }

    lassign $hp h p
    if {![string is integer -strict $p]} { Fail $p $x {port not integer} }
    if {$p <= 0}                         { Fail $p $x {port <= 0} }
    if {$h eq {}}                        { Fail $p $x {empty host name} }

    debug.validate/hostport {= OK}
    return $hp
}

proc ::stackato::validate::hostport::Fail {p x msg} {
    debug.validate/hostport {= FAIL, $msg}
    fail $p HOSTPORT "a host:port" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::hostport 0
