# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations. Management of domains.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::ask
package require cmdr::color
package require stackato::log
package require stackato::mgr::client
package require stackato::mgr::corg
package require stackato::mgr::cspace
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
	create map unmap list create delete
    namespace ensemble create

    namespace import ::cmdr::ask
    namespace import ::cmdr::color
    namespace import ::stackato::log::display
    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::client
    namespace import ::stackato::mgr::corg
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::v2
}

# # ## ### ##### ######## ############# #####################
# S3.0 commands

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

	display "Creating new domain [color name $name] ... " false
	$domain commit
	display [color good OK]
    }

    debug.cmd/domains {domain = $domain ([$domain @name])}

    # Make the (new) domain available to both current organization,
    # and current space.

    set org   [corg   get]
    set space [cspace get]

    display "Mapping [color name [$domain @name]] to [color name [$org @name]] ... " false
    $org   @domains add $domain
    display [color good OK]

    display "Mapping [color name [$domain @name]] to [color name [$space @name]] ... " false
    $space @domains add $domain
    display [color good OK]
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

    display "Unmapping [color name [$domain @name]] from [color name [$space @name]] ... " false
    $space @domains remove $domain
    display [color good OK]
    return
}

# # ## ### ##### ######## ############# #####################
# S3.2+ commands

proc ::stackato::cmd::domains::create {config} {
    debug.cmd/domains {}
    # @name   - name of new domain
    # @shared - flag, true if domain shall have no owner and be shared across all.

    # @space        - object, implied in cspace
    # @organization - object, implied in corg

    set name   [$config @name]
    set shared [$config @shared]

    # Check if the domain exists. If not, create it.
    try {
	set domain [v2 domain find-by-name $name]
    } on ok {e o} {
	err "Unable to create domain $name, it exists already."

    } trap {STACKATO CLIENT V2 DOMAIN NAME NOTFOUND} {e o} {

	debug.cmd/domains {domain unknown, create}

	set domain [v2 domain new]
	$domain @name                set $name
	$domain @wildcard            set 1

	if {!$shared} {
	    $domain @owning_organization set [corg get]
	    set note "[color note "Owned by"] [color name [[corg get] @name]]"
	} else {
	    set note [color note "Shared"]
	}

	display "Creating new domain [color name $name] ($note) ... " false
	$domain commit
	display [color good OK]
    }

    debug.cmd/domains {domain = $domain ([$domain @name])}
    return
}

proc ::stackato::cmd::domains::delete {config} {
    debug.cmd/domains {}
    # @name - domain name

    set name [$config @name]

    # Check if the domain exists. If not, fail.
    # TODO: Move to validation type and dispatcher.
    try {
	set domain [v2 domain find-by-name $name]
    } trap {STACKATO CLIENT V2 DOMAIN NAME NOTFOUND} {e o} {
	err "Unknown domain $name"
    }

    debug.cmd/domains {domain = $domain ([$domain @name])}

    if {[cmdr interactive?] &&
	![ask yn \
	      "\nReally delete \"[color name [$domain @name]]\" ? " \
	      no]} return

    if {![$domain @owning_organization defined?]} {
	set type shared
    } else {
	set type private
    }

    $domain delete

    display "Deleting $type domain [color name [$domain @name]] ... " false
    $domain commit
    display [color good OK]
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::domains::list {config} {
    debug.cmd/domains {}
    # @all, @space
    # No arguments.

    if {[$config @all]} {
	set domains [v2 domain list 1 \
			 include-relations owning_organization]
    } else {
	if {[package vsatisfies [[$config @client] server-version] 3.1]} {
	    # 3.2+
	    set domains [[corg get] @domains get* \
			     {depth 1 include-relations owning_organization}]
	    if {![$config @json]} {
		display "Org [color name [[corg get] @name]]..."
	    }
	} else {
	    # 3.0
	    set domains [[cspace get] @domains get* \
			     {depth 1 include-relations owning_organization}]
	    if {![$config @json]} {
		display "Space [color name [[cspace get] @name]]..."
	    }
	}
    }

    if {[$config @json]} {
	set tmp {}
	foreach r $domains {
	    lappend tmp [$r as-json]
	}
	display [json::write array {*}$tmp]
	return
    }

    [table::do t {Name Owner Shared} {
	foreach domain [v2 sort @name $domains -dict] {
	    if {[$domain @owning_organization defined?]} {
		set owner  [$domain @owning_organization @name]
		set shared {}
	    } else {
		set owner  {}
		set shared *
	    }
	    $t add [color name [$domain @name]] $owner $shared
	}
    }] show display
    return
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::domains 0

