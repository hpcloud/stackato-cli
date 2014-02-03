# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations. Management of routes.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require stackato::color
package require stackato::log
package require stackato::mgr::client
package require stackato::term
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

    namespace import ::stackato::color
    namespace import ::stackato::log::display
    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::client
    namespace import ::stackato::term
    namespace import ::stackato::v2
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::routes::delete {config} {
    debug.cmd/routes {}
    # @name - Route object

    set route [$config @name]

    if {[cmdr interactive?] &&
	![term ask/yn \
	      "\nReally delete \"[$route name]\" ? " \
	      no]} return

    $route delete

    display "Deleting route [$route name] ... " false
    $route commit
    display [color green OK]
    return
}

proc ::stackato::cmd::routes::list {config} {
    debug.cmd/routes {}
    # No arguments.

    if {[$config @json]} {
	set tmp {}
	foreach r [v2 route list] {
	    lappend tmp [$r as-json]
	}
	display [json::write array {*}$tmp]
	return
    }

    [table::do t {Url Space Applications Space} {
	foreach route [v2 sort name [v2 route list 2] -dict] {
	    set adata {}
	    foreach a [$route @apps] {
		lappend adata [::list [$a @name] [$a @space full-name]]
	    }
	    set adata [lsort -dict $adata]
	    set aspace {}
	    set aname {}
	    foreach item $adata {
		lassign $item name space
		lappend aname $name
		lappend aspace $space
	    }
	    $t add \
		[$route name] \
		[$route @space full-name] \
		[join $aname \n] \
		[join $aspace \n]
	}
    }] show display
    return
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::routes 0

