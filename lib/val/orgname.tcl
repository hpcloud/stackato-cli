## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Organization names
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate
package require stackato::mgr::client;# pulls v2 also
package require stackato::mgr::self
package require stackato::validate::common

debug level  validate/orgname
debug prefix validate/orgname {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export orgname
    namespace ensemble create
}

namespace eval ::stackato::validate::orgname {
    namespace export default validate complete release acceptable
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-unknown-simple-msg
    namespace import ::stackato::v2
    namespace import ::stackato::mgr::self
    namespace import ::stackato::validate::common::refresh-client
}

proc ::stackato::validate::orgname::default  {p}   { return {} }
proc ::stackato::validate::orgname::release  {p x} { return }
proc ::stackato::validate::orgname::complete {p x} {
    refresh-client $p
    complete-enum [struct::list map [v2 organization list] [lambda o {
	$o @name
    }]] 0 $x
}

proc ::stackato::validate::orgname::validate {p x} {
    debug.validate/orgname {}

    refresh-client $p

    # See also corg::get.

    if {![catch {
	set x [v2 organization find-by-name $x]
    }]} {
	debug.validate/orgname {OK/canon = $x}
	return $x
    }
    debug.validate/orgname {FAIL}
    fail-unknown-simple-msg \
	"[self please orgs Run] to see list of organizations" \
	$p ORGNAME "organization" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::orgname 0
