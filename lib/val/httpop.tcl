## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Http operations.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::validate

debug level  validate/http-operation
debug prefix validate/http-operation {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export http-operation
    namespace ensemble create
}

namespace eval ::stackato::validate::http-operation {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail

    variable legalvalues {get put post head delete}
}

proc ::stackato::validate::http-operation::default  {p}   { return {} }
proc ::stackato::validate::http-operation::release  {p x} { return }
proc ::stackato::validate::http-operation::complete {p x} {
    variable legalvalues
    complete-enum $legalvalues 1 $x
}

proc ::stackato::validate::http-operation::validate {p x} {
variable legalvalues
    debug.validate/http-operation {}

    if {[string tolower $x] in $legalvalues} {
	debug.validate/http-operation {OK}
	return [string toupper $x]
    }
    debug.validate/http-operation {FAIL}
    fail $p HTTP-OPERATION "http operation" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::http-operation 0
