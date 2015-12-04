# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations. Management of space quota plans.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::ask
package require cmdr::color
package require stackato::jmap
package require stackato::log
package require stackato::mgr::client ; # pulls all of v2
package require stackato::mgr::context
package require stackato::mgr::corg
package require stackato::mgr::cspace
package require table

debug level  cmd/spacequotas
debug prefix cmd/spacequotas {[debug caller] | }

namespace eval ::stackato::cmd {
    namespace export spacequotas
    namespace ensemble create
}
namespace eval ::stackato::cmd::spacequotas {
    namespace export \
	create delete update rename list show \
	select-for setq unsetq
    namespace ensemble create

    namespace import ::cmdr::ask
    namespace import ::cmdr::color
    namespace import ::stackato::v2
    namespace import ::stackato::jmap
    namespace import ::stackato::log::display
    namespace import ::stackato::log::psz
    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::context
    namespace import ::stackato::mgr::corg
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::v2

    # name required definition
    # required is only for creation. The marked attributes must be
    # present in the new quota. The others get defaults from the CC.

    # Attention: sync with spaces.tcl/show
    variable map {
	memory_limit               1 {MEM       mem}
	instance_memory_limit      1 {MEM       instance-mem}
	non_basic_services_allowed 1 {Permitted paid-services-allowed}
	total_routes               1 {ID        routes}
	total_services             1 {ID        services}
    }
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::spacequotas::create {config} {
    variable map
    debug.cmd/spacequotas {}
    # @name - String, validated to not exist

    set name [$config @name]
    if {![$config @name set?]} {
	$config @name undefined!
    }
    if {$name eq {}} {
	err "An empty space quota name is not allowed"
    }

    set sq [v2 space_quota_definition new]

    display "Creating new space quota \"[color name $name]\" ... "
    $sq @name set $name

    foreach {a required def} $map {
	lassign $def convert k
	if {![$config @$k set?] && !$required} continue
	$sq @$a set [$config @$k]
	display "  [$sq @$a label]: [$convert [$sq @$a]]"
    }

    $sq @organization set [corg get]
    display "  [$sq @organization label]: [color name [[corg get] @name]]"

    display "Committing ... " false
    $sq commit
    display [color good OK]

    return
}

proc ::stackato::cmd::spacequotas::update {config} {
    variable map
    debug.cmd/spacequotas {}
    # @name    - space_quota_definition's object.

    set sq [$config @name]

    # Map config to entity.
    # Might be a useful utility procedure.
    foreach {a __ def} $map {
	lassign $def __ k
	if {![$config @$k set?]} continue
	$sq @$a set [$config @$k]
    }

    display "Changing space quota \"[color name [$sq @name]]\" ... "

    set changes [dict sort [$sq journal]]
    if {[dict size $changes]} {
	dict for {attr details} $changes {
	    lassign $details was old
	    set new [$sq @$attr]

	    set label [$sq @$attr label]
	    set verb   was
	    set prefix [color note Setting]
	    if {!$was} {
		display "    $prefix $label: $new ($verb <undefined>)"
	    } else {
		display "    $prefix $label: $new ($verb $old)"
	    }
	}

	display "Committing ... " false
	$sq commit
	display [color good OK]
    } else {
	display [color good {No changes}]
    }
    return
}

proc ::stackato::cmd::spacequotas::delete {config} {
    debug.cmd/spacequotas {}
    # @name    - quota_definition's object.

    set sq [$config @name]

    if {[cmdr interactive?] &&
	![ask yn \
	      "\nReally delete \"[color name [$sq @name]]\" ? " \
	      no]} return

    $sq delete

    display "Deleting space quota \"[color name [$sq @name]]\" ... " false
    $sq commit
    display [color good OK]
    return
}

proc ::stackato::cmd::spacequotas::rename {config} {
    debug.cmd/spacequotas {}
    # @name    - quota_definition's object.
    # @newname - String, validated to not exist as quota name.

    set sq  [$config @name]
    set old [$sq @name]
    set new [$config @newname]

    $sq @name set $new

    display "Renaming space quota \"[color name $old]\" to [color name [$sq @name]] ... " false
    $sq commit
    display [color good OK]
    return
}

proc ::stackato::cmd::spacequotas::setq {config} {
    debug.cmd/spacequotas {}

    set space [cspace get]
    set sname [$space @name]
    set sq    [$config @name]

    if {[$space @space_quota_definition defined?]} {
	set sqb [$space @space_quota_definition]
	if {[$sqb == $sq]} {
	    display [color note {No change}]
	    return
	}
	err "The space \"$sname\" already has an assigned space quota: [$space @space_quota_definition @name]"
    }

    display "Assigning space quota \"[color name [$sq @name]]\" to space [color name $sname] ... " false
    $sq @spaces add $space
    display [color good OK]
    return
}

proc ::stackato::cmd::spacequotas::unsetq {config} {
    debug.cmd/spacequotas {}

    set space [cspace get]
    set sname [$space @name]

    if {![$space @space_quota_definition defined?]} {
	err "The space \"$sname\" has no assigned space quota"
    }

    set sq [$space @space_quota_definition]

    display "Dropping space quota \"[color name [$sq @name]]\" from space [color name $sname] ... " false
    $sq @spaces remove $space
    display [color good OK]
    return
}

proc ::stackato::cmd::spacequotas::list {config} {
    debug.cmd/spacequotas {}
    # No arguments.

    if {![$config @json]} {
	if {[$config @all]} {
	    set context [context format-target]
	} else {
	    set context [context format-org]
	}
	display "\nSpace Quotas: $context"
    }

    if {[$config @all]} {
	set thequotas [v2 space_quota_definition list]
    } else {
	set thequotas [[corg get] @space_quota_definitions]
    }

    set thequotas [v2 sort @name $thequotas -dict]

    if {[$config @json]} {
	set tmp {}
	foreach sq $thequotas {
	    lappend tmp [$sq as-json]
	}
	display [json::write array {*}$tmp]
	return
    }

    if {![llength $thequotas]} {
	display [color note "No Space Quota"]
	return
    }

    set full [$config @full]
    if {$full} {
	set titles {Name {Owner Org} Spaces Memory {Instance Memory} Services Routes {Paid Services?}}
    } else {
	set titles {Name {Owner Org} Memory {Instance Memory} Services Routes {Paid Services?}}
    }

    [table::do t $titles {
	# TODO: Might be generalizable via attr listing + labeling
	foreach sq $thequotas {
	    lappend values [color name [$sq @name]]
	    lappend values [$sq @organization @name]

	    if {$full} {
		lappend values [join [lsort -dict [$sq @spaces @name]] \n]
	    }

	    lappend values [MEM [$sq @memory_limit]]
	    lappend values [MEM [$sq @instance_memory_limit]]
	    lappend values [$sq @total_services]
	    lappend values [$sq @total_routes]
	    lappend values [Permitted [$sq @non_basic_services_allowed]]

	    $t add {*}$values
	    unset values
	}
    }] show display
    return
}

proc ::stackato::cmd::spacequotas::show {config} {
    debug.cmd/spacequotas {}
    variable map
    # @name - quota_definition's object.

    set sq [$config @name]

    if {[$config @json]} {
	puts [$sq as-json]
	return
    }

    display "[context format-target] - [color name [$sq @name]]"
    [table::do t {Key Value} {
	$t add {Owning Organization} [$sq @organization @name]
	foreach {a __ def} $map {
	    set label [string trim [$sq @$a label]]
	    if {[$sq @$a defined?]} {
		lassign $def convert k
		set value [$convert [$sq @$a]]
	    } else {
		set value {(Not supported by target)}
	    }
	    $t add $label $value
	}
	$t add {Using Spaces} [join [lsort -dict [$sq @spaces full-name]] \n]
    }] show display
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::spacequotas::select-for {what p {mode noauto}} {
    debug.cmd/spacequotas {}
    # generate callback - (p)arameter argument.

    # Modes
    # - auto   : If there is only a single space quota, take it without asking the user.
    # - noauto : Always ask the user.

    # generate callback for 'quota delete|rename|update|show: name'.

    # Implied client.
    debug.cmd/spacequotas {Retrieve list of space_quota_definitions...}

    ::set choices [v2 space_quota_definition list]
    debug.cmd/spacequotas {QUOTA [join $choices "\nQUOTA "]}

    if {([llength $choices] == 1) && ($mode eq "auto")} {
	return [lindex $choices 0]
    }

    if {![cmdr interactive?]} {
	debug.cmd/spacequotas {no interaction}
	$p undefined!
	# implied return/failure
    }

    if {![llength $choices]} {
	err "No space quotas available to $what"
    }

    foreach o $choices {
	dict set objmap [$o @name] $o
    }
    ::set choices [lsort -dict [dict keys $objmap]]
    ::set name [ask menu "" \
		    "Which space quota to $what ? " \
		    $choices]

    return [dict get $objmap $name]
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::spacequotas::ID  {x} { return $x }
proc ::stackato::cmd::spacequotas::MEM {x} {
    if {$x >= 0} {
	return [psz [MB $x]]
    }
    return [color note unlimited]
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::spacequotas::MB {x} {
    expr {$x * 1024 * 1024}
}

proc ::stackato::cmd::spacequotas::Permitted {x} {
    expr {$x ? "[color note allowed]" : "disallowed"}
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::spacequotas 0

