# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Space Quota plans, NOT
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require cmdr::validate
package require stackato::mgr::client
package require stackato::validate::common

debug level  validate/notspacequota
debug prefix validate/notspacequota {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export notspacequota
    namespace ensemble create
}

namespace eval ::stackato::validate::notspacequota {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-known-thing
    namespace import ::stackato::v2
    namespace import ::stackato::validate::common::refresh-client
}

proc ::stackato::validate::notspacequota::default  {p}   { return {} }
proc ::stackato::validate::notspacequota::release  {p x} { return }
proc ::stackato::validate::notspacequota::complete {p x} { return {} }

proc ::stackato::validate::notspacequota::validate {p x} {
    debug.validate/notspacequota {}

    refresh-client $p

    # ATTENTION: This entity apparently does not support server-side
    # filtering by name. The 'cf' does client-side filtering as well,
    # going by its REST trace.

    set matches [struct::list filter [v2 space_quota_definition list] [lambda {x o} {
	string equal $x	[$o @name]
    } $x]]

    if {![llength $matches]} {
	debug.validate/notspacequota {OK}
	return $x
    }

    debug.validate/notspacequota {FAIL}
    fail-known-thing $p NOTSPACEQUOTA "space quota plan" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::notspacequota 0
