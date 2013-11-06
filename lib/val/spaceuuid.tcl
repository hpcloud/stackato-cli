## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Space uuids
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate ;# Fail utility command.
package require stackato::mgr::client;# pulls v2 also
package require stackato::mgr::corg
package require stackato::validate::common

debug level  validate/spaceuuid
debug prefix validate/spaceuuid {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export spaceuuid
    namespace ensemble create
}

namespace eval ::stackato::validate::spaceuuid {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::fail
    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::stackato::mgr::corg
    namespace import ::stackato::v2
    namespace import ::stackato::validate::common::refresh-client
}

proc ::stackato::validate::spaceuuid::default  {p}   { return {} }
proc ::stackato::validate::spaceuuid::release  {p x} { return }
proc ::stackato::validate::spaceuuid::complete {p x} {
    refresh-client $p
    complete-enum [struct::list map [v2 space list] [lambda o {
	$i id
    }]] 0 $x
}

proc ::stackato::validate::spaceuuid::validate {p x} {
    debug.validate/spaceuuid {}
    # Accept the default.
    if {$x eq {}} { debug.validate/spaceuuid {OK/default} ; return $x }

    refresh-client $p

    if {![catch {
	set s [v2 deref-type space $x]
	$s @name ;# force resolution of a phantom => actual load and check.
    }]} {
	debug.validate/spaceuuid {OK/canon = $x}
	return $s
    }

    debug.validate/spaceuuid {FAIL}
    fail $p SPACEUUID "a space uuid" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::spaceuuid 0
