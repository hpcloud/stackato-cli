## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Space names, NOT
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate
package require stackato::mgr::client
package require stackato::mgr::corg
package require stackato::validate::common

debug level  validate/notspacename
debug prefix validate/notspacename {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export notspacename
    namespace ensemble create
}

namespace eval ::stackato::validate::notspacename {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-known-thing
    namespace import ::stackato::mgr::corg
    namespace import ::stackato::v2
    namespace import ::stackato::validate::common::refresh-client
}

proc ::stackato::validate::notspacename::default  {p}   { return {} }
proc ::stackato::validate::notspacename::release  {p x} { return }
proc ::stackato::validate::notspacename::complete {p x} { return {} }

proc ::stackato::validate::notspacename::validate {p x} {
    debug.validate/notspacename {}

    # Accept the default.
    if {$x eq {}} {
	debug.validate/notspacename {OK/default}
	return $x
    }

    refresh-client $p

    # find space by name in current organization
    set theorg [corg get]
    set matches [$theorg @spaces get* [list q name:$x]]

    if {![llength $matches]} {
	# Not found, good.
	debug.validate/notspacename {OK/canon = $x}
	return $x
    }

    debug.validate/notspacename {FAIL}
    fail-known-thing $p NOTSPACENAME "space" $x " in organization '[$theorg @name]'"
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::notspacename 0
