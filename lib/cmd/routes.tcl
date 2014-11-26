# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations. Management of routes.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::ask
package require cmdr::color
package require stackato::log
package require stackato::mgr::client
package require stackato::mgr::context
package require stackato::mgr::cspace
package require stackato::v2
package require table

debug level  cmd/routes
debug prefix cmd/routes {[debug caller] | }

namespace eval ::stackato::cmd {
    namespace export routes
    namespace ensemble create
}
namespace eval ::stackato::cmd::routes {
    namespace export \
	create delete list
    namespace ensemble create

    namespace import ::cmdr::ask
    namespace import ::cmdr::color
    namespace import ::stackato::log::display
    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::client
    namespace import ::stackato::mgr::context
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::v2
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::routes::delete {config} {
    debug.cmd/routes {}
    # @name - Route object

    if {[$config @unused]} {
	if {[$config @all]} {
	    set routes [v2 route list 2 include-relations apps]
	} else {
	    if {[cspace get] eq {}} {
		err "Unable to delete routes of the space. No space specified."
	    }

	    set routes [[cspace get] @apps @routes get* \
			    {depth 2 include-relations apps}]
	}

	set routes [FilterUsed $routes]
    } else {
	set routes [$config @name]
    }

    if {![llength $routes]} {
	display [color note "No Routes to delete"]
	return
    }

    foreach route $routes {
	if {[cmdr interactive?] &&
	    ![ask yn \
		  "\nReally delete \"[color name [$route name]]\" ? " \
		  yes]} return

	$route delete

	display "Deleting route \"[color name [$route name]]\" ... " false
	$route commit
	display [color good OK]
    }

    return
}

proc ::stackato::cmd::routes::list {config} {
    debug.cmd/routes {}
    # I. Retrieve routes
    if {[$config @json]} {
	if {[$config @all]} {
	    set routes [v2 route list]
	} else {
	    if {[cspace get] eq {}} {
		err "Unable to show routes of the space. No space specified."
	    }
	    set routes [[cspace get] @apps @routes]
	}
    } else {
	if {[$config @all]} {
	    set routes [v2 route list 2 include-relations domain,apps,space,organization]
	    display "\nRoutes: [context format-target]"
	} else {
	    set routes [[cspace get] @apps @routes get* \
			    {depth 2 include-relations domain,apps,space,organization}]
	    display "\nRoutes: [context format-short]"
	}
    }

    # II. Filter
    if {[$config @unused]} {
	set routes [FilterUsed $routes]
    }

    # III. Display in the chosen format.
    if {[$config @json]} {
	set tmp {}
	foreach r $routes {
	    lappend tmp [$r as-json]
	}
	display [json::write array {*}$tmp]
	return
    }

    if {![llength $routes]} {
	display [color note "No Routes"]
	return
    }

    [table::do t {Url Space Applications} {
	foreach route [v2 sort name $routes -dict] {
	    $t add \
		[color name http://[$route name]] \
		[$route @space full-name] \
		[join [lsort -dict [$route @apps @name]] \n]
	}
    }] show display
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::routes::FilterUsed {routes} {
    set tmp {}
    foreach r $routes {
	# Ignore used routes.
	if {[llength [$r @apps]]} continue
	lappend tmp $r
    }
    return $tmp
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::routes 0

