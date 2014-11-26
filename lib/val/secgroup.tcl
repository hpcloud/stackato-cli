## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Security_Group names
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate
package require stackato::mgr::client;# pulls v2 also
package require stackato::validate::common

debug level  validate/securitygroup
debug prefix validate/securitygroup {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export security_group
    namespace ensemble create
}

namespace eval ::stackato::validate::securitygroup {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-unknown-thing
    namespace import ::stackato::v2
    namespace import ::stackato::validate::common::refresh-client
}

proc ::stackato::validate::securitygroup::default  {p}   { return {} }
proc ::stackato::validate::securitygroup::release  {p x} { return }
proc ::stackato::validate::securitygroup::complete {p x} {
    refresh-client $p
    complete-enum [struct::list map [v2 security_group list] [lambda o {
	$o @name
    }]] 0 $x
}

proc ::stackato::validate::securitygroup::validate {p x} {
    debug.validate/securitygroup {}
    # Accept the default.
    if {$x eq {}} { debug.validate/securitygroup {OK/default} ; return $x }

    refresh-client $p

    # See also corg::get.

    if {![catch {
	set x [v2 security_group find-by-name $x]
    }]} {
	debug.validate/securitygroup {OK/canon = $x}
	return $x
    }
    debug.validate/securitygroup {FAIL}
    fail-unknown-thing $p SECURITYGROUP "security_group" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::securitygroup 0
