# -*- tcl -*-
# # ## ### ##### ######## ############# #####################
# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::client::cli::command::Base

debug level  cli/logstream
debug prefix cli/logstream {[::debug::snit::call] | }

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::client::cli::command::LogStream {
    superclass ::stackato::client::cli::command::Base

    # # ## ### ##### ######## #############

    constructor {args} {
	Debug.cli/logstream {}

	# active - counter of active tail requests.
	#          dictionary keyed by appname.

	# fast   - true if new fast logging is possible.
	# pid    - process id of the child doing the logging.
	#          dictonary keyed by appname.

	set active {}
	set pid    {}
	# leave fast undefined, until first check

	next {*}$args
    }

    destructor {
	Debug.cli/logstream {}
    }

    # # ## ### ##### ######## #############

    method TailStart {appname {mode fast}} {
	Debug.cli/logstream {|f[my Fast]|a($active)|p($pid)||}
	# mode in (fast, any)
	# Ignore request we cannot fulfill
	if {$mode eq "fast" && ![my Fast]} return

	# Ignore request by user's choice.
	Debug.cli/logstream {$appname, tail = [my TailUse]}
	if {![my TailUse]} return

	# Start nesting, ignore if was already active before.
	set count [dict get' $active $appname 0]
	incr count
	dict set active $appname $count

	if {$count > 1} return

	# Now we tail the operation of the server, maybe just the
	# stager...

	if {[my Fast]} {
	    # For a fast-log enabled stackato simply use a suitably
	    # filtered log --follow as sub-process.

	    set newer [my GetLast $appname]
	    set child [exec::bgrun 2>@ stderr >@ stdout \
			   {*}[my appself] logs $appname \
			   --follow --no-timestamps \
			   --newer $newer
		      ]
	    Debug.cli/logstream {$appname, self pid = $child}
	} else {
	    # Stackato pre 2.3: Launch a ssh sub-process going through
	    # stackato-ssh with special arguments.

	    # XXX unclear if we have access to this method from the derived class.
	    set child [my run_ssh {} $appname - 1]
	    Debug.cli/logstream {$appname, ssh pid = $child}
	}

	dict set pid $appname $child
	return
    }

    method TailActive {appname} {
	return [expr {[dict exist $active $appname] && [dict get $active $appname]}]
    }

    method TailStop {appname {mode any}} {
	Debug.cli/logstream {|f[my Fast]|a($active)|p($pid)||}
	# mode in (slow, any)
	# Ignore request we cannot fulfill
	if {($mode eq "slow") && [my Fast]} return

	# Ignore request by user's choice.
	Debug.cli/logstream {$appname, tail = [my TailUse]}
	if {![my TailUse]} return

	# Stop nesting, ignore if still active.
	set  count [dict get' $active $appname 0]
	incr count -1
	dict set active $appname $count

	if {$count > 0} return

	set child [dict get $pid $appname]

	if {$child ne {}} {
	    Debug.cli/logstream {$appname, kill pid = $child}
	    ::exec::drop $child
	}
	return
    }

    method GetLast {appname} {
	Debug.cli/logstream {}
	set last [[my client] logs $appname 1]
	set last [lindex [split [string trim $last] \n] end]

	Debug.cli/logstream {last = $last}

	if {$last eq {}} {
	    Debug.cli/logstream {--> everything }
	    return 0
	}

	set last [json::json2dict $last]
	dict with last {} ; # => timestamp, instance, source, text, filename

	Debug.cli/logstream {--> newer than $timestamp}
	return $timestamp
    }

    method TailUse {} {
	return [dict get' [my options] tail [my Default]]
    }

    method Default {} {
	return [expr {[my Fast] || ($::tcl_platform(platform) ne "windows")}]
    }

    method Fast {} {
	if {[info exists fast]} { return $fast }
	set fast [package vsatisfies [my ServerVersion] 2.3]
	return $fast
    }

    # # ## ### ##### ######## #############
    ## State

    variable pid active fast

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::client::cli::command::LogStream 0
