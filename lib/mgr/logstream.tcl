# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require dictutil
package require exec
package require json
package require stackato::log
package require stackato::mgr::auth
package require stackato::mgr::cgroup
package require stackato::mgr::client
package require stackato::mgr::ctarget
package require stackato::mgr::self
package require stackato::mgr::ssh

package require stackato::mgr::client

namespace eval ::stackato::mgr {
    namespace export logstream
    namespace ensemble create
}

namespace eval ::stackato::mgr::logstream {
    namespace export start active stop set-use get-use \
	needfast needslow set-use-c get-use-c
    namespace ensemble create

    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::auth
    namespace import ::stackato::mgr::cgroup
    namespace import ::stackato::mgr::client
    namespace import ::stackato::mgr::ctarget
    namespace import ::stackato::mgr::self
    namespace import ::stackato::mgr::ssh
}

debug level  mgr/logstream
debug prefix mgr/logstream {[debug caller] | }

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::logstream::start {config appname {mode fast}} {
    variable active
    variable pid

    set client [$config @client]
    if {[$client isv2]} return

    debug.mgr/logstream {|f[Fast $client]|a($active)|p($pid)||}
    # mode in (fast, any)
    # Ignore request we cannot fulfill
    if {$mode eq "fast" && ![Fast $client]} return

    # Ignore request by user's choice.
    debug.mgr/logstream {$appname, tail = [get-use $client]}
    if {![get-use $client]} return

    # Start nesting, ignore if was already active before.
    set count [dict get' $active $appname 0]
    incr count
    dict set active $appname $count

    if {$count > 1} return

    # Now we tail the operation of the server, maybe just the
    # stager...

    if {[Fast $client]} {
	# For a fast-log enabled stackato simply use a suitably
	# filtered log --follow as sub-process.

	# Note how we pass the current configuration (target, auth
	# token, group) to the child. Without these the child will
	# pull the information from the default locations, and this
	# might be wrong, namely if this process got overrides from
	# the command line. So, the child must have overrides from the
	# command line.

	set newer [GetLast $client $appname]

	set cmd [list {*}[self exe] --child logs \
		     $appname \
		     --follow --no-timestamps \
		     --newer $newer \
		     \
		     --target [ctarget get] \
		     --token  [auth get]]
	if {[cgroup get] ne {}} {
	    lappend cmd --group [cgroup get]
	}

	set child [exec::bgrun 2>@ stderr >@ stdout {*}$cmd]
	debug.mgr/logstream {$appname, self pid = $child}
    } else {
	# Stackato pre 2.3: Launch an ssh sub-process going through
	# stackato-ssh with special arguments.

	set child [ssh run $config {} $appname - 1]
	debug.mgr/logstream {$appname, ssh pid = $child}
    }

    dict set pid $appname $child
    return
}

proc ::stackato::mgr::logstream::active {appname} {
    variable active
    return [expr {[dict exist $active $appname] &&
		  [dict get $active $appname]}]
}

proc ::stackato::mgr::logstream::stop {config appname {mode any}} {
    variable active
    variable pid

    set client [$config @client]
    if {[$client isv2]} return

    debug.mgr/logstream {|f[Fast $client]|a($active)|p($pid)||}
    # mode in (slow, any)
    # Ignore request we cannot fulfill
    if {($mode eq "slow") && [Fast $client]} return

    # Ignore request by user's choice.
    debug.mgr/logstream {$appname, tail = [get-use $client]}
    if {![get-use $client]} return

    # Stop nesting, ignore if still active.
    set  count [dict get' $active $appname 0]
    incr count -1
    dict set active $appname $count

    if {$count > 0} return

    set child [dict get $pid $appname]

    if {$child ne {}} {
	debug.mgr/logstream {$appname, kill pid = $child}
	::exec::drop $child
    }
    return
}

proc ::stackato::mgr::logstream::needfast {p x} {
    # when-set callback of the .logs options (cmdr.tcl).
    set client [$p config @client]
    if {[$client isv2]} {
	err "This option requires a CFv1 target"
    }
    if {[Fast $client]} return
    err "This option requires a target version 2.4 or higher"
}

proc ::stackato::mgr::logstream::needslow {p x} {
    # when-set callback of the .logs options (cmdr.tcl).
    set client [$p config @client]
    if {[$client isv2]} {
	err "This option requires a CFv1 target"
    }
    if {![Fast $client]} return
    err "This option requires a target version 2.2 or lower"
}

# # ## ### ##### ######## ############# #####################
## Callbacks for option --tail, see cmdr.tcl, common .tail)
## Enables/disables log stream use.

proc ::stackato::mgr::logstream::set-use-c {p flag} { set-use $flag }
proc ::stackato::mgr::logstream::get-use-c {p}      { get-use [$p config @client] }

proc ::stackato::mgr::logstream::set-use {flag} {
    debug.mgr/logstream {}
    variable use $flag
    return
}

proc ::stackato::mgr::logstream::get-use {client} {
    debug.mgr/logstream {}
    variable use

    if {![info exists use]} {
	debug.mgr/logstream {fill cache}
	set use [Default $client]
    }

    debug.mgr/logstream {==> $use}
    return $use
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::logstream::Default {client} {
    return [expr {[Fast $client] || ($::tcl_platform(platform) ne "windows")}]
}

proc ::stackato::mgr::logstream::Fast {client} {
    if {[info exists fast]} { return $fast }
    set fast [package vsatisfies [client server-version $client] 2.3]
    return $fast
}

proc ::stackato::mgr::logstream::GetLast {client appname} {
    debug.mgr/logstream {}
    set last [$client logs $appname 1]
    set last [lindex [split [string trim $last] \n] end]

    debug.mgr/logstream {last = $last}

    if {$last eq {}} {
	debug.mgr/logstream {--> everything }
	return 0
    }

    set last [json::json2dict $last]
    dict with last {} ; # => timestamp, instance, source, text, filename

    debug.mgr/logstream {--> newer than $timestamp}
    return $timestamp
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::mgr::logstream {
    # active - counter of active tail requests.
    #          dictionary keyed by appname.
    # fast   - true if new fast logging is possible.
    # pid    - process id of the child doing the logging.
    #          dictionary keyed by appname.

    variable pid    {}
    variable active {}
    variable fast   ;# fast is left undefined until the 1st check
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::logstream 0
return
