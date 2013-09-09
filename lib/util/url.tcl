# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5

# # ## ### ##### ######## ############# #####################

namespace eval ::url {
    namespace export base canon
    namespace ensemble create
}

# # ## ### ##### ######## ############# #####################

proc ::url::base {url} {
    return [join [lrange [split $url .] 1 end] .]
}

proc ::url::canon {url} {
    #checker -scope local exclude warnArgWrite
    if {![regexp {^https?} $url]} {
	set url https://$url
    }
    return [string trimright $url /]
}

# # ## ### ##### ######## ############# #####################

package provide url 0
