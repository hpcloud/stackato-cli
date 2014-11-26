# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations. Management of features.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::color
package require stackato::log
package require stackato::mgr::context
package require stackato::v2
package require table

debug level  cmd/features
debug prefix cmd/features {[debug caller] | }

namespace eval ::stackato::cmd {
    namespace export features
    namespace ensemble create
}
namespace eval ::stackato::cmd::features {
    namespace export list show enable disable
    namespace ensemble create

    namespace import ::cmdr::color
    namespace import ::stackato::log::display
    namespace import ::stackato::mgr::context
    namespace import ::stackato::v2
}

# # ## ### ##### ######## ############# #####################
# S3.6 commands

proc ::stackato::cmd::features::list {config} {
    debug.cmd/features {}

    set features [v2 feature_flag list]

    if {[$config @json]} {
	set tmp {}
	foreach o $features {
	    lappend tmp [$o as-json]
	}
	display [json::write array {*}$tmp]
	return
    }

    display [context format-target]

    if {![llength $features]} {
	display [color note "No Features"]
	return
    }

    [table::do t {Name State Overridden Default} {
	foreach o [v2 sort @name $features -dict] {
	    $t add \
		[color name [$o @name]] \
		[State [$o @enabled]] \
		[$o @overridden] \
		[State [$o @default_value]]
	    # overridden, default, error_message
	}
    }] show display

    return
}
proc ::stackato::cmd::features::show {config} {
    debug.cmd/features {}

    set feature [$config @name]

    if {[$config @json]} {
	display [$feature as-json]
	return
    }

    display [context format-target]
    [table::do t {Key Value} {
	$t add Name            [color name [$feature @name]]
	$t add State           [State [$feature @enabled]]
	$t add Overridden      [$feature @overridden]
	$t add Default         [State [$feature @default_value]]
	$t add {Error Message} [$feature @error_message]
    }] show display
    return
}

proc ::stackato::cmd::features::enable {config} {
    debug.cmd/features {}

    display [context format-target]
    set feature [$config @name]
    $feature @enabled set 1

    display "Enabling feature \[[color name [$feature @name]]\] ... " false
    $feature commit
    display [color good OK]
    return
}

proc ::stackato::cmd::features::disable {config} {
    debug.cmd/features {}

    display [context format-target]
    set feature [$config @name]
    $feature @enabled set 0

    display "Disabling feature \[[color name [$feature @name]]\] ... " false
    $feature commit
    display [color good OK]
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::features::State {x} {
    expr { $x ? "enabled" : "disabled" }
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::features 0

