# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

## Command implementations. Groups/Users management.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require stackato::color
package require stackato::jmap
package require stackato::log
package require stackato::mgr::client
package require table

debug level  cmd/groups
debug prefix cmd/groups {[debug caller] | }

namespace eval ::stackato::cmd {
    namespace export groups
    namespace ensemble create
}
namespace eval ::stackato::cmd::groups {
    namespace export \
	add-user delete-user create delete limits show users \
	add-user-core limits-core
    namespace ensemble create

    namespace import ::stackato::color
    namespace import ::stackato::jmap
    namespace import ::stackato::log::display
    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::client
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::groups::add-user {config} {
    debug.cmd/groups {}

    set client [$config @client]

    set group [$config @group]
    set user  [$config @user]

    # TODO: Might be possible to place into validation types.
    if {$group eq {}} {
	err "Need a valid group name"
    }
    if {$user eq {}} {
	err "Need a valid user name"
    }

    add-user-core $client $group $user
    return
}

proc ::stackato::cmd::groups::delete-user {config} {
    debug.cmd/groups {}

    set client [$config @client]
    client check-group-support $client

    set group [$config @group]
    set user  [$config @user]

    # TODO: Might be possible to place into validation types.
    if {$group eq {}} {
	err "Need a valid group name"
    }
    if {$user eq {}} {
	err "Need a valid user name"
    }

    display {Removing User From Group ... } false
    $client group_remove_user $group $user
    display [color green OK]
    return
}

proc ::stackato::cmd::groups::create {config} {
    debug.cmd/groups {}

    set client [$config @client]
    client check-group-support $client

    set group [$config @name]

    # TODO: Might be possible to place into validation types.
    if {$group eq {}} {
	err "Need a valid group name"
    }

    display {Creating New Group ... } false
    $client add_group $group
    display [color green OK]
    return
}

proc ::stackato::cmd::groups::delete {config} {
    debug.cmd/groups {}
    set client [$config @client]
    client check-group-support $client

    set group [$config @name]

    # TODO: Might be possible to place into validation types.
    if {$group eq {}} {
	err "Need a valid group name"
    }

    display {Deleting Group ... } false
    $client delete_group $group
    display [color green OK]
    return
}

proc ::stackato::cmd::groups::limits {config} {
    debug.cmd/groups {}

    set client [$config @client]

    set group [$config @group]
    # TODO: Might be possible to place into cmdr generator
    # Without a current group fall back to the user (== personal group)
    if {$group eq {}} {
	set group [dict get [$client info] user]
    }

    limits-core $client $group $config
    return
}

proc ::stackato::cmd::groups::show {config} {
    debug.cmd/groups {}

    set client [$config @client]
    client check-group-support $client

    set groups [$client groups]
    # json = dict (groupname -> list (member...))

    if {[$config @json]} {
	display [jmap groups $groups]
	return
    }

    display ""
    if {![llength $groups]} {
	display "No Groups"
	return
    }

    table::do t {Group Members} {
	foreach {name members} [dict sort $groups] {
	    set members [lsort -dict $members]
	    set members [join $members {, }]
	    set members [textutil::adjust::adjust $members -length 60 -strictlength 1]
	    $t add $name $members
	}
    }
    #display ""
    $t show display
    return
}

proc ::stackato::cmd::groups::users {config} {
    debug.cmd/groups {}

    set client [$config @client]
    client check-group-support $client

    set group [$config @group]

    if {$group eq {}} {
	err "Need a valid group name"
    }

    set users [$client group_list_users $group]

    if {[$config @json]} {
	display [jmap map array $users]
	return
    }

    display ""
    if {![llength $users]} {
	display "No Users"
	return
    }

    table::do t {Member} {
	foreach email $users {
	    $t add $email
	}
    }
    #display ""
    $t show display
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::groups::add-user-core {client group user} {
    client check-group-support $client

    display {Adding User To Group ... } false
    $client group_add_user $group $user
    display [color green OK]
    return
}

proc ::stackato::cmd::groups::limits-core {client group config} {
    debug.cmd/groups {}

    client check-group-support $client

    # Pull current settings
    set oldlimits [$client group_limits_get $group]

    # Determine new settings.
    set changed 0
    set unsupported 0
    foreach {o key} {
	@apps     apps
	@appuris  app_uris
	@drains   drains
	@mem      memory
	@services services
	@sudo     sudo
    } {
	# Ignore missing options, treated as unchanged.
	if {![$config $o set?]} continue

	# Ignore limits which were specified, but are not
	# supported by the target.
	if {![dict exists $oldlimits $key]} {
	    display [color yellow "Warning: Unable to modify unsupported limit \"$key\"."]
	    set unsupported 1
	    continue
	}

	# Everything passing is considered a change (even if the
	# new value is the same as the old).
	#
	# NOTE: Validation already happened, by cmdr.
	# TODO: Use custom validation types for custom messaging.
	#
	# {my mem_choice_to_quota}
	# {my Integer {Bad application limit} {LIMIT APPS}}
	# {my Integer {Bad app uri limit}     {LIMIT APPURIS}}
	# {my Integer {Bad services limit}    {LIMIT SERVICES}}
	# {my Boolean {Bad sudo flag}         {LIMIT SUDO}}
	# {my Integer {Bad drains limit}      {LIMIT DRAINS}}

	lappend limits $key [$config $o]
	set changed 1
    }

    if {!$changed && $unsupported} {
	return
    }

    if {!$changed} {
	set limits $oldlimits

	if {[$config @json]} {
	    display [jmap limits $limits]
	    return
	}

	display ""
	display "Group: $group"
	table::do t {Limit Value} {
	    foreach {k v} $limits {
		$t add $k $v
	    }
	}
	#display ""
	$t show display
	return
    }

    display {Updating Group Limits ... } false
    $client group_limits_set $group $limits
    display [color green OK]
    return
}

proc ::stackato::cmd::groups::show {config} {
    debug.cmd/groups {}

    set client [$config @client]
    client check-group-support $client

    set groups [$client groups]
    # json = dict (groupname -> list (member...))

    if {[$config @json]} {
	display [jmap groups $groups]
	return
    }

    display ""
    if {![llength $groups]} {
	display "No Groups"
	return
    }

    table::do t {Group Members} {
	foreach {name members} [dict sort $groups] {
	    set members [lsort -dict $members]
	    set members [join $members {, }]
	    set members [textutil::adjust::adjust $members -length 60 -strictlength 1]
	    $t add $name $members
	}
    }
    #display ""
    $t show display
    return
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::groups 0

