# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

## Command implementations. Management of organizations.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require stackato::color
package require stackato::jmap
package require stackato::log
package require stackato::mgr::client ; # pulls all of v2
package require stackato::mgr::context
package require stackato::mgr::corg
package require stackato::mgr::cspace
package require stackato::mgr::ctarget
package require stackato::term
package require table

debug level  cmd/orgs
debug prefix cmd/orgs {[debug caller] | }

namespace eval ::stackato::cmd {
    namespace export orgs
    namespace ensemble create
}
namespace eval ::stackato::cmd::orgs {
    namespace export \
	create delete rename list show switch
    namespace ensemble create

    namespace import ::stackato::color
    namespace import ::stackato::v2
    namespace import ::stackato::jmap
    namespace import ::stackato::log::display
    namespace import ::stackato::log::psz
    namespace import ::stackato::term
    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::client
    namespace import ::stackato::mgr::context
    namespace import ::stackato::mgr::corg
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::mgr::ctarget
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::orgs::switch {config} {
    debug.cmd/orgs {}
    # @name

    set org [$config @name]

    display "Switching to organization [$org @name] ... " false
    corg set $org
    corg save
    display [color green OK]

    # Invalidate current space
    display "Unsetting current space ... " false
    cspace reset
    cspace save
    display [color green OK]

    display [context format-large]
    return
}

proc ::stackato::cmd::orgs::create {config} {
    debug.cmd/orgs {}
    # @name - String, validated to not exist

    set name [$config @name]
    set org [v2 organization new]
    $org @name set $name

    if {[$config @add-self]} {
	display "Adding you as developer ... " false
	set user [v2 deref-type user [[$config @client] user]]
	$org @users add $user
	display [color green OK]
    }

    display "Creating new organization $name ... " false
    $org commit
    display [color green OK]

    if {[$config @activate]} {
	display "Switching to organization [$org @name] ... " false
	corg set $org
	corg save
	cspace reset
	cspace save
	display [color green OK]

	display [color red {No spaces available. Please create some with }][color green create-space]

	display [context format-large]
    }

    return
}

proc ::stackato::cmd::orgs::delete {config} {
    debug.cmd/orgs {}
    # @name    - Organization's object.

    set org [$config @name]

    if {[cmdr interactive?] &&
	![term ask/yn \
	      "\nReally delete \"[$org @name]\" ? " \
	      no]} return

    $org delete

    display "Deleting organization [$org @name] ... " false
    $org commit
    display [color green OK]
    return
}

proc ::stackato::cmd::orgs::rename {config} {
    debug.cmd/orgs {}
    # @name    - Organization's object.
    # @newname - String, validated to not exist as org name.

    set org [$config @name]
    set new [$config @newname]

    $org @name set $new

    display "Renaming organization to [$org @name] ... " false
    $org commit
    display [color green OK]
    return
}

proc ::stackato::cmd::orgs::list {config} {
    debug.cmd/orgs {}
    # No arguments.
    # TODO: Implement 'orgs --full'.

    display "In [ctarget get]..."
    set co [corg get]

    set titles {{} Name Spaces Domains}
    set full [$config @full]
    set depth 1
    if {$full} {
	lappend titles Applications Services
	set depth 2
    }

    [table::do t $titles {
	foreach org [v2 organization list $depth] {
	    lappend values [expr {($co ne {}) && [$co == $org] ? "x" : ""}]
	    lappend values [$org @name]
	    lappend values [join [$org @spaces  @name] \n]
	    lappend values [join [$org @domains @name] \n]

	    if {$full} {
		lappend values [join [$org @spaces @apps @name] \n]
		lappend values [join [$org @spaces @service_instances @name] \n]
	    }

	    $t add {*}$values
	    unset values
	}
    }] show display
    return
}

proc ::stackato::cmd::orgs::show {config} {
    debug.cmd/orgs {}
    # @name - Organization's object.

    set org [$config @name]
    # TODO: org load - Depth 1/2 - How to specify ? Must be in dispatcher.

    if {[$config @json]} {
	puts [$org as-json]
	return
    }

    # TODO: Make it more tabular...
    #display "Organization: [$org @name]"

    display [context format-org]
    [table::do t {Key Value} {
	if {[$config @full]} {
	    $t add Billed [$org @billing_enabled]

	    $t add Users              [join [$org @users            email] \n]
	    $t add Managers           [join [$org @managers         email] \n]
	    $t add "Billing Managers" [join [$org @billing_managers email] \n]
	    $t add Auditors           [join [$org @auditors         email] \n]
	}
	$t add Domains [join [$org @domains @name] \n]
	$t add Spaces  [join [$org @spaces @name] \n]

	if {[$config @full]} {
	    $t add "Quota ([$org @quota_definition @name])"
	    $t add "- Extended Services" [$org @quota_definition @non_basic_services_allowed]
	    $t add "- # Services"        [$org @quota_definition @total_services]
	    $t add "- Memory"            [psz [MB [$org @quota_definition @memory_limit]]]
	}
    }] show display
    return
}

proc ::stackato::cmd::orgs::MB {x} {
    expr {$x * 1024 * 1024}
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::orgs 0

