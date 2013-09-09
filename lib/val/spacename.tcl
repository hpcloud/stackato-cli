## -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Space names
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate ;# Fail utility command.
package require stackato::mgr::client;# pulls v2 also
package require stackato::mgr::corg
package require stackato::validate::common

debug level  validate/spacename
debug prefix validate/spacename {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export spacename
    namespace ensemble create
}

namespace eval ::stackato::validate::spacename {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::fail
    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::stackato::mgr::corg
    namespace import ::stackato::v2
    namespace import ::stackato::validate::common::refresh-client
}

proc ::stackato::validate::spacename::default  {p}   { return {} }
proc ::stackato::validate::spacename::release  {p x} { return }
proc ::stackato::validate::spacename::complete {p x} {
    refresh-client $p
    complete-enum [[corg get] @spaces @name] 0 $x
}

proc ::stackato::validate::spacename::validate {p x} {
    debug.validate/spacename {}
    # Accept the default.
    if {$x eq {}} { debug.validate/spacename {OK/default} ; return $x }

    refresh-client $p

    # find space by name in current organization
    set matches [[corg get] @spaces filter-by @name $x]
    # NOTE: searchable-on in v2/space should help
    # (in v2/org using it) to filter server side.

    if {[llength $matches] == 1} {
	# Found, good.
	set x [lindex $matches 0]
	debug.validate/spacename {OK/canon = $x}
	return $x
    }
    debug.validate/spacename {FAIL}
    fail $p SPACENAME "a space name" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::spacename 0
