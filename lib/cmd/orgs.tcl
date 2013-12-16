# -*- tcl -*-
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
	create delete rename list show switch \
	set-quota
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

proc ::stackato::cmd::orgs::set-quota {config} {
    debug.cmd/orgs {}
    # @name

    set org [$config @name]
    set qd  [$config @quota]

    display "Setting quota of [$org @name] to [$qd @name] ... " false
    $org @quota_definition set $qd
    $org commit
    display [color green OK]
    return
}

proc ::stackato::cmd::orgs::switch {config} {
    debug.cmd/orgs {}
    # @name

    try {
	set org [$config @name]
    } trap {CMDR VALIDATE ORGNAME} {e o} {
	set name [$config @name string]
	err "Unable to switch to organization \"$name\" (not found, or not a member)"
    }

    if {$org eq {}} {
	display [color yellow {Unable to switch, no organization specified}]
	return
    }

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

    set org       [$config @name]
    set iscurrent [$org == [corg get]]
    set recursive [$config @recursive]

    if {$recursive} {
	set suffix { and all its contents}
    } else {
	set suffix {}
    }

    if {[cmdr interactive?] &&
	![term ask/yn \
	      "\nReally delete \"[$org @name]\"$suffix ? " \
	      no]} return

    if {$recursive} {
	$org delete recursive true
    } else {
	$org delete
    }

    display "Deleting organization [$org @name] ... " false
    $org commit
    display [color green OK]

    # Update (remove) the current org (and its space, if that is the
    # org we just deleted.
    if {$iscurrent} {
	display "Dropped removed organization as current organization."

	corg reset
	corg save
	cspace reset
	cspace save
    }
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

    if {![$config @json]} {
	display "In [ctarget get]..."
    }
    set co [corg get]

    set titles {{} Name Quota Spaces Domains}
    set full [$config @full]
    set depth 1
    if {$full} {
	lappend titles Applications Services
	set depth 2
    }

    set theorgs [v2 organization list $depth]

    if {[$config @json]} {
	set tmp {}
	foreach org $theorgs {
	    lappend tmp [$org as-json]
	}
	display [json::write array {*}$tmp]
	return
    }

    [table::do t $titles {
	foreach org $theorgs {
	    lappend values [expr {($co ne {}) && [$co == $org] ? "x" : ""}]
	    lappend values [$org @name]
	    lappend values [$org @quota_definition @name]
	    lappend values [join [lsort -dict [$org @spaces  @name]] \n]
	    lappend values [join [lsort -dict [$org @domains @name]] \n]

	    if {$full} {
		lappend values [join [lsort -dict [$org @spaces @apps @name]] \n]
		lappend values [join [lsort -dict [$org @spaces @service_instances get* {user-provided true} @name]] \n]
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

	    $t add Users              [join [lsort -dict [$org @users            the_name]] \n]
	    $t add Managers           [join [lsort -dict [$org @managers         the_name]] \n]
	    $t add "Billing Managers" [join [lsort -dict [$org @billing_managers the_name]] \n]
	    $t add Auditors           [join [lsort -dict [$org @auditors         the_name]] \n]
	}
	$t add Domains [join [lsort -dict [$org @domains @name]] \n]
	$t add Spaces  [join [lsort -dict [$org @spaces  @name]] \n]
	$t add Quota   [$org @quota_definition @name]

	if {[$config @full]} {
	    $t add "- Memory Limit"    [psz [MB [$org @quota_definition @memory_limit]]]
	    $t add "- Paid Services"   [$org @quota_definition @non_basic_services_allowed]
	    $t add "- Total Services"  [$org @quota_definition @total_services]
	    $t add "- Trial Databases" [$org @quota_definition @trial_db_allowed]
	    $t add "- Allow Sudo"      [$org @quota_definition @allow_sudo]
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

