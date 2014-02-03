## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Route names, restricted to an application.
## Dependency: config @client
#
## User visible routes are host + domain

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate
package require stackato::mgr::client;# pulls v2 also
package require stackato::mgr::manifest
package require stackato::validate::common

debug level  validate/approute
debug prefix validate/approute {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export approute
    namespace ensemble create
}

namespace eval ::stackato::validate::approute {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::stackato::mgr::manifest
    namespace import ::stackato::validate::common::refresh-client
    namespace import ::stackato::validate::common::expected
    namespace import ::stackato::v2
}

proc ::stackato::validate::approute::default  {p }  { return {} }
proc ::stackato::validate::approute::release  {p x} { return }
proc ::stackato::validate::approute::complete {p x} {
    if {![[refresh-client $p] isv2]} {
	# Against a v1 target we cannot complete.
	return {}
    }
    set theapp [$p config @application]
    set routenames [$theapp @routes name]
    complete-enum $routenames 0 $x
}

proc ::stackato::validate::approute::validate {p x} {
    debug.validate/approute {}

    if {![[refresh-client $p] isv2]} {
	# Against a v1 target we cannot validate urls, and accept all
	debug.validate/approute {OK/v1 pass = $x}
	return $x
    }

    # The route list here is cached (compare 'routename' for a
    # non-caching VT), as it came from the application entity, and
    # entities are cached.

    # Assert: Manifest processor is here already initialized.
    manifest user_1app_do theapp {
	set matches [$theapp @routes filter-by name $x]
	# Note: name, not @name. The 'name' contains the domain part as well.
    }

    if {[llength $matches] == 1} {
	debug.validate/approute {OK/canon = $x}
	return [lindex $matches 0]
    }
    debug.validate/approute {FAIL}
    expected $p APPROUTE "route" $x " for application '[$theapp @name]'"
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::approute 0
