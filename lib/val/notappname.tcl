## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Application names, NOT
##                              Yet possible
## <==> syntactically valid app-name, not known to target.
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
package require stackato::validate::appname-lex
package require stackato::validate::common

debug level  validate/notappname
debug prefix validate/notappname {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export notappname
    namespace ensemble create
}

namespace eval ::stackato::validate::notappname {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::fail
    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::stackato::mgr::client
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::validate::common::refresh-client
    namespace import ::stackato::validate::common::not
    namespace import ::stackato::validate::appname-lex
}

proc ::stackato::validate::notappname::default  {p}   { return {} }
proc ::stackato::validate::notappname::release  {p x} { return }
proc ::stackato::validate::notappname::complete {p x} { return {} }

proc ::stackato::validate::notappname::validate {p x} {
    debug.validate/notappname {}
    # Accept the default. The manifest processing will come up with
    # the proper name.

    if {$x eq {}} {
	debug.validate/notappname {OK/empty}
	return $x
    }

    set c [refresh-client $p]

    if {[$c isv2]} {
	debug.validate/notappname {/v2}

	set thespace [cspace get]
	if {$thespace eq {}} {
	    if {![appname-lex ok $p $x]} {
		debug.validate/notappname {FAIL}
		fail $p NOTAPPNAME "an application name" $x
	    }

	    # No space to check against. Accept all and hope that later
	    # REST calls will error out properly.

	    debug.validate/notappname {NO-SPACE/pass = $x}
	    return $x
	}

	# find app by name in current space.
	set matches [$thespace @apps get* [list q name:$x]]
	# NOTE: searchable-on in v2/space should help
	# (in v2/org using it) to filter server side.

	if {![llength $matches]} {
	    # Not found, good.
	    if {![appname-lex ok $p $x]} {
		debug.validate/notappname {FAIL}
		fail $p NOTAPPNAME "an application name" $x
	    }

	    debug.validate/notappname {OK/canon = $x}
	    return $x
	}
    } else {
	debug.validate/notappname {/v1}

	if {![client app-exists? $c $x]} {
	    if {![appname-lex ok $p $x]} {
		debug.validate/notappname {FAIL}
		fail $p NOTAPPNAME "an application name" $x
	    }

	    debug.validate/notappname {OK}
	    return $x
	}
    }

    debug.validate/notappname {FAIL}
    not $p NOTAPPNAME "application" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::notappname 0
