# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Space Quota plans
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require cmdr::validate
package require stackato::mgr::self
package require stackato::mgr::client;# pulls v2 also
package require stackato::validate::common

debug level  validate/spacequota
debug prefix validate/spacequota {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export spacequota
    namespace ensemble create
}

namespace eval ::stackato::validate::spacequota {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-unknown-simple-msg
    namespace import ::stackato::mgr::self
    namespace import ::stackato::v2
    namespace import ::stackato::validate::common::refresh-client
}

proc ::stackato::validate::spacequota::default  {p}   { return {} }
proc ::stackato::validate::spacequota::release  {p x} { return }
proc ::stackato::validate::spacequota::complete {p x} {
    refresh-client $p
    complete-enum [struct::list map [v2 space_quota_definition list] [lambda o {
	$o @name
    }]] 0 $x
}

proc ::stackato::validate::spacequota::validate {p x} {
    debug.validate/spacequota {}

    refresh-client $p

    # ATTENTION: This entity apparently does not support server-side
    # filtering by name. The 'cf' does client-side filtering as well,
    # going by its REST trace.

    set matches [struct::list filter [v2 space_quota_definition list] [lambda {x o} {
	string equal $x	[$o @name]
    } $x]]

    if {[llength $matches] == 1} {
	set x [lindex $matches 0]
	debug.validate/spacequota {OK/canon = $x}
	return $x
    }
    debug.validate/spacequota {FAIL}
    fail-unknown-simple-msg \
	"[self please space-quotas Run] to see list of space quota plans" \
	$p SPACEQUOTA "space quota plan" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::spacequota 0
