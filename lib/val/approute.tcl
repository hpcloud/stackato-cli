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
package require stackato::mgr::self
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
    namespace import ::cmdr::validate::common::fail-unknown-simple-msg
    namespace import ::stackato::mgr::self
    namespace import ::stackato::mgr::manifest
    namespace import ::stackato::validate::common::refresh-client
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
	set matches [$theapp @routes \
			 get* {depth 1 include-relations domain} \
			 filter-by name $x]
	# Note: We are using 'name' here, not '@name'.
	#       The 'name' pseudo-attribute contains the domain part
	#       as well.
	#
	# Note 2: The list of routes is for the specific application,
	# and expected to be small. This means that doing the search
	# and filter here on the client-side is not expected to be a
	# scaling problem.
	#
	# Note 3: However adding include-relations is possible and
	# does helps with reducing the traffic.
    }

    if {[llength $matches] == 1} {
	debug.validate/approute {OK/canon = $x}
	return [lindex $matches 0]
    }
    debug.validate/approute {FAIL}
    fail-unknown-simple-msg \
	"[self please [list app [$theapp @name]] Run] to see list of routes" \
	$p APPROUTE "route" $x " for application '[$theapp @name]'"
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::approute 0
