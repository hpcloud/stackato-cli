# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::client::cli::command::MemHelp
package require stackato::client::cli::command::ServiceHelp
package require stackato::client::cli::usage
package require stackato::color
package require stackato::log
package require stackato::term
package require stackato::client
package require stackato::jmap
package require linenoise
package require table
package require url
package require dictutil

namespace eval ::stackato::client::cli::command::Misc {}

debug level  cli/misc
debug prefix cli/misc {[::debug::snit::call] | }

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::client::cli::command::Misc {
    superclass ::stackato::client::cli::command::ServiceHelp \
	::stackato::client::cli::command::MemHelp

    # # ## ### ##### ######## #############

    constructor {args} {
	Debug.cli/misc {}

	# Namespace import, sort of.
	namespace path [linsert [namespace path] end \
			    ::stackato ::stackato::log ::stackato::client::cli]
	next {*}$args
    }

    destructor {
	Debug.cli/misc {}
    }

    # # ## ### ##### ######## #############
    ## API

    method host_add {__ ip args} {
	Debug.cli/misc {}
	lassign [my HostGet] hostfile hosts

	if {[my HostContains hosts $args]} {
	    err "Unable to add, at least one of\n\t[join $args \n\t]\nalready has a mapping"
	}

	# Add entries for the new mappings.
	lappend hosts {}
	foreach host $args {
	    lappend hosts "$ip $host"
	}

	my HostCompress hosts
	my HostWrite $hostfile $hosts
	return
    }

    method host_update {__ ip args} {
	Debug.cli/misc {}
	lassign [my HostGet] hostfile hosts

	if {[my HostContains hosts $args]} {
	    err "Unable to add, at least one of\n\t[join $args \n\t]\nalready has a mapping"
	}

	# Remove the old mappings involving the ip-address.
	my HostRemoveAddress hosts $ip

	# Add entries for the new mappings, completing the replacement.
	lappend hosts {}
	foreach host $args {
	    lappend hosts "$ip $host"
	}

	my HostCompress hosts
	my HostWrite $hostfile $hosts
	return
    }


    method host_remove {__ args} {
	Debug.cli/misc {}

	lassign [my HostGet] hostfile hosts

	# Remove all references to the specified ip-addresses and hostnames.
	my HostRemove   hosts $args
	my HostCompress hosts
	my HostWrite $hostfile $hosts
	return
    }

    method host_list {__} {
	Debug.cli/misc {}
	lassign [my HostGet] hostfile hosts
	display [join $hosts \n]
	return
    }

    # # ## ### ##### ######## ############# #####################
    method HostRemoveAddress {hvar ipaddress} {
	upvar 1 $hvar hosts
	my HostApply hosts [callback __HostRemoveAddress $ipaddress]
	return
    }
    method __HostRemoveAddress {ipaddress entry} {
	set pos [lsearch -exact $entry $ipaddress]
	# Ignore not-match, and match as host.
	if {$pos != 0} {
	    if {[string equal {} [string trim $entry]]} { return { } }
	    return $entry
	}
	# Match a ip-adress, squash whole line.
	return { }
    }

    # # ## ### ##### ######## ############# #####################
    method HostRemove {hvar hostoriplist} {
	upvar 1 $hvar hosts
	my HostApply hosts [callback __HostRemove $hostoriplist]
	return
    }
    method __HostRemove {hostoriplist entry} {
	foreach h $hostoriplist {
	    set pos [lsearch -exact $entry $h]
	    # Ignore not-match
	    if {$pos < 0} continue
	    # Match a ip-adress, squash whole line.
	    if {$pos == 0} { return { } }
	    # Match as host, remove
	    set entry [lreplace $entry $pos $pos]
	}
	# Only hosts matched, if any. If only ip-address left squash
	# the line, else return the modified state.
	if {[llength $entry] <= 1} {
	    return { }
	} else {
	    return $entry
	}
    }

    # # ## ### ##### ######## ############# #####################
    method HostCompress {hvar} {
	upvar 1 $hvar hosts
	set lastempty 0
	my HostApply hosts [callback __HostCompress]
	return
    }
    method __HostCompress {entry} {
	upvar 1 lastempty lastempty
	set empty [string equal {} [string trim $entry]]
	if {$empty && $lastempty} {
	    return {}
	}
	set lastempty $empty
	if {$empty} { return { } }
	return $entry
    }

    # # ## ### ##### ######## ############# #####################
    method HostContains {hvar hostnames} {
	upvar 1 $hvar hosts
	return [my HostMatch hosts [callback __HostContains $hostnames]]
    }
    method __HostContains {hostnames entry} {
	foreach h $hostnames {
	    set pos [lsearch -exact $entry $h]
	    # Not found, or ip-address column -> ignore
	    if {$pos <= 0} continue
	    # Found, stop.
	    return 1
	}
	return 0
    }

    # # ## ### ##### ######## ############# #####################
    method HostApply {hvar cmd} {
	upvar 1 $hvar hosts
	foreach entry $hosts {
	    if {[string match "\#*" [string trim $entry]]} {
		lappend new $entry
	    } else {
		set centry [uplevel 1 [list {*}$cmd $entry]]
		if {$centry ne {}} {
		    lappend new $centry
		}
	    }
	}
	set hosts $new
	return
    }

    method HostMatch {hvar cmd} {
	upvar 1 $hvar hosts
	foreach entry $hosts {
	    if {[string match "\#*" [string trim $entry]]} {
		continue
	    }
	    if {[{*}$cmd $entry]} {
		return 1
	    }
	}
	return 0
    }

    # # ## ### ##### ######## ############# #####################
    method HostWrite {hostfile lines} {
	# Save to a temp file first.

	if {[dict get [my options] dry]} {
	    puts "CHANGED [join $lines "\nCHANGED "]"
	    return
	}

	set tmp [fileutil::tempfile stackato_winhost_]
	fileutil::writeFile $tmp [string trim [join $lines \n]]\n
	config::FixPermissions $tmp 0644

	# Now for the tricky part, copying the modified file content
	# into the system file.
	#
	# - Generate a .bat file which runs a powershell script which
	#   launches a copy command in elevated mode.
	#
	# - Execute powershell to launch a copy command in elevated
	#   privileges
	#
	# What system restrictions doe use of powershell pose ?
	# XP+, Vista+, Win7+ ?

	# Atomic overwrite of the true destination.
	if {[catch {
	    file rename -force $tmp $hostfile
	} msg]} {
	    global tcl_platform

	    #file delete $tmp
	    if {$tcl_platform(platform) eq "windows"} {
		err "Unable write changes back into $hostfile: $msg"
	    } else {
		err "Unable write changes back into $hostfile: $msg.\nPlease consider running the command via 'sudo'."
	    }
	}
	return
    }

    # Return content of the system's hosts file, as a list of lines.
    method HostGet {} {
	set base [my HostFileLocate]
	foreach f [list $base $base.txt] {
	    if {![file exists $f]} continue
	    if {[catch {
		fileutil::cat $f
	    } res]} {
		err $res
	    }
	    return [list $f [split $res \n]]
	}
	return -code error "Windows Hosts file not found"
    }

    # Return path to the Win32 hosts file.
    method HostFileLocate {} {
	global tcl_platform
	if {$tcl_platform(platform) eq "windows"} {
	    return $::env(SystemRoot)/system32/drivers/etc/hosts
	} else {
	    return /etc/hosts
	}
    }

    # # ## ### ##### ######## ############# #####################

    method debug_home {} {
	Debug.cli/misc {}

	catch { say "STACKATO_APP_ROOT=$::env(STACKATO_APP_ROOT)" }
	say "HOME=             $::env(HOME)"
	say "~=                [file normalize ~]"
	return
    }

    method revision {} {
	Debug.cli/misc {}

	if {[catch {
	    set revfile $::starkit::topdir/lib/application/revision.txt
	}] || ![file exists $revfile]} {
	    say "local: [exec git describe]"
	} else {
	    say "wrapped: [fileutil::cat $revfile]"
	}
	return
    }

    method columns {} {
	Debug.cli/misc {}

	say [linenoise columns]
	return
    }

    method version {} {
	Debug.cli/misc {}

	say "[usage me] [package present stackato::client::cli]"
	return
    }

    method target {} {
	Debug.cli/misc {}

	if {[my GenerateJson]} {
	    display [jmap target [dict create target [my target_url]]]
	    return
	}

	banner \[[my target_url]\]
	return
    }

    method targets {} {
	Debug.cli/misc {}

	set targets [config targets]
	# @type targets = dict(<any>/string)

	if {[my GenerateJson]} {
	    display [jmap targets $targets]
	    return
	}
	if {![llength $targets]} {
	    display "None specified"
	    return
	}

	table::do t {Target Authorization} {
	    foreach {target token} $targets {
		$t add $target $token
	    }
	}
	display ""
	$t show display
	return
    }

    method tokens {} { my targets }

    method set_target {target_url} {
	Debug.cli/misc {}

	set target_url [url canon $target_url]

	if {![config allow-http] && [regexp {^http:} $target_url]} {
	    err "Illegal use of $target_url.\nEither re-target to use https, or force acceptance via --allow-http"
	}

	set client  [stackato::client new $target_url]
	set verbose [dict get [my options] verbose]

	if {[$client target_valid?]} {
	    config store_target $target_url
	    say [color green "Successfully targeted to \[$target_url\]"]
	} else {
	    display [color red "Host is not valid: '$target_url'"]

	    if {![regexp {^https?://api\.} $target_url]} {
		display [color yellow "Warning: Did you wish to specify \[[my guessurl $target_url]\] instead ?"]
	    }

	    if {$verbose ||
		([my promptok] && 
		 [term ask/yn "Would you like see the response ? " no])} {
		my ShowRawTargetResponse $client
	    }
	    exit 1
	}

	return
    }

    method guessurl {target_url} {
	if {![regexp {^https?://} $target_url]} {
	    return https://api.$target_url
	}
	regsub {^(https?://)} $target_url {\1api.} newurl
	return $newurl
    }

    method ShowRawTargetResponse {client} {
	Debug.cli/misc {}

	# Have to capture errors, like target_valid? does.
	try {
	    set raw [$client raw_info]
	} on error e {
	    set raw $e
	}
	display "\n<<<\n$raw\n>>>\n"
	return
    }

    method group_show {} {
	Debug.cli/misc {}
	if {[[my client] logged_in?]} {
	    my CheckGroupSupport
	}

	if {[dict exists [my options] reset]} {
	    Debug.cli/misc {RESET}

	    config reset_group
	    say "Reset current group: [color green OK]"
	    return
	}

	if {[my GenerateJson]} {
	    display [jmap group [dict create group [my group]]]
	    return
	}

	banner \[[my group]\]
	return
    }

    method group_set {name} {
	Debug.cli/misc {}
	my CheckGroupSupport

	set groups [my TheUsersGroups]
	if {$name ni $groups} {
	    display [color red "You are not a member of group '$name'"]
	    display [color red "Groups available to you:\n\t[join $groups \n\t]"]
	    ::exit 1
	}

	config store_group $name
	say [color green "Successfully set current group to \[$name\]"]
	return
    }

    method groups_show {} {
	Debug.cli/misc {}
	my CheckGroupSupport

	set groups [[my client] groups]
	# json = dict (groupname -> list (member...))

	if {[my GenerateJson]} {
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

    method group_create {__ groupname} {
	Debug.cli/misc {}
	my CheckGroupSupport

	if {$groupname eq {}} {
	    err "Need a valid group name"
	}

	display {Creating New Group: } false
	[my client] add_group $groupname
	display [color green OK]
	return
    }

    method group_delete {__ groupname} {
	Debug.cli/misc {}
	my CheckGroupSupport

	if {$groupname eq {}} {
	    err "Need a valid group name"
	}

	display {Deleting Group: } false
	[my client] delete_group $groupname
	display [color green OK]
	return
    }

    method group_add_user {__ groupname username} {
	Debug.cli/misc {}
	my CheckGroupSupport

	# XXX: Possibly extend syntax to make user name optional and query it interactively.

	if {$groupname eq {}} {
	    err "Need a valid group name"
	}
	if {$username eq {}} {
	    err "Need a valid user name"
	}

	display {Adding User To Group: } false
	[my client] group_add_user $groupname $username
	display [color green OK]
	return
    }

    method group_remove_user {__ groupname username} {
	Debug.cli/misc {}
	my CheckGroupSupport

	# XXX: Possibly extend syntax to make user name optional and query it interactively.

	if {$groupname eq {}} {
	    err "Need a valid group name"
	}
	if {$username eq {}} {
	    err "Need a valid user name"
	}

	display {Removing User From Group: } false
	[my client] group_remove_user $groupname $username
	display [color green OK]
	return
    }

    method group_users {__ {groupname {}}} {
	Debug.cli/misc {}
	my CheckGroupSupport

	if {$groupname eq {}} {
	    set groupname [config group]
	}
	if {$groupname eq {}} {
	    err "Need a valid group name"
	}

	set users [[my client] group_list_users $groupname]

	if {[my GenerateJson]} {
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

    method group_limits {__ {groupname {}}} {
	my group_limits1 $groupname
    }

    method group_limits1 {{groupname {}}} {
	Debug.cli/misc {}
	my CheckGroupSupport

	# Without a group specified fall back to the current group
	if {$groupname eq {}} {
	    set groupname [config group]
	}

	# Without a current group fall back to the user (== personal group)
	if {$groupname eq {}} {
	    set groupname [dict get [my client_info] user]
	}

	set oldlimits [[my client] group_limits_get $groupname]

	set changed 0
	set unsupported 0
	foreach {o key validatecmd} {
	    mem             memory   {my mem_choice_to_quota}
	    limit-apps      apps     {my Integer {Bad application limit} {LIMIT APPS}}
	    limit-appuris   app_uris {my Integer {Bad app uri limit}     {LIMIT APPURIS}}
	    limit-services  services {my Integer {Bad services limit}    {LIMIT SERVICES}}
	    limit-sudo      sudo     {my Boolean {Bad sudo flag}         {LIMIT SUDO}}
	    limit-drains    drains   {my Integer {Bad drains limit}      {LIMIT DRAINS}}
	} {
	    if {![dict exists [my options] $o]} continue
	    if {![dict exists $oldlimits $key]} {
		display [color yellow "Warning: Unable to modify unsupported limit \"$key\"."]
		set unsupported 1
		continue
	    }
	    lappend limits $key [{*}$validatecmd [dict get [my options] $o]]
	    set changed 1
	}

	if {!$changed && $unsupported} {
	    return
	}

	if {!$changed} {
	    set limits $oldlimits

	    if {[my GenerateJson]} {
		display [jmap limits $limits]
		return
	    }

	    display ""
	    display "Group: $groupname"
	    table::do t {Limit Value} {
		foreach {k v} $limits {
		    $t add $k $v
		}
	    }
	    #display ""
	    $t show display
	    return
	}

	display {Updating Group Limits: } false
	[my client] group_limits_set $groupname $limits
	display [color green OK]
	return
    }

    method Integer {prefix code x} {
	if {![string is integer -strict $x]} {
	    return -code error -errorcode [list STACKATO CLIENT CLI {*}$code] \
		"$prefix: Expected integer value, got \"$x\""
	}
	return $x
    }

    method Boolean {prefix code x} {
	if {![string is bool -strict $x]} {
	    return -code error -errorcode [list STACKATO CLIENT CLI {*}$code] \
		"$prefix: Expected boolean value, got \"$x\""
	}
	return $x
    }

    method usage {{userOrGroup {}}} {
	Debug.cli/misc {}

	# Make the current group available, if any, ensuring validity
	my confer-group

	set all [dict get [my options] all]

	set info [[my client] usage $all $userOrGroup]

	if {[my GenerateJson]} {
	    #@type info = dict:
	    # allocated:
	    #   mem: KB
	    # usage:   
	    #   mem: KB

	    display [jmap usageinfo $info]
	    return
	}

	display "Allocated Memory: [log psz [expr {1024*[dict get $info allocated mem]}]]"
	display "Used Memory:      [log psz [expr {1024*[dict get $info usage mem]}]]"
	return
    }

    method info {} {
	Debug.cli/misc {}

	# Make the current group available, if any, ensuring validity
	if {[[my client] logged_in?]} {
	    my confer-group 0
	    my clientinfo_reset
	}

	set info [my client_info]
	if {[my GenerateJson]} {
	    #@type info = dict:
	    #    name build support version description /string
	    #    user/dict: 
	    #    usage/dict: apps memory services /string
	    #    limits/dict: sa + app_uris
	    #    frameworks/dict: <any>/dict:
	    #        appservers/array(dict)
	    #        runtimes/array(dict)
	    #        detection/array(dict)
	    #	     */string

	    display [jmap clientinfo $info]
	    return
	}

	dict validate $info
	dict with info {
	    if {[dict exists $info vendor_version]} {
		display "\n$description $vendor_version"
	    } else {
		display "\n$description"
	    }
	    display "For support visit $support"
	    display ""
	    display "Target:   [my target_url] (v$version)"
	    display "Client:   v[package present stackato::client::cli]"
	}

	if {[dict exists $info user] ||
	    [dict exists $info groups]} {
	    display ""
	    if {[dict exists $info user]} {
		display "User:     [dict get $info user]"
	    }
	    if {[dict exists $info groups]} {
		set groups [dict get $info groups]
		set current [config group]
		if {$current ne {}} {
		    set pos [lsearch -exact $groups $current]
		    if {$pos >= 0} {
			lset groups $pos \[$current\]
		    }
		}
		display "Groups:   [join $groups "\n          "]"
	    }
	}

	if {[dict exist $info usage] &&
	    [dict exist $info limits]} {
	    set usage  [dict get $info usage] 
	    set limits [dict get $info limits]

	    dict with limits {
		set tmem  [log psz [expr {$memory*1024*1024}]]
		set tser  $services
		if {[catch { set tapps $apps }]} { set tapps 0 }
	    }

	    dict with usage {
		set mem  [log psz [expr {$memory*1024*1024}]]
		set ser  $services
		if {[catch { set apps $apps }]} { set apps 0 }
	    }

	    display "Usage:    Memory   ($mem of $tmem total)"
	    display "          Services ($ser of $tser total)"

	    if {[dict exists $limits apps]} {
		display "          Apps     ($apps of $tapps total)"
	    }
	}

	return
    }

    method apps {} {
	Debug.cli/misc {}

	# Make the current group available, if any, ensuring validity
	my confer-group

	set apps [[my client] apps]
	#@type apps = list (...) /@todo fill element type

	set apps [lsort -command [lambda {a b} {
	    string compare [dict getit $a name] [dict getit $b name]
	}] $apps]

	if {[my GenerateJson]} {
	    # Same hack as done in service_dbshell,
	    # for consistent output.
	    set apps [struct::list map $apps [lambda {fc app} {
		if {[dict exists $app services_connect_info]} {
		    set sci [dict get $app services_connect_info]
		    set newsci {}
		    foreach s $sci {
			lappend newsci [{*}$fc $s]
		    }
		    dict set app services_connect_info $newsci
		}
		return $app
	    } [callback FixCredentials]]]

	    display [jmap apps $apps]
	    return
	}

	display ""
	if {![llength $apps]} {
	    display "No Applications"
	    return
	}

	table::do t {Application \# Health URLS Services} {
	    foreach app $apps {
		set health [my health $app]
		if {[string is double -strict $health]} {
		    append health %
		}
		$t add \
		    [dict getit $app name] \
		    [dict getit $app instances] \
		    $health \
		    [join [dict getit $app uris] \n] \
		    [join [dict getit $app services] \n]
	    }
	}
	#display ""
	$t show display
	return
    }

    method services {} {
	Debug.cli/misc {}

	# Make the current group available, if any, ensuring validity
	my confer-group

	set ss [[my client] services_info]
	#@type services = dict (database, key-value /DESC)
	#@type DESC = dict (<any-name>/dict (<any-version>/VERSION)
	#@type VERSION

	set ps [[my client] services]
	#@type ps = list (services?)

	set ps [lsort -command [lambda {a b} {
	    string compare [dict getit $a name] [dict getit $b name]
	}] $ps]

	if {[my GenerateJson]} {
	    display [jmap services \
			 [dict create \
			      system      $ss \
			      provisioned $ps]]
	    return
	}

	my display_system_services      $ss
	my display_provisioned_services $ps
    }

    method runtimes {} {
	Debug.cli/misc {}

	my CheckLogin
	if {[my GenerateJson]} {
	    display [jmap runtimes [my runtimes_info]]
	    return
	}

	if {![llength [my runtimes_info]]} {
	    display "No Runtimes"
	    return
	}

	table::do t {Name Description Version} {
	    dict for {_ rt} [my runtimes_info] {
		$t add \
		    [dict getit $rt name] \
		    [dict getit $rt description] \
		    [dict getit $rt version]
	    }
	}
	display ""
	$t show display
	return
    }

    method frameworks {} {
	Debug.cli/misc {}

	my CheckLogin
	if {[my GenerateJson]} {
	    display [jmap frameworks [my frameworks_info]]
	    return
	}
	if {![llength [my frameworks_info]]} {
	    display "No Frameworks"
	    return
	}

	table::do t {Name} {
	    foreach {name subf} [my frameworks_info] {
		if {[llength $subf]} {
		    foreach s $subf {
		    $t add "$name - $s"
		    }
		} else {
		    $t add $name
		}
	    }
	}
	display ""
	$t show display
	return
    }

    method aliases {} {
	Debug.cli/misc {}

	set aliases [config aliases]
	#@type aliases = dict(<any>/string)

	if {[my GenerateJson]} {
	    display [jmap aliases $aliases]
	    return
	}

	if {![llength $aliases]} {
	    display "No Aliases"
	    return
	}

	table::do t {Alias Command} {
	    foreach {k v} $aliases {
		$t add $k $v
	    }
	}
	display ""
	$t show display
	return
    }

    method alias {k {v {}}} {
	Debug.cli/misc {}

	if {[llength [info level 0]] == 3} {
	    lassign [split $k =] k v
	}

	set aliases [config aliases] ;#dict
	dict set aliases $k $v
	config store_aliases $aliases
	display [color green "Successfully aliased '$k' to '$v'"]
	return
    }

    method unalias {key} {
	Debug.cli/misc {}

	set aliases [config aliases] ;#dict

	if {[dict exists $aliases $key]} {
	    dict unset aliases $key
	    config store_aliases $aliases
	    display [color green "Successfully unaliased '$key'"]
	} else {
	    display [color red "Unknown alias '$key'"]
	}
	return
    }

    # # ## ### ##### ######## #############
    ## Internal commands.

    method CheckGroupSupport {} {
	Debug.cli/misc {}
	my CheckLogin
	if {![my HasGroupSupport]} {
	    return -code error -errorcode {STACKATO CLIENT CLI GROUP SUPPORT NO} \
		"Target \[[my target_url]\] does not support groups and limits."
	}
    }

    method HasGroupSupport {} {
	Debug.cli/misc {[array set ci [my client_info]][parray ci][unset ci]}
	return [dict exists [my client_info] groups]
    }

    # # ## ### ##### ######## #############
    ## State

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::client::cli::command::Misc 0
