# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## This module manages the persistent database of per-target adjunct
## information for all targets we are logged into. Note that this
## database maps from target to a dictionary of data. The main
## information, the authentication token (and ssh key), are handled
## separately, by the 'targets' manager. For compatibility.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require fileutil
package require json
package require stackato::mgr::cfile
package require stackato::log

namespace eval ::stackato::mgr {
    namespace export tadjunct
    namespace ensemble create
}
namespace eval ::stackato::mgr::tadjunct {
    namespace export \
	has add remove remove-all known store \
	set-path get-path keyfile reset get get'
    namespace ensemble create

    namespace import ::stackato::mgr::cfile
    namespace import ::stackato::log::err
}

debug level  mgr/tadjunct
debug prefix mgr/tadjunct {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## API for the user visible commands.

proc ::stackato::mgr::tadjunct::has {url} {
    return [dict exists [known] $url]
}

proc ::stackato::mgr::tadjunct::add {url key value} {
    debug.mgr/tadjunct {}

    set tadjunct [known] ;#dict
    dict set tadjunct $url $key $value
    Store $tadjunct
    return
}

proc ::stackato::mgr::tadjunct::get {url key} {
    debug.mgr/tadjunct {}
    return [dict get [known] $url $key]
}

proc ::stackato::mgr::tadjunct::get' {url key default} {
    debug.mgr/tadjunct {}
    #checker -scope line exclude badOption
    return [dict get' [known] $url $key $default]
}

proc ::stackato::mgr::tadjunct::remove {url {key {}}} {
    debug.mgr/tadjunct {}
    set tadjunct [known] ;#dict

    if {$key eq {}} {
	dict unset tadjunct $url
    } elseif {[dict exists $tadjunct $url $key]} {
	dict unset tadjunct $url $key
    }
    Store $tadjunct
    return
}

proc ::stackato::mgr::tadjunct::remove-all {} {
    debug.mgr/tadjunct {}
    Clear
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::tadjunct::reset {} {
    debug.mgr/tadjunct {}
    variable cfile ; unset -nocomplain cfile
    return
}

# # ## ### ##### ######## ############# #####################
## Access to the name of the database file.
## Default is overridable from higher layers (--token-file).

proc ::stackato::mgr::tadjunct::set-path {name} {
    debug.mgr/tadjunct {}
    variable cfile $name
    return
}

proc ::stackato::mgr::tadjunct::get-path {} {
    debug.mgr/tadjunct {}
    variable cfile

    if {![info exists cfile]} {
	#checker -scope line exclude badOption
	set cfile [cfile get token2]
    }

    debug.mgr/tadjunct {==> $cfile}
    return $cfile
}

# # ## ### ##### ######## ############# #####################
## Low level access to the client's persistent state for tadjunct.

proc ::stackato::mgr::tadjunct::known {} {
    debug.mgr/tadjunct {}

    set path [get-path]

    if {![fileutil::test $path efr]} {
	return {}
    }

    # @todo@ cache json parse result ?
    try {
	set adjunct [json::json2dict \
			 [string trim \
			      [fileutil::cat $path]]]
    } trap {JSON} {e o} {
	err "Bad configuration file $path: Bad JSON: $e"
    }
    return $adjunct
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::tadjunct::Clear {} {
    debug.mgr/tadjunct {}
    file delete -- {*}[cfile names token2]
    return
}

proc ::stackato::mgr::tadjunct::Store {tadjunct} {
    debug.mgr/tadjunct {}
    # tadjunct = dict, cmd -> true command.

    set path [get-path]
    fileutil::writeFile   $path [stackato::jmap tadjunct $tadjunct]\n
    cfile fix-permissions $path

    debug.mgr/tadjunct {OK}
    return
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::mgr::tadjunct {
    variable cfile
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::tadjunct 0
