# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require clock::iso8601
package require cmdr::tty
package require debug
package require linenoise
package require textutil::adjust

debug level  log
debug prefix log {[debug caller] | }

namespace eval ::stackato::log {
    namespace export log
    namespace ensemble create

   # EL (Erase Line)
    #    Sequence: ESC [ n K
    # ** Effect: if n is 0 or missing, clear from cursor to end of line
    #    Effect: if n is 1, clear from beginning of line to cursor
    #    Effect: if n is 2, clear entire line

    variable eeol \033\[K
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::log::wrap {text {down 0}} {
    global env
    if {[info exists env(STACKATO_NO_WRAP)]} {
	return $text
    }
    set c [expr {[linenoise columns]-$down}]
    return [textutil::adjust::adjust $text -length $c -strictlength 1]
}

proc ::stackato::log::wrapl {text {down 0}} {
    set lines {}
    foreach l [split $text \n] {
	# Pass empty lines through as they are.
	if {$l eq {}} {
	    lappend lines $l
	    continue
	}
	# Untabify
	set l [string map {{	} {        }} $l]
	# Get indent as string
	set i [::textutil::string::longestCommonPrefixList [list $l]]
	regexp {^([ 	]*)} $i -> i
	# Size of indent (Here the untabify helps)
	set il [string length $i]
	# Line after the indent, i.e. actual content.
	set lt [string range $l $il end]
	# Wrap the line, reducing the space it has by the indent.
	set lt [wrap $lt [expr {$il + $down}]]
	# Add wrap result to output, re-indented.
	foreach l [split $lt \n] {
	    lappend lines $i$l
	}
    }
    return [join $lines \n]
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::log::to {chan} {
    debug.log {}
    variable log $chan
    if {($chan ne "stdout") || ![cmdr tty stdout]} {
	# No feedback when not logging to stdout,
	# or stdout is not a tty.
	variable feedback 0
    }
    return
}

proc ::stackato::log::defined {} {
    debug.log {}
    variable log
    return [expr {$log ne {}}]
}

proc ::stackato::log::feedback {} {
    variable feedback
    debug.log {==> $feedback}
    return $feedback
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::log::say! {text} {
    debug.log {log=stderr t=[fconfigure stderr -translation] e=[fconfigure stderr -encoding]}
    puts stderr $text
    return
}

proc ::stackato::log::say {text} {
    variable log
    if {$log eq {}} return
    debug.log {log=$log t=[fconfigure $log -translation] e=[fconfigure $log -encoding]}
    puts $log $text
    return
}

proc ::stackato::log::say* {text} {
    variable log
    if {$log eq {}} return
    debug.log {log=$log t=[fconfigure $log -translation] e=[fconfigure $log -encoding]}
    variable last $text
    puts -nonewline $log $text
    flush $log
    return
}

proc ::stackato::log::again+ {text} {
    variable log
    if {$log eq {}} return
    variable feedback
    if {!$feedback} return
    variable eeol
    variable last
    puts -nonewline $log \r$eeol\r$last$text
    flush $log
    return
}

proc ::stackato::log::clearlast {} {
    variable log
    if {$log eq {}} return
    variable feedback
    if {!$feedback} return
    variable eeol
    variable last {}
    puts -nonewline $log \r$eeol\r
    flush $log
    return
}

proc ::stackato::log::clear {{size 80}} {
    variable log
    if {$log eq {}} return
    variable feedback
    if {!$feedback} return
    variable eeol
    puts -nonewline $log \r$eeol\r
    flush $log
    return
}

proc ::stackato::log::header {message {filler -}} {
    say \n
    say $message
    say [string repeat $filler [string length $message]]
    return
}

proc ::stackato::log::banner {message} {
    say ""
    say $message
    return
}

proc ::stackato::log::display {message {newline 1}} {
    if {$newline} {
	say $message
    } else {
	say* $message
    }
    return
}

proc ::stackato::log::err {message {prefix {Error: }}} {
    return -code error \
	-errorcode {STACKATO CLIENT CLI CLI-EXIT} \
	$prefix$message
}

proc ::stackato::log::warn {message {prefix {Warning: }}} {
    return -code error \
	-errorcode {STACKATO CLIENT CLI CLI-WARN} \
	$prefix$message
}

proc ::stackato::log::quit {{message {}}} {
    return -code error \
	-errorcode {STACKATO CLIENT CLI GRACEFUL-EXIT} \
	$message
}

proc ::stackato::log::uptime {delta} {
    #@type delta = float

    set seconds  $delta
    set days    [expr {int($seconds /  (60 * 60 * 24))}]
    set seconds [expr {$seconds - $days    * (60 * 60 * 24)}]
    set hours   [expr {int($seconds /  (60 * 60))}]
    set seconds [expr {$seconds - $hours   * (60 * 60)}]
    set minutes [expr {int($seconds /  60)}]
    set seconds [expr {int($seconds - $minutes * 60)}]

    return "${days}d:${hours}h:${minutes}m:${seconds}s"
}

proc ::stackato::log::psz {size {prec 1}} {
    # unit (size) = Bytes
    # see also ::stackato::validate::memspec::format

    #checker -scope local exclude warnArgWrite
    if {$size eq {}} { return NA }
    if {$size < 1024} { return ${size}B }
    set size [expr {$size/1024.0}]
    if {$size < 1024}  { return [format "%.${prec}f" $size]K }
    set size [expr {$size/1024.0}]
    if {$size < 1024}  { return [format "%.${prec}f" $size]M }
    set size [expr {$size/1024.0}]
    return [format "%.${prec}f" $size]G
}

proc ::stackato::log::pretty-since {x} {
    if {$x <=       0} { return "just now" }
    if {$x <=       1} { return "a second ago" }
    if {$x <=      59} { return "$x seconds ago" }
    if {$x <=     119} { return "a minute ago" }
    if {$x <=    3540} { return "[expr {int($x/60)}] minutes ago" }
    if {$x <=    7100} { return "an hour ago" }
    if {$x <=   82800} { return "[expr {int(($x+99)/3600)}] hours ago" }
    if {$x <=  172000} { return "a day ago" }
    if {$x <=  518400} { return "[expr {int(($x+800)/86400)}] days ago" }
    if {$x <= 1036800} { return "a week ago" }
    return "[expr {int(($x+180000)/604800)}] weeks ago"

    # Notes on the various constants:
    #    120 = 2 minutes |
    #   3600 = 1 hour    |   3540  = 1h - 1m
    #  86400 = 1 day     |   82800 = 1d - 1h
    # 604800 = 1 week    |  518400 = 1w - 1d
    #                    | 1036800 = 1w + 5d
    #
    #     99 = 1m 39s
    #    800 = 13m 20s
    # 180000 = 2d 2h
}

proc ::stackato::log::since {x} {
    expr {[clock seconds] - $x}
}

proc ::stackato::log::epoch-of {x} {
    return [clock::iso8601::parse_time $x]
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::log {
    namespace export say say! header banner display clear err quit \
	uptime psz to defined again+ clearlast wrap wrapl feedback \
	warn pretty-since since epoch-of
    namespace ensemble create

    variable feedback 1
    variable log {}
    variable last {}
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::log 0
