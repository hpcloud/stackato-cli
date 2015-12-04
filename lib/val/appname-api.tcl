# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Application names + Special string "api".
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate
package require stackato::mgr::self
package require stackato::mgr::client
package require stackato::mgr::cspace
package require stackato::validate::common

debug level  validate/appname-api
debug prefix validate/appname-api {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export appname-api
    namespace ensemble create
}

namespace eval ::stackato::validate::appname-api {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-unknown-simple-msg
    namespace import ::stackato::mgr::self
    namespace import ::stackato::mgr::client
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::validate::common::refresh-client
    namespace import ::stackato::validate::common::nospace
}

proc ::stackato::validate::appname-api::default  {p}   { return {} }
proc ::stackato::validate::appname-api::release  {p x} { return }
proc ::stackato::validate::appname-api::complete {p x} {
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

    lappend possibles api
    complete-enum $possibles 0 $x
}

proc ::stackato::validate::appname-api::validate {p x} {
    debug.validate/appname-api {}

    # Accept the special form "api", and the default. The manifest
    # processing will come up with the proper name.
    if {($x eq "api") || ($x eq {})} {
	debug.validate/appname-api {OK}
	return $x
    }

    set c [refresh-client $p]

    # TODO FUTURE: val/appname-api -- mgr/client, v2/client -- consolidate in client class.

    if {[$c isv2]} {
	debug.validate/appname-api {/v2}

	set thespace [cspace get]
	if {$thespace eq {}} {
	    # No space to check against.
	    # No way to convert the application name into object.
	    debug.validate/appname-api {FAIL/missing space}
	    nospace $p APPNAME "application name" $x
	}

	# find app by name in current space.
	set matches [$thespace @apps get* [list q name:$x]]
	# NOTE: searchable-on in v2/space should help
	# (in v2/org using it) to filter server side.

	if {[llength $matches] == 1} {
	    # Found, good.
	    set x [lindex $matches 0]
	    debug.validate/appname-api {OK/canon = $x}
	    return $x
	}
    } else {
	debug.validate/appname-api {/v1}

	if {[client app-exists? $c $x]} {
	    debug.validate/appname-api {OK}
	    return $x
	}
    }

    debug.validate/appname-api {FAIL}
    fail-unknown-simple-msg \
	"[self please apps Run] to see list of applications" \
	$p APPNAME-API "application" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::appname-api 0
