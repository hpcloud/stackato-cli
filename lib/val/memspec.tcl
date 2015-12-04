# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Memory specifications.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::validate ;# Fail utility command.
package require fileutil

debug level  validate/memspec
debug prefix validate/memspec {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export memspec
    namespace ensemble create
}

namespace eval ::stackato::validate::memspec {
    namespace export default validate complete release format
    namespace ensemble create
    namespace import ::cmdr::validate::common::fail
}

proc ::stackato::validate::memspec::format {x} {
    # unit (x) = MB.
    # see also ::stackato::log::psz

    debug.validate/memspec {}
    if {$x < 1024} {
	set formatted ${x}M
    } else {
	set formatted [::format %.1f [expr {$x/1024.}]]G
    }
    debug.validate/memspec {= $formatted}
    return $formatted
}

proc ::stackato::validate::memspec::default  {p}   { return 0 }
proc ::stackato::validate::memspec::release  {p x} { return }
proc ::stackato::validate::memspec::complete {p x} {
    # Memory specifications can be plain integer, or
    # integer mega- and gigabytes, or fractional gigabytes.
    if {[string is int -strict $x]} {
	return [list $x ${x}M ${x}G]
    } elseif {[string is double -strict $x]} {
	return [list ${x}G]
    } else {
	return {}
    }
}

proc ::stackato::validate::memspec::validate {p x} {
    debug.validate/memspec {}
    # Acceptable input
    # n
    # nK
    # nM
    # nG, x.yG
    # Returns canonical memory value in integral megabytes.

    # See "mem_choice_to_quota" for the original converter/validator.

    # A plain number is memory in MB. Must be integer, double not
    # allowed.

    if {[string is int -strict $x]} {
	debug.validate/memspec {= $x}
	return $x
    } elseif {[string is double -strict $x]} {
	debug.validate/memspec {FAIL, plain double invalid}
	fail $p {STACKATO MEMORY} "a memory specification" $x
    }

    # Non-plain number, accept only M and G as units, and separate
    # value from unit.

    if {![regexp -nocase {^(.*)([mMgG])$} $x -> value unit]} {
	debug.validate/memspec {FAIL, bad unit}
	fail $p {STACKATO MEMORY} "a memory specification" $x
    }

    # The value must be a double at least.
    if {![string is double -strict $value]} {
	debug.validate/memspec {FAIL, !double}
	fail $p {STACKATO MEMORY} "a memory specification" $x
    }

    # But for megabytes we do not accept fractions.
    if {$unit in {m M}} {
	if {![string is int -strict $value]} {
	    debug.validate/memspec {FAIL, bad fraction for MB}
	    fail $p {STACKATO MEMORY} "a memory specification" $x
	}
	debug.validate/memspec {= $value}
	return $value
    }

    # Gigabytes are converted to integral megabytes.
    set value [expr {int($value * 1024)}]
    debug.validate/memspec {= $value}
    return $value
}

# # ## ### ##### ######## ############# #####################

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::memspec 0
