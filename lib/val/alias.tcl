## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Application names
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::validate
package require stackato::mgr::alias
package require stackato::mgr::self

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
    namespace import ::cmdr::validate::common::fail-unknown-thing-msg
    namespace import ::stackato::mgr::alias
    namespace import ::stackato::mgr::self
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
    fail-unknown-thing-msg \
	"[self please aliases] to see the available names" \
	$p ALIAS alias $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::alias 0
