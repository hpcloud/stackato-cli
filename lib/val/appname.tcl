## -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Application names
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate ;# Fail utility command.
package require stackato::mgr::client
package require stackato::mgr::cspace
package require stackato::validate::common

debug level  validate/appname
debug prefix validate/appname {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export appname
    namespace ensemble create
}

namespace eval ::stackato::validate::appname {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::fail
    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::stackato::mgr::client
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::validate::common::refresh-client
}

proc ::stackato::validate::appname::default  {p }  { return {} }
proc ::stackato::validate::appname::release  {p x} { return }
proc ::stackato::validate::appname::complete {p x} {
    set c [refresh-client $p]
    if {[$c isv2]} {
	# v2
	set space [cspace get]
	set possibles [expr {($space eq {}) ? {} : [$space @apps @name]}]
    } else {
	# v1
	set possibles [struct::list map [$c apps] [lambda {x} {
	    dict getit $x name
	}]]
    }
    complete-enum $possibles 0 $x
}

proc ::stackato::validate::appname::validate {p x} {
    debug.validate/appname {}
    # Accept the default. The manifest processing will come up with
    # the proper name.

    if {$x eq {}} {
	debug.validate/appname {OK/empty}
	return $x
    }

    set c [refresh-client $p]

    # TODO FUTURE: val/appname -- mgr/client, v2/client -- consolidate in client class.

    if {[$c isv2]} {
	debug.validate/appname {/v2}

	set thespace [cspace get]
	if {$thespace eq {}} {
	    # No space to check against.
	    # No way to convert the application name into object.
	    debug.validate/appname {FAIL}
	    fail $p APPNAME "an application name" $x
	}

	# find app by name in current space.
	set matches [$thespace @apps filter-by @name $x]
	# NOTE: searchable-on in v2/space should help
	# (in v2/org using it) to filter server side.

	if {[llength $matches] == 1} {
	    # Found, good.
	    set x [lindex $matches 0]
	    debug.validate/appname {OK/canon = $x}
	    return $x
	}
    } else {
	debug.validate/appname {/v1}

	if {[client app-exists? $c $x]} {
	    debug.validate/appname {OK}
	    return $x
	}
    }
    debug.validate/appname {FAIL}
    fail $p APPNAME "an application name" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::appname 0
