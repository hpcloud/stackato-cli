# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

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
package require stackato::log
package require stackato::mgr::tadjunct
package require stackato::mgr::ctarget
package require stackato::mgr::corg
package require stackato::term
package require stackato::v2::client

namespace eval ::stackato::mgr {
    namespace export cspace
    namespace ensemble create
}

namespace eval ::stackato::mgr::cspace {
    namespace export set get get-auto reset save select-for setc getc
    namespace ensemble create

    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::tadjunct
    namespace import ::stackato::mgr::ctarget
    namespace import ::stackato::mgr::corg
    namespace import ::stackato::term
    namespace import ::stackato::v2
}

debug level  mgr/cspace
debug prefix mgr/cspace {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## API

proc ::stackato::mgr::cspace::setc {p name} { set $name }
proc ::stackato::mgr::cspace::getc {p}      { get }

proc ::stackato::mgr::cspace::set {obj} {
    debug.mgr/cspace {}
    variable current $obj
    return
}

proc ::stackato::mgr::cspace::get {} {
    debug.mgr/cspace {}
    variable current

    if {![info exists current]} {
	debug.mgr/cspace {fill cache}

	::set target [ctarget get]
	::set known  [tadjunct known]

	debug.mgr/cspace {from  $target}
	debug.mgr/cspace {known $known}

	#checker -scope line exclude badOption
	::set uuid [dict get' $known $target space {}]
	if {$uuid ne {}} {
	    # Convert uuid into entity instance in-memory.
	    ::set current [v2 deref-type space $uuid]
	} else {
	    ::set current {}
	}

    }

    debug.mgr/cspace {==> [Show]}
    return $current
}

proc ::stackato::mgr::cspace::get-auto {args} {
    debug.mgr/cspace {}
    # get, and if that fails, automagically determine and save a
    # suitable space.

    ::set space [get]
    if {$space ne {}} {
	debug.mgr/cspace {current ==> [Show]}
	return $space
    }

    ::set space [select-for choose auto]
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

proc ::stackato::mgr::cspace::select-for {what {mode noauto}} {
    debug.mgr/cspace {}

    # Modes
    # - auto   : If there is only a single space, take it without asking the user.
    # - noauto : Always ask the user.

    # generate callback for 'spacemgr delete|rename: name'.
    # Also: usermgr/login: PostLoginV2 proc

    # Implied client. Current org for context.
    ::set choices [[corg get] @spaces]
    debug.mgr/cspace {SPACE [join $choices "\nSPACE "]}

    if {([llength $choices] == 1) && ($mode eq "auto")} {
	return [lindex $choices 0]
    }

    if {![cmdr interactive?]} {
	debug.mgr/cspace {no interaction}
	cmdr::parameter undefined space
	# implied return/failure
    }

    if {![llength $choices]} {
	err "No spaces available to $what"
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
