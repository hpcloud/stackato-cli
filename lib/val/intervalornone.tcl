## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Time Interval specifications, or NONE.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::validate ;# Fail utility command.
package require fileutil

debug level  validate/intervalornone
debug prefix validate/intervalornone {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export intervalornone
    namespace ensemble create
}

namespace eval ::stackato::validate::intervalornone {
    namespace export default validate complete release
    namespace ensemble create
    namespace import ::cmdr::validate::common::fail
}

proc ::stackato::validate::intervalornone::default  {p}   { return none }
proc ::stackato::validate::intervalornone::release  {p x} { return }
proc ::stackato::validate::intervalornone::complete {p x} {
    # Intervalornone specifications can be
    # - "", "default, or "none"
    # - plain integer [seconds]
    # - integer seconds (s)
    # - integer minutes (m)
    # - integer hours   (h)
    # - integer days    (d)

    if {[string is int -strict $x]} {
	return [list $x ${x}s ${x}m ${x}h ${x}d]
    } else {
	return [complete-enum {default none {}} 0 $x]
    }
}

proc ::stackato::validate::intervalornone::validate {p x} {
    debug.validate/intervalornone {}
    # Acceptable input
    # "", "default, or "none"
    # <n>  - seconds
    # <n>s - seconds (== <n>)
    # <n>m - minutes (*    60)
    # <n>h - hours   (*  3600)
    # <n>d - days    (* 86400)
    # Returns canonical intervalornone value in integral seconds.

    # Special values for 'no interval'.

    if {$x in {{} default none}} {
	debug.validate/intervalornone {= $x}
	return $x
    }

    # A plain number is interval in seconds. Must be integer.

    if {[string is int -strict $x]} {
	debug.validate/intervalornone {= $x}
	return $x
    }

    # Non-plain number, accept units [smhd], and separate value from
    # unit.

    if {![regexp -nocase {^(.*)([smhd])$} $x -> value unit]} {
	debug.validate/intervalornone {FAIL, bad unit}
	fail $p {STACKATO INTERVALORNONE} "a time interval specification, or none" $x
    }

    # The value must be an integer. No fractions allowed.
    if {![string is int -strict $value]} {
	debug.validate/interval {FAIL, !int}
	fail $p {STACKATO INTERVALORNONE} "a time interval specification, or none" $x
    }

    # Convert value to seconds as per the units.
    switch -exact -- $unit {
	s {
	    # no conversion required.
	}
	m {
	    set value [expr {int($value * 60)}]	}
	h {
	    set value [expr {int($value * 3600)}]
	}
	d {
	    set value [expr {int($value * 86400)}]
	}
	default { error "Cannot happen" }
    }

    debug.validate/intervalornone {= $value}
    return $value
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::intervalornone 0
