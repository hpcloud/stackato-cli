# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## This module manages the client instances doing the REST calls.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require dictutil
package require cmdr::color
package require stackato::client
package require stackato::v2::client
package require stackato::jmap
package require stackato::log
package require stackato::misc
package require stackato::mgr::auth
package require stackato::mgr::cfile
package require stackato::mgr::cgroup
package require stackato::mgr::ctarget
package require stackato::mgr::targets
package require stackato::mgr::tadjunct
package require stackato::validate::memspec

namespace eval ::stackato::mgr {
    namespace export client
    namespace ensemble create
}

namespace eval ::stackato::mgr::client {
    namespace export \
	auth+group plain authenticated support \
	reset plain-reset authenticated-reset \
	confer-group frameworks runtimes \
	the-users-groups check-group-support \
	check-login app-exists? max-version \
	app-started-properly? check-capacity \
	check-app-limit notv2 isv2 isv2cmd notv2cmd \
	trace= plainc authenticatedc restlog \
	get-ssh-key description min-version \
	hasdrains chasdrains is-stackato \
	is-stackato-opt close-restlog license-status \
	max-version-opt min-version-opt rawc has-plain \
	has-authenticated
    namespace ensemble create

    namespace import ::cmdr::color
    namespace import ::stackato::mgr::cfile
    namespace import ::stackato::mgr::cgroup
    namespace import ::stackato::mgr::ctarget
    namespace import ::stackato::mgr::tadjunct
    namespace import ::stackato::mgr::targets
    namespace import ::stackato::mgr::auth
    namespace import ::stackato::client
    namespace import ::stackato::v2
    namespace import ::stackato::misc
    namespace import ::stackato::jmap
    namespace import ::stackato::log::err
    namespace import ::stackato::log::display
    namespace import ::stackato::validate::memspec

    # The possible state of a target's *stackato) licensing, plus associated message.
    variable license_state {
	NO_LICENSE_COMPLIANT                       {No license installed.@nUsing @U of @L.}
	NO_LICENSE_NONCOMPLIANT_UNDER_FREE_MEMORY  {No license installed.@nUsing @U of @L (@@ over licensed limit).@nGet a free license: @R}
	NO_LICENSE_NONCOMPLIANT_OVER_FREE_MEMORY   {No license installed.@nUsing @U of @L (@@ over licensed limit).@nBuy a license: @R}
	HAS_LICENSE_COMPLIANT                      {License installed, less than licensed memory in use.@n@S for "@O"@nUsing @U of @L.}
	HAS_LICENSE_NONCOMPLIANT                   {License installed, more than licensed memory in use.@n@S for "@O"@nUsing @U of @L (@@ over licensed limit).@nUpgrade your license: @R}
    }
}

