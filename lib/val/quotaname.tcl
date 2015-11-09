## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Quota plan names
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require cmdr::validate
package require stackato::mgr::self
package require stackato::mgr::client;# pulls v2 also
package require stackato::validate::common

debug level  validate/quotaname
debug prefix validate/quotaname {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export quotaname
    namespace ensemble create
}

namespace eval ::stackato::validate::quotaname {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-unknown-simple-msg
    namespace import ::stackato::mgr::self
    namespace import ::stackato::v2
    namespace import ::stackato::validate::common::refresh-client
}

proc ::stackato::validate::quotaname::default  {p}   { return {} }
proc ::stackato::validate::quotaname::release  {p x} { return }
proc ::stackato::validate::quotaname::complete {p x} {
    refresh-client $p
    complete-enum [struct::list map [v2 quota_definition list] [lambda o {
	$o @name
    }]] 0 $x
}

proc ::stackato::validate::quotaname::validate {p x} {
    debug.validate/quotaname {}

    refresh-client $p

    if {![catch {
	set x [v2 quota_definition find-by-name $x]
    }]} {
	debug.validate/quotaname {OK = $x}
	return $x
    }
    debug.validate/quotaname {FAIL}
    fail-unknown-simple-msg \
	"[self please quotas Run] to see list of quota plans" \
	$p QUOTANAME "quota plan" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::quotaname 0
