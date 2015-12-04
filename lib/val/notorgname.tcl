# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Organization names, NOT
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate
package require stackato::mgr::client
package require stackato::validate::common

debug level  validate/notorgname
debug prefix validate/notorgname {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export notorgname
    namespace ensemble create
}

namespace eval ::stackato::validate::notorgname {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-known-thing
    namespace import ::stackato::v2
    namespace import ::stackato::validate::common::refresh-client
}

proc ::stackato::validate::notorgname::default  {p}   { return {} }
proc ::stackato::validate::notorgname::release  {p x} { return }
proc ::stackato::validate::notorgname::complete {p x} { return {} }

proc ::stackato::validate::notorgname::validate {p x} {
    debug.validate/notorgname {}

    refresh-client $p

    try {
	v2 organization find-by-name $x
    } trap {STACKATO CLIENT V2 ORGANIZATION NAME NOTFOUND} {e o} {
	debug.validate/notorgname {OK}
	return $x
    } trap {STACKATO CLIENT V2 ORGANIZATION NAME} {e o} {
	# Swallow. Ambiguity means that the name is in use.
    }

    debug.validate/notorgname {FAIL}
    fail-known-thing $p NOTORGNAME "organization" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::notorgname 0
