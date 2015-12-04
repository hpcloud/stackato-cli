# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Memory specifications.
## Allow -1 and "unlimited" as inputs to specify unlimited memory.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::validate ;# Fail utility command.
package require fileutil

debug level  validate/memspecplus
debug prefix validate/memspecplus {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export memspecplus
    namespace ensemble create
}

namespace eval ::stackato::validate::memspecplus {
    namespace export default validate complete release format
    namespace ensemble create
    namespace import ::cmdr::validate::common::fail
}

proc ::stackato::validate::memspecplus::format {x} {
    # unit (x) = MB.
    # see also ::stackato::log::psz

    debug.validate/memspecplus {}
    if {$x < 0} {
	set formatted unlimited
    } elseif {$x < 1024} {
	set formatted ${x}M
    } else {
	set formatted [::format %.1f [expr {$x/1024.}]]G
    }
    debug.validate/memspecplus {= $formatted}
    return $formatted
}

proc ::stackato::validate::memspecplus::default  {p}   { return 0 }
proc ::stackato::validate::memspecplus::release  {p x} { return }
proc ::stackato::validate::memspecplus::complete {p x} {
    # Memory specifications can be plain integer, or
    # integer mega- and gigabytes, or fractional gigabytes.
    # Also allow -1 and "unlimited".
    if {[string is int -strict $x]} {
	return [list $x ${x}M ${x}G]
    } elseif {[string is double -strict $x]} {
	return [list ${x}G]
    } else {
	return [complete-enum {unlimited -1} 0 $x]
    }
}

proc ::stackato::validate::memspecplus::validate {p x} {
    debug.validate/memspecplus {}
    # Acceptable input
    # n (>= 0)
    # nK
    # nM
    # nG, x.yG
    # -1
    # "unlimited"
    # Returns canonical memory value in integral megabytes.

    # See "mem_choice_to_quota" for the original converter/validator.

    # A plain number is memory in MB. Must be integer, double not
    # allowed.

    if {$x in {unlimited -1}} {
	debug.validate/memspecplus {= -1 (unlimited)}
	return -1
    }

    if {[string is int -strict $x]} {
	debug.validate/memspecplus {= $x}
	return $x
    } elseif {[string is double -strict $x]} {
	debug.validate/memspecplus {FAIL, plain double invalid}
	fail $p {STACKATO MEMORY} "a memory specification" $x
    }

    # Non-plain number, accept only M and G as units, and separate
    # value from unit.

    if {![regexp -nocase {^(.*)([mMgG])$} $x -> value unit]} {
	debug.validate/memspecplus {FAIL, bad unit}
	fail $p {STACKATO MEMORY} "a memory specification" $x
    }

    # The value must be a double at least.
    if {![string is double -strict $value]} {
	debug.validate/memspecplus {FAIL, !double}
	fail $p {STACKATO MEMORY} "a memory specification" $x
    }

    # But for megabytes we do not accept fractions.
    if {$unit in {m M}} {
	if {![string is int -strict $value]} {
	    debug.validate/memspecplus {FAIL, bad fraction for MB}
	    fail $p {STACKATO MEMORY} "a memory specification" $x
	}
	debug.validate/memspecplus {= $value}
	return $value
    }

    # Gigabytes are converted to integral megabytes.
    set value [expr {int($value * 1024)}]
    debug.validate/memspecplus {= $value}
    return $value
}

# # ## ### ##### ######## ############# #####################

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::memspecplus 0
