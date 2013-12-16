# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations. Management of quota definitions.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require stackato::color
package require stackato::jmap
package require stackato::log
package require stackato::mgr::client ; # pulls all of v2
package require stackato::mgr::ctarget
package require stackato::term
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

    namespace import ::stackato::color
    namespace import ::stackato::v2
    namespace import ::stackato::jmap
    namespace import ::stackato::log::display
    namespace import ::stackato::log::psz
    namespace import ::stackato::term
    namespace import ::stackato::mgr::ctarget
    namespace import ::stackato::v2
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::quotas::create {config} {
    debug.cmd/quotas {}
    # @name - String, validated to not exist

    set name [$config @name]
    set qd [v2 quota_definition new]

    $qd @name                       set $name
    $qd @non_basic_services_allowed set [$config @paid-services-allowed]
    $qd @total_services             set [$config @services]
    $qd @memory_limit               set [$config @mem]

    display "Creating new quota definition $name ... "
    display "  Paid services allowed:  [$qd @non_basic_services_allowed]"
    display "  Max number of services: [$qd @total_services]"
    display "  Memory limit:           [psz [MB [$qd @memory_limit]]]"
    display "Committing ... " false

    $qd commit
    display [color green OK]

    return
}

proc ::stackato::cmd::quotas::configure {config} {
    debug.cmd/quotas {}
    # @name    - quota_definition's object.

    set qd [$config @name]

    # Map config to entity.
    # Might be a useful utility procedure.
    foreach {a k} {
	non_basic_services_allowed paid-services-allowed
	total_services             services
	memory_limit               mem
	trial_db_allowed           trial-db-allowed
	allow_sudo                 allow-sudo
    } {
	if {![$config @$k set?]} continue
	$qd @$a set [$config @$k]
    }

    display "Changing quota definition [$qd @name] ... "

    set changes [dict sort [$qd journal]]
    if {[dict size $changes]} {
	dict for {attr details} $changes {
	    lassign $details was old
	    set new [$qd @$attr]

	    set label [$qd @$attr label]
	    set verb   was
	    set prefix [color blue Setting]
	    if {!$was} {
		display "    $prefix $label: $new ($verb <undefined>)"
	    } else {
		display "    $prefix $label: $new ($verb $old)"
	    }
	}

	display "Committing ... " false
	$qd commit
	display [color green OK]
    } else {
	display [color green {No changes}]
    }
    return
}

proc ::stackato::cmd::quotas::delete {config} {
    debug.cmd/quotas {}
    # @name    - quota_definition's object.

    set qd [$config @name]

    if {[cmdr interactive?] &&
	![term ask/yn \
	      "\nReally delete \"[$qd @name]\" ? " \
	      no]} return

    $qd delete

    display "Deleting quota definition [$qd @name] ... " false
    $qd commit
    display [color green OK]
    return
}

proc ::stackato::cmd::quotas::rename {config} {
    debug.cmd/quotas {}
    # @name    - quota_definition's object.
    # @newname - String, validated to not exist as quota name.

    set qd  [$config @name]
    set new [$config @newname]

    $qd @name set $new

    display "Renaming quota definition to [$qd @name] ... " false
    $qd commit
    display [color green OK]
    return
}

proc ::stackato::cmd::quotas::list {config} {
    debug.cmd/quotas {}
    # No arguments.

    if {![$config @json]} {
	display "In [ctarget get]..."
    }

    set thequotas [v2 quota_definition list 1]

    if {[$config @json]} {
	set tmp {}
	foreach qd $thequotas {
	    lappend tmp [$qd as-json]
	}
	display [json::write array {*}$tmp]
	return
    }

    [table::do t {Name Paid? Services Memory {Trial DB?} Sudo?} {
	# TODO: Might be generalizable via attr listing + labeling
	foreach qd $thequotas {
	    lappend values [$qd @name]
	    lappend values [$qd @non_basic_services_allowed]
	    lappend values [$qd @total_services]
	    lappend values [psz [MB [$qd @memory_limit]]]
	    lappend values [$qd @trial_db_allowed]
	    lappend values [$qd @allow_sudo]
	    $t add {*}$values
	    unset values
	}
    }] show display
    return
}

proc ::stackato::cmd::quotas::show {config} {
    debug.cmd/quotas {}
    # @name - quota_definition's object.

    set qd [$config @name]

    if {[$config @json]} {
	puts [$qd as-json]
	return
    }

    display "[ctarget get] - [$qd @name]"
    [table::do t {Key Value} {
	# TODO: make generic using attr listing + labeling.
	$t add {Memory Limit}    [psz [MB [$qd @memory_limit]]]
	$t add {Paid Services}   [$qd @non_basic_services_allowed]
	$t add {Total Services}  [$qd @total_services]
	$t add {Trial Databases} [$qd @trial_db_allowed]
	$t add {Allow sudo}      [$qd @allow_sudo]
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
	err "No quota definitions available to $what"
    }

    foreach o $choices {
	dict set map [$o @name] $o
    }
    ::set choices [lsort -dict [dict keys $map]]
    ::set name [term ask/menu "" \
		    "Which quota definition to $what ? " \
		    $choices]

    return [dict get $map $name]
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::quotas::MB {x} {
    expr {$x * 1024 * 1024}
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::quotas 0

