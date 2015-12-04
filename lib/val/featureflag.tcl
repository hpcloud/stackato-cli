# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Route names
## Dependency: config @client
#
## User visible routes are host + domain

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

debug level  validate/featureflag
debug prefix validate/featureflag {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export featureflag
    namespace ensemble create
}

namespace eval ::stackato::validate::featureflag {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-unknown-simple-msg
    namespace import ::stackato::validate::common::refresh-client
    namespace import ::stackato::mgr::self
    namespace import ::stackato::v2
}

proc ::stackato::validate::featureflag::default  {p}   { return {} }
proc ::stackato::validate::featureflag::release  {p x} { return }
proc ::stackato::validate::featureflag::complete {p x} {
    refresh-client $p
    complete-enum [struct::list map [v2 feature_flag list] [lambda o {
	$o @name
    }]] 0 $x
}

proc ::stackato::validate::featureflag::validate {p x} {
    debug.validate/featureflag {}

    refresh-client $p

    # Note: The route list is not cached. Multiple round trips are
    # made when validating multiple routes.

    # Note: x, the route, is the combination of host and domain.
    # We are not accepting just a domain without host.

    set matches [struct::list filter [v2 feature_flag list] [lambda {x o} {
	string equal $x	[$o @name]
    } $x]]

    if {[llength $matches] == 1} {
	debug.validate/featureflag {OK/canon = $x}
	return [lindex $matches 0]
    }
    debug.validate/featureflag {FAIL}
    fail-unknown-simple-msg \
	"[self please feature-flags Run] to see list of feature flags" \
	$p FEATUREFLAG "feature flag" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::featureflag 0
