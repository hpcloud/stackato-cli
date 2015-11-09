## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Application names
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::validate

debug level  validate/colormode
debug prefix validate/colormode {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export colormode
    namespace ensemble create
}

namespace eval ::stackato::validate::colormode {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail

    variable legalvalues {always auto never}
}

proc ::stackato::validate::colormode::default  {p}   { return auto }
proc ::stackato::validate::colormode::release  {p x} { return }
proc ::stackato::validate::colormode::complete {p x} {
    variable legalvalues
    complete-enum $legalvalues 0 $x
}

proc ::stackato::validate::colormode::validate {p x} {
variable legalvalues
    debug.validate/colormode {}

    if {$x in $legalvalues} {
	debug.validate/colormode {OK}
	return $x
    }
    debug.validate/colormode {FAIL}
    fail $p COLORMODE "one of 'always', 'auto', or 'never'" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::colormode 0
