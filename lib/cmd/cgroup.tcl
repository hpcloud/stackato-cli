# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations.
## Current group commands on top of the cgroup manager.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require table
package require cmdr::color
package require stackato::jmap
package require stackato::log
package require stackato::mgr::cgroup
package require stackato::mgr::client

namespace eval ::stackato::cmd {
    namespace export cgroup
    namespace ensemble create
}
namespace eval ::stackato::cmd::cgroup {
    namespace export getorset set-core reset-core
    namespace ensemble create

    namespace import ::cmdr::color
    namespace import ::stackato::jmap
    namespace import ::stackato::log::banner
    namespace import ::stackato::log::display
    namespace import ::stackato::log::err
    namespace import ::stackato::log::say
    namespace import ::stackato::mgr::cgroup
    namespace import ::stackato::mgr::client
}

debug level  cmd/cgroup
debug prefix cmd/cgroup {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Command implementations.

proc ::stackato::cmd::cgroup::getorset {config} {
    debug.cmd/cgroup {}

    # assert !(reset && name)

    if {[$config @reset set?] ||
	[$config @name set?]} {
	Set $config
    } else {
	Show $config
    }
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::cgroup::Set {config} {
    debug.cmd/cgroup {}

    if {[$config @reset]} {
	reset-core
	return
    }

    set name   [$config @name]
    set client [$config @client]

    set-core $client $name
    return
}

proc ::stackato::cmd::cgroup::set-core {client name} {
    debug.cmd/cgroup {}

    client check-group-support $client
    set groups [client the-users-groups $client]

    if {$name ni $groups} {
	append msg  "You are not a member of group '$name'.\n"
	append msg  "Groups available to you:\n\t[join $groups \n\t]"
	err $msg
    }

    cgroup set $name
    cgroup save

    say [color good "Successfully set current group to \[$name\]"]
    return
}

proc ::stackato::cmd::cgroup::reset-core {{client {}}} {
    debug.cmd/cgroup {}

    cgroup reset
    cgroup save

    if {($client ne {}) &&
	![dict exists [$client info] groups]} return
    say "Reset current group: [color good OK]"
    return
}

proc ::stackato::cmd::cgroup::Show {config} {
    debug.cmd/cgroup {}

    set client [$config @client]

    if {[$client logged_in?]} {
	client check-group-support $client
    }

    set group [cgroup get]

    if {[$config @json]} {
	display [jmap group [dict create group $group]]
	return
    }

    banner \[$group\]
    return
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::cmd::cgroup {}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::cgroup 0
