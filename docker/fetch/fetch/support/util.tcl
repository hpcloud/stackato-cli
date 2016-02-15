## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## CMDR - Util - General utilities

# @@ Meta Begin
# Package cmdr::util 0
# Meta author   {Andreas Kupries}
# Meta location https://core.tcl.tk/akupries/cmdr
# Meta platform tcl
# Meta summary     Internal. General utilities.
# Meta description Internal. General utilities.
# Meta subject {command line}
# Meta require {Tcl 8.5-}
# Meta require textutil::adjust
# Meta require debug
# Meta require debug::caller
# @@ Meta End

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require debug
package require debug::caller

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::cmdr {
    namespace export util
    namespace ensemble create
}

namespace eval ::cmdr::util {
    namespace export padr dictsort
    namespace ensemble create
}

# # ## ### ##### ######## ############# #####################

debug define cmdr/util
debug level  cmdr/util
debug prefix cmdr/util {[debug caller] | }

# # ## ### ##### ######## ############# #####################

proc ::cmdr::util::padr {list} {
    debug.cmdr/util {}
    if {[llength $list] <= 1} {
	return $list
    }
    set maxl 0
    foreach str $list {
	set l [string length $str]
	if {$l <= $maxl} continue
	set maxl $l
    }
    set res {}
    foreach str $list { lappend res [format "%-*s" $maxl $str] }
    return $res
}

proc ::cmdr::util::dictsort {dict} {
    set r {}
    foreach k [lsort -dict [dict keys $dict]] {
	lappend r $k [dict get $dict $k]
    }
    return $r
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide cmdr::util 1.0
