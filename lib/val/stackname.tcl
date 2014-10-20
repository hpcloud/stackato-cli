## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Stack names (v2 only)
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

debug level  validate/stackname
debug prefix validate/stackname {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export stackname
    namespace ensemble create
}

namespace eval ::stackato::validate::stackname {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-unknown-thing
    namespace import ::stackato::mgr::client
    namespace import ::stackato::validate::common::refresh-client
    namespace import ::stackato::v2
}

proc ::stackato::validate::stackname::default  {p}   { return {} }
proc ::stackato::validate::stackname::release  {p x} { return }
proc ::stackato::validate::stackname::complete {p x} {
    refresh-client $p
    complete-enum [v2 stack @name] 0 $x
}

proc ::stackato::validate::stackname::validate {p x} {
    debug.validate/stackname {}

    refresh-client $p

    # TODO FUTURE: val/stackname -- mgr/client, v2/client -- consolidate in client class.

    debug.validate/stackname {/v2}

    if {![catch {
	set x [v2 stack find-by-name $x]
    }]} {
	debug.validate/stackname {OK/canon = $x}
	return $x
    }
    debug.validate/stackname {FAIL}
    fail-unknown-thing $p STACKNAME "OS stack" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::stackname 0
