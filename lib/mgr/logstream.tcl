# -*- tcl -*-
# # ## ### ##### ######## ############# #####################
# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require dictutil
package require exec
package require json
package require cmdr::color
package require stackato::log
package require stackato::mgr::auth
package require stackato::mgr::cgroup
package require stackato::mgr::client
package require stackato::mgr::ctarget
package require stackato::mgr::self
package require stackato::mgr::ssh
package require stackato::mgr::ws

namespace eval ::stackato::mgr {
    namespace export logstream
    namespace ensemble create
}

# app: logs -> LogsStream -> tail, show1
# app: general -> start, stop

namespace eval ::stackato::mgr::logstream {
    namespace export start stop stop-m active \
	set-use-c get-use-c set-use get-use \
	needfast needslow isfast show1 tail \
	new-entries no-new-entries kill
    namespace ensemble create

    namespace import ::cmdr::color
    namespace import ::stackato::log::err
    namespace import ::stackato::log::display
    namespace import ::stackato::mgr::auth
    namespace import ::stackato::mgr::cgroup
    namespace import ::stackato::mgr::client
    namespace import ::stackato::mgr::ctarget
    namespace import ::stackato::mgr::self
    namespace import ::stackato::mgr::ssh
    namespace import ::stackato::mgr::ws
}

debug level  mgr/logstream
debug prefix mgr/logstream {[debug caller] | }

