# -*- tcl -*- Copyright (c) 2012 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## Manage multiple log streams to files.
## Further manage logging to the terminal.

namespace eval ::kettle::stream {
    namespace export {[a-z]*}
    namespace ensemble create

    namespace import ::kettle::option
    namespace import ::kettle::io

    # Dictonary of open streams.
    variable stream {}
}

# # ## ### ##### ######## ############# #####################
## Logging of test/benchmark output, into multiple streams.
## Irrelevant to work database keying.

# Logging is to a set of files, for multiple log 'streams'.  The
# option --log specifies their (path) stem.  If no stem is specified
# no streams are generated.

kettle option define --log {
    Log option. Path (stem) for a set of files to log to
    (independent of logging to the terminal).
} {} path
kettle option onchange    --log {} { set! --log [path norm $new] }
kettle option no-work-key --log

kettle option define --log-append {
    Associate to --log. Open files in append mode.
} off boolean
kettle option no-work-key --log-append

# # ## ### ##### ######## ############# #####################
## Verbosity setting for logging to the terminal.
## Irrelevant to work database keying.

kettle option define --log-mode {
    Verbosity of the logging to the terminal by Tcl-based
    sub-processes like the execution of testsuites and
    benchmarks.
} compact {enum {compact full}}
kettle option no-work-key --log-mode

# # ## ### ##### ######## ############# #####################
## API.

proc ::kettle::stream::active {} {
    expr {[option get --log] ne {}}
}

proc ::kettle::stream::to {name text} {
    variable stream
    if {![active]} return
    set text [uplevel 1 [list subst $text]]

    if {![dict exists $stream $name]} {
	set stem [option get --log]

	file mkdir [file dirname $stem.$name]

	set mode [expr {[option get --log-append]
			? "a"
			: "w"}]

	set ch [open $stem.$name $mode]
	dict set stream $name $ch
    } else {
	set ch [dict get $stream $name]
    }

    ::puts $ch $text
    flush  $ch
    return
}

# # ## ### ##### ######## ############# #####################
## Terminal log.

proc ::kettle::stream::term {mode text} {
    if {($mode ne "always") &&
	($mode ne [option get --log-mode])} return
    io puts $text
    return
}

proc ::kettle::stream::aopen {} {
    if {[option get --log-mode] ne "compact"} return
    io animation begin
    return
}

proc ::kettle::stream::aclose {text} {
    upvar 1 state state

    if {[option get --log-mode] eq "compact"} {
	io animation last $text
    }

    if {![active]} return

    set file [file tail [dict get $state file]]
    if {[dict exists $state fmap $file]} {
	set file [dict get $state fmap $file]
    }

    set text "$file $text"

    to summary {$text}
    # Maybe use a mapping table here instead, status to stream.
    switch -exact -- [dict get $state suite/status] {
	error   -
	fail    { to failures {$text} }
	none    { to none     {$text} }
	aborted { to aborted  {$text} }
    }
    return
}

proc ::kettle::stream::aextend {text} {
    if {[option get --log-mode] ne "compact"} return
    io animation indent $text
    io animation write  ""
    return
    
}

proc ::kettle::stream::awrite {text} {
    if {[option get --log-mode] ne "compact"} return
    io animation write $text
    return
}

# # ## ### ##### ######## ############# #####################
return
