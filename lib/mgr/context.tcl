# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## This module sits on top of ctarget, corg, cspace to provide
## general context information in one go for display and the like.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::color
package require stackato::log
package require stackato::mgr::corg
package require stackato::mgr::cspace
package require stackato::mgr::ctarget

namespace eval ::stackato::mgr {
    namespace export context
    namespace ensemble create
}

namespace eval ::stackato::mgr::context {
    namespace export format-target format-org format-short format-large \
	get-name 2org
    namespace ensemble create

    namespace import ::cmdr::color
    namespace import ::stackato::log::display
    namespace import ::stackato::mgr::corg
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::mgr::ctarget
}

debug level  mgr/context
debug prefix mgr/context {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## API

proc ::stackato::mgr::context::2org {config theorg} {
    # Requires @space slot.
    debug.mgr/context {}

    display "Switching to organization [$theorg @name] ... " false
    corg set $theorg
    corg save
    display [color good OK]

    # Update current space ...
    # Make the user choose a space if none is defined.
    # (or auto-choose if only one space possible).
    set thespace [cspace get-auto [$config @space self]]

    # The remembered space does not belong to the newly chosen
    # org. Make the user choose a new space (or auto-choose,
    # see above).
    if {![$thespace @organization == $theorg]} {
	# Flush, fully (i.e. down to the persistent state).
	cspace reset
	cspace save
	# ... and ask for new.
	cspace get-auto [$config @space self]
    }

    display [color good OK]

    debug.mgr/context {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::context::format-target {{suffix {}}} {
    debug.mgr/context {}
    set t [ctarget get]

    debug.mgr/context {/done ==> "$t$suffix"}
    return "[color name $t]$suffix"
}

proc ::stackato::mgr::context::format-org {{suffix {}}} {
    debug.mgr/context {}
    set t [ctarget get]
    set o [GetOrg]

    debug.mgr/context {/done ==> "$t -> $o$suffix"}
    return "[color name $t] -> $o$suffix"
}

proc ::stackato::mgr::context::format-short {{suffix {}}} {
    debug.mgr/context {}
    format-org " -> [GetSpace]$suffix"
}

proc ::stackato::mgr::context::format-large {} {
    debug.mgr/context {}

    set t [ctarget get]
    set o [GetOrg]
    set s [GetSpace]

    lappend lines "Target:       [color name $t]"
    lappend lines "Organization: $o"
    lappend lines "Space:        $s"

    debug.mgr/context {/done}
    return [join $lines \n]
}

proc ::stackato::mgr::context::GetOrg {} {
    debug.mgr/context {}

    # TODO: Use get-name
    try {
	set o [corg get]
	if {$o eq {}} {
	    debug.mgr/context {==> NONE}
	    return [color note <none>]
	}

	set on [color name [$o @name]]
    } trap {STACKATO CLIENT AUTHERROR} {e options} - \
      trap {STACKATO CLIENT V2 AUTHERROR} {e options} {
	set lsuffix [color bad "(not resolved: $e)"]
	  set on "[color name [corg get-id]] $lsuffix"
    } trap {STACKATO CLIENT V2 NOTFOUND} {e options} {
	# cannot happen anymore. corg discarded data, returned <none>
	set lsuffix [color bad "(not resolved: not found)"]
	set on "[color name [$o id]] $lsuffix"
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
	    return [color note <none>]
	}
	set sn [color name [$s @name]]
    } trap {STACKATO CLIENT AUTHERROR} {e options} - \
      trap {STACKATO CLIENT V2 AUTHERROR} {e options} {
	set lsuffix [color bad "(not resolved: $e)"]
	  set sn "[color name [cspace get-id]] $lsuffix"
    } trap {STACKATO CLIENT V2 NOTFOUND} {e options} {
	# cannot happen anymore. cspace discarded data, returned <none>
	set lsuffix [color bad "(not resolved: not found)"]
	set sn "[color name [$s id]] $lsuffix"
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
