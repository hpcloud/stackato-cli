# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::client::cli::command::Base

debug level  cli/memory/support
debug prefix cli/memory/support {[::debug::snit::call] | }

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::client::cli::command::MemHelp {
    superclass ::stackato::client::cli::command::Base

    # # ## ### ##### ######## #############

    constructor {args} {
	Debug.cli/memory/support {}
	next {*}$args
    }

    destructor {
	Debug.cli/memory/support {}
    }

    # # ## ### ##### ######## #############

    method mem_choice_to_quota {mem_choice} {
	Debug.cli/memory/support {}

	# Plain number is memory in MB. Must be integer, double not
	# allowed.

	if {[string is int $mem_choice]} {
	    return $mem_choice
	} elseif {[string is double $mem_choice]} {
	    return -code error -errorcode {STACKATO CLIENT CLI BAD MEMORY} \
		"Bad memory specification: Non-integer value in \"${mem_choice}M\""
	}

	# Non-plain number, accept only M and G as units, and separate
	# value from unit.

	if {![regexp -nocase {([MG])$} $mem_choice -> unit]} {
	    return -code error -errorcode {STACKATO CLIENT CLI BAD MEMORY} \
		"Bad memory specification: Unknown unit letter in \"$mem_choice\""
	}
	set mem_value [string range $mem_choice 0 end-1]

	# Must be double at least.
	if {![string is double $mem_value]} {
	    return -code error -errorcode {STACKATO CLIENT CLI BAD MEMORY} \
		"Bad memory specification: Non-numeric value in \"$mem_choice\""
	}

	# But for MB we do not accept fractions.
	if {$unit in {m M}} {
	    if {![string is int $mem_value]} {
		return -code error -errorcode {STACKATO CLIENT CLI BAD MEMORY} \
		    "Bad memory specification: Non-integer value in \"$mem_choice\""
	    }
	    return $mem_value
	}

	return [expr {int($mem_value * 1024)}]
    }

    # # ## ### ##### ######## #############
    ## State

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::client::cli::command::MemHelp 0
