## -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Application names, regular and NOT.
## Dependency: @no-create

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate ;# Fail utility command.
package require stackato::mgr::client
package require stackato::validate::appname
package require stackato::validate::notappname

debug level  validate/vappname
debug prefix validate/vappname {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export vappname
    namespace ensemble create
}

namespace eval ::stackato::validate::vappname {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::fail
    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::stackato::mgr::client
    namespace import ::stackato::validate::appname
    namespace import ::stackato::validate::notappname
}

proc ::stackato::validate::vappname::default  {p}   { return {} }
proc ::stackato::validate::vappname::release  {p x} { return }
proc ::stackato::validate::vappname::complete {p x} {
    # no-create => assume app exists => appname valid
    if {[$p config @no-create]} {
	return [appname complete $x]
    } else {
	return [notappname complete $x]
    }
}

proc ::stackato::validate::vappname::validate {p x} {
    debug.validate/vappname {}
    # no-create => assume app exists => appname valid
    if {[$p config @no-create]} {
	return [appname validate $p $x]
    } else {
	return [notappname validate $p $x]
    }
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::vappname 0
