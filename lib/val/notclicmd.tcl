## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - CLI command names, NOT
## Dependency: None.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::validate ;# Fail utility command.

debug level  validate/notclicmd
debug prefix validate/notclicmd {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export alias
    namespace ensemble create
}

namespace eval ::stackato::validate::notclicmd {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::fail
    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::stackato::mgr::notclicmd
}

proc ::stackato::validate::notclicmd::default  {p}   { return {} }
proc ::stackato::validate::notclicmd::release  {p x} { return }
proc ::stackato::validate::notclicmd::complete {p x} { return {} }

proc ::stackato::validate::notclicmd::validate {p x} {
    debug.validate/notclicmd {}
    if {![stackato-cli has $x]} {
	debug.validate/notclicmd {OK}
	return $x
    }
    debug.validate/notclicmd {FAIL}
    fail $p NOTCLICMD "an unused '[stackato-cli name]' command name" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::notclicmd 0
