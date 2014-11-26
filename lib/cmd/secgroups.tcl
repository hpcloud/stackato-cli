# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations. Management of security-groups.

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

debug level  cmd/secgroups
debug prefix cmd/secgroups {[debug caller] | }

namespace eval ::stackato::cmd {
    namespace export secgroups
    namespace ensemble create
}
namespace eval ::stackato::cmd::secgroups {
    namespace export \
	show list create update delete bind unbind
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

proc ::stackato::cmd::secgroups::create {config} {
    debug.cmd/secgroups {}

    set group [$config @security_group]
    set rules [$config @rules]

    # Read and validate the rules a bit.
    set rules [fileutil::cat $rules]
    try {
	json::json2dict $rules
    } trap {JSON} {e o} {
	err "Bad json data for network rules: $e"
    }

    display "Creating new security group \"[color name $group]\" ... " false

    set thegroup [v2 security_group new]
    $thegroup @name  set $group
    $thegroup @rules set $rules
    $thegroup commit
    display [color good OK]
    return
}

proc ::stackato::cmd::secgroups::delete {config} {
    debug.cmd/secgroups {}

    set thegroup [$config @security_group]

    if {[cmdr interactive?] &&
	![ask yn \
	      "\nReally delete \"[color name [$thegroup @name]]\" ? " \
	      no]} return

    display "Deleting security group \"[color name [$thegroup @name]]\" ... " false
    $thegroup delete
    $thegroup commit
    display [color good OK]
    return
}

proc ::stackato::cmd::secgroups::update {config} {
    debug.cmd/secgroups {}

    set thegroup [$config @security_group]
    set rules    [$config @rules]

    # Read and validate the rules a bit.
    set rules [fileutil::cat $rules]
    try {
	json::json2dict $rules
    } trap {JSON} {e o} {
	err "Bad json data for network rules: $e"
    }

    display "Updating security group \"[color name [$thegroup @name]]\" ... " false

    $thegroup @rules set $rules
    $thegroup commit
    display [color good OK]
    return
}

proc ::stackato::cmd::secgroups::show {config} {
    debug.cmd/secgroups {}

    set thegroup [$config @security_group]

    if {[$config @json]} {
	display [$thegroup as-json]
	return
    }

    display \n[context format-target " [color name [$thegroup @name]]"]
    [table::do t {Key Value} {
	$t add Name    [color name [$thegroup @name]]
	$t add Rules   [$thegroup @rules]
	$t add Spaces  [join [lsort -dict [$thegroup @spaces full-name]] \n]
	$t add Staging [$thegroup @staging_default]
	$t add Running [$thegroup @running_default]
    }] show display
    return
}

proc ::stackato::cmd::secgroups::bind {config} {
    debug.cmd/secgroups {}

    set thegroup [$config @security_group]

    if {[$config @staging]} {
	set dest [color note {Staging Default}]
    } elseif {[$config @running]} {
	set dest [color note {Running Default}]
    } else {
	set thespace [cspace get]
	set dest "space [color name [$thespace full-name]]"
    }

    display "Binding security group \"[color name [$thegroup @name]]\" to $dest ... " false

    if {[$config @staging]} {
	$thegroup stager-default yes
    } elseif {[$config @running]} {
	$thegroup run-default yes
    } else {
	$thegroup @spaces add $thespace
    }
    display [color good OK]
    return
}

proc ::stackato::cmd::secgroups::unbind {config} {
    debug.cmd/secgroups {}

    set thegroup [$config @security_group]

    if {[$config @staging]} {
	set dest [color note {Staging Default}]
    } elseif {[$config @running]} {
	set dest [color note {Running Default}]
    } else {
	set thespace [cspace get]
	set dest "space [color name [$thespace full-name]]"
    }

    display "Unbinding security group \"[color name [$thegroup @name]]\" from $dest ... " false

    if {[$config @staging]} {
	$thegroup stager-default no
    } elseif {[$config @running]} {
	$thegroup run-default no
    } else {
	$thegroup @spaces remove $thespace
    }
    display [color good OK]
    return
}

proc ::stackato::cmd::secgroups::list {config} {
    debug.cmd/secgroups {}

    if {[$config @staging]} {
	set thegroups  [v2 security_group stager-defaults]
	set ctx        [context format-target " ([color name Staging])"]
    } elseif {[$config @running]} {
	set thegroups  [v2 security_group run-defaults]
	set ctx        [context format-target " ([color name Running])"]
    } else {
	set thegroups [v2 security_group list 2]
	set ctx       [context format-target]
    }

    if {[$config @json]} {
	set tmp {}
	foreach g $thegroups {
	    lappend tmp [$g as-json]
	}
	display [json::write array {*}$tmp]
	return
    }

    display "\nSecurity-Groups: $ctx"
    if {![llength $thegroups]} {
	display [color note "No Security Groups"]
	return
    }

    [table::do t {Name {#Rules} Spaces Staging Running} {
	foreach g $thegroups {
	    $t add \
		[color name [$g @name]] \
		[llength [json::json2dict [$g @rules]]] \
		[join [lsort -dict [$g @spaces full-name]] \n] \
		[$g @staging_default] \
		[$g @running_default]
	}
    }] show display

    return
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::secgroups 0

