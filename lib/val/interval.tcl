# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Time Interval specifications.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::validate ;# Fail utility command.
package require fileutil

debug level  validate/interval
debug prefix validate/interval {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export interval
    namespace ensemble create
}

namespace eval ::stackato::validate::interval {
    namespace export default validate complete release format
    namespace ensemble create
    namespace import ::cmdr::validate::common::fail
}

proc ::stackato::validate::interval::format {x} {
    # unit (x) = MB.
    # see also ::stackato::log::psz

    debug.validate/interval {}
    if {$x < 1024} {
	set formatted ${x}M
    } else {
	set formatted [::format %.1f [expr {$x/1024.}]]G
    }
    debug.validate/interval {= $formatted}
    return $formatted
}

proc ::stackato::validate::interval::default  {p}   { return 120 }
proc ::stackato::validate::interval::release  {p x} { return }
proc ::stackato::validate::interval::complete {p x} {
    # Interval specifications can be
    # - plain integer [seconds]
    # - integer seconds (s)
    # - integer minutes (m)
    # - integer hours   (h)
    # - integer days    (d)

    if {[string is int -strict $x]} {
	return [list $x ${x}s ${x}m ${x}h ${x}d]
    } else {
	return {}
    }
}

proc ::stackato::validate::interval::validate {p x} {
    debug.validate/interval {}
    # Acceptable input
    # <n>  - seconds
    # <n>s - seconds (== <n>)
    # <n>m - minutes (*    60)
    # <n>h - hours   (*  3600)
    # <n>d - days    (* 86400)
    # Returns canonical interval value in integral seconds.

    # A plain number is interval in seconds. Must be integer.

    if {[string is int -strict $x]} {
	debug.validate/interval {= $x}
	return $x
    }

    # Non-plain number, accept units [smhd], and separate value from
    # unit.

    if {![regexp -nocase {^(.*)([smhd])$} $x -> value unit]} {
	debug.validate/interval {FAIL, bad unit}
	fail $p {STACKATO INTERVAL} "a time interval specification" $x
    }

    # The value must be an integer. No fractions allowed.
    if {![string is int -strict $value]} {
	debug.validate/interval {FAIL, !int}
	fail $p {STACKATO INTERVAL} "a time interval specification" $x
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

    debug.validate/interval {= $value}
    return $value
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::interval 0
