## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Application names
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::validate
package require stackato::validate::common

debug level  validate/envmode
debug prefix validate/envmode {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export envmode
    namespace ensemble create
}

namespace eval ::stackato::validate::envmode {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::stackato::validate::common::expected

    variable legalvalues {append preserve replace}
}

proc ::stackato::validate::envmode::default  {p}   { return {} }
proc ::stackato::validate::envmode::release  {p x} { return }
proc ::stackato::validate::envmode::complete {p x} {
    variable legalvalues
    complete-enum $legalvalues 0 $x
}

proc ::stackato::validate::envmode::validate {p x} {
variable legalvalues
    debug.validate/envmode {}

    if {$x in $legalvalues} {
	debug.validate/envmode {OK}
	return $x
    }
    debug.validate/envmode {FAIL}
    expected $p ENVMODE "env-mode" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::envmode 0
