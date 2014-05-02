## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Buildpacks
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

debug level  validate/buildpack
debug prefix validate/buildpack {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export buildpack
    namespace ensemble create
}

namespace eval ::stackato::validate::buildpack {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-unknown-thing
    namespace import ::stackato::v2
    namespace import ::stackato::validate::common::refresh-client
}

proc ::stackato::validate::buildpack::default  {p}   { return {} }
proc ::stackato::validate::buildpack::release  {p x} { return }
proc ::stackato::validate::buildpack::complete {p x} {
    refresh-client $p
    complete-enum [struct::list map [v2 buildpack list] [lambda o {
	$o @name
    }]] 0 $x
}

proc ::stackato::validate::buildpack::validate {p x} {
    debug.validate/buildpack {}

    refresh-client $p

    if {![catch {
	set x [v2 buildpack find-by-name $x]
    }]} {
	debug.validate/buildpack {OK/canon = $x}
	return $x
    }
    debug.validate/buildpack {FAIL}
    fail-unknown-thing $p BUILDPACK "buildpack" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::buildpack 0
