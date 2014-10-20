## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Service Plan (within type), Not
## Dependency: config @client
## Dependency: @vendor (context)

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate
package require stackato::mgr::client;# pulls v2 also
package require stackato::validate::common

debug level  validate/notserviceplan
debug prefix validate/notserviceplan {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export serviceplan
    namespace ensemble create
}

namespace eval ::stackato::validate::notserviceplan {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-known-thing
    namespace import ::stackato::mgr::corg
    namespace import ::stackato::v2
    namespace import ::stackato::validate::common::refresh-client
}

proc ::stackato::validate::notserviceplan::default  {p}   { return {} }
proc ::stackato::validate::notserviceplan::release  {p x} { return }
proc ::stackato::validate::notserviceplan::complete {p x} { return {} }

proc ::stackato::validate::notserviceplan::validate {p x} {
    debug.validate/notserviceplan {}

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

    if {![llength $matches]} {
	# Not found, good.
	debug.validate/notserviceplan {OK = $x}
	return $x
    }
    # Something found, bad.
    debug.validate/notserviceplan {FAIL}
    fail-known-thing $p NOTSERVICEPLAN "service plan" $x " for '[$vendor @label]'"
}

# # ## ### ##### ######## ############# #####################

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::notserviceplan 0
