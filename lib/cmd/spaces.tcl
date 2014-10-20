# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations. Management of spaces.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::ask
package require cmdr::color
package require stackato::jmap
package require stackato::log
package require stackato::mgr::client
package require stackato::mgr::context
package require stackato::mgr::corg
package require stackato::mgr::cspace
package require stackato::mgr::ctarget
package require stackato::v2
package require table

debug level  cmd/spaces
debug prefix cmd/spaces {[debug caller] | }

namespace eval ::stackato::cmd {
    namespace export spaces
    namespace ensemble create
}
namespace eval ::stackato::cmd::spaces {
    namespace export \
	create delete rename list show switch \
	update
    namespace ensemble create

    namespace import ::cmdr::ask
    namespace import ::cmdr::color
    namespace import ::stackato::jmap
    namespace import ::stackato::log::display
    namespace import ::stackato::log::err
    namespace import ::stackato::log::wrap
    namespace import ::stackato::mgr::client
    namespace import ::stackato::mgr::context
    namespace import ::stackato::mgr::corg
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::mgr::ctarget
    namespace import ::stackato::v2
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::spaces::update {config} {
    debug.cmd/spaces {}
    # @name, @newname, @default

    set space [$config @name]
    set changes 0

    set sname [$space @name]

    foreach {label cattr attr transform} {
	name    @newname @name              {}
	default @default @is_default        {}
    } {
	if {![$config $cattr set?]} continue

	$space $attr set [set newvalue [$config $cattr]]
	if {!$changes} {
	    display "Changing '[color name $sname]' ..."
	}

	if {$transform ne {}} {
	    set newvalue [{*}$transform $newvalue]
	}

	display "    Setting $label to \"$newvalue\" ... "
	incr changes
    }

    if {$changes} {
	display Committing... false
	$space commit
	display [color good OK]
    } else {
	display [color note {No changes}]
    }
    return
}

proc ::stackato::cmd::spaces::switch {config} {
    debug.cmd/spaces {}
    # @name
    # @organization

    set org [$config @organization]

    try {
	set space [$config @name]
    } trap {CMDR VALIDATE SPACENAME} {e o} {
	set name [$config @name string]
	err "Unable to switch to space \"$name\" (not found, or not a member)"
    }

    if {$org eq {}} {
	display [color warning {Unable to switch, no organization specified}]
	return
    }
    if {$space eq {}} {
	display [color warning {Unable to switch, no space specified}]
	return
    }

    display "Switching to organization [color name [$org @name]] ... " false
    corg set $org
    corg save
    display [color good OK]

    display "Switching to space [color name [$space @name]] ... " false
    cspace set $space
    cspace save
    display [color good OK]

    display [context format-large]
    return
}

proc ::stackato::cmd::spaces::create {config} {
    debug.cmd/spaces {}
    # @name
    # @organization

    set name [$config @name]
    if {![$config @name set?]} {
	$config @name undefined!
    }
    if {$name eq {}} {
	err "An empty space name is not allowed"
    }

    set thespace [v2 space new]
    set theorg   [corg get]

    display [context format-org]

    display "Creating new space \"[color name $name]\" ... " false

    $thespace @name         set $name
    $thespace @organization set $theorg
    $thespace @is_default   set [$config @default]
    $thespace commit
    display [color good OK]

    if {[$config @developer] ||
	[$config @manager]   ||
	[$config @auditor]} {
	set user [v2 deref-type user [[$config @client] user]]

	set relationissues 0
	foreach {attrc attre label} {
	    @developer @developers developer
	    @manager   @managers   manager
	    @auditor   @auditors   auditor
	} {
	    if {![$config $attrc]} continue

	    set header "  Adding you as $label ... "
	    set hlen [string length $header]
	    display $header false
	    try {
		$thespace $attre add $user

	    } trap {STACKATO CLIENT V2 INVALID RELATION} {e o} {
		incr relationissues
		display [wrap [color bad $e] $hlen]
	    } on error {e o} {
		# General error, just show its message.
		display [wrap [color bad $e] $hlen]
	    } on ok {e o} {
		display [color good OK]
	    }
	}

	if {$relationissues} {
	    # Relation errors, ping user about possible cause
	    display [wrap [color note "Are you a developer for organization \"[$theorg @name]\" ?"]]
	    display [wrap [color note "  For if not would explain the invalid-relation errors we got issued."]]
	}
    }

    if {[$config @activate]} {
	display "Switching to space [color name [$thespace @name]] ... " false
	cspace set $thespace
	cspace save
	display [color good OK]

	display [context format-large]
    }
    return
}

proc ::stackato::cmd::spaces::delete {config} {
    debug.cmd/spaces {}
    # @name - Space object

    set space     [$config @name]
    set iscurrent [$space == [cspace get]]
    set recursive [$config @recursive]

    if {$recursive} {
	set suffix { and all its contents}
    } else {
	set suffix {}
    }

    if {[cmdr interactive?] &&
	![ask yn \
	      "\nReally delete \"[color name [$space @name]]\"$suffix ? " \
	      no]} return

    if {$recursive} {
	$space delete recursive true
    } else {
	$space delete
    }

    display "Deleting space [color name [$space @name]] ... " false
    $space commit
    display [color good OK]

    # Update (remove) the current space, if that is the space we just
    # deleted.
    if {$iscurrent} {
	display [color warning "Dropped removed space as current space."]

	cspace reset
	cspace save
    }
    return
}

proc ::stackato::cmd::spaces::rename {config} {
    debug.cmd/spaces {}
    # @name
    # @newname

    set space [$config @name]
    set new   [$config @newname]

    if {![$config @newname set?]} {
	$config @newname undefined!
    }
    if {$new eq {}} {
	err "An empty space name is not allowed"
    }

    $space @name set $new

    display "Renaming space to [color name [$space @name]] ... " false
    $space commit
    display [color good OK]
    return
}

proc ::stackato::cmd::spaces::list {config} {
    debug.cmd/spaces {}
    # No arguments.

    if {[$config @json]} {
	set tmp {}
	foreach s [[corg get] @spaces get] {
	    lappend tmp [$s as-json]
	}
	display [json::write array {*}$tmp]
	return
    }

    display "In [color name [[corg get] @name]]..."
    set cs [cspace get]

    set titles {{} Name Default Apps Services}
    set full [$config @full]

    dict set sc depth 1
    dict set sc include-relations apps
    # ,service_instances -- Don't include this.
    # Doing so would preempt the 'user-provided=1' below,
    # thus listing only managed services instead of all.
    if {$full} {
	lappend titles Developers Managers Auditors
	dict set    sc depth 2
	dict append sc include-relations ,developers,managers,auditors
    }

    [table::do t $titles {
	set spaces [[corg get] @spaces get* $sc]

	foreach space [v2 sort @name $spaces -dict] {
	    if {[$space @is_default defined?]} {
		set isdef [expr { [$space @is_default] ? "x" : "" }]
	    } else {
		# attribute not supported by target.
		set isdef "N/A"
	    }

	    lappend values [expr {($cs ne {}) && [$cs == $space] ? "x" : ""}]
	    lappend values [color name [$space @name]]
	    lappend values $isdef
	    lappend values [join [lsort -dict [$space @apps @name]] \n]
	    lappend values [join [lsort -dict [$space @service_instances get* {user-provided true} @name]] \n]

	    if {$full} {
		lappend values [join [lsort -dict [$space @developers the_name]] \n]
		lappend values [join [lsort -dict [$space @managers   the_name]] \n]
		lappend values [join [lsort -dict [$space @auditors   the_name]] \n]
	    }

	    $t add {*}$values
	    unset values
	}
    }] show display
    return
}

proc ::stackato::cmd::spaces::show {config} {
    debug.cmd/spaces {}
    # @name

    set space [$config @name]
    # TODO: space load - Depth 1/2 - How to specify ? Must be in dispatcher.

    if {[$config @json]} {
	puts [$space as-json]
	return
    }

    display [context format-short]
    [table::do t {Key Value} {
	foreach {var attr} {
	    isdef is_default
	} {
	    if {[$space @$attr defined?]} {
		set $var [$space @$attr]
	    } else {
		# attribute not supported by target.
		set $var "N/A (not supported by target)"
	    }
	}

	$t add Default      $isdef
	$t add Organization [$space @organization @name]
	$t add Apps         [join [lsort -dict [$space @apps @name]] \n]
	$t add Services     [join [lsort -dict [$space @service_instances get* {user-provided true} @name]] \n]
	$t add Domains      [join [lsort -dict [$space @domains @name]] \n]

	if {[$config @full]} {
	    $t add Developers [join [lsort -dict [$space @developers the_name]] \n]
	    $t add Managers   [join [lsort -dict [$space @managers   the_name]] \n]
	    $t add Auditors   [join [lsort -dict [$space @auditors   the_name]] \n]
	}

    }] show display
    return
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::spaces 0

