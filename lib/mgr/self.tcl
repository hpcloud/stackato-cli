# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## This module manages information about the client itself.
## - Location
## - Name
## - Revision

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cd

namespace eval ::stackato::mgr {
    namespace export self
    namespace ensemble create
}

namespace eval ::stackato::mgr::self {
    namespace export topdir me revision exe plain-revision please
    namespace ensemble create
}

debug level  mgr/self
debug prefix mgr/self {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## API

proc ::stackato::mgr::self::topdir {} {
    debug.mgr/self {}
    variable topdir

    debug.mgr/self {= $topdir}
    return $topdir
}

proc ::stackato::mgr::self::please {cmd {prefix {Please use}}} {
    set msg "$prefix '"
    if {![stackato-cli exists *in-shell*] ||
	![stackato-cli get    *in-shell*]} {
	# Not in a shell, full message.
	append msg [me] " "
    }
    append msg $cmd '
    return $msg
}

proc ::stackato::mgr::self::me {} {
    debug.mgr/self {}
    variable me
    if {[info exists me]} {
	debug.mgr/self {= $me}
	return $me
    }

    variable wrapped

    debug.mgr/self {fill cache, wrapped=$wrapped}
    if {$wrapped} {
	set base [info nameofexecutable]
    } else {
	global argv0
	set base $argv0
    }

    set me [file tail $base]
    debug.mgr/self {= $me}
    return $me
}

proc ::stackato::mgr::self::revision {} {
    debug.mgr/self {}
    set revfile [topdir]/revision.txt
    if {![file exists $revfile]} {
	cd::indir [topdir] {
	    set rev "local: [exec git describe]"
	}
    } else {
	set rev "wrapped: [fileutil::cat $revfile]"
    }

    debug.mgr/self {= $rev}
    return $rev
}

proc ::stackato::mgr::self::plain-revision {} {
    debug.mgr/self {}
    set revfile [topdir]/revision.txt
    if {![file exists $revfile]} {
	cd::indir [topdir] {
	    set rev [exec git describe]
	}
    } else {
	set rev [fileutil::cat $revfile]
    }

    debug.mgr/self {= $rev}
    return $rev
}

proc ::stackato::mgr::self::exe {} {
    debug.mgr/self {}
    variable wrapped

    debug.mgr/self {wrapped=$wrapped}
    set noe [info nameofexecutable]

    if {$wrapped} {
	set exe [list $noe]
    } else {
	global argv0
	set exe [list $noe $argv0]
    }
    debug.mgr/self {= $exe}
    return $exe
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::mgr::self {
    variable self    [file normalize [info script]]
    variable topdir  [file dirname [file dirname [file dirname $self]]]
    variable wrapped [expr {[lindex [file system [info script]] 0] ne "native"}]
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::self 0
