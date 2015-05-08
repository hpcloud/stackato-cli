# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations. Management of placement zones.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::ask
package require cmdr::color
package require stackato::cmd::app
package require stackato::log
package require stackato::mgr::client ; # pulls all of v2
package require stackato::mgr::context
package require stackato::mgr::ctarget
package require stackato::mgr::manifest
package require table

debug level  cmd/zones
debug prefix cmd/zones {[debug caller] | }

namespace eval ::stackato::cmd {
    namespace export zones
    namespace ensemble create
}
namespace eval ::stackato::cmd::zones {
    namespace export \
	set unset list show select-for
    namespace ensemble create

    namespace import ::cmdr::ask
    namespace import ::cmdr::color
    namespace import ::stackato::cmd::app
    namespace import ::stackato::log::display
    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::context
    namespace import ::stackato::mgr::ctarget
    namespace import ::stackato::mgr::manifest
    namespace import ::stackato::v2
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::zones::set {config} {
    debug.cmd/zones {}
    manifest user_1app each $config ::stackato::cmd::zones::Set
    return
}

proc ::stackato::cmd::zones::Set {config theapp} {
    debug.cmd/zones {}

    ::set z [[$config @zone] @name]
    # get entity name, for - app zone attribute :: string (not entity ref!)

    display "Setting placement zone of \"[$theapp @name]\" to \"$z\" ... " false

    SetCore $config $theapp $z
    return
}

proc ::stackato::cmd::zones::unset {config} {
    debug.cmd/zones {}
    manifest user_1app each $config ::stackato::cmd::zones::Unset
    return
}

proc ::stackato::cmd::zones::Unset {config theapp} {
    debug.cmd/zones {}
    display "Drop placement zone from \"[$theapp @name]\" ... " false

    SetCore $config $theapp default
    return
}

proc ::stackato::cmd::zones::SetCore {config theapp newzone} {
    debug.cmd/zones {}

    if {![$theapp @distribution_zone defined?] ||
	($newzone ne [$theapp @distribution_zone])} {

	$theapp @distribution_zone set $newzone
	$theapp commit

	display [color good OK]

	app check-app-for-restart $config $theapp
    } else {
	display [color note Unchanged]
    }

    return
}

proc ::stackato::cmd::zones::list {config} {
    debug.cmd/zones {}
    # No arguments.

    if {![$config @json]} {
	display "\nPlacement-zones: [context format-target]"
    }

    try {
	::set thezones [v2 sort @name [v2 zone list] -dict]
    } trap {STACKATO CLIENT V2 UNKNOWN REQUEST} {e o} {
	err "Placement zones not supported by target"
    }

    if {[$config @json]} {
	::set tmp {}
	foreach z $thezones {
	    lappend tmp [$z as-json]
	}
	display [json::write array {*}$tmp]
	return
    }

    if {![llength $thezones]} {
	display [color note "No placement-zones"]
	return
    }

    [table::do t {Name DEA} {
	# TODO: Might be generalizable via attr listing + labeling
	foreach z $thezones {
	    lappend values [$z @name]
	    lappend values [join [$z @deas] \n]
	    $t add {*}$values
	    ::unset values
	}
    }] show display
    return
}

proc ::stackato::cmd::zones::show {config} {
    debug.cmd/zones {}
    # @name - zones's object.

    ::set zone [$config @zone]

    if {[$config @json]} {
	puts [$zone as-json]
	return
    }

    display "[ctarget get] - [$zone @name]"
    [table::do t {DEA} {
	foreach dea [$zone @deas] {
	    $t add $dea
	}
    }] show display
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::zones::select-for {what p {mode noauto}} {
    debug.cmd/zones {}
    # generate callback - (p)arameter argument.

    # Implied client.
    debug.cmd/zones {Retrieve list of zones...}

    # --- TODO --- trap error (missing endpoint, report nicely)

    try {
	::set choices [v2 zone list]
    } trap {STACKATO CLIENT V2 UNKNOWN REQUEST} {e o} {
	err "Placement zones not supported by target"
    }

    debug.cmd/zones {ZONE [join $choices "\nZONE "]}

    if {![cmdr interactive?]} {
	debug.cmd/zones {no interaction}
	$p undefined!
	# implied return/failure
    }

    if {![llength $choices]} {
	err "No zones available to $what"
    }

    foreach o $choices {
	dict set map [$o @name] $o
    }
    ::set choices [lsort -dict [dict keys $map]]
    ::set name [ask menu "" \
		    "Which zone to $what ? " \
		    $choices]

    return [dict get $map $name]
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::zones 0

