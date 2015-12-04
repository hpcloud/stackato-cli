# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Buildpacks, Not.
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate
package require stackato::mgr::client;# pulls v2 also
package require stackato::validate::common

debug level  validate/notbuildpack
debug prefix validate/notbuildpack {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export notbuildpack
    namespace ensemble create
}

namespace eval ::stackato::validate::notbuildpack {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-known-thing
    namespace import ::stackato::v2
    namespace import ::stackato::validate::common::refresh-client
}

proc ::stackato::validate::notbuildpack::default  {p}   { return {} }
proc ::stackato::validate::notbuildpack::release  {p x} { return }
proc ::stackato::validate::notbuildpack::complete {p x} { return {} }

proc ::stackato::validate::notbuildpack::validate {p x} {
    debug.validate/notbuildpack {}

    refresh-client $p

    try {
	v2 buildpack find-by-name $x

    } trap {STACKATO CLIENT V2 BUILDPACK NAME NOTFOUND} {e o} {
	debug.validate/notbuildpack {OK}
	return $x
    } trap {STACKATO CLIENT V2 BUILDPACK NAME} {e o} {
	# Swallow. Ambiguity means that the name is in use.
    }

    debug.validate/notbuildpack {FAIL}
    fail-known-thing $p NOTBUILDPACK "buildpack" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::notbuildpack 0
