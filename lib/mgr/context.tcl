# -*- tcl -*-
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
    namespace export format-org format-short format-large \
	get-name
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
    debug.mgr/context {}

    # TODO: Use get-name
    try {
	set o [corg get]
	if {$o eq {}} {
	    debug.mgr/context {==> NONE}
	    return <none>
	}

	set on [$o @name]
    } trap {STACKATO CLIENT AUTHERROR} {e options} - \
      trap {STACKATO CLIENT V2 AUTHERROR} {e options} {
	set lsuffix [color red "(not resolved: not logged in, or not authorized)"]
	set on "[$o id] $lsuffix"
    } trap {STACKATO CLIENT V2 NOTFOUND} {e options} {
	set lsuffix [color red "(not resolved: not found)"]
	set on "[$o id] $lsuffix"
    }

    debug.mgr/context {==> $on}
    return $on
}

proc ::stackato::mgr::context::GetSpace {} {
    debug.mgr/context {}

    # TODO: Use get-name
    try {
	set s [cspace get]
	if {$s eq {}} {
	    debug.mgr/context {==> NONE}
	    return <none>
	}
	set sn [$s @name]
    } trap {STACKATO CLIENT AUTHERROR} {e options} - \
      trap {STACKATO CLIENT V2 AUTHERROR} {e options} {
	set lsuffix [color red "(not resolved: not logged in, or not authorized)"]
	set sn "[$s id] $lsuffix"
    } trap {STACKATO CLIENT V2 NOTFOUND} {e options} {
	set lsuffix [color red "(not resolved: not found)"]
	set sn "[$s id] $lsuffix"
    }

    debug.mgr/context {==> $sn}
    return $sn
}

proc ::stackato::mgr::context::get-name {obj ev} {
    debug.mgr/context {}
    upvar 1 $ev err

    if {$obj eq {}} {
	debug.mgr/context {==> NONE}
	set err {not defined}
	return {}
    }

    try {
	set err {}
	set name [$obj @name]
    } trap {STACKATO CLIENT AUTHERROR} {e options} - \
      trap {STACKATO CLIENT V2 AUTHERROR} {e options} {
	  set err "not resolved: not logged in, or not authorized"
	  set name {}
    } trap {STACKATO CLIENT V2 NOTFOUND} {e options} {
	set err "not resolved: not found"
	set name {}
    }

    debug.mgr/context {==> $name}
    return $name
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::context 0
