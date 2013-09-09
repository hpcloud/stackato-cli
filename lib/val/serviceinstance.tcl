## -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Service Instances
## Dependency: config @client, current space.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate ;# Fail utility command.
package require stackato::mgr::client;# pulls v2 also
package require stackato::mgr::cspace
package require stackato::validate::common

debug level  validate/serviceinstance
debug prefix validate/serviceinstance {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export serviceinstance
    namespace ensemble create
}

namespace eval ::stackato::validate::serviceinstance {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::fail
    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::stackato::validate::common::refresh-client
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::v2
}

proc ::stackato::validate::serviceinstance::default  {p}   { return {} }
proc ::stackato::validate::serviceinstance::release  {p x} { return }
proc ::stackato::validate::serviceinstance::complete {p x} {
    if {![[refresh-client $p] isv2]} {
	# Against a v1 target we cannot complete.
	return {}
    }
    set space [cspace get]
    set possibles [expr {($space eq {}) ? {} : [$space @service_instances @name]}]
    complete-enum $possibles 0 $x
}

proc ::stackato::validate::serviceinstance::validate {p x} {
    debug.validate/serviceinstance {}

    # Accept the default.
    if {$x eq {}} { debug.validate/serviceinstance {OK/default} ; return $x }

    if {![[refresh-client $p] isv2]} {
	# Against a v1 target we cannot validate and accept all
	debug.validate/serviceinstance {OK/v1 pass = $x}
	return $x
    }

    set thespace [cspace get]
    if {$thespace eq {}} {
	# No space to check against.
	# No way to convert the instance name into object.
	debug.validate/serviceinstance {FAIL}
	fail $p SERVICEINSTANCE "a service instance name" $x
    }

    set matches [$thespace @service_instances filter-by @name $x]
    if {[llength $matches] == 1} {
	debug.validate/serviceinstance {OK/canon = $x}
	return [lindex $matches 0]
    }
    debug.validate/serviceinstance {FAIL}
    fail $p SERVICEINSTANCE "a service instance name" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::serviceinstance 0