debug level  mgr/client
debug prefix mgr/client {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## API

proc ::stackato::mgr::client::trace= {p value} {
    debug.mgr/client {}
    variable trace $value
    return
}

proc ::stackato::mgr::client::restlog {client} {
    debug.mgr/client {}
    $client trace 1
    $client configure -trace-fd [RestLog]
    return $client
}

proc ::stackato::mgr::client::close-restlog {} {
    debug.mgr/client {}
    variable restlog
    if {![info exists restlog]} { return 0 }
    close $restlog
    unset restlog
    return 1
}

proc ::stackato::mgr::client::RestLog {} {
    debug.mgr/client {}
    variable restlog
    global CHILD ; # See bin/stackato for definition.
    # This is a hack to quickly get the information about
    # process context.

    if {[info exists restlog]} {
	return $restlog
    }

    if {$CHILD} {
	# Child, append to master log
	set trace [open [cfile get rest] a]
    } else {
	# Toplevel, replace previous log.
	file mkdir [file dirname [cfile get rest]]
	set trace [open [cfile get rest] w]
    }

    fconfigure $trace -encoding utf-8

    debug.mgr/client {==> $trace (child $CHILD)}
    set restlog $trace
    return $trace
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::client::rawc {p} {
    debug.mgr/client {}
    $p config @motd
    $p config @cafile
    $p config @skip-ssl-validation

    return [restlog [client new [ctarget get] [auth get]]]
    # No target redirection.
    # No login check.
    # No determination of API version and switching classes.
}

proc ::stackato::mgr::client::plainc {p} {
    debug.mgr/client {}
    $p config @motd
    $p config @cafile
    $p config @skip-ssl-validation
    plain
}
proc ::stackato::mgr::client::authenticatedc {p} {
    debug.mgr/client {}
    $p config @motd
    $p config @cafile
    $p config @skip-ssl-validation
    authenticated
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::client::has-plain {} {
    debug.mgr/client {}
    variable plain
    return [info exists plain]
}

proc ::stackato::mgr::client::has-authenticated {} {
    debug.mgr/client {}
    variable auth
    return [info exists auth]
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::client::plain {} {
    debug.mgr/client {}
    variable plain

    if {![info exists plain]} {
	variable auth
	if {[info exists auth]} {
	    set id [$auth info]
	} else {
	    set id {}
	}
	set plain [Make $id]
    }

    # Note: While a token may be present login is not checked. This is
    # for commands which can operate with and without login, and may
    # even checking on their own to change behaviour. (Ex: s info).

    debug.mgr/client {==> $plain}
    return $plain
}

proc ::stackato::mgr::client::authenticated {} {
    debug.mgr/client {}
    variable auth

    if {![info exists auth]} {
	variable plain
	if {[info exists plain]} {
	    set id [$plain info]
	} else {
	    set id {}
	}

	set auth [Make $id]
    }

    check-login $auth

    debug.mgr/client {==> $auth}
    return $auth
}

proc ::stackato::mgr::client::auth+group {p} {
    debug.mgr/client {}
    # generate callback
    $p config @motd
    $p config @cafile
    $p config @skip-ssl-validation
    confer-group [authenticated]
}

proc ::stackato::mgr::client::reset {} {
    debug.mgr/client {}
    plain-reset
    authenticated-reset
    close-restlog
    return
}

proc ::stackato::mgr::client::plain-reset {} {
    debug.mgr/client {}
    variable plain
    if {![info exists plain]} return
    variable trace [$plain trace?]
    $plain destroy
    unset plain
    return
}

proc ::stackato::mgr::client::authenticated-reset {} {
    debug.mgr/client {}
    variable auth
    if {![info exists auth]} return
    variable trace [$auth trace?]
    variable group [$auth group?]
    $auth destroy
    unset auth
    return
}

proc ::stackato::mgr::client::Make {{infodata {}}} {
    debug.mgr/client {create}
    set aclient [restlog [client new [ctarget get] [auth get]]]
    debug.mgr/client {= $aclient}

    if {$infodata ne {}} { $aclient info= $infodata }

    variable group

    # Validate target first. While the 'target' command does this
    # before storing the information it is always possible that the
    # store (~/.stackato/client/target) was manually edited, not to
    # speak of env(STACKATO_TARGET) as possible source.

    set cc [::stackato-cli get (cc)]
    set warn [expr { ![$cc has @json] || ![$cc @json] }]

    while {1} {
	set emessage "Invalid target '[$aclient target]'"
	switch -exact -- [$aclient target_valid? newtarget emessage] {
	    0 {
		return -code error -errorcode {STACKATO CLIENT BADTARGET} \
		    $emessage
	    }
	    1 { break }
	    2 {
		# Redirection, follow.
		$aclient retarget $newtarget
		if {$warn} {
		    puts [color note "Note: Target '[$aclient target]' redirected to: '$newtarget'"]
		}
	    }
	    default { error "Cannot happen" }
	}
    }

    if {[package vcompare [$aclient api-version] 2] >= 0} {
	# API version 2 or higher. Switch to new client.

	# Note, we keep and save the /info we got, preventing the v2
	# client from making its own, redundant request. We also track
	# any changes the client may have made to the in-memory target
	# (by following redirections issued by the official target).
	set sinfo   [$aclient info]
	set starget [$aclient target]
	set sauth   [$aclient authtoken]

	$aclient destroy

	debug.mgr/client {create V2}
	set aclient [restlog [v2 client new $starget $sauth]]
	$aclient info= $sinfo

	debug.mgr/client {= $aclient}

	unset -nocomplain group
    }

    #variable trace
    #if {[info exists trace]} {}
        #debug.mgr/client {trace ($trace)}
	#$aclient trace [expr {$trace ? $trace : ""}]
    #{}

    if {[info exists group]} {
	debug.mgr/client {group ($group)}
	$aclient group $group
    }

    # Extract and stash theming information for use by internal stack
    # traces.
    variable description [dict get [$aclient info] description]
    variable support     [dict get [$aclient info] support]

    return $aclient
}

# # ## ### ##### ######## ############# #####################
## API operation, possibly movable ito the client REST class.

proc ::stackato::mgr::client::runtimes {client} {
    debug.mgr/client {}

    set info [$client info]

    debug.mgr/client {Compute runtimes}
    set runtimes {}
    if {[dict exists $info frameworks]} {
	foreach f [dict values [dict get $info frameworks]] {
	    if {![dict exists $f runtimes]} continue
	    foreach r [dict get $f runtimes] {
		dict set runtimes [dict getit $r name] $r
	    }

	}
    }

    #checker -scope line exclude badOption
    return [dict sort $runtimes]
    #@type = dict (<name> -> dict)
}

proc ::stackato::mgr::client::frameworks {client} {
    debug.mgr/client {}

    set info [$client info]

    debug.mgr/client {ci = [jmap clientinfo $info]}

    debug.mgr/client {Compute frameworks}
    set frameworks {}

    if {[dict exists $info frameworks]} {
	set fw [dict get $info frameworks]
	debug.mgr/client {fw = [jmap fwinfo $fw]}

	foreach f [dict values $fw] {
	    debug.mgr/client {** $f}
	    set name     [dict getit $f name]
	    set subframe [dict get'  $f sub_frameworks {}]
	    lappend frameworks $name $subframe
	}
    }

    return [dict sort $frameworks]
    #@type = list(string)
}


proc ::stackato::mgr::client::confer-group {client {check 1}} {
    debug.mgr/client {}
    if {[$client isv2]} {
	debug.mgr/client {stackato groups not supported by a CF v2 target}
	return $client
    }
    if {$check} { check-login $client }

    set group [cgroup get]
    debug.mgr/client {confering ($group)}

    if {($group ne {}) && ($group ni [the-users-groups $client])} {
	err "The current group \[$group\] is not known to the target."
    }

    $client group $group
    # Squash client information we got without a group set.
    $client info_reset
    return $client
}

proc ::stackato::mgr::client::get-ssh-key {client {show 1}} {
    try {
	set sshkey [dict get' [$client get_ssh_key] sshkey {}]
    } trap {REST HTTP 404} {e o} - \
      trap {STACKATO CLIENT V2 UNKNOWN REQUEST} {e o} - \
      trap {STACKATO CLIENT V2 NOTFOUND} {e o} {
	if {$show} {
	    display [color warning "No ssh key available"]
	}
	set sshkey {}
    }
    return $sshkey
}

proc ::stackato::mgr::client::check-login {client} {
    debug.mgr/client {}
    if {[$client logged_in?]} return

    # Not logged in. For CFv2 try to refresh the token before asking
    # the user to fully re-login.

    if {[$client isv2]} {
	set target [$client target]
	debug.mgr/client {/v2 T: $target}

	set refresh [dict get' [tadjunct known] $target refresh {}]
	if {$refresh ne {}} {
	    # We have a token to try a refresh
	    debug.mgr/client {/v2 R: $refresh}

	    # Refresh was ok.
	    try {
		set newtoken [$client refresh $refresh]
		debug.mgr/client {/v2 T: $newtoken}
	    } trap {REST HTTP 400} {e o} {
		# Refresh is invalid. Fallback to plain auth error.
		::stackato::client::AuthError
	    }

	    # Check if the updated token is good.
	    if {[$client logged_in?]} {
		# It is, so we make it permanent.

		set sshkey [get-ssh-key $client 0]

		debug.mgr/client {/v2 S: $sshkey}

		targets  remove $target
		targets  add    $target $newtoken $sshkey

		# OP 302380 - Update in-memory database as well.
		auth set $newtoken
		return
	    }
	}
    }

    ::stackato::client::AuthError
    return
}

proc ::stackato::mgr::client::check-group-support {client} {
    debug.mgr/client {}

    check-login $client

    if {![has-group-support $client]} {
	return -code error -errorcode {STACKATO CLIENT CLI GROUP SUPPORT NO} \
	    "Target \[[$client target]\] does not support groups and limits."
    }
    return
}

proc ::stackato::mgr::client::has-group-support {client} {
    debug.mgr/client {[array set ci [$client info]][parray ci][unset ci]}

    return [dict exists [$client info] groups]
}

proc ::stackato::mgr::client::the-users-groups {client} {
    debug.mgr/client {}

    set cinfo [$client info]
    if {![dict exists $cinfo user]} { return {} }

    debug.mgr/client {[array set ci $cinfo][parray ci][unset ci]}

    if {[dict exists $cinfo admin] &&
	[dict get    $cinfo admin]} {
	set groups [dict get $cinfo all_groups]
    } else {
	set groups [dict get $cinfo groups]
    }
    return $groups
}

proc ::stackato::mgr::client::notv2 {p x} {
    debug.mgr/client {}
    # when-set callback of the 'login' command's --group option
    # (cmdr.tcl).
    # Dependencies: @client (implied @target)
    $p config @motd
    set client [$p config @client]
    if {[$client isv2]} {
	err "This option requires a target exporting the CF v1 API"
    }
    return $x
}

proc ::stackato::mgr::client::notv2cmd {p} {
    debug.mgr/client {}
    # generate callback of the V2-specific commands.
    # Dependencies: @client (implied @target)
    $p config @motd
    set client [$p config @client]
    if {[$client isv2]} {
	err "This command requires a target exporting the CF v1 API"
    }
    return
}

proc ::stackato::mgr::client::hasdrains {p} {
    debug.mgr/client {}
    $p config @motd
    # generate callback to commands having to
    # test if drain API is supported.
    # Dependencies: @client (implied @target)
    if {![chasdrains [$p config @client]]} {
	err "This command requires a target exporting the Stackato drain API"
    }
}

proc ::stackato::mgr::client::chasdrains {client} {
    debug.mgr/client {}
    if {[$client isv2]} {
	return [$client is-stackato]
    } else {
	# v1 API, S2 target version.
	# Drain supported started with 2.6
	return [MinCheck $client 2.5]
    }
    return
}

proc ::stackato::mgr::client::max-version {version p} {
    debug.mgr/client {}
    $p config @motd

    set client [$p config @client]
    if {[MaxCheck $client $version]} return
    err "This command requires a target with version $version or earlier."
    return
}

proc ::stackato::mgr::client::min-version {version p} {
    debug.mgr/client {}
    $p config @motd

    set client [$p config @client]
    if {[MinCheck $client $version]} return
    err "This command requires a target with version $version or later."
    return
}

proc ::stackato::mgr::client::max-version-opt {version p args} {
    debug.mgr/client {}
    $p config @motd

    set client [$p config @client]
    if {[MaxCheck $client $version]} return
    err "The option [$p flag] requires a target with version $version or earlier."
    return
}

proc ::stackato::mgr::client::min-version-opt {version p args} {
    debug.mgr/client {}
    $p config @motd

    set client [$p config @client]
    if {[MinCheck $client $version]} return
    err "The option [$p flag] requires a target with version $version or later."
    return
}

proc ::stackato::mgr::client::MaxCheck {client version} {
    debug.mgr/client {}

    set  precision [llength [split $version .]]
    debug.mgr/client {precision = $precision}
    
    set found [$client server-version]
    debug.mgr/client {found/* = $found}

    set found [join [lrange [split $found .] 0 [incr precision -1]] .]
    debug.mgr/client {found/[incr precision] = $found <= $version}

    if {[catch {
	set ok [expr {[package vcompare $found $version] <= 0}]
    } msg o]} {
	if {[string match {expected version *} $msg]} {
	    err "Bad version number \"$found\" reported by [$client target]"
	}
	return {*}$o $msg
    }
    return $ok
}

proc ::stackato::mgr::client::MinCheck {client version} {
    debug.mgr/client {}

    set tversion [$client server-version]
    debug.mgr/client {server = $tversion}

    if {[catch {
	set ok [package vsatisfies $tversion $version]
    } msg o]} {
	if {[string match {expected version *} $msg]} {
	    err "Bad version number \"$tversion\" reported by [$client target]"
	}
	return {*}$o $msg
    }
    return $ok
}

proc ::stackato::mgr::client::is-stackato {p} {
    debug.mgr/client {}
    $p config @motd
    if {![[$p config @client] is-stackato]} {
	err "This command requires a stackato target."
    }
    return
}

proc ::stackato::mgr::client::is-stackato-opt {p x} {
    debug.mgr/client {}
    $p config @motd
    # when-set callback
    if {![[$p config @client] is-stackato]} {
	err "This option requires a stackato target."
    }
    return
}

proc ::stackato::mgr::client::isv2 {p x} {
    debug.mgr/client {}
    $p config @motd
    # when-set callback of the 'login' command's options
    # --organization and --space (cmdr.tcl).
    # Dependencies: @client (implied @target)
    set client [$p config @client]
    if {![$client isv2]} {
	err "This option requires a target exporting the CF v2 API"
    }
    return $x
}

proc ::stackato::mgr::client::isv2cmd {p} {
    debug.mgr/client {}
    $p config @motd
    # generate callback of the V2-specific commands.
    # Dependencies: @client (implied @target)
    set client [$p config @client]
    if {![$client isv2]} {
	err "This command requires a target exporting the CF v2 API"
    }
    return
}

proc ::stackato::mgr::client::app-exists? {client appname {appinfovar {}}} {
    debug.mgr/client {}
    if {$appinfovar ne {}} {
	upvar 1 $appinfovar app
    }
    try {
	set app [$client app_info $appname]
	set found [expr {$app ne {}}]
	debug.mgr/client {found = $found}
	return $found
    } trap {STACKATO CLIENT NOTFOUND} {e o} {
	debug.mgr/client {$e}
	return 0
    }
}

proc ::stackato::mgr::client::app-started-properly? {client appname error_on_health} {
    debug.mgr/client {}

    set app    [$client app_info $appname]
    set health [misc health $app]
    switch -- $health {
	N/A {
	    # Health manager not running.
	    if {$error_on_health} {
		err "Application '$appname's state is undetermined, not enough information available." 
	    }
	    return 0
	}
	RUNNING { return 1 }
	STOPPED { return 0 }
	default {
	    if {$health > 0} {
		return 1
	    }
	    return 0
	}
    }
}

proc ::stackato::mgr::client::check-capacity {client mem_wanted context} {
    #checker -scope local exclude badOption
    debug.mgr/client {}

    set ci     [$client info]
    set usage  [dict get' $ci usage  {}]
    set limits [dict get' $ci limits {}]

    debug.mgr/client {client info usage  = [jmap map dict $usage]}
    debug.mgr/client {client info limits = [jmap map dict $limits]}

    if {($usage  eq {}) ||
	($limits eq {})
    } {
	debug.mgr/client {no usage, or no limits -- no checking}
	return
    }

    set tmem [dict getit $limits memory]
    set mem  [dict getit $usage  memory]

    set available [expr {$tmem - $mem}]

    debug.mgr/client {MB Total limit = $tmem}
    debug.mgr/client {MB Total used  = $mem}
    debug.mgr/client {MB Available   = $available}
    debug.mgr/client {MB Requested   = $mem_wanted}

    if {$mem_wanted <= $available} return

    # From here on we know that the user requested more than the
    # system can provide.

    set ftmem      [memspec format $tmem]
    set fmem       [memspec format $mem]
    set favailable [memspec format $available]
    set fwanted    [memspec format $mem_wanted]

    switch -- $context {
	mem {
	    if {$available <= 0} {
		set favailable none
	    }
	    set    message "Not enough capacity ($fwanted requested) for operation."
	    append message "\nCurrent Usage: $fmem of $ftmem total, $favailable available for use"
	}
	push {
	    set message "Unable to push. "
	    if {$available < 0} {
		append message "The total memory usage of $fmem exceeds the allowed limit of ${ftmem}."
	    } else {
		append message "Not enough capacity available ($favailable, but $fwanted requested)."
	    }
	}
	default {
	    error "bad context $context for memory error"
	}
    }

    display ""
    err $message
    return
}

proc ::stackato::mgr::client::check-app-limit {client} {
    debug.mgr/client {}

    #checker -scope local exclude badOption
    set ci     [$client info]
    set usage  [dict get' $ci usage  {}]
    set limits [dict get' $ci limits {}]

    debug.mgr/client {usage  = $usage}
    debug.mgr/client {limits = $limits}

    if {($usage  eq {}) ||
	($limits eq {}) ||
	([dict get' $limits apps {}] eq {})
    } return

    set tapps [dict get' $limits apps 0]
    set apps  [dict get' $usage  apps 0]

    if {$apps < $tapps} return

    err "Not enough capacity for operation.\nCurrent Usage: ($apps of $tapps total apps already in use)"
}

proc ::stackato::mgr::client::description {} {
    variable description
    return  $description
}

proc ::stackato::mgr::client::support {} {
    variable support
    return  $support
}

proc ::stackato::mgr::client::license-status {client {onlyover 1} {prefix {}}} {
    debug.mgr/client {}

    set info [$client info]
    if {![dict exists $info license]} return

    set use    [dict get $info license memory_in_use]
    set limit  [dict get $info license memory_limit]
    set over   [expr {$use - $limit}]

    if {($over <= 0) && $onlyover} return

    # TODO: see if we can get colorization into the strings.
    # Might have to replace the state table with a switch.

    variable license_state

    regsub -all {.} $prefix { } prefixb

    set url    [dict get' $info license url          {}]
    set org    [dict get' $info license organization <UnknownCustomer>]
    set serial [dict get' $info license serial       <UnknownSerial>]
    set state  [dict get' $info license state        {}]
    set msg    [dict get' $license_state $state $state]

    lappend map @R $url
    lappend map @@ $over
    lappend map @n \n$prefixb
    lappend map @U ${use}G
    lappend map @L ${limit}G
    lappend map @O $org
    lappend map @S $serial

    display $prefix[string map $map $msg]
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::mgr::client {
    variable plain ; # cache of plain client
    variable auth  ; # cache of an authenticated client
    variable trace ; # remember tracing status
    variable group ; # remember group status

    # Communication from client instances (target) specifying theming
    # information: System description, and where to direct stacktraces
    # of internal errors.
    variable description {this system}
    variable support     {}
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::client 0
