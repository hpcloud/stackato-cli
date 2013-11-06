# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## This module manages the client instances doing the REST calls.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require dictutil
package require stackato::color
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
	auth+group plain authenticated \
	reset plain-reset authenticated-reset \
	confer-group frameworks runtimes \
	the-users-groups check-group-support \
	check-login server-version app-exists? \
	app-started-properly? check-capacity \
	check-app-limit notv2 isv2 isv2cmd notv2cmd \
	trace= plainc authenticatedc restlog \
	get-ssh-key
    namespace ensemble create

    namespace import ::stackato::color
    namespace import ::stackato::mgr::cfile
    namespace import ::stackato::mgr::cgroup
    namespace import ::stackato::mgr::ctarget
    namespace import ::stackato::mgr::tadjunct
    namespace import ::stackato::mgr::targets
    namespace import ::stackato::mgr::auth
    namespace import ::stackato::client
    namespace import ::stackato::v2
    namespace import ::stackato::misc
    namespace import ::stackato::log::err
    namespace import ::stackato::log::display
    namespace import ::stackato::validate::memspec
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

proc ::stackato::mgr::client::RestLog {} {
    debug.mgr/client {}
    global CHILD ; # See bin/stackato for definition.
    # This is a hack to quickly get the information about
    # process context.

    if {$CHILD} {
	# Child, append to master log
	set trace [open [cfile get rest] a]
    } else {
	# Toplevel, replace previous log.
	file mkdir [file dirname [cfile get rest]]
	set trace [open [cfile get rest] w]
    }

    # Memoize. All future clients go to the same channel.
    proc ::stackato::mgr::client::RestLog {} [list return $trace]

    debug.mgr/client {==> $trace (child $CHILD)}
    return $trace
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::client::plainc         {p} { plain         }
proc ::stackato::mgr::client::authenticatedc {p} { authenticated }

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::client::plain {} {
    debug.mgr/client {}
    variable plain

    if {![info exists plain]} {
	set plain [Make]
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
	set auth [Make]
    }

    check-login $auth

    debug.mgr/client {==> $auth}
    return $auth
}

proc ::stackato::mgr::client::auth+group {p} {
    # generate callback
    confer-group [authenticated]
}

proc ::stackato::mgr::client::reset {} {
    plain-reset
    authenticated-reset
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

proc ::stackato::mgr::client::Make {} {
    debug.mgr/client {create}
    set aclient [restlog [client new [ctarget get] [auth get]]]
    debug.mgr/client {= $aclient}

    variable group

    if {[package vcompare [$aclient api-version] 2] >= 0} {
	# API version 2 or higher. Switch to new client.

	# Note, we keep and save the /info we got, preventing the v2
	# client from making its own, redundant request.
	set info [$aclient info]
	$aclient destroy

	debug.mgr/client {create V2}
	set aclient [restlog [v2 client new [ctarget get] [auth get]]]
	$aclient info= $info

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
	    display [color yellow "No ssh key available"]
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

proc ::stackato::mgr::client::server-version {client} {
    debug.mgr/client {}
    set v [dict get' [$client info] vendor_version 0.0]
    regsub -- {-g.*$} $v {} v
    set v [string map {v {} - .} $v]
    debug.mgr/client {= $v}
    return $v
}

proc ::stackato::mgr::client::notv2 {p x} {
    debug.mgr/client {}
    # when-set callback of the 'login' command's --group option
    # (cmdr.tcl).
    # Dependencies: @client (implied @target)
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
    set client [$p config @client]
    if {[$client isv2]} {
	err "This command requires a target exporting the CF v1 API"
    }
    return
}

proc ::stackato::mgr::client::isv2 {p x} {
    debug.mgr/client {}
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

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::mgr::client {
    variable plain ; # cache of plain client
    variable auth  ; # cache of an authenticated client
    variable trace ; # remember tracing status
    variable group ; # remember group status
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::client 0
