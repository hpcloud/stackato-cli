# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

## -*- tcl -*-
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
package require cmdr::validate
package require stackato::mgr::self
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
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-unknown-simple-msg
    namespace import ::stackato::mgr::self
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

    refresh-client $p

    # NOTE: service-plans are not searchable server-side by name.
    # Search must be done client-side. Should not be a big issue
    # as we are already restricted to the plans of the vendor,
    # which should be small.

    set vendor  [$p config @vendor]
    set matches [$vendor @service_plans get* {
	depth 1 include-relations service
    } filter-by @name $x]

    # Drop plans based on inactive service types.
    set matches [struct::list filter $matches [lambda {s} {
	$s @service @active
    }]]

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
    fail-unknown-simple-msg \
	"[self please service-plans Run] to see list of service plans and vendors" \
	$p SERVICEPLAN "service plan" $x " for '[$vendor @label]'"
}

# # ## ### ##### ######## ############# #####################

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::serviceplan 0