debug level  mgr/logstream/data
debug prefix mgr/logstream/data {}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::logstream::stop-m {config theapp {mode any}} {
    stop $config $mode
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::logstream::start {config theapp {mode fast}} {
    variable active
    variable pid
    variable client

    set client [$config @client]
    if {[$client isv2]} {
	set appname [$theapp @name]
    } else {
	set appname $theapp
    }

    debug.mgr/logstream {|fast [Fast $client]|active $active|pid ($pid)||}
    # mode in (fast, any)
    # Ignore request we cannot fulfill
    if {$mode eq "fast" && ![Fast $client]} return

    # Ignore request by user's choice.
    debug.mgr/logstream {tail = [get-use $client]}
    if {![get-use $client]} return

    # Start nesting, ignore if was already active before.
    incr active
    debug.mgr/logstream {active $active}
    if {$active > 1} return

    # Now we tail the operation of the server, maybe just the
    # stager...

    if {[Fast $client]} {
	# For a fast-log enabled stackato simply use a suitably
	# filtered log --follow as in-process green thread. This
	# implicitly inherits the current configuration, i.e. target,
	# auth token, group, etc.

	set newer [GetLast $client $theapp]

	# See also ::stackato::cmd::app::LogsStream (consolidate)
	dict set mconfig _config   $config
	dict set mconfig client    $client
	dict set mconfig json      0
	dict set mconfig nosts     1
	dict set mconfig pattern   *
	dict set mconfig pinstance ""
	dict set mconfig pnewer    $newer
	dict set mconfig plogfile  *
	dict set mconfig plogtext  *
	dict set mconfig max       100
	dict set mconfig appname   $theapp ;# name or entity, per CF version

	if {[isws $mconfig]} {
	    dict set mconfig max 0
	    set pid [tail-ws $mconfig 0]
	    # Started the tailing, no waiting, using the main event loop.
	} else {
	    Tail $mconfig ;# pid handling implied.
	    debug.mgr/logstream {self pid /async in process}
	}
    } else {
	# Stackato pre 2.3: Launch an ssh sub-process going through
	# stackato-ssh with special arguments.

	set child [ssh run $config {} $theapp - 1]
	debug.mgr/logstream {ssh pid = $child}
	set pid $child
    }

    return
}

proc ::stackato::mgr::logstream::stop {config {mode any}} {
    variable active
    variable pid

    set client [$config @client]

    debug.mgr/logstream {|fast [Fast $client]|active $active|pid ($pid)|}
    # mode in (slow, any)
    # Ignore request we cannot fulfill
    if {($mode eq "slow") && [Fast $client]} return

    # Ignore request by user's choice.
    debug.mgr/logstream {tail = [get-use $client]}
    if {![get-use $client]} return

    # Stop nesting, ignore if still active.
    incr active -1

    debug.mgr/logstream {active $active}
    if {$active > 0} return

    if {$pid ne {}} {
	variable stopdelay
	# Wait for NNN millis without new log entries before actually
	# stopping the log-stream and the command calling for it.
	DelayForInactive $stopdelay

	debug.mgr/logstream {kill pid = $pid}
	# pid = handle of the currently running async log request.
	#  or | handle of the timer delaying the next log request.
	# Either must be canceled

	if {[string match sock* $pid]} {
	    # websocket tail
	    ws close
	} elseif {[string match after* $pid]} {
	    catch { after cancel $pid }
	} else {
	    catch { $client logs_cancel $pid }
	}
    }

    set pid {}
    return
}

proc ::stackato::mgr::logstream::kill {} {
    variable pid
    variable active
    variable client

    if {$pid ne {}} {
	variable stopdelay
	# Wait for NNN millis without new log entries before actually
	# stopping the log-stream and the command calling for it.
	DelayForInactive $stopdelay

	debug.mgr/logstream {kill pid = $pid}
	# pid = handle of the currently running async log request.
	#  or | handle of the timer delaying the next log request.
	# Either must be canceled
	if {[string match after* $pid]} {
	    catch { after cancel $pid }
	} else {
	    catch { $client logs_cancel $pid }
	}
    }

    set active 0
    set pid {}
    set client {}
    return
}

proc ::stackato::mgr::logstream::DelayForInactive {delay} {
    debug.mgr/logstream {}
    # Wait until 'delay' passes without new log entries.
    while {1} {
	After $delay
	if {![new-entries]} break
	debug.mgr/logstream {/continue}
    }
    debug.mgr/logstream {/done}
    return
}

proc ::stackato::mgr::logstream::After {delay} {
    # Do sync after with full execution of other events.
    # I.e. a plain after <delay> is not correct, as it suppresses
    # other events (file events = concurrent log stream rest
    # requests).

    after $delay {set ::stackato::mgr::logstream::ping .}
    vwait ::stackato::mgr::logstream::ping
    return
}

proc ::stackato::mgr::logstream::active {} {
    variable active
    debug.mgr/logstream {==> $active}
    return  $active
}

proc ::stackato::mgr::logstream::new-entries {} {
    # query if the logstream saw new entries since the last check, and
    # reset the counter
    variable hasnew
    set result $hasnew
    set hasnew 0
    debug.mgr/logstream {==> $result}
    return $result
}

proc ::stackato::mgr::logstream::no-new-entries {} {
    # query if the logstream saw no new entries since the last check.
    # leave the counter intact, this is sampling in-between main checks.
    variable hasnew
    set result [expr {!$hasnew}]
    debug.mgr/logstream {==> $result}
    return $result
}

proc ::stackato::mgr::logstream::needfast {p x} {
    debug.mgr/logstream {}
    # when-set callback of the .logs options (cmdr.tcl).
    set client [$p config @client]
    if {[Fast $client]} return
    err "This option requires a target version 2.4 or higher"
}

proc ::stackato::mgr::logstream::needslow {p x} {
    debug.mgr/logstream {}
    # when-set callback of the .logs options (cmdr.tcl).
    set client [$p config @client]
    if {![Fast $client]} return
    err "This option requires a target version 2.2 or lower"
}

proc ::stackato::mgr::logstream::isfast {config} {
    debug.mgr/logstream {}
    set client [$config @client]
    return [Fast $client]
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
    debug.mgr/logstream {}
    return [expr {[Fast $client] || ($::tcl_platform(platform) ne "windows")}]
}

proc ::stackato::mgr::logstream::Fast {client} {
    debug.mgr/logstream {}
    variable fast
    if {[info exists fast]} {
	debug.mgr/logstream {/cached ==> $fast}
	return $fast
    }
    if {[$client isv2]} {
	debug.mgr/logstream {/v2}
	# v2 feature check, differentiate S3 vs. CF.
	set fast [$client is-stackato]
    } else {
	debug.mgr/logstream {/v1}
	set fast [package vsatisfies [$client server-version] 2.3]
    }
    debug.mgr/logstream {/done ==> $fast}
    return $fast
}

proc ::stackato::mgr::logstream::GetLast {client theapp} {
    debug.mgr/logstream {}

    if {[$client isv2]} {
	set last [$theapp logs 1]
    } else {
	set last [$client logs $theapp 1]
    }

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

proc ::stackato::mgr::logstream::Tail {config} {
    debug.mgr/logstream {}
    dict set config follow 1 ;# configure filtering in show1
    variable previous {} ;# nothing seen yet.
    variable hasnew   0  ;# initialize indicator

    TailRun $config
    return
}

proc ::stackato::mgr::logstream::TailRun {config} {
    variable pid {}

    debug.mgr/logstream {}
    dict with config {}

    set done [list ::stackato::mgr::logstream::TailNext $config]

    if {[$client isv2]} {
	set handle [$appname logs-async $done $max]
    } else {
	set handle [$client logs_async $done $appname $max]
    }

    debug.mgr/logstream {$appname, async handle = $handle}
    set pid $handle
    return
}

proc ::stackato::mgr::logstream::TailNext {config cmd {details {}}} {
    variable pid {}
    debug.mgr/logstream/data {TailNext ($config) ($cmd)}

    dict with config {}

    # cmd = reset
    #     | return (with details = options + result)

    # reset  ==> abort. No arguments.
    # return ==> may be error. args = list/1 (return-dict).

    # Reset  - Do nothing
    # Error  - Print, abort log processing.
    # Return - Print log entries and restart.

    if {$cmd eq "reset"} {
	return
    }

    set o [lrange $details 0 end-1]
    set r [lindex $details end]

    if {[dict get $o -code] in {error 1}} {
	display [color bad $r]
	return
    }

    # r = code data headers
    lassign $r code data headers

    if {[catch {
	ShowLines $config [split [string trimright $data \n] \n]
    } e]} {
	display [color bad $::errorInfo]
	return
    }

    # Run log faster than the ping loop.
    # Should reduce risk of truncation at the end.
    variable logdelay
    set pid [after $logdelay [list ::stackato::mgr::logstream::TailRun $config]]
    return
}


# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::logstream::isws {config} {
    # Web-socket API can be disabled by the user.
    if {[[dict get $config _config] @no-ws]} { return 0 }

    set client [dict get $config client]
    set ci [$client info]
    return [dict exists $ci applog_endpoint]
}

proc ::stackato::mgr::logstream::getws {config} {
    set client [dict get $config client]
    set ci [$client info]
    return [dict get $ci applog_endpoint]
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::logstream::tail {config} {
    debug.mgr/logstream {}
    # config = dict

    if {[isws $config]} {
	tail-ws $config
	return
    }

    tail-poll $config
    return
}

proc ::stackato::mgr::logstream::tail-poll {config} {
    debug.mgr/logstream {}

    dict set config follow 1 ;# configure filtering in show1
    variable previous {}     ;# nothing seen yet
    variable hasnew   0      ;# initialize indicator

    while {1} {
	show1 $config
	after 1000
    }
    return
}

proc ::stackato::mgr::logstream::tail-ws {config {wait 1}} {
    debug.mgr/logstream {}
    set theapp [dict get $config appname]

    set target [getws $config]
    set url    [$theapp url]/tail

    debug.mgr/logstream {target = $target}
    debug.mgr/logstream {url    = $url}

    set num [dict get $config max]
    set urlb $url
    if {$num > 0} { append urlb ?num=$num }

    set sock [ws open $target $urlb \
		  [dict create \
		       text  [namespace code [list tail-ws-text      $config]] \
		       close [namespace code [list tail-ws-reconnect $config $target $url]]]]

    if {!$wait} { return $sock }
    ws wait
    return
}

proc ::stackato::mgr::logstream::tail-ws-text {config msg} {
    variable hasnew 1
    ShowLine1 $config $msg
}

proc ::stackato::mgr::logstream::tail-ws-reconnect {config target url} {
    debug.mgr/logstream {}
    ws open $target $url \
	[dict create \
	     text  [namespace code [list tail-ws-text      $config]] \
	     close [namespace code [list tail-ws-reconnect $config $target $url]]]
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::logstream::show1 {config} {
    debug.mgr/logstream {}

    if {[isws $config]} {
	show1-ws $config
	return
    }

    show1-poll $config
    return
}

proc ::stackato::mgr::logstream::show1-poll {config} {
    debug.mgr/logstream {}

    # Main config(uration information) provided as dict. We cannot
    # assume to have cmdr config here (internal calls).
    #
    # General keys:
    # - client:    obj cmd  - client == target to talk to.
    # - max:       int      - max lines to pull per call
    # - appname:   v1: string      - application name
    #              v2: obj command - application entity
    # - follow:    presence - tail mode, filter control
    #
    # Filter keys:
    # - json:      bool   - json mode
    # - nosts:     bool   - no-timestamps.
    # - pattern:   glob   - source
    # - pinstance: string - instance id
    # - pnewer:    int    - epoch value
    # - plogfile:  glob   - file name
    # - plogtext:  glob   - log text

    dict with config {}

    debug.mgr/logstream { Filter Source    |$pattern| }
    debug.mgr/logstream { Filter Instance  |$pinstance| }
    debug.mgr/logstream { Filter Timestamp |$pnewer| }
    debug.mgr/logstream { Filter Filename  |$plogfile| }
    debug.mgr/logstream { Filter Text      |$plogtext| }

    if {[$client isv2]} {
	set lines [$appname logs $max]
    } else {
	set lines [$client logs $appname $max]
    }

    ShowLines $config \
	[split [string trimright $lines \n] \n]
    return
}

proc ::stackato::mgr::logstream::show1-ws {config} {
    debug.mgr/logstream {}
    set theapp [dict get $config appname]

    set target [getws $config]
    set url    [$theapp url]/recent

    debug.mgr/logstream {target = $target}
    debug.mgr/logstream {url    = $url}

    ws open $target $url?num=[dict get $config max] \
	[dict create \
	     text [namespace code [list ShowLine1 $config]]]
    ws wait
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::logstream::ShowLines {config lines} {
    dict with config {} ;# --> follow, client, json, nosts, p*, max, appname

    if {[info exists follow]} {
	set lines [Skip $lines]
	debug.mgr/logstream/data {SHOW [llength $lines]}
    }

    foreach line $lines {
	ShowLine1 $config $line
    }
    return
}

proc ::stackato::mgr::logstream::ShowLine1 {config line} {
    # Ignore empty lines (should not happen).
    if {[string trim $line] eq {}} return

    debug.mgr/logstream/data {LINE $line}

    # Parse the json, and filter...
    set record [Peel $line]

    # New-style record is has keys "error" and "value". Latter's value is a string,
    # contains serialized json. 2nd parsing pass required for it.

    # Check for and show server error information first.
    if {[dict exists $record error]} {
	set m [dict get $record error]
	if {$m ne {}} {
	    display [color bad $m]
	    return
	}
    }
    if {[dict exists $record value]} {
	# Peel the onion
	set record [Peel [dict get $record value]]

	# Recreate the missing old-style fields needed for filtering,
	# from the equivalent new-style fields.
	dict set record timestamp [dict get $record unix_time     ]
	dict set record instance  [dict get $record instance_index]
	dict set record nodeid    [dict get $record node_id       ]
    }

    dict with config {} ;# --> follow, client, json, nosts, p*, max, appname

    if {[Filter $record]} return

    # Format for display, and print.

    if {$json} {
	# Raw JSON as it came from the server.
	display $line
    } else {
	dict with record {} ;# => instance, source, text, ...

	set original_source $source
	
	# Append instance index to the app log filename, in a manner similar
	# to how stackato* sources have instance index suffixed.
	if {$filename ne "" && $original_source ne "staging"} { 
	    if {$instance >= 0} { append filename .$instance }
	    append source \[$filename\] 
	}

	# The color of stackato.* (source) messages differ from
	# app messages.
	# colors: red green yellow white blue cyan bold
	if {[string match "stackato*" $source]} {
	    set linecolor log-sys
	} else {
	    set linecolor log-app
	}
	
	if {$nosts} {
	    # --no-timestamps
	    set date ""
	} else {
	    set date "[clock format $timestamp -format {%Y-%m-%dT%H:%M:%S%z}] "
	}

	display "[color $linecolor $date$source]: [EolCode $text]"
    }
}

proc ::stackato::mgr::logstream::Peel {line} {
    if {[catch {
	set record [json::json2dict $line]
    } emsg]} {
	# Parse error, or other issue.
	# Show the raw JSON as it came from the server, plus the error message we got.
	# Note that this disables all filters also.
	display "(($line)) ([color bad $emsg])"
	return -code return ;# Stop not only self, but caller as well.
    }
    return $record
}

proc ::stackato::mgr::logstream::Skip {lines} {
    debug.mgr/logstream/data {SKIP handling}

    variable previous ;# previously seen entries.
    variable hasnew   ;# new entry indicator flag.

    # We are now matching the new set of entries against previous,
    # looking for the largest prefix of "lines" which is a suffix
    # of "previous".
    # 
    # General situation:
    #
    # pppppppppppppppppppp        - previous
    #       lllllllllllllllllllll - current
    #
    # Different lengths of previous and lines.
    #
    # Shortcuts:
    # - new is empty => no change, skip all
    # - previous is empty => all is new, skip nothing
    # - previous is full prefix of lines.
    #   (Assumes previous shorter than lines).
    # - previous == lines => no change, skip all

    # Short 0: Nothing received
    if {![llength $lines]} {
	debug.mgr/logstream/data {SKIP all (empty)}

	set previous $lines
	return $lines
    }

    # Short 1: Nothing seen before, accept all new.
    if {![llength $previous]} {
	debug.mgr/logstream/data {SKIP none (no previous)}

	set hasnew 1
	set previous $lines
	return $lines
    }

    # Have something to compare to.

    set np [llength $previous]
    set nn [llength $lines]

    debug.mgr/logstream/data {OLD $np}
    debug.mgr/logstream/data {NEW $nn}

    # Short 2: new extension of previous?
    if {$np < $nn} {
	incr np -1
	if {$previous eq [lrange $lines 0 $np]} {
	    incr np
	    debug.mgr/logstream/data {SKIP $np (full prefix)}

	    set previous $lines
	    set hasnew 1
	    return [lrange $lines $np end]
	}
	incr np
    }

    # Short 3: new same as previous?
    if {$previous eq $lines} {
	# Same as last time.
	debug.mgr/logstream/data {SKIP ALL (same as previous)}
	return {}
    }

    # Find the largest prefix of new as suffix in previous.
    # prefix must be shorter than previous, or new.

    # As lines != previous, and previous was not empty we have
    # to look for the largest suffix of previous which is
    # prefix of lines. These are the entries to skip.

    #foreach l $previous { debug.mgr/logstream/data {OLD $l} }
    #foreach l $lines    { debug.mgr/logstream/data {NEW $l} }

    set n 1
    set stop [expr {min($nn,$np)}]

    debug.mgr/logstream/data {MAX-WINDOW $stop}

    while {$n < $stop} {
	# First slice at the end of previous ... n..end
	set suffixp [lrange $previous $n end]

	# Then slice at the beginning of current, of the same length
	# as the suffix. len(suffix)=np-n. Index one less.
	# The short2 check above is essentially this for n==0.
	# We are moving a window across previous and new, from large
	# to small.
       
	set prefixn [lrange $lines 0 [expr {$np-$n-1}]]

	# Lastly check for match
	if {$prefixn eq $suffixp} {
	    debug.mgr/logstream/data {DROPPED $n}
	    break
	}
	incr n
    }
    if {$n == $stop} {
	# No prefix of new is a suffix in the previous.
	# I.e. we get an all-new set of entries.
	# Note that we may have missed entries now.
	# Show the entirety of the new.
	set toshow $lines

	debug.mgr/logstream/data {SKIP 0 (gap possible)}
    } else {
	set toshow [lrange $lines [llength $prefixn] end]

	debug.mgr/logstream/data {SKIP [llength $prefixn]}
    }

    set previous $lines
    set hasnew 1

    return $toshow
}

proc ::stackato::mgr::logstream::Filter {record} {
    upvar 1 \
	pnewer    pnewer    \
	plogfile  plogfile  \
	plogtext  plogtext  \
	pinstance pinstance \
	pattern   pattern

    dict with record {} ; # => timestamp, instance, source, text, filename

    # Filter for time.
    if {$pnewer >= $timestamp} {
	debug.mgr/logstream/data {Filter Timestamp '$timestamp' rejected by '$pnewer' }
	return 1
    }

    # Filter for filename
    if {![string match $plogfile $filename]} {
	debug.mgr/logstream/data {Filter Filename '$filename' rejected by '$plogfile' }
	return 1
    }
    # Filter for text
    if {![string match $plogtext $text]} {
	debug.mgr/logstream/data {Filter Text '$text' rejected by '$plogtext' }
	return 1
    }

    # Filter for instance.
    if {($pinstance ne {}) && ($instance ne $pinstance)} {
	debug.mgr/logstream/data {Filter Instance '$instance' rejected by '$pinstance' }
	return 1
    }

    # Filter for log source...
    if {![string match $pattern $source]} {
	debug.mgr/logstream/data {Filter Source '$source' rejected by '$pattern' }
	return 1
    }

    return 0
}

# Bug 105090 - Encode EOLs in log entries to make them visible.
proc ::stackato::mgr::logstream::EolCode {text} {
    return [string map [EolMap] $text]
}
proc ::stackato::mgr::logstream::EolMap {} {
    # Lazy creation. Ensures that we have a proper active color system.
    # Memoization to avoid redoing this for each line.
    lappend  eolmap \n [color note "\\n"]
    lappend  eolmap \r [color note "\\r"]
    proc ::stackato::mgr::logstream::EolMap {} [list return $eolmap ]
    return $eolmap
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::mgr::logstream {

    # active - counter of active tail requests. No keying by appname, as only one
    #          log thread is possible.
    # fast   - true if new fast logging is possible.
    # pid    - after id, or http token of the internal log thread
    #          only one such is possible, thus no keying by app name or else.

    variable pid    {}
    variable active 0
    variable fast   ;# fast is left undefined until the 1st check

    # tail filtering - list of entries from the last retrieval
    # operation (see TailRun).
    variable previous

    # Indicator flag set when new entries arrived and where shown.
    # Reset on query.
    variable hasnew 0

    # Configuration settings. Various delays. All in milliseconds
    # (suitable for after without modification).
    variable stopdelay 800
    variable logdelay  200
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::logstream 0
return
