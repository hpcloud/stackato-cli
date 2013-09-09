# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

## This module manages the set of persistent configuration files used
## by the cli.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require fileutil

namespace eval ::stackato::mgr {
    namespace export cfile
    namespace ensemble create
}

namespace eval ::stackato::mgr::cfile {
    namespace export fix-permissions names get getc
    namespace ensemble create
}

debug level  mgr/cfile
debug prefix mgr/cfile {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## API

# # ## ### ##### ######## ############# #####################

if {$::tcl_platform(platform) eq "windows"} {
    #checker exclude warnRedefine
    proc ::stackato::mgr::cfile::fix-permissions {path {mask_ignored {}}} {
	debug.mgr/cfile {/windows}
	#checker exclude nonPortCmd
	file attribute $path -readonly 0
    }
} else {
    #checker exclude warnRedefine
    proc ::stackato::mgr::cfile::fix-permissions {path {mask 0600}} {
	debug.mgr/cfile {/unix}
	#checker exclude nonPortCmd
	file attribute $path -permissions $mask
    }
}

proc ::stackato::mgr::cfile::names {key} {
    debug.mgr/cfile {}
    variable config
    return [dict get $config $key]
}

proc ::stackato::mgr::cfile::getc {key p {suffix {}}} { get $key $suffix }

proc ::stackato::mgr::cfile::get {key {suffix {}}} {
    debug.mgr/cfile {}
    variable config

    # Search for the possible configuration files we maintain.
    set files [dict get $config $key]
    set first 1
    set found 0

    foreach f $files {
	set f $f$suffix
	if {![file exists $f]} { set first 0 ; continue }
	set found 1
	break
    }

    set ff [lindex $files 0]$suffix

    if {!$found} {
	# First in the list is the default we should write to.
	return $ff
    }

    # We found an older file. To shorten future searches we now copy
    # it over to the first, primary file to use. We do not delete the
    # older file tough, so that older clients may still have, although
    # the information may be outdated.

    if {!$first} {
	file mkdir [file dirname $ff]
	file copy -- $f $ff
    }

    # With the copy of the old file in place of the primary we can
    # always return the path to the primary file for reading (or
    # writing).

    return [file normalize $ff]
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::mgr::cfile {
    variable config {
	target    {~/.stackato/client/target    ~/.stackato/target    ~/.stackato_target   }
	token     {~/.stackato/client/token     ~/.stackato/token     ~/.stackato_token    }
	token2    {~/.stackato/client/token2}
	key       {~/.stackato/client/key       ~/.stackato/key       ~/.stackato_key      }
	instances {~/.stackato/client/instances ~/.stackato/instances ~/.stackato_instances}
	aliases   {~/.stackato/client/aliases   ~/.stackato/aliases   ~/.stackato_aliases ~/.stackato-aliases}
	clients   {~/.stackato/client/clients   ~/.stackato/clients   ~/.stackato_clients}
	group     {~/.stackato/client/group}
	rest      {~/.stackato/client/trace-rest}
    }
}

# Normalize the ~ in the paths, to show full paths in debug output.
apply {{} {
    variable config
    set newc {}
    foreach {k v} $config {
	set new {}
	foreach path $v {
	    lappend new [file normalize $path]
	}
	lappend newc $k $new
    }
    set config $newc

} ::stackato::mgr::cfile}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::cfile 0
