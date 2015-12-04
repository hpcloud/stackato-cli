# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

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
package require try

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

    if {![$config @json]} {
	display "Feature-flags: [context format-target]"
    }

    set features [v2 feature_flag list]

    if {[$config @json]} {
	set tmp {}
	foreach o $features {
	    lappend tmp [$o as-json]
	}
	display [json::write array {*}$tmp]
	return
    }

    if {![llength $features]} {
	display [color note "No Features"]
	return
    }

    [table::do t {Name State Overridden Default} {
	foreach o [v2 sort @name $features -dict] {
	    set name    [color name [$o @name]]
	    set enabled [State [$o @enabled]]
	    try {
		set over [$o @overridden]
	    } trap {STACKATO CLIENT V2 UNDEFINED ATTRIBUTE} {e opt} {
		# opt, to not clash with iteraton variable o
		set over [color bad {<<not supplied>>}]
	    }
	    try {
		set defvalue [State [$o @default_value]]
	    } trap {STACKATO CLIENT V2 UNDEFINED ATTRIBUTE} {e opt} {
		# opt, to not clash with iteraton variable o
		set defvalue [color bad {<<not supplied>>}]
	    }

	    $t add $name $enabled $over $defvalue
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
	set name    [color name [$feature @name]]
	set enabled [State [$feature @enabled]]
	set errmsg  [$feature @error_message]

	try {
	    set over [$feature @overridden]
	} trap {STACKATO CLIENT V2 UNDEFINED ATTRIBUTE} {e o} {
	    set over [color bad {<<not supplied by target>>}]
	}
	try {
	    set default [State [$feature @default_value]]
	} trap {STACKATO CLIENT V2 UNDEFINED ATTRIBUTE} {e o} {
	    set default [color bad {<<not supplied by target>>}]
	}

	$t add Name            $name
	$t add State           $enabled
	$t add Overridden      $over
	$t add Default         $default
	$t add {Error Message} $errmsg
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

