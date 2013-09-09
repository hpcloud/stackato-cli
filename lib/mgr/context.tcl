# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

## This module sits on top of ctarget, corg, cspace to provide
## general context information in one go for display and the like.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require stackato::color
package require stackato::mgr::corg
package require stackato::mgr::cspace
package require stackato::mgr::ctarget

namespace eval ::stackato::mgr {
    namespace export context
    namespace ensemble create
}

namespace eval ::stackato::mgr::context {
    namespace export format-org format-short format-large
    namespace ensemble create

    namespace import ::stackato::color
    namespace import ::stackato::mgr::corg
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::mgr::ctarget
}

debug level  mgr/context
debug prefix mgr/context {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## API

proc ::stackato::mgr::context::format-org {{suffix {}}} {
    set t [ctarget get]
    set o [GetOrg]

    return "$t -> $o$suffix"
}

proc ::stackato::mgr::context::format-short {{suffix {}}} {
    format-org " -> [GetSpace]$suffix"
}

proc ::stackato::mgr::context::format-large {} {
    debug.mgr/context {}

    set t [ctarget get]
    set o [GetOrg]
    set s [GetSpace]

    lappend lines "Target:       $t"
    lappend lines "Organization: $o"
    lappend lines "Space:        $s"

    return [join $lines \n]
}

proc ::stackato::mgr::context::GetOrg {} {
    set o [corg get]
    if {$o eq {}} {
	return <none>
    }

    try {
	set on [$o @name]
    } trap {STACKATO CLIENT AUTHERROR} {e options} {
	set lsuffix [color red "(not resolved, not logged in)"]
	set on "[$o id] $lsuffix"
    } trap {STACKATO CLIENT V2 NOTFOUND} {e options} {
	set lsuffix [color red "(not resolved, not found)"]
	set on "[$o id] $lsuffix"
    }

    return $on
}

proc ::stackato::mgr::context::GetSpace {} {
    set s [cspace get]
    if {$s eq {}} {
	return <none>
    }

    try {
	set sn [$s @name]
    } trap {STACKATO CLIENT AUTHERROR} {e options} {
	set lsuffix [color red "(not resolved, not logged in)"]
	set sn "[$s id] $lsuffix"
    } trap {STACKATO CLIENT V2 NOTFOUND} {e options} {
	set lsuffix [color red "(not resolved, not found)"]
	set sn "[$s id] $lsuffix"
    }

    return $sn
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::context 0
