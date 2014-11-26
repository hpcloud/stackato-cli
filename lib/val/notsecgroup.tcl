## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Security_Group names, NOT
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate
package require stackato::mgr::client
package require stackato::validate::common

debug level  validate/notsecuritygroup
debug prefix validate/notsecuritygroup {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export notsecuritygroup
    namespace ensemble create
}

namespace eval ::stackato::validate::notsecuritygroup {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-known-thing
    namespace import ::stackato::v2
    namespace import ::stackato::validate::common::refresh-client
}

proc ::stackato::validate::notsecuritygroup::default  {p}   { return {} }
proc ::stackato::validate::notsecuritygroup::release  {p x} { return }
proc ::stackato::validate::notsecuritygroup::complete {p x} { return {} }

proc ::stackato::validate::notsecuritygroup::validate {p x} {
    debug.validate/notsecuritygroup {}

    # Accept the default.
    if {$x eq {}} {
	debug.validate/notsecuritygroup {OK/default}
	return $x
    }

    refresh-client $p

    try {
	v2 security_group find-by-name $x
    } trap {STACKATO CLIENT V2 SECURITY_GROUP NAME NOTFOUND} {e o} {
	debug.validate/notsecuritygroup {OK}
	return $x
    } trap {STACKATO CLIENT V2 SECURITY_GROUP NAME} {e o} {
	# Swallow. Ambiguity means that the name is in use.
    }

    debug.validate/notsecuritygroup {FAIL}
    fail-known-thing $p NOTSECURITYGROUP "security_group" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::notsecuritygroup 0
