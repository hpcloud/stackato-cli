# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require dictutil

debug level  mgr/framework/base
debug prefix mgr/framework/base {[debug caller] | }

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::mgr::framework::base {
    # # ## ### ##### ######## #############

    constructor {{key {}} {name {}} {options {}}} {
	namespace eval [self namespace] {
	    namespace import ::stackato::mgr::framework
	}

	debug.mgr/framework/base {}

	if {$name eq {}} {
	    set name [framework defaultframe]
	}
	set myname $name
	#checker -scope local exclude badOption
	set mykey         [dict get' $options key $key]
	set mymemory      [dict get' $options mem [framework defaultmem]]
	set mydescription [dict get' $options description Unknown]
	set myexec        [dict get' $options exec {}]
	return
    }

    destructor {
	debug.mgr/framework/base {}
    }

    # # ## ### ##### ######## #############
    ## API

    method key {} {
	debug.mgr/framework/base {}
	return $mykey
    }
    method name {} {
	debug.mgr/framework/base {}
	return $myname
    }
    method description {} {
	debug.mgr/framework/base {}
	return $mydescription
    }
    method memory {{runtime {}}} {
	debug.mgr/framework/base {}
	return $mymemory
    }
    method mem {{runtime {}}} { my memory $runtime }

    method exec {{value {}}} {
	debug.mgr/framework/base {}
	if {[llength [info level 0]] == 2} {
	    set myexec $value
	}
	return $myexec
    }

    # to_s = description.

    # query commands, overrideable in derived classes
    method require_url? {} {
	debug.mgr/framework/base {}
	return 1
    }
    method require_start_command? {} {
	debug.mgr/framework/base {}
	return 0
    }
    method prompt_for_runtime? {} {
	debug.mgr/framework/base {}
	return 0
    }
    method default_runtime {path} {
	debug.mgr/framework/base {}
	return {}
    }

    # # ## ### ##### ######## #############
    ## Internal commands.

    # # ## ### ##### ######## #############
    ## State

    variable myname mydescription mymemory myexec mykey

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::framework::base 0
