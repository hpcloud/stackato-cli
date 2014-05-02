## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Key:\s*Value information.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::validate ;# Fail utility command.

debug level  validate/http-header
debug prefix validate/http-header {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export http-header
    namespace ensemble create
}

namespace eval ::stackato::validate::http-header {
    namespace export default validate complete release
    namespace ensemble create
    namespace import ::cmdr::validate::common::fail
}

proc ::stackato::validate::http-header::default  {p}   { return {} }
proc ::stackato::validate::http-header::release  {p x} { return }
proc ::stackato::validate::http-header::complete {p x} { return {} }

proc ::stackato::validate::http-header::validate {p x} {
    debug.validate/http-header {}

    # Must contain colon separator.
    # Must contain colon separator only once (2 list elements).
    # 1st element must not be empty.

    if {![string match *:* $x]} {
	Fail $p $x {missing colon}
    }

    # Note: While colon (:) is the separator of key and value the
    #       value is allowed to and may contain further colons.
    # So we search only for the first colon to split, and split via regexp.

    if {![regexp {^([^:]*):(.*)$} $x -> k v]} {
	Fail $p $x {bad syntax}
    }

    if {$k eq {}} {
	Fail $p $x {empty key name}
    }

    debug.validate/http-header {= OK}

    # normalize, strip leading/trailing white space out of each part.
    set k [string trim $k]
    set v [string trim $v]

    return [list $k $v]
}

proc ::stackato::validate::http-header::Fail {p x msg} {
    debug.validate/http-header {= FAIL, $msg}
    fail $p HTTP-HEADER "a http header assignment" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::http-header 0
