# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

## This module manages the persistent database of targets we are
## logged into. Note that this database maps from target to
## authentication token for that target.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require fileutil
package require json
package require stackato::mgr::cfile

namespace eval ::stackato::mgr {
    namespace export targets
    namespace ensemble create
}
namespace eval ::stackato::mgr::targets {
    namespace export \
	has add remove remove-all known store \
	set-path get-path keyfile reset
    namespace ensemble create

    namespace import ::stackato::mgr::cfile
}

debug level  mgr/targets
debug prefix mgr/targets {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## API for the user visible commands.

proc ::stackato::mgr::targets::has {url} {
    return [dict exists [known] $url]
}

proc ::stackato::mgr::targets::add {url token {sshkey}} {
    debug.mgr/targets {}

    set targets [known] ;#dict
    dict set targets $url $token
    Store $targets

    if {[llength [info level 0]] <= 3} return
    if {$sshkey eq {}} return
    # We have an ssh key. Save it as well.
    StoreSSH $token $sshkey
    return
}

proc ::stackato::mgr::targets::remove {url} {
    debug.mgr/targets {}

    set targets [known] ;#dict
    set token   [dict get' $targets $url {}]
    dict unset targets $url
    Store $targets

    RemoveSSH $token
    return
}

proc ::stackato::mgr::targets::remove-all {} {
    debug.mgr/targets {}
    Clear
    return
}

proc ::stackato::mgr::targets::keyfile {token} {
    debug.mgr/targets {}
    set path [cfile get key _$token]

    debug.mgr/targets {= $path}
    return $path
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::targets::reset {} {
    debug.mgr/targets {}
    variable cfile ; unset -nocomplain cfile
    return
}

# # ## ### ##### ######## ############# #####################
## Access to the name of the database file.
## Default is overridable from higher layers (--token-file).

proc ::stackato::mgr::targets::set-path {p name} {
    debug.mgr/targets {}
    variable cfile $name
    return
}

proc ::stackato::mgr::targets::get-path {} {
    debug.mgr/targets {}
    variable cfile

    if {![info exists cfile]} {
	#checker -scope line exclude badOption
	set cfile [cfile get token]
    }

    debug.mgr/targets {==> $cfile}
    return $cfile
}

# # ## ### ##### ######## ############# #####################
## Low level access to the client's persistent state for targets.

proc ::stackato::mgr::targets::known {} {
    debug.mgr/targets {}

    set path [get-path]

    if {![fileutil::test $path efr]} {
	return {}
    }

    # @todo@ cache json parse result ?
    return [json::json2dict \
		[string trim \
		     [fileutil::cat $path]]]
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::targets::Clear {} {
    debug.mgr/targets {}

    set todelete [cfile names token]
    foreach stem [cfile names key] {
	lappend todelete {*}[glob -nocomplain ${stem}*]
    }
    file delete -- {*}$todelete
    return
}

proc ::stackato::mgr::targets::Store {targets} {
    debug.mgr/targets {}
    # targets = dict, cmd -> true command.

    set path [get-path]
    fileutil::writeFile   $path [stackato::jmap targets $targets]\n
    cfile fix-permissions $path

    debug.mgr/targets {OK}
    return
}

proc ::stackato::mgr::targets::StoreSSH {token sshkey} {
    debug.mgr/targets {}

    set path [cfile get key _$token]
    fileutil::writeFile   $path $sshkey
    cfile fix-permissions $path
    return
}

proc ::stackato::mgr::targets::RemoveSSH {token} {
    debug.mgr/targets {}

    if {$token eq {}} return

    set todelete {}
    foreach stem [cfile names key] {
	foreach kf [glob -nocomplain ${stem}*] {
	    debug.mgr/targets {candidate: $kf}
	    if {![string match key_${token}* [file tail $kf]]} continue
	    debug.mgr/targets {schedule for delete: $kf}
	    lappend todelete $kf
	}
    }

    if {![llength $todelete]} return
    debug.mgr/targets {delete [join $todelete "\ndelete "]}

    file delete -- {*}$todelete
    return
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::mgr::targets {
    variable cfile
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::targets 0
