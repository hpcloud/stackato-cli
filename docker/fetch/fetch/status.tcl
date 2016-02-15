# -*- tcl -*- Copyright (c) 2012 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## General goal status handling

# # ## ### ##### ######## ############# #####################
## Export (internals - recipe definitions, other utilities)

namespace eval ::kettle::status {
    namespace export {[a-z]*}
    namespace ensemble create

    namespace import ::kettle::io
}

# # ## ### ##### ######## ############# #####################
## State

namespace eval ::kettle::status {
    # Stack of currently executing goals.
    variable current {}

    # Dictionary holding the status of all goals executed.
    variable work {}
}

# # ## ### ##### ######## ############# #####################
## API.
##
## Note: The database keys contain the source-dir (normalized absolute
## path) to make the data shareable across multiple kettle instances
## calling on each other. This, the location in the key, makes the
## goals properly distinguishable.

proc ::kettle::status::begin {goal} {
    variable current
    variable work

    set key [list [kettle path sourcedir] $goal [kettle option config]]

    if {[dict exists $work $key]} {
	set status [dict get $work $key]
	# ok/fail for the goal -> do not run it again.
	if {$status ne "@work"} {
	    io trace {RUN ($goal) ... DONE ALREADY, STOP}
	    return -code return
	}

	# goal still at work -> found a cycle of goals calling
	# themselves recursively.

	return -code error -errorcode {KETTLE STATUS CYCLE} \
	    "Cycle in goal definitions: $goal"
	# TODO: Determine full set of goals @work.
    }

    # goal has not run yet. Mark for work, reset overall state, and
    # save work database back to the configuration.

    dict set work $key state @work
    dict set work $key msg   {}

    lappend current $goal
    return
}

proc ::kettle::status::ok {} {
    variable current
    variable work

    io trace {status ok :[lindex $current end]}

    set key     [list [kettle path sourcedir] [lindex $current end] [kettle option config]]
    set current [lreplace $current end end]

    #io trace {.... [lindex $key 0]}
    #io trace {.... [lindex $key 1]}
    #io trace {.... [lindex $key 2]}

    dict set work $key state ok
    dict set work $key msg   OK

    Show $key
    return -errorcode {KETTLE STATUS OK} -code error ""
}

proc ::kettle::status::fail {{msg FAIL}} {
    variable current
    variable work

    io trace {status fail :[lindex $current end] $msg}

    set key     [list [kettle path sourcedir] [lindex $current end] [kettle option config]]
    set current [lreplace $current end end]

    dict set work $key state fail
    dict set work $key msg $msg

    Show $key
    return -errorcode {KETTLE STATUS FAIL} -code error ""
}

proc ::kettle::status::is {goal {src {}} args} {
    variable work
    # possible results: unknown|ok|fail|work

    #io trace {status is :$goal ($args)}
    #io trace {          @$src}
    #io trace {          %$args}

    if {$src eq {}} { set src [kettle path sourcedir] }
    set key [list $src $goal [kettle option config {*}$args]]

    #io trace {.... [lindex $key 0]}
    #io trace {.... [lindex $key 1]}
    #io trace {.... [lindex $key 2]}

    if {![dict exists $work $key state]} {
	return unknown
    }

    return [dict get $work $key state]
}

proc ::kettle::status::save {{path {}}} {
    variable work
    if {$path eq {}} {
	set path [kettle path tmpfile state_]
	kettle path ensure-cleanup $path
    }
    kettle path write $path $work

    io trace {status saved to    $path}
    return $path
}

proc ::kettle::status::load {file} {
    io trace {status loaded from $file}
    variable work [kettle path cat $file]
    return
}

proc ::kettle::status::clear {} {
    variable work {}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::kettle::status::Show {key} {
    variable work

    set state [dict get $work $key state]
    set msg   [dict get $work $key msg]

    if {$state ne "ok"} {
	io $state { io puts $msg }
    } else {
	io for-gui {
	    io $state { io puts $msg }
	}
    }
    return
}

# # ## ### ##### ######## ############# #####################
return

