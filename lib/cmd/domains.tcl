# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations. Management of domains.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require stackato::color
package require stackato::log
package require stackato::mgr::client
package require stackato::mgr::corg
package require stackato::mgr::cspace
package require stackato::term
package require stackato::v2
package require table

debug level  cmd/domains
debug prefix cmd/domains {[debug caller] | }

namespace eval ::stackato::cmd {
    namespace export domains
    namespace ensemble create
}
namespace eval ::stackato::cmd::domains {
    namespace export \
	create map unmap list
    namespace ensemble create

    namespace import ::stackato::color
    namespace import ::stackato::log::display
    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::client
    namespace import ::stackato::mgr::corg
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::term
    namespace import ::stackato::v2
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::domains::map {config} {
    debug.cmd/domains {}
    # @name
    # @space        - object, implied in cspace
    # @organization - object, implied in corg

    set name [$config @name]

    # Check if the domain exists. If not, create it.
    try {
	set domain [v2 domain find-by-name $name]
    } trap {STACKATO CLIENT V2 DOMAIN NAME NOTFOUND} {e o} {

	debug.cmd/domains {domain unknown, create}

	set domain [v2 domain new]
	$domain @name                set $name
	$domain @owning_organization set [corg get]
	$domain @wildcard            set 1

	display "Creating new domain $name ... " false
	$domain commit
	display [color green OK]
    }

    debug.cmd/domains {domain = $domain ([$domain @name])}

    # Make the (new) domain available to both current organization,
    # and current space.

    set org   [corg   get]
    set space [cspace get]

    display "Mapping [$domain @name] to [$org @name] ... " false
    $org   @domains add $domain
    display [color green OK]

    display "Mapping [$domain @name] to [$space @name] ... " false
    $space @domains add $domain
    display [color green OK]
    return
}

proc ::stackato::cmd::domains::unmap {config} {
    debug.cmd/domains {}
    # @name
    # @space        - object, implied in cspace
    # @organization - object, implied in corg

    set name [$config @name]

    # Check if the domain exists. If not, fail.
    # TODO: Move to validation type and dispatcher.
    try {
	set domain [v2 domain find-by-name $name]
    } trap {STACKATO CLIENT V2 DOMAIN NAME NOTFOUND} {e o} {
	err "Unknown domain $name"
    }

    debug.cmd/domains {domain = $domain ([$domain @name])}

    # Remove the domain from current space.

    set space [cspace get]

    display "Unmapping [$domain @name] from [$space @name] ... " false
    $space @domains remove $domain
    display [color green OK]
    return
}

proc ::stackato::cmd::domains::list {config} {
    debug.cmd/domains {}
    # @all, @space
    # No arguments.

    [table::do t {Name Owner} {
	if {[$config @all]} {
	    set domains [v2 domain list 1]
	} else {
	    set domains [[cspace get] @domains get 1]
	    display [[cspace get] @name]...
	}
	foreach domain $domains {
	    set owner [expr {[$domain @owning_organization defined?]
			     ? [$domain @owning_organization @name]
			     : ""}]
	    $t add [$domain @name] $owner
	}
    }] show display
    return
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::domains 0

