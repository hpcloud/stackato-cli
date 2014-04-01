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
    namespace import ::stackato::mgr::client
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::validate::common::refresh-client
    namespace import ::stackato::validate::common::nospace
    namespace import ::stackato::validate::common::expected
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

    set c [refresh-client $p]

    if {[$c isv2] && ([cspace get] eq {})} {
	debug.validate/appname {FAIL/missing space}
	nospace $p APPNAME "application name" $x
    }

    if {[known $c $x intrep]} {
	return $intrep
    }

    if {[$c isv2]} {
	expected $p APPNAME "application" $x " in space '[[cspace get] @name]'"
    } else {
	expected $p APPNAME "application" $x
    }
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::appname 0
