# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

# -*- tcl -*-
# # ## ### ##### ######## ############# #####################
# # ## ### ##### ######## ############# #####################

package require Tcl 8.5

# # ## ### ##### ######## ############# #####################

namespace eval ::url {
    namespace export base canon domain ws
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

proc ::url::ws {url} {
    #checker -scope local exclude warnArgWrite
    regsub {^http:/}  $url {ws:/} url
    regsub {^https:/} $url {wss:/} url
    return $url
}

# # ## ### ##### ######## ############# #####################

package provide url 0
