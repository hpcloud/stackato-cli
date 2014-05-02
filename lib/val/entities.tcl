## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Known entity types
## Dependency:

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::validate
package require stackato::v2::client ;# get all entity classes.

debug level  validate/entity
debug prefix validate/entity {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export entity
    namespace ensemble create
}

namespace eval ::stackato::validate::entity {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-unknown-thing
    namespace import ::stackato::v2
}

proc ::stackato::validate::entity::default  {p}   { return {} }
proc ::stackato::validate::entity::release  {p x} { return }
proc ::stackato::validate::entity::complete {p x} {
    complete-enum [v2 types] 0 $x
}

proc ::stackato::validate::entity::validate {p x} {
    debug.validate/entity {}
    if {$x in [v2 types]} {
	debug.validate/entity {OK}
	return $x
    }
    debug.validate/entity {FAIL}
    fail-unknown-thing $p ENTITY "CFv2 entity type" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::entity 0
