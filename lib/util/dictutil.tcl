# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################
# package require dict

namespace eval ::dictutil {}

proc ::dictutil::validate {dict} {
    if {[llength $dict] % 2 == 1} {
	return -code error -errorcode {STACKATO SERVER DATA ERROR} \
	    "Expected a dictionary, got \"$dict\""
    }
}

# get value for key, with custom default if key not present.
proc ::dictutil::get' {dict args} {
    if {[llength $dict] % 2 == 1} {
	return -code error -errorcode {STACKATO SERVER DATA ERROR} \
	    "Expected a dictionary, got \"$dict\""
    }
    set keys [lrange $args 0 end-1]
    if {[dict exists $dict {*}$keys]} {
	return [dict get $dict {*}$keys]
    } else {
	return [lindex $args end]
    }
}

# get value for key, throw custom stackato error if missing.
proc ::dictutil::getit {dict args} {
    if {[llength $dict] % 2 == 1} {
	return -code error -errorcode {STACKATO SERVER DATA ERROR} \
	    "Expected a dictionary, got \"$dict\""
    }
    if {![dict exists $dict {*}$args]} {
	return -code error -errorcode {STACKATO SERVER DATA ERROR} \
	    "Missing value for key \"$args\""
    }
    return [dict get $dict {*}$args]
}

proc ::dictutil::sort {dict args} {
    set res {}
    foreach key [lsort {*}$args [dict keys $dict]] {
        dict set res $key [dict get $dict $key] 
    }
    return $res
}

proc ::dictutil::print {dict {pattern *}} {
    set maxl 0
    set names [lsort -dict [dict keys $dict $pattern]]
    foreach name $names {
        if {[string length $name] > $maxl} {
            set maxl [string length $name]
        }
    }

    set lines {}

    set maxl [expr {$maxl + 2}]
    foreach name $names {
        lappend lines [format "%-*s = %s" \
			   $maxl $name \
			   [dict get $dict $name]]
    }

    return [join $lines \n]
}

proc ::dictutil::printx {prefix dict {pattern *}} {
    set maxl 0
    set names [lsort -dict [dict keys $dict $pattern]]
    foreach name $names {
        if {[string length $name] > $maxl} {
            set maxl [string length $name]
        }
    }

    set lines {}

    set maxl [expr {$maxl + 2}]
    foreach name $names {
        lappend lines $prefix[format "%-*s = %s" \
				  $maxl $name \
				  [dict get $dict $name]]
    }

    return [join $lines \n]
}

namespace ensemble configure dict \
    -map [linsert [namespace ensemble configure dict -map] end \
	      validate ::dictutil::validate \
	      print    ::dictutil::print \
	      printx   ::dictutil::printx \
	      sort     ::dictutil::sort \
	      getit    ::dictutil::getit \
	      get'     ::dictutil::get']

package provide dictutil 0
