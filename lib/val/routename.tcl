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
package require url
package require dictutil
package require cmdr::validate
package require stackato::mgr::self
package require stackato::mgr::client;# pulls v2 also
package require stackato::validate::common

debug level  validate/routename
debug prefix validate/routename {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export routename
    namespace ensemble create
}

namespace eval ::stackato::validate::routename {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-unknown-simple-msg
    namespace import ::stackato::validate::common::refresh-client
    namespace import ::stackato::mgr::self
    namespace import ::stackato::v2
}

proc ::stackato::validate::routename::default  {p}   { return {} }
proc ::stackato::validate::routename::release  {p x} { return }
proc ::stackato::validate::routename::complete {p x} {
    refresh-client $p
    complete-enum [struct::list map [v2 route list] [lambda o {
	$o name
    }]] 0 $x
}

proc ::stackato::validate::routename::validate {p x} {
    debug.validate/routename {}

    refresh-client $p

    # Note: The route list is not cached. Multiple round trips are
    # made when validating multiple routes.

    # Note: x, the route, is the combination of host and domain.
    # We are not accepting just a domain without host.

    # Pre-filter the routes by host (target-side) ...
    # Accept routes with http(s):// prefix and strip said prefix.
    set r    [url domain $x]
    set host [lindex [split $r .] 0]

    debug.validate/routename {r    = $r}
    debug.validate/routename {host = $host}

    set matches [v2 route list-by-host $host 1 {include-relations domain}]

    # ... then filter by full name (i.e. including domain),
    # client-side.
    set matches [struct::list filter $matches [lambda {x o} {
	string equal $x	[$o name]
    } $r]]

    if {[llength $matches] == 1} {
	debug.validate/routename {OK/canon = $x}
	return [lindex $matches 0]
    }
    debug.validate/routename {FAIL}
    fail-unknown-simple-msg \
	"[self please routes Run] to see list of routes" \
	$p ROUTENAME "route" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::routename 0
