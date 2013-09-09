## -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Service Plan (within type)
## Dependency: config @client
## Dependency: @vendor (context)

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate ;# Fail utility command.
package require stackato::mgr::client;# pulls v2 also
package require stackato::validate::common

debug level  validate/serviceplan
debug prefix validate/serviceplan {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export serviceplan
    namespace ensemble create
}

namespace eval ::stackato::validate::serviceplan {
    namespace export default validate complete release \
	get-candidates
    namespace ensemble create

    namespace import ::cmdr::validate::common::fail
    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::stackato::mgr::corg
    namespace import ::stackato::v2
    namespace import ::stackato::validate::common::refresh-client
}

proc ::stackato::validate::serviceplan::default  {p}   { return {} }
proc ::stackato::validate::serviceplan::release  {p x} { return }
proc ::stackato::validate::serviceplan::complete {p x} {
    refresh-client $p
    set possibles [[$p config @vendor] @service_plans @name]
    complete-enum $possibles 0 $x
}

proc ::stackato::validate::serviceplan::validate {p x} {
    debug.validate/serviceplan {}
    # Accept the default.
    if {$x eq {}} { debug.validate/serviceplan {OK/default} ; return $x }

    refresh-client $p

    set vendor  [$p config @vendor]
    set matches [$vendor @service_plans filter-by @name $x]

    # See also app.tcl, LocateService2, for equivalent code, based on
    # different input (manifest service specification).
    #
    # TODO/FUTURE: See if we can consolidate and refactor here and
    # there.

    if {[llength $matches] == 1} {
	# Found, good.
	set x [lindex $matches 0]
	debug.validate/serviceplan {OK/canon = $x}
	return $x
    }
    debug.validate/serviceplan {FAIL}
    fail $p SERVICEPLAN "a [$vendor @label] service plan" $x
}

# # ## ### ##### ######## ############# #####################

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::serviceplan 0
