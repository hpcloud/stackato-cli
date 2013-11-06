## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - User names, NOT
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate ;# Fail utility command.
package require stackato::mgr::client
package require stackato::validate::common

debug level  validate/notusername
debug prefix validate/notusername {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export notusername
    namespace ensemble create
}

namespace eval ::stackato::validate::notusername {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::fail
    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::stackato::mgr::client
    namespace import ::stackato::validate::common::refresh-client
    namespace import ::stackato::v2
}

proc ::stackato::validate::notusername::default  {p}   { return {} }
proc ::stackato::validate::notusername::release  {p x} { return }
proc ::stackato::validate::notusername::complete {p x} { return {} }

proc ::stackato::validate::notusername::validate {p x} {
    debug.validate/notusername {}

    set c [refresh-client $p]

    # TODO FUTURE: val/notusername -- mgr/client, v2/client -- consolidate in client class.

    if {[$c isv2]} {
	debug.validate/notusername {/v2}

	try {
	    v2 user find-by-name $x
	} trap {STACKATO CLIENT V2 USER NAME NOTFOUND} {e o} {
	    debug.validate/notusername {OK}
	    return $x
	} trap {STACKATO CLIENT V2 USER NAME} {e o} {
	    # Swallow. Ambiguity means that the name is in use.
	}
    } else {
	debug.validate/notusername {/v1}

	set possibles [struct::list map [$c users] [lambda {x} {
	    dict getit $x email
	}]]
	if {$x ni $possibles} {
	    debug.validate/notusername {OK}
	    return $x
	}
    }
    debug.validate/notusername {FAIL}
    fail $p NOTUSERNAME "an unused user name" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::notusername 0
