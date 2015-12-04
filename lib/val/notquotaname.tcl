# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Quota plan names, NOT
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require cmdr::validate
package require stackato::mgr::client
package require stackato::validate::common

debug level  validate/notquotaname
debug prefix validate/notquotaname {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export notquotaname
    namespace ensemble create
}

namespace eval ::stackato::validate::notquotaname {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-known-thing
    namespace import ::stackato::v2
    namespace import ::stackato::validate::common::refresh-client
}

proc ::stackato::validate::notquotaname::default  {p}   { return {} }
proc ::stackato::validate::notquotaname::release  {p x} { return }
proc ::stackato::validate::notquotaname::complete {p x} { return {} }

proc ::stackato::validate::notquotaname::validate {p x} {
    debug.validate/notquotaname {}

    refresh-client $p

    try {
	v2 quota_definition find-by-name $x
    } trap {STACKATO CLIENT V2 QUOTA_DEFINITION NAME NOTFOUND} {e o} {
	debug.validate/notquotaname {OK}
	return $x
    } trap {STACKATO CLIENT V2 QUOTA_DEFINITION NAME} {e o} {
	# Swallow. Ambiguity means that the name is in use.
    }

    debug.validate/notquotaname {FAIL}
    fail-known-thing $p NOTQUOTANAME "quota plan" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::notquotaname 0
