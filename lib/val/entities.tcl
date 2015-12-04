# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Known entity types
## Dependency:

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::validate
package require struct::list
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
    namespace import ::cmdr::validate::common::fail ;#-unknown-thing
    namespace import ::stackato::v2
}

proc ::stackato::validate::entity::default  {p}   { return {} }
proc ::stackato::validate::entity::release  {p x} { return }
proc ::stackato::validate::entity::complete {p x} {
    complete-enum [v2 types] 0 $x
}

proc ::stackato::validate::entity::validate {p x} {
    debug.validate/entity {}

    # Keep synchronized with ::stackato::cmd::query::named-entities
    set types [v2 types]
    struct::list delete types managed_service_instance
    struct::list delete types user_provided_service_instance
    struct::list delete types feature_flag
    struct::list delete types config/environment_variable_group

    if {$x in $types} {
	debug.validate/entity {OK}
	return $x
    }
    debug.validate/entity {FAIL}
    fail $p ENTITY "one of [linsert [join [lsort -dict $types] {, }] end-1 or]" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::entity 0
