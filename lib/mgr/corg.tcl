# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## This module manages the current (active) organization. Note that
## persistence is handled through the "tadjunct" manager, with the help
## of the current target. I.e. in a per-target manner.

## Another note of importance: In the API this package takes and
## return in-memory organization instance objects. Externally this is
## converted from and to the uuid of the organization.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require stackato::mgr::tadjunct
package require stackato::mgr::ctarget
package require stackato::term
package require stackato::v2::client

namespace eval ::stackato::mgr {
    namespace export corg
    namespace ensemble create
}

namespace eval ::stackato::mgr::corg {
    namespace export set get get-auto reset save select-for setc getc
    namespace ensemble create

    namespace import ::stackato::mgr::tadjunct
    namespace import ::stackato::mgr::ctarget
    namespace import ::stackato::term
    namespace import ::stackato::v2
}

debug level  mgr/corg
debug prefix mgr/corg {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## API

proc ::stackato::mgr::corg::setc {p obj} { set $obj }
proc ::stackato::mgr::corg::getc {p}     { get      }

proc ::stackato::mgr::corg::set {obj} {
    debug.mgr/corg {}
    variable current $obj
    return
}

proc ::stackato::mgr::corg::get {} {
    debug.mgr/corg {}
    variable current

    if {![info exists current]} {
	debug.mgr/corg {fill cache}

	# Priority order (first to last taken):
	# (1) --organization, -o (via set)
	# (2) $STACKATO_ORG
	# (3) $HOME/.stackato/client/token2 (adjunct)

	if {[info exists env(STACKATO_ORG)]} {
	    ::set name $env(STACKATO_ORG)

	    # Inline form of orgname validate.
	    # Not using parameter reference here.

	    if {![catch {
		set o [v2 organization find-by-name $name]
	    }]} {
		set uuid [$o id]
	    } else {
		set uuid {}
	    }

	    debug.mgr/corg {env var   = $name}
	    debug.mgr/corg {env var   = $uuid}
	} else {
	    ::set target [ctarget get]
	    ::set known  [tadjunct known]

	    debug.mgr/corg {from  $target}
	    debug.mgr/corg {known $known}

	    #checker -scope line exclude badOption
	    ::set uuid [dict get' $known $target organization {}]

	    debug.mgr/corg {file/dflt = $uuid}
	}

	if {$uuid ne {}} {
	    # Convert uuid into entity instance in-memory.
	    ::set current [v2 deref-type organization $uuid]
	} else {
	    ::set current {}
	}
    }

    debug.mgr/corg {==> [Show]}
    return $current
}

proc ::stackato::mgr::corg::get-auto {p} {
    # generate callback
    debug.mgr/corg {}
    # get, and if that fails, automagically determine and save a
    # suitable organization.

    if {![[$p config @client] isv2]} {
	return {}
    }

    ::set org [get]
    if {$org ne {}} {
	debug.mgr/corg {current ==> [Show]}
	return $org
    }

    ::set org [select-for choose $p auto]
    set $org
    save

    debug.mgr/corg {auto ==> [Show]}
    return $org
}

proc ::stackato::mgr::corg::reset {} {
    debug.mgr/corg {}
    variable current
    unset -nocomplain current
    return
}

proc ::stackato::mgr::corg::save {} {
    debug.mgr/corg {}
    variable current

    if {[info exists current] && ($current ne {})} {
	# Saved reference is the organization's uuid.
	tadjunct add [ctarget get] organization [$current id]
    } else {
	tadjunct remove [ctarget get] organization
    }

    debug.mgr/corg {OK}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::corg::select-for {what p {mode noauto}} {
    debug.mgr/corg {}
    # generate callback - (p)arameter argument.

    # Modes
    # - auto   : If there is only a single organization, take it without asking the user.
    # - noauto : Always ask the user.

    # generate callback for 'orgmgr delete|rename: name'.
    # ditto 'spacemgr ... .parentorg'
    # Also: usermgr/login: PostLoginV2 proc

    # Implied client.
    debug.mgr/corg {Retrieve list of organizations...}

    ::set choices [v2 organization list]
    debug.mgr/corg {ORG [join $choices "\nORG "]}

    if {([llength $choices] == 1) && ($mode eq "auto")} {
	return [lindex $choices 0]
    }

    if {(![cmdr interactive?] ||
	 ![llength $choices]) &&
	[$p config has @ignore-missing] &&
	[$p config @ignore-missing]} {
	return {}
    }

    if {![cmdr interactive?]} {
	debug.mgr/corg {no interaction}
	$p undefined!
	# implied return/failure
    }

    if {![llength $choices]} {
	err "No organizations available to $what"
    }

    foreach o $choices {
	dict set map [$o @name] $o
    }
    ::set choices [lsort -dict [dict keys $map]]
    ::set name [term ask/menu "" \
		    "Which organization to $what ? " \
		    $choices]

    return [dict get $map $name]
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::corg::Show {} {
    variable current
    if {![info exists current]} { return UNDEF }
    if {$current eq {}}         { return $current }
    return "$current ([$current id] = \"[$current @name]\")"
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::corg 0
