# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

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
package require cmdr::ask
package require cmdr::color
package require stackato::log
package require stackato::mgr::ctarget
package require stackato::mgr::self
package require stackato::mgr::tadjunct
package require stackato::v2::client

namespace eval ::stackato::mgr {
    namespace export corg
    namespace ensemble create
}

namespace eval ::stackato::mgr::corg {
    namespace export \
	set setc get getc get-auto get-id \
	reset save select-for
    namespace ensemble create

    namespace import ::cmdr::ask
    namespace import ::cmdr::color
    namespace import ::stackato::log::display
    namespace import ::stackato::log::warn
    namespace import ::stackato::mgr::ctarget
    namespace import ::stackato::mgr::self
    namespace import ::stackato::mgr::tadjunct
    namespace import ::stackato::v2
}

debug level  mgr/corg
debug prefix mgr/corg {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## API

proc ::stackato::mgr::corg::setc {p obj} { set $obj }
proc ::stackato::mgr::corg::getc {p} {
    # A v1 target cannot have orgs, and any information we may have in
    # the cli state files for it is wrong. Ignore it, don't even
    # try. And to be sure, squash any bad information.
    if {[$p config has @client] && ![[$p config @client] isv2]} {
	tadjunct remove [ctarget get] organization
	return {}
    }
    get
}

proc ::stackato::mgr::corg::set {obj} {
    debug.mgr/corg {}
    variable current $obj
    return
}

proc ::stackato::mgr::corg::get-id {} {
    debug.mgr/corg {}
    variable current
    global env

    # If cached, use that.
    if {[info exists current]} {
	if {$current eq {}} {
	    return $current
	} else {
	    return [$current id]
	}
    }

    # Not cached, pull id from the possible sources.
    # NOTE! Result is not cached, as it was not validated.

    # Priority order (first to last taken):
    # (1) --organization, -o (via set)
    # (2) $STACKATO_ORG
    # (3) $HOME/.stackato/client/token2 (adjunct)

    if {[info exists env(STACKATO_ORG)]} {
	::set name $env(STACKATO_ORG)

	# Inline form of orgname validate.
	# Not using parameter reference here.

	if {![catch {
	    ::set o [v2 organization find-by-name $name]
	}]} {
	    ::set uuid [$o id]
	} else {
	    ::set uuid {}
	}

	debug.mgr/corg {env var   = $name}
	debug.mgr/corg {env var   = $uuid}
    } else {
	::set target [ctarget get]
	debug.mgr/corg {from  $target}

	::set uuid [tadjunct get' $target organization {}]
	debug.mgr/corg {file/dflt = $uuid}
    }

    return $uuid
}

proc ::stackato::mgr::corg::get {} {
    debug.mgr/corg {}
    variable current
    global env

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
		::set o [v2 organization find-by-name $name]
	    }]} {
		::set uuid [$o id]
	    } else {
		::set uuid {}
	    }

	    debug.mgr/corg {env var   = $name}
	    debug.mgr/corg {env var   = $uuid}
	    ::set store 0
	} else {
	    ::set target [ctarget get]
	    debug.mgr/corg {from  $target}

	    ::set uuid [tadjunct get' $target organization {}]
	    debug.mgr/corg {file/dflt = $uuid}
	    ::set store 1
	}

	if {$uuid ne {}} {
	    debug.mgr/corg {load $uuid uuid}

	    # Convert uuid into entity instance in-memory. We use an
	    # attribute access to force resolution and validate the
	    # org's existence. A failure is treated as if no current
	    # org is set at all, effectively discarding the value.  If
	    # it came from the filesystem the discard is propagated to
	    # it.
	    ::set current [v2 deref-type organization $uuid]
	    try {
		$current @name
	    } trap {STACKATO CLIENT V2 AUTHERROR} {e o} - \
	      trap {STACKATO CLIENT AUTHERROR} {e o} {
		debug.mgr/corg {org auth failure}
		# Could not validate, not logged in.
		# Keep information, treat is no current org set
		::set current {}

	    } trap {STACKATO CLIENT V2 NOTFOUND} {e o} {
		# Failed to validate.
		debug.mgr/corg {org validation failure}
		Discard $store $uuid
	    }
	} else {
	    debug.mgr/corg {no current org}
	    ::set current {}
	}
    }

    debug.mgr/corg {==> [Show]}
    return $current
}

proc ::stackato::mgr::corg::Discard {store uuid} {
    debug.mgr/corg {}
    variable current
    $current destroy
    ::set current {}

    # Discard external as well, if that was the source.
    if {$store} {
	display [color warning "Resetting current org, invalid value."]
	save
    } else {
	display [color warning "Ignoring STACKATO_ORG, invalid value."]
    }
    return
}

proc ::stackato::mgr::corg::get-auto {p} {
    # generate callback
    debug.mgr/corg {}
    # get, and if that fails, automagically determine and save a
    # suitable organization.

    # Check for and handle disabled automatic.
    if {[$p config has @org_auto] && ![$p config @org_auto]} {
	debug.mgr/corg {disabled}
	return {}
    }

    # 1b1. Test for and re-validate a cached current org.
    # 1b2. Keep a valid cached org.
    # 1b3. Choose a current when none found, or invalid.
    # 1b3a. Retrieve a list of possible orgs.
    # 1b3b. If this list has more than one entry let the user choose interactively.
    # 1b3c. With a single entry automatically choose this org.
    # 1b3d. For an empty list throw an error.

    # Irrelevant when talking to a CF API v1 target.
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

    # The choice of org is restricted to the orgs associated with the
    # user we are logged in as. Bug 104693.
    ::set client [$p config @client]
    ::set user [$client current_user_id]

    if {$user eq {}} {
	# Not logged in, but we have to be
	stackato::client::AuthError
    } else {
	::set user    [v2 deref-type user $user]
	::set choices [$user @organizations]
	::set user    [$client current_user]
    }
 
    debug.mgr/corg {ORG [join $choices "\nORG "]}

    if {([llength $choices] == 1) && ($mode eq "auto")} {
	::set neworg [lindex $choices 0]
	display "$user Choosing the one available organization: \"[color name [$neworg @name]]\""
	return $neworg
    }

    if {(![cmdr interactive?] ||
	 ![llength $choices]) &&
	[$p config has @ignore-missing] &&
	[$p config @ignore-missing]} {
	return {}
    }

    if {![llength $choices]} {
	warn "No organizations available to ${what}. [self please link-user-org] to connect users with orgs."
    }

    if {![cmdr interactive?]} {
	debug.mgr/corg {no interaction}
	$p undefined!
	# implied return/failure
    }

    foreach o $choices {
	dict set map [$o @name] $o
    }
    ::set choices [lsort -dict [dict keys $map]]
    ::set name [ask menu "" \
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
