# -*- tcl -*-
# # ## ### ##### ######## ############# #####################
# # ## ### ##### ######## ############# #####################

package require Tcl 8.5

# # ## ### ##### ######## ############# #####################

namespace eval ::url {
    namespace export base canon domain
    namespace ensemble create
}

# # ## ### ##### ######## ############# #####################

proc ::url::base {url} {
    return [join [lrange [split $url .] 1 end] .]
}

proc ::url::domain {url} {
    regsub ^https?:// $url {} url
    return $url
}

proc ::url::canon {url} {
    #checker -scope local exclude warnArgWrite
    if {![regexp {^https?://} $url]} {
	set url https://$url
    }
    return [string trimright $url /]
}

# # ## ### ##### ######## ############# #####################

package provide url 0
