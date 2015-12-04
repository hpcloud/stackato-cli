# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Service Auth Tokens, Not
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require cmdr::validate
package require stackato::mgr::client;# pulls v2 also
package require stackato::validate::common

debug level  validate/notserviceauthtoken
debug prefix validate/notserviceauthtoken {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export notserviceauthtoken
    namespace ensemble create
}

namespace eval ::stackato::validate::notserviceauthtoken {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-known-thing
    namespace import ::stackato::validate::common::refresh-client
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::v2
}

proc ::stackato::validate::notserviceauthtoken::default  {p}   { return {} }
proc ::stackato::validate::notserviceauthtoken::release  {p x} { return }
proc ::stackato::validate::notserviceauthtoken::complete {p x} { return {} }

proc ::stackato::validate::notserviceauthtoken::validate {p x} {
    debug.validate/notserviceauthtoken {}

    refresh-client $p

    # See also query.tcl, map-named-entity.
    set matches [v2 service_auth_token list 0 q label:$x]

    if {![llength $matches]} {
	debug.validate/notserviceauthtoken {OK/canon = $x}
	return $x
    }
    debug.validate/notserviceauthtoken {FAIL}
    fail-known-thing $p NOTSERVICEAUTHTOKEN "service auth token" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::notserviceauthtoken 0
