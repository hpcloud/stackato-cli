## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Application names
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::validate
package require stackato::mgr::alias

debug level  validate/alias
debug prefix validate/alias {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export alias
    namespace ensemble create
}

namespace eval ::stackato::validate::alias {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-unknown-thing
    namespace import ::stackato::mgr::alias
}

proc ::stackato::validate::alias::default  {p}   { return {} }
proc ::stackato::validate::alias::release  {p x} { return }
proc ::stackato::validate::alias::complete {p x} {
    complete-enum [dict keys [alias known]] 0 $x
}

proc ::stackato::validate::alias::validate {p x} {
    debug.validate/alias {}
    if {[alias has $x]} {
	debug.validate/alias {OK}
	return $x
    }
    debug.validate/alias {FAIL}
    fail-unknown-thing $p ALIAS alias $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::alias 0
