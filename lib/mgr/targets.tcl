# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## This module manages the persistent database of targets we are
## logged into. Note that this database maps from target to
## authentication token for that target.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require fileutil
package require json
package require url
package require stackato::mgr::cfile
package require stackato::log

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
    namespace import ::stackato::log::err
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
    StoreSSH $url $token $sshkey
    return
}

proc ::stackato::mgr::targets::remove {url} {
    debug.mgr/targets {}

    set targets [known] ;#dict
    set token   [dict get' $targets $url {}]
    dict unset targets $url
    Store $targets

    RemoveSSH $url $token
    return
}

proc ::stackato::mgr::targets::remove-all {} {
    debug.mgr/targets {}
    Clear
    return
}

proc ::stackato::mgr::targets::keyfile {url token} {
    debug.mgr/targets {}

    set url  [url domain $url]
    set path [cfile get key _$url]

    if {![file exists $path]} {
	set path [cfile get key _$token]
    }

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

    try {
	set data [fileutil::cat $path]
	debug.mgr/targets {data = ($data)}

	set map [json::json2dict [string trim $data]]
	debug.mgr/targets {map = ($map)}
    } trap {JSON} {e o} {
	err "JSON error reading token-file \"$path\": $e"
    }
    try {
	dict size $map
    } on error {e o} {
	err "General error reading token-file \"$path\": Expected json object not found"
    }
    return $map
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

proc ::stackato::mgr::targets::StoreSSH {url token sshkey} {
    debug.mgr/targets {}

    # Store SSH keyed by target.  While originally keyed by token, the
    # token is based on the target. While the token is principally
    # dependent on the user we log in as as well, only one user can be
    # logged in per target and the unix user we are. Storage under
    # $HOME takes care of the latter, and keying by target of the
    # former.
   
    set path [cfile get key _[url domain $url]]
    fileutil::writeFile   $path $sshkey
    cfile fix-permissions $path
    return
}

proc ::stackato::mgr::targets::RemoveSSH {url token} {
    debug.mgr/targets {}

    set url [url domain $url]

    set todelete {}
    foreach stem [cfile names key] {
	foreach kf [glob -nocomplain -- ${stem}*] {
	    debug.mgr/targets {candidate: $kf}
	    # Delete key stored per token (old-style), and key stored
	    # per target (new).
	    if {($token ne {}) && [string match key_${token}* [file tail $kf]]} {
		debug.mgr/targets {schedule for delete: $kf}
		lappend todelete $kf
	    }
	    if {($url ne {}) && [string match key_${url}* [file tail $kf]]} {
		debug.mgr/targets {schedule for delete: $kf}
		lappend todelete $kf
	    }
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
