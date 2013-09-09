# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require dict

namespace eval ::varsub {}

proc ::varsub::resolve {str resolver} {
    # Simplified RE compared to vmc, using 'string trim' to get
    # rid of whitespace around the actual variable name. Using
    # --all --inline to get the matches in one step, and to avoid
    # processing variable references which might be introduced

    # matches - array of unique varnames encountered, and associated value.
    # map     - array from unique references to associated value.
    # Multiple references may use the same variable.

    set all [regexp -all -inline -- {\${([^\}]+)}} $str]
    foreach {match fullvarname} $all {
	set varname [string trim $fullvarname]
	set ref "\$\{$fullvarname\}"
	if {[info exists matches($varname)]} {
	    set map($ref) $matches($varname)
	    continue
	}

	set value [{*}$resolver $varname]

	set matches($varname) $value
	set map($ref) $matches($varname)
    }

    #parray matches
    #parray map

    set str [string map [array get map] $str]
    return $str
}


package provide varsub 0
