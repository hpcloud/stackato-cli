## -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Target urls.
## Not for validation, but transformation (url canon) of user input.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::validate ;# Fail utility command.
package require url

debug level  validate/target
debug prefix validate/target {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export target
    namespace ensemble create
}

namespace eval ::stackato::validate::target {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::fail
    namespace import ::cmdr::validate::common::complete-enum
}

proc ::stackato::validate::target::default  {p}   { return {} }
proc ::stackato::validate::target::release  {p x} { return }
proc ::stackato::validate::target::complete {p x} {
    # Maybe complete using the token map = targets known and logged into.
    return {}
}

proc ::stackato::validate::target::validate {p x} {
    debug.validate/target {}
    # Accept all, transform to proper url if it is not yet.
    return [url canon $x]
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::target 0
