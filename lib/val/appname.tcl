# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Application names
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate
package require stackato::log
package require stackato::mgr::self
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
    namespace export default validate complete release known
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-unknown-simple-msg
    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::self
    namespace import ::stackato::mgr::client
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::validate::common::refresh-client
    namespace import ::stackato::validate::common::nospace
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

proc ::stackato::validate::appname::known {client x rv} {
    upvar 1 $rv intrep
    debug.validate/appname {}

    if {[$client isv2]} {
	debug.validate/appname {/v2}

	set thespace [cspace get]

	debug.validate/appname {space: $thespace}

	if {$thespace eq {}} {
	    # No space to check against.
	    # No way to convert the application name into object.
	    debug.validate/appname {FAIL/no space}
	    return 0
	}

	debug.validate/appname {space: $thespace [$thespace full-name]}

	# find app by name in current space.
	set matches [$thespace @apps get* [list q name:$x]]

	debug.validate/appname {matches = ($matches)}

	# NOTE: searchable-on in v2/space should help
	# (in v2/org using it) to filter server side.

	if {[llength $matches] == 1} {
	    # Found, good.
	    set intrep [lindex $matches 0]
	    debug.validate/appname {OK/canon = $x}
	    return 1
	}
    } else {
	debug.validate/appname {/v1}

	if {[client app-exists? $client $x]} {
	    debug.validate/appname {OK}
	    set intrep $x
	    return 1
	}
    }
    debug.validate/appname {FAIL/not found}
    return 0
}


proc ::stackato::validate::appname::validate {p x} {
    debug.validate/appname {}

    try {
	# Force setup of context, if not done yet. This can/will
	# happen for dbshell which does an application argument
	# validation as part of deciding if the argument is an
	# application or not (sole place oing this ('test' mode of
	# handling an optional parameter). As this swallows CMDR
	# VALIDATE errors we trap these and convert to a general error
	# to show that the test in itself could not be done.
	$p config @organization
	$p config @space
    } trap {CMDR VALIDATE} {e o} {
	err $e
    }

    set c [refresh-client $p]

    if {[$c isv2] && ([cspace get] eq {})} {
	debug.validate/appname {FAIL/missing space}
	nospace $p APPNAME "application name" $x
    }

    if {[known $c $x intrep]} {
	return $intrep
    }

    fail-unknown-simple-msg \
	"[self please apps Run] to see list of applications" \
	$p APPNAME "application" $x \
	[expr {[$c isv2]
	       ? " in space '[[cspace get] full-name]'"
	       : ""}]

}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::appname 0
