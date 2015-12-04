# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations. Management of quota plans.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::ask
package require cmdr::color
package require stackato::jmap
package require stackato::log
package require stackato::mgr::client ; # pulls all of v2
package require stackato::mgr::context
package require stackato::mgr::ctarget
package require table

debug level  cmd/quotas
debug prefix cmd/quotas {[debug caller] | }

namespace eval ::stackato::cmd {
    namespace export quotas
    namespace ensemble create
}
namespace eval ::stackato::cmd::quotas {
    namespace export \
	create delete rename list show configure select-for
    namespace ensemble create

    namespace import ::cmdr::ask
    namespace import ::cmdr::color
    namespace import ::stackato::v2
    namespace import ::stackato::jmap
    namespace import ::stackato::log::display
    namespace import ::stackato::log::psz
    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::context
    namespace import ::stackato::mgr::ctarget
    namespace import ::stackato::v2

    # name required definition
    # required is only for creation. The marked attributes must be
    # present in the new quota. The others get defaults from the CC.
    variable map {
	non_basic_services_allowed 1 {Permitted paid-services-allowed}
	total_services             1 {ID        services}
	memory_limit               1 {MEM       mem}
	instance_memory_limit      0 {MEM       instance-mem}
	trial_db_allowed           0 {Permitted trial-db-allowed}
	allow_sudo                 0 {Permitted allow-sudo}
	total_routes               1 {ID        routes}
	total_droplets             0 {ID        droplets}
    }
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::quotas::create {config} {
    variable map
    debug.cmd/quotas {}
    # @name - String, validated to not exist

    set name [$config @name]
    if {![$config @name set?]} {
	$config @name undefined!
    }
    if {$name eq {}} {
	err "An empty quota plan name is not allowed"
    }

    set qd [v2 quota_definition new]

    display "Creating new quota plan [color name $name] ... "
    $qd @name set $name

    foreach {a required def} $map {
	lassign $def convert k
	if {![$config @$k set?] && !$required} continue
	$qd @$a set [$config @$k]
	display "  [$qd @$a label]: [$convert [$qd @$a]]"
    }

    display "Committing ... " false
    $qd commit
    display [color good OK]

    return
}

proc ::stackato::cmd::quotas::configure {config} {
    variable map
    debug.cmd/quotas {}
    # @name    - quota_definition's object.

    set qd [$config @name]

    # Map config to entity.
    # Might be a useful utility procedure.
    foreach {a __ def} $map {
	lassign $def __ k
	if {![$config @$k set?]} continue
	$qd @$a set [$config @$k]
    }

    display "Changing quota plan [color name [$qd @name]] ... "

    set changes [dict sort [$qd journal]]
    if {[dict size $changes]} {
	dict for {attr details} $changes {
	    lassign $details was old
	    set new [$qd @$attr]

	    set label [$qd @$attr label]
	    set verb   was
	    set prefix [color note Setting]
	    if {!$was} {
		display "    $prefix $label: $new ($verb <undefined>)"
	    } else {
		display "    $prefix $label: $new ($verb $old)"
	    }
	}

	display "Committing ... " false
	$qd commit
	display [color good OK]
    } else {
	display [color good {No changes}]
    }
    return
}

proc ::stackato::cmd::quotas::delete {config} {
    debug.cmd/quotas {}
    # @name    - quota_definition's object.

    set qd [$config @name]

    if {[cmdr interactive?] &&
	![ask yn \
	      "\nReally delete \"[color name [$qd @name]]\" ? " \
	      no]} return

    $qd delete

    display "Deleting quota plan [color name [$qd @name]] ... " false
    $qd commit
    display [color good OK]
    return
}

proc ::stackato::cmd::quotas::rename {config} {
    debug.cmd/quotas {}
    # @name    - quota_definition's object.
    # @newname - String, validated to not exist as quota name.

    set qd  [$config @name]
    set new [$config @newname]

    $qd @name set $new

    display "Renaming quota plan to [color name [$qd @name]] ... " false
    $qd commit
    display [color good OK]
    return
}

proc ::stackato::cmd::quotas::list {config} {
    debug.cmd/quotas {}
    # No arguments.

    if {![$config @json]} {
	display "Quotas: [context format-target]"
    }

    set thequotas [v2 sort @name [v2 quota_definition list] -dict]

    if {[$config @json]} {
	set tmp {}
	foreach qd $thequotas {
	    lappend tmp [$qd as-json]
	}
	display [json::write array {*}$tmp]
	return
    }

    if {![llength $thequotas]} {
	display [color note "No quotas"]
	return
    }

    [table::do t {Name Paid? Services Memory {Instance Memory} {Trial DB?} Sudo? Routes Droplets} {
	# TODO: Might be generalizable via attr listing + labeling
	foreach qd $thequotas {
	    lappend values [color name [$qd @name]]
	    lappend values [Permitted [$qd @non_basic_services_allowed]]
	    lappend values [$qd @total_services]
	    lappend values [MEM [$qd @memory_limit]]
	    lappend values [MEM [$qd @instance_memory_limit]]

	    if {[$qd @trial_db_allowed defined?]} {
		lappend values [Permitted [$qd @trial_db_allowed]]
	    } {
		lappend values N/A
	    }

	    lappend values [Permitted [$qd @allow_sudo]]

	    if {[$qd @total_routes defined?]} {
		lappend values [$qd @total_routes]
	    } {
		lappend values N/A
	    }
	    if {[$qd @total_droplets defined?]} {
		lappend values [$qd @total_droplets]
	    } {
		lappend values N/A
	    }
	    $t add {*}$values
	    unset values
	}
    }] show display
    return
}

proc ::stackato::cmd::quotas::show {config} {
    debug.cmd/quotas {}
    variable map
    # @name - quota_definition's object.

    set qd [$config @name]

    if {[$config @json]} {
	puts [$qd as-json]
	return
    }

    display "[color name [ctarget get]] - [color name [$qd @name]]"
    [table::do t {Key Value} {
	foreach {a __ def} $map {
	    set label [string trim [$qd @$a label]]
	    if {[$qd @$a defined?]} {
		lassign $def convert k
		set value [$convert [$qd @$a]]
	    } else {
		set value {(Not supported by target)}
	    }
	    $t add $label $value
	}
    }] show display
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::quotas::select-for {what p {mode noauto}} {
    debug.cmd/quotas {}
    # generate callback - (p)arameter argument.

    # Modes
    # - auto   : If there is only a single organization, take it without asking the user.
    # - noauto : Always ask the user.

    # generate callback for 'quota delete|rename|configure|show: name'.

    # Implied client.
    debug.cmd/quotas {Retrieve list of quota_definitions...}

    ::set choices [v2 quota_definition list]
    debug.cmd/quotas {QUOTA [join $choices "\nQUOTA "]}

    if {([llength $choices] == 1) && ($mode eq "auto")} {
	return [lindex $choices 0]
    }

    if {![cmdr interactive?]} {
	debug.cmd/quotas {no interaction}
	$p undefined!
	# implied return/failure
    }

    if {![llength $choices]} {
	err "No quota plans available to $what"
    }

    foreach o $choices {
	dict set objmap [$o @name] $o
    }
    ::set choices [lsort -dict [dict keys $objmap]]
    ::set name [ask menu "" \
		    "Which quota plan to $what ? " \
		    $choices]

    return [dict get $objmap $name]
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::quotas::ID  {x} { return $x }
proc ::stackato::cmd::quotas::MEM {x} {
    if {$x < 0} { return [color note unlimited] }
    return [psz [MB $x]]
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::quotas::Permitted {x} {
    expr {$x ? "[color note allowed]" : "disallowed"}
}

proc ::stackato::cmd::quotas::MB {x} {
    expr {$x * 1024 * 1024}
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::quotas 0

