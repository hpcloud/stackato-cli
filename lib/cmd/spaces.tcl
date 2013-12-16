# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations. Management of spaces.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require stackato::color
package require stackato::jmap
package require stackato::log
package require stackato::mgr::client
package require stackato::mgr::context
package require stackato::mgr::corg
package require stackato::mgr::cspace
package require stackato::mgr::ctarget
package require stackato::term
package require stackato::v2
package require table

debug level  cmd/spaces
debug prefix cmd/spaces {[debug caller] | }

namespace eval ::stackato::cmd {
    namespace export spaces
    namespace ensemble create
}
namespace eval ::stackato::cmd::spaces {
    namespace export \
	create delete rename list show switch
    namespace ensemble create

    namespace import ::stackato::color
    namespace import ::stackato::jmap
    namespace import ::stackato::log::display
    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::client
    namespace import ::stackato::mgr::context
    namespace import ::stackato::mgr::corg
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::mgr::ctarget
    namespace import ::stackato::term
    namespace import ::stackato::v2
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::spaces::switch {config} {
    debug.cmd/spaces {}
    # @name
    # @organization

    set org [$config @organization]

    try {
	set space [$config @name]
    } trap {CMDR VALIDATE SPACENAME} {e o} {
	set name [$config @name string]
	err "Unable to switch to space \"$name\" (not found, or not a member)"
    }

    if {$org eq {}} {
	display [color yellow {Unable to switch, no organization specified}]
	return
    }
    if {$space eq {}} {
	display [color yellow {Unable to switch, no space specified}]
	return
    }

    display "Switching to organization [$org @name] ... " false
    corg set $org
    corg save
    display [color green OK]

    display "Switching to space [$space @name] ... " false
    cspace set $space
    cspace save
    display [color green OK]

    display [context format-large]
    return
}

proc ::stackato::cmd::spaces::create {config} {
    debug.cmd/spaces {}
    # @name
    # @organization

    set name  [$config @name]
    set space [v2 space new]

    display [context format-org]

    display "Creating new space $name ... "

    $space @name         set $name
    $space @organization set [corg get]

    if {[$config @developer] ||
	[$config @manager]   ||
	[$config @auditor]} {
	set user [v2 deref-type user [[$config @client] user]]

	if {[$config @developer]} {
	    display "  Adding you as developer ... " false
	    $space @developers add $user
	    display [color green OK]
	}
	if {[$config @manager]} {
	    display "  Adding you as manager ... " false
	    $space @managers add $user
	    display [color green OK]
	}
	if {[$config @auditor]} {
	    display "  Adding you as auditor ... " false
	    $space @auditors add $user
	    display [color green OK]
	}
    }

    display "Committing ... " false
    $space commit
    display [color green OK]

    if {[$config @activate]} {
	display "Switching to space [$space @name] ... " false
	cspace set $space
	cspace save
	display [color green OK]

	display [context format-large]
    }
    return
}

proc ::stackato::cmd::spaces::delete {config} {
    debug.cmd/spaces {}
    # @name - Space object

    set space     [$config @name]
    set iscurrent [$space == [cspace get]]
    set recursive [$config @recursive]

    if {$recursive} {
	set suffix { and all its contents}
    } else {
	set suffix {}
    }

    if {[cmdr interactive?] &&
	![term ask/yn \
	      "\nReally delete \"[$space @name]\"$suffix ? " \
	      no]} return

    if {$recursive} {
	$space delete recursive true
    } else {
	$space delete
    }

    display "Deleting space [$space @name] ... " false
    $space commit
    display [color green OK]

    # Update (remove) the current space, if that is the space we just
    # deleted.
    if {$iscurrent} {
	display "Dropped removed space as current space."

	cspace reset
	cspace save
    }
    return
}

proc ::stackato::cmd::spaces::rename {config} {
    debug.cmd/spaces {}
    # @name
    # @newname

    set space [$config @name]
    set new   [$config @newname]

    $space @name set $new

    display "Renaming space to [$space @name] ... " false
    $space commit
    display [color green OK]
    return
}

proc ::stackato::cmd::spaces::list {config} {
    debug.cmd/spaces {}
    # No arguments.

    if {[$config @json]} {
	set tmp {}
	foreach s [[corg get] @spaces get] {
	    lappend tmp [$s as-json]
	}
	display [json::write array {*}$tmp]
	return
    }

    display "In [[corg get] @name]..."
    set cs [cspace get]

    set titles {{} Name Apps Services}
    set full [$config @full]
    set depth 1
    if {$full} {
	lappend titles Developers Managers Auditors
	set depth 2
    }

    [table::do t $titles {
	# TODO: spaces list - Depth 1/2 - How to specify ?
	foreach space [[corg get] @spaces get 2] {
	    lappend values [expr {($cs ne {}) && [$cs == $space] ? "x" : ""}]
	    lappend values [$space @name]
	    lappend values [join [lsort -dict [$space @apps @name]] \n]
	    lappend values [join [lsort -dict [$space @service_instances get* {user-provided true} @name]] \n]

	    if {$full} {
		lappend values [join [$space @developers the_name] \n]
		lappend values [join [$space @managers   the_name] \n]
		lappend values [join [$space @auditors   the_name] \n]
	    }

	    $t add {*}$values
	    unset values
	}
    }] show display
    return
}

proc ::stackato::cmd::spaces::show {config} {
    debug.cmd/spaces {}
    # @name

    set space [$config @name]
    # TODO: space load - Depth 1/2 - How to specify ? Must be in dispatcher.

    if {[$config @json]} {
	puts [$space as-json]
	return
    }

    display [context format-short]
    [table::do t {Key Value} {
	$t add Organization [$space @organization @name]
	$t add Apps         [join [lsort -dict [$space @apps @name]] \n]
	$t add Services     [join [lsort -dict [$space @service_instances get* {user-provided true} @name]] \n]
	$t add Domains      [join [lsort -dict [$space @domains @name]] \n]

	if {[$config @full]} {
	    $t add Developers [join [lsort -dict [$space @developers the_name]] \n]
	    $t add Managers   [join [lsort -dict [$space @managers   the_name]] \n]
	    $t add Auditors   [join [lsort -dict [$space @auditors   the_name]] \n]
	}

    }] show display
    return
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::spaces 0

