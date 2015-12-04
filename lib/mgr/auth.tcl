# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## This module manages the current (active) authentication token.
## Note that persistence is handled through the "targets" manager, with
## the help of the current target. I.e. in a per-target manner.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require stackato::mgr::targets
package require stackato::mgr::ctarget

namespace eval ::stackato::mgr {
    namespace export auth
    namespace ensemble create
}

namespace eval ::stackato::mgr::auth {
    namespace import ::stackato::mgr::targets
    namespace import ::stackato::mgr::ctarget
}

debug level  mgr/auth
debug prefix mgr/auth {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## API

proc ::stackato::mgr::auth::setc {p token} { set $token }
proc ::stackato::mgr::auth::getc {p} { get }

proc ::stackato::mgr::auth::set {token} {
    debug.mgr/auth {}

    variable current $token
    return
}

proc ::stackato::mgr::auth::get {} {
    debug.mgr/auth {}
    variable current

    if {![info exists current]} {
	debug.mgr/auth {fill cache}

	::set target [ctarget get]
	::set known  [targets known]

	debug.mgr/auth {from $target}
	debug.mgr/auth {known $known}

	#checker -scope line exclude badOption
	::set current [dict get' $known $target {}]
    }

    debug.mgr/auth {==> $current}
    return $current
}

proc ::stackato::mgr::auth::reset {} {
    debug.mgr/auth {}
    variable current
    unset -nocomplain current
    return
}

proc ::stackato::mgr::auth::save {} {
    debug.mgr/auth {}
    variable current

    if {[info exists current] && ($current ne {})} {
	targets add [ctarget get] $current
    } else {
	targets remove [ctarget get]
    }

    debug.mgr/auth {OK}
    return
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::mgr::auth {
    namespace export set get reset save setc getc
    namespace ensemble create
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::auth 0
