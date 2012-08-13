# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require try            ;# I want try/catch/finally
package require TclOO
package require dictutil

debug level  cli/framework/base
debug prefix cli/framework/base {[::debug::snit::call] | }

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::client::cli::framework::base {
    # # ## ### ##### ######## #############

    constructor {{key {}} {name {}} {options {}}} {
	Debug.cli/framework/base {}

	if {$name eq {}} {
	    set name $::stackato::client::cli::framework::default_frame
	}
	set myname $name
	#checker -scope local exclude badOption
	set mykey         [dict get' $options key $key]
	set mymemory      [dict get' $options mem $::stackato::client::cli::framework::default_mem]
	set mydescription [dict get' $options description Unknown]
	set myexec        [dict get' $options exec {}]
	return
    }

    destructor {
	Debug.cli/framework/base {}
    }

    # # ## ### ##### ######## #############
    ## API

    method key {} {
	Debug.cli/framework/base {}
	return $mykey
    }
    method name {} {
	Debug.cli/framework/base {}
	return $myname
    }
    method description {} {
	Debug.cli/framework/base {}
	return $mydescription
    }
    method memory {{runtime {}}} {
	Debug.cli/framework/base {}
	return $mymemory
    }
    method mem {{runtime {}}} { my memory $runtime }

    method exec {{value {}}} {
	Debug.cli/framework/base {}
	if {[llength [info level 0]] == 2} {
	    set myexec $value
	}
	return $myexec
    }

    # to_s = description.

    # query commands, overrideable in derived classes
    method require_url? {} {
	Debug.cli/framework/base {}
	return 1
    }
    method require_start_command? {} {
	Debug.cli/framework/base {}
	return 0
    }
    method prompt_for_runtime? {} {
	Debug.cli/framework/base {}
	return 0
    }
    method default_runtime {path} {
	Debug.cli/framework/base {}
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
package provide stackato::client::cli::framework::base 0
