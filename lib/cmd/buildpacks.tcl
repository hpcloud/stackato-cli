# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations. Management of buildpacks.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require stackato::color
package require stackato::log
package require stackato::mgr::client
package require stackato::term
package require stackato::v2
package require table

debug level  cmd/buildpacks
debug prefix cmd/buildpacks {[debug caller] | }

namespace eval ::stackato::cmd {
    namespace export buildpacks
    namespace ensemble create
}
namespace eval ::stackato::cmd::buildpacks {
    namespace export \
	list create rename update delete select-for
    namespace ensemble create

    namespace import ::stackato::color
    namespace import ::stackato::log::display
    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::client
    namespace import ::stackato::term
    namespace import ::stackato::v2
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::buildpacks::create {config} {
    debug.cmd/buildpacks {}

    set buildpack [v2 buildpack new]

    $buildpack @name set [$config @name]

    if {[$config @position set?]} {
	$buildpack @position set [$config @position]
    }
    if {[$config @enabled set?]} {
	$buildpack @enabled set [$config @enabled]
    }

    display "Creating new buildpack [$buildpack @name] ... " false
    $buildpack commit
    display [color green OK]

    display "Uploading buildpack bits ... " false

    $buildpack upload! [$config @zip]

    display [color green OK]

    debug.cmd/buildpacks {buildpack = $buildpack ([$buildpack @name])}
    return
}

proc ::stackato::cmd::buildpacks::rename {config} {
    debug.cmd/buildpacks {}

    set buildpack [$config @name]
    set old [$buildpack @name]
    set new [$config @newname]

    if {![$config @newname set?]} {
	$config @newname undefined!
    }
    if {$new eq {}} {
	err "An empty buildpack name is not allowed"
    }

    $buildpack @name set $new

    display "Renaming buildpack \[$old\] to '$new' ... " false
    $buildpack commit
    display [color green OK]
    return
}

proc ::stackato::cmd::buildpacks::update {config} {
    debug.cmd/buildpacks {}

    set buildpack [$config @name]
    debug.cmd/buildpacks {buildpack = $buildpack ([$buildpack @name])}

    display "Updating buildpack \[[$buildpack @name]\] ..."

    set changes 0
    foreach {attr label} {
	@position {Position}
	@enabled  {Enabled }
    } {
	display "  $label ... " false
	if {![$config $attr set?]} {
	    display [color blue Unchanged]
	    continue
	}
	display "Changed to [$config $attr]"
	$buildpack $attr set [$config $attr]
	incr changes
    }

    if {$changes} {
	$buildpack commit
	display [color green OK]
    }

    if {[$config @zip set?]} {
	display "Uploading new buildpack bits ... " false
	$buildpack upload! [$config @zip]
	display [color green OK]
    }
    return
}

proc ::stackato::cmd::buildpacks::delete {config} {
    debug.cmd/buildpacks {}
    # @name - buildpack name

    set buildpack [$config @name]
    debug.cmd/buildpacks {buildpack = $buildpack ([$buildpack @name])}

    if {[cmdr interactive?] &&
	![term ask/yn \
	      "\nReally delete \"[$buildpack @name]\" ? " \
	      no]} return

    $buildpack delete

    display "Deleting buildpack [$buildpack @name] ... " false
    $buildpack commit
    display [color green OK]
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::buildpacks::list {config} {
    debug.cmd/buildpacks {}
    # No arguments.

    if {[$config @json]} {
	set tmp {}
	foreach r [v2 buildpack list] {
	    lappend tmp [$r as-json]
	}
	display [json::write array {*}$tmp]
	return
    }

    set buildpacks [v2 buildpack list]

    [table::do t {# Name Enabled} {
	foreach buildpack [v2 sort @position $buildpacks -dict] {
	    $t add [$buildpack @position] [$buildpack @name] [$buildpack @enabled]
	}
    }] show display
    return
}

# # ## ### ##### ######## ############# #####################
## Support. Generator callback.

proc ::stackato::cmd::buildpacks::select-for {what p {mode noauto}} {
    debug.cmd/buildpacks {}
    # generate callback - (p)arameter argument.

    # Modes
    # - auto   : If there is only a single buildpack, take it without asking the user.
    # - noauto : Always ask the user.

    # generate callback for 'buildpack delete|rename: name'.

    # Implied client.
    debug.cmd/buildpacks {Retrieve list of buildpacks...}

    ::set choices [v2 buildpack list]
    debug.cmd/buildpacks {BPACK [join $choices "\nBPACK "]}

    if {([llength $choices] == 1) && ($mode eq "auto")} {
	::set newpack [lindex $choices 0]
	display "Choosing the one available buildpack: \"[$newpack @name]\""
	return $newpack
    }

    if {![llength $choices]} {
	warn "No buildpacks available to ${what}."
    }

    if {![cmdr interactive?]} {
	debug.cmd/buildpacks {no interaction}
	$p undefined!
	# implied return/failure
    }

    foreach o $choices {
	dict set map [$o @name] $o
    }
    ::set choices [lsort -dict [dict keys $map]]
    ::set name [term ask/menu "" \
		    "Which buildpack to $what ? " \
		    $choices]

    return [dict get $map $name]
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::buildpacks 0

