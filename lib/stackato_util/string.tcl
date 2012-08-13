# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5

namespace eval ::stackato::string {}

# # ## ### ##### ######## ############# #####################

proc ::stackato::string::truncate {str {limit 80}} {
    if {[blank? $str]} {return {}}
    set etc ...

    set stripped [string range [string trim $str] 0 $limit]
    if {[string length $stripped] <= $limit} {
	return $stripped
    }

    return [regsub {\s+?(\S+)?} $stripped {}]$etc
}

proc ::stackato::string::blank? {str} {
    regexp {^\s*$} $str
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::string {
    namespace export blank truncate
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::string 0
