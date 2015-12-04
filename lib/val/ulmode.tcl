# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Application names
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::validate

debug level  validate/ulmode
debug prefix validate/ulmode {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export ulmode
    namespace ensemble create
}

namespace eval ::stackato::validate::ulmode {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail

    variable legalvalues {name related all}
}

proc ::stackato::validate::ulmode::default  {p}   { return name }
proc ::stackato::validate::ulmode::release  {p x} { return }
proc ::stackato::validate::ulmode::complete {p x} {
    variable legalvalues
    complete-enum $legalvalues 0 $x
}

proc ::stackato::validate::ulmode::validate {p x} {
variable legalvalues
    debug.validate/ulmode {}

    if {$x in $legalvalues} {
	debug.validate/ulmode {OK}
	return $x
    }
    debug.validate/ulmode {FAIL}
    fail $p ULMODE "one of 'name', 'related', or 'all'" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::ulmode 0
