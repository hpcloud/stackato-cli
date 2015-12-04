# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Service Instances, Not
## Dependency: config @client, current space.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate
package require stackato::mgr::client;# pulls v2 also
package require stackato::mgr::cspace
package require stackato::validate::common

debug level  validate/notserviceinstance
debug prefix validate/notserviceinstance {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export notserviceinstance
    namespace ensemble create
}

namespace eval ::stackato::validate::notserviceinstance {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-known-thing
    namespace import ::stackato::validate::common::refresh-client
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::v2
}

proc ::stackato::validate::notserviceinstance::default  {p}   { return {} }
proc ::stackato::validate::notserviceinstance::release  {p x} { return }
proc ::stackato::validate::notserviceinstance::complete {p x} { return {} }

proc ::stackato::validate::notserviceinstance::validate {p x} {
    debug.validate/notserviceinstance {}

    if {![[refresh-client $p] isv2]} {
	# Against a v1 target we cannot validate and accept all
	debug.validate/notserviceinstance {OK/v1 pass = $x}
	return $x
    }

    set thespace [cspace get]
    if {$thespace eq {}} {
	# No space to check against. Accept all and hope that later
	# REST calls will error out properly.

	debug.validate/notserviceinstance {NO-SPACE/pass = $x}
	return $x
    }

    dict set sc user-provided true
    dict set sc q             name:$x

    set matches [$thespace @service_instances get* $sc]

    if {![llength $matches]} {
	debug.validate/notserviceinstance {OK/canon = $x}
	return $x
    }
    debug.validate/notserviceinstance {FAIL}
    fail-known-thing $p NOTSERVICEINSTANCE "service instance" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::notserviceinstance 0
