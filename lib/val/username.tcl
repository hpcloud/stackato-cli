## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - User names
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

debug level  validate/username
debug prefix validate/username {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export username
    namespace ensemble create
}

namespace eval ::stackato::validate::username {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::fail
    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::stackato::mgr::client
    namespace import ::stackato::validate::common::refresh-client
    namespace import ::stackato::v2
}

proc ::stackato::validate::username::default  {p}   { return {} }
proc ::stackato::validate::username::release  {p x} { return }
proc ::stackato::validate::username::complete {p x} {
    set c [refresh-client $p]
    if {[$c isv2]} {
	# v2
	set possibles [struct::list map [v2 user list] [lambda {o} {
	    $o the_name
	}]]
    } else {
	# v1
	set possibles [struct::list map [$c users] [lambda {x} {
	    dict getit $x email
	}]]
    }
    complete-enum $possibles 0 $x
}

proc ::stackato::validate::username::validate {p x} {
    debug.validate/username {}

    set c [refresh-client $p]

    # TODO FUTURE: val/username -- mgr/client, v2/client -- consolidate in client class.

    if {[$c isv2]} {
	debug.validate/username {/v2}

	if {![catch {
	    set x [v2 user find-by-name $x]
	}]} {
	    debug.validate/username {OK/canon = $x}
	    return $x
	}
    } else {
	debug.validate/username {/v1}

	set possibles [struct::list map [$c users] [lambda {x} {
	    dict getit $x email
	}]]
	if {$x in $possibles} {
	    debug.validate/username {OK}
	    return $x
	}
    }
    debug.validate/username {FAIL}
    fail $p USERNAME "a user name" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::username 0
