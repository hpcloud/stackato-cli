# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## This module manages the current (active) space. Note that
## persistence is handled through the "tadjunct" manager, with the help
## of the current target. I.e. in a per-target manner.

## Another note of importance: In the API this package takes and
## return in-memory space instance objects. Externally this is
## converted from and to the uuid of the space.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require stackato::color
package require stackato::log
package require stackato::mgr::tadjunct
package require stackato::mgr::ctarget
package require stackato::mgr::corg
package require stackato::mgr::self
package require stackato::term
package require stackato::v2::client

namespace eval ::stackato::mgr {
    namespace export cspace
    namespace ensemble create
}

namespace eval ::stackato::mgr::cspace {
    namespace export \
	set setc get getc get-auto get-id \
	reset save select-for
    namespace ensemble create

    namespace import ::stackato::color
    namespace import ::stackato::log::display
    namespace import ::stackato::log::warn
    namespace import ::stackato::mgr::tadjunct
    namespace import ::stackato::mgr::ctarget
    namespace import ::stackato::mgr::corg
    namespace import ::stackato::mgr::self
    namespace import ::stackato::term
    namespace import ::stackato::v2
}

debug level  mgr/cspace
debug prefix mgr/cspace {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## API

proc ::stackato::mgr::cspace::setc {p obj} { set $obj }
proc ::stackato::mgr::cspace::getc {p}     { get      }

proc ::stackato::mgr::cspace::set {obj} {
    debug.mgr/cspace {}
    variable current $obj
    return
}

proc ::stackato::mgr::cspace::get-id {} {
    debug.mgr/cspace {}
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
    # (1) --group
    # (2a) $STACKATO_SPACE_GUID
    # (2b) $STACKATO_SPACE
    # (3) $HOME/.stackato/client/token2 (adjunct)

    if {[info exists env(STACKATO_SPACE_GUID)]} {
	::set uuid $env(STACKATO_SPACE_GUID)
	debug.mgr/cspace {env var/id   = $uuid}

    } elseif {[info exists env(STACKATO_SPACE)]} {
	::set name $env(STACKATO_SPACE)

	# Inlined form of spacename validate.
	# Not using parameter reference here.

	::set matches [[corg get] @spaces filter-by @name $name]
	if {[llength $matches] == 1} {
	    ::set uuid [[lindex $matches] id]
	} else {
	    ::set uuid {}
	}

	debug.mgr/cspace {env var/name = $name}
	debug.mgr/cspace {env var/name = $uuid}

    } else {
	::set target [ctarget get]
	debug.mgr/cspace {from  $target}

	::set uuid [tadjunct get' $target space {}]
	debug.mgr/cspace {file/default = $uuid}
	::set store 1
    }

    return $uuid
}

proc ::stackato::mgr::cspace::get {} {
    debug.mgr/cspace {}
    variable current
    global env

    if {![info exists current]} {
	debug.mgr/cspace {fill cache}

	# Priority order (first to last taken):
	# (1) --group
	# (2a) $STACKATO_SPACE_GUID
	# (2b) $STACKATO_SPACE
	# (3) $HOME/.stackato/client/token2 (adjunct)

	if {[info exists env(STACKATO_SPACE_GUID)]} {
	    ::set uuid $env(STACKATO_SPACE_GUID)
	    debug.mgr/cspace {env var/id   = $uuid}
	    ::set store 2

	} elseif {[info exists env(STACKATO_SPACE)]} {
	    ::set name $env(STACKATO_SPACE)

	    # Inlined form of spacename validate.
	    # Not using parameter reference here.

	    ::set matches [[corg get] @spaces filter-by @name $name]
	    if {[llength $matches] == 1} {
		::set uuid [[lindex $matches] id]
	    } else {
		::set uuid {}
	    }

	    debug.mgr/cspace {env var/name = $name}
	    debug.mgr/cspace {env var/name = $uuid}
	    ::set store 0

	} else {
	    ::set target [ctarget get]
	    debug.mgr/cspace {from  $target}

	    ::set uuid [tadjunct get' $target space {}]
	    debug.mgr/cspace {file/default = $uuid}
	    ::set store 1
	}

	if {$uuid ne {}} {
	    debug.mgr/cspace {load $uuid}

	    # Convert uuid into entity instance in-memory. We use an
	    # attribute access to force resolution and validate the
	    # space's existence. A failure is treated as if no current
	    # space is set at all, effectively discarding the value.
	    # If it came from the filesystem the discard is propagated
	    # to it.
	    ::set current [v2 deref-type space $uuid]

	    try {
		$current @name
	    } trap {STACKATO CLIENT V2 AUTHERROR} {e o} - \
	      trap {STACKATO CLIENT AUTHERROR} {e o} {
		debug.mgr/cspace {space auth failure}
		# Could not validate, not logged in.
		# Keep information, treat as if no current space set
		::set current {}

	    } trap {STACKATO CLIENT V2 NOTFOUND} {e o} {
		# Failed to validate.
		debug.mgr/cspace {space validation failure}
		Discard $store $uuid
	    } on ok {e o} {
		# Secondary check for specification by-cache or
		# by-name. The chosen/cached space has to belong to
		# the current organization.
		if {($store < 2) && !([corg get] == [$current @organization])} {
		    debug.mgr/cspace {space not within the current org}
		    Discard $store $uuid {outside of current org}
		}
	    }
	} else {
	    debug.mgr/cspace {no current space}
	    ::set current {}
	}
    }

    debug.mgr/cspace {==> [Show]}
    return $current
}

proc ::stackato::mgr::cspace::Discard {store uuid {reason {invalid value}}} {
    debug.mgr/cspace {}
    variable current
    $current destroy
    ::set current {}

    # Discard external as well, if that was the source.
    if {$store} {
	display [color yellow "Resetting current space, $reason."]
	save
    } else {
	display [color yellow "Ignoring STACKATO_SPACE, $reason."]
    }
    return
}

proc ::stackato::mgr::cspace::get-auto {p} {
    # generate callback
    debug.mgr/cspace {}
    # get, and if that fails, automagically determine and save a
    # suitable space.

    # 1b1. Test for and re-validate a cached current space.
    # 1b2. Keep a valid cached space.
    # 1b3. Choose a current when none found, or invalid.
    # 1b3a. Retrieve a list of possible space.
    # 1b3b. If this list has more than one entry let the user choose interactively.
    # 1b3c. With a single entry automatically choose this space.
    # 1b3d. For an empty list throw an error.

    # Irrelevant when talking to a CF API v1 target.
    if {![[$p config @client] isv2]} {
	return {}
    }

    ::set space [get]
    if {$space ne {}} {
	debug.mgr/cspace {current ==> [Show]}
	return $space
    }

    ::set space [select-for choose $p auto]
    set $space
    save

    debug.mgr/cspace {auto ==> [Show]}
    return $space
}

proc ::stackato::mgr::cspace::reset {} {
    debug.mgr/cspace {}
    variable current
    unset -nocomplain current
    return
}

proc ::stackato::mgr::cspace::save {} {
    debug.mgr/cspace {}
    variable current

    if {[info exists current] && ($current ne {})} {
	# Saved reference is the space's uuid.
	tadjunct add [ctarget get] space [$current id]
    } else {
	tadjunct remove [ctarget get] space
    }

    debug.mgr/cspace {OK}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::cspace::select-for {what p {mode noauto}} {
    debug.mgr/cspace {}
    # cmdr generate callback - (p)arameter argument. Ignored.

    # Modes
    # - auto   : If there is only a single space, take it without asking the user.
    # - noauto : Always ask the user.

    # generate callback for 'spacemgr delete|rename: name'.
    # Also: usermgr/login: PostLoginV2 proc

    # Implied client. Using the current org as our context.
    ::set choices [[corg get] @spaces]
    debug.mgr/cspace {SPACE [join $choices "\nSPACE "]}

    if {([llength $choices] == 1) && ($mode eq "auto")} {
	::set newspace [lindex $choices 0]
	display "Choosing the one available space: \"[$newspace @name]\""
	return $newspace
    }

    if {(![cmdr interactive?] ||
	 ![llength $choices]) &&
	[$p config has @ignore-missing] &&
	[$p config @ignore-missing]} {
	return {}
    }

    if {![cmdr interactive?]} {
	debug.mgr/cspace {no interaction}
	$p undefined!
	# implied return/failure
    }

    if {![llength $choices]} {
	warn "No spaces available to ${what}. [self please link-user-space] to connect users with spaces."
    }

    foreach o $choices {
	dict set map [$o @name] $o
    }
    ::set choices [lsort -dict [dict keys $map]]
    ::set name [term ask/menu "" \
		    "Which space to $what ? " \
		    $choices]

    return [dict get $map $name]
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::cspace::Show {} {
    variable current
    if {![info exists current]} { return UNDEF }
    if {$current eq {}}         { return $current }
    return "$current ([$current id] = \"[$current @name]\")"
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::cspace 0
