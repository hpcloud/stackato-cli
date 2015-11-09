## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Zone names
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate ;# Fail utility command.
package require stackato::mgr::client;# pulls v2 also
package require stackato::mgr::self
package require stackato::validate::common
package require stackato::log

debug level  validate/zonename
debug prefix validate/zonename {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export zonename
    namespace ensemble create
}

namespace eval ::stackato::validate::zonename {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-unknown-simple-msg
    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::self
    namespace import ::stackato::v2
    namespace import ::stackato::validate::common::refresh-client
}

proc ::stackato::validate::zonename::default  {p}   { return {} }
proc ::stackato::validate::zonename::release  {p x} { return }
proc ::stackato::validate::zonename::complete {p x} {
    refresh-client $p

    try {
	set zlist [v2 zone list]
    } trap {STACKATO CLIENT V2 UNKNOWN REQUEST} {e o} {
	err "Distribution zones not supported by target"
    }

    complete-enum [struct::list map $zlist [lambda o {
	$o @name
    }]] 0 $x
}

proc ::stackato::validate::zonename::validate {p x} {
    debug.validate/zonename {}

    refresh-client $p

    # See also czone::get.

    try {
	set x [v2 zone find-by-name $x]
    } trap {STACKATO CLIENT V2 UNKNOWN REQUEST} {e o} {
	err "Distribution zones not supported by target"
    } trap {STACKATO CLIENT V2 ZONE NAME NOTFOUND} {e o} {
	# fall through
    } on ok {e o} {
	debug.validate/zonename {OK/canon = $x}
	return $x
    }

    debug.validate/zonename {FAIL}
    fail-unknown-simple-msg \
	"[self please placement-zones Run] to see list of zones" \
	 $p ZONENAME "zone" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::zonename 0
