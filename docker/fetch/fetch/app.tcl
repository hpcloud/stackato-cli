# -*- tcl -*- Copyright (c) 2012 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## Application Core

namespace eval ::kettle {}

# # ## ### ##### ######## ############# #####################
## API commands.

proc ::kettle::Application {} {
    global argv tcl_platform

    # Handle ^C (int, term signals) by cleanly exiting.
    # This will invoke all handlers registered with atexit.
    # Especially 'path ensure-cleanup' runs here.

    if {![catch {
	package require Tclx
    }]} {
	set flags {}
	if {$tcl_platform(platform) ne "windows"} {
	    lappend flags -restart
	}
	signal {*}$flags trap {TERM INT} {
	    puts "\n[kettle io mred Interrupted]\n"
	    exit 1
	}
    }

    try {
	# Process arguments: -f, -trace, --* options, and goals

	set first [lindex $argv 0]

	if {[string match @* $first]} {
	    # Special operation detected, bypass the whole processing
	    # of options, and goals.

	    special [string range $first 1 end] {*}[lassign $argv __]
	    ::exit 0
	}

	if {$first eq {-f}} {
	    set argv     [lassign $argv __ path]
	    set declfile [path norm $path]

	} elseif {[file exists $first]} {
	    set argv     [lassign $argv __]
	    set declfile [path norm $first]

	} elseif {[file exists build.tcl]} {
	    set declfile [path norm build.tcl]
	} else {
	    io err {
		io puts "Build declaration file neither specified, nor found"
	    }
	    ::exit 1
	}

	# Early trace activation.
	if {[lindex $argv 0] eq {-trace}} {
	    set argv [lrange $argv 1 end]
	    option set --verbose on
	}

	set goals {}

	set dotfile ~/.kettle/config
	if {[file exists   $dotfile] &&
	    [file isfile   $dotfile] &&
	    [file readable $dotfile]} {
	    io trace {Loading dotfile $dotfile ...}
	    set argv [list {*}[path cat $dotfile] {*}$argv]
	}

	io trace {cmdline = ([join $argv {) (}])}

	while {[llength $argv]} {
	    set o [lindex $argv 0]
	    switch -glob -- $o {
		--* {
		    if {![option known $o]} {
			error "Unable to process unknown option $o." {} KETTLE
		    }
		    option set $o [lindex $argv 1]
		    set argv [lrange $argv 2 end]
		}
		default {
		    lappend goals $o
		    option set @goals $goals
		    set argv [lrange $argv 1 end]
		}
	    }
	}

	# Process the user's build declarations for the sources (-f)

	option set @srcscript $declfile
	option set @srcdir    [file dirname $declfile]

	::source $declfile

	# And execute the chosen goals
	recipe run {*}[option get @goals]

	# Were we invoked as sub-process? If yes, save the work state
	# back for the caller to pick up.
	set state [option get --state]
	if {$state ne {}} {
	    status save $state
	}

	::exit 0

    } trap {KETTLE STATUS FAIL} {e o} {
	::exit 1
    } trap {KETTLE STATUS OK} {e o} {
	::exit 0
    } trap {KETTLE} {e o} {
	io err { io puts $e }
	::exit 1
    } trap {POSIX EPIPE} {e o} {
	# Broken pipe, try to report on stderr.
	# May fail, as it may be using the same pipe.
	catch { ::puts stderr $e }
	::exit 1
    } on error {e o} {
	# Report general troubles in the declarations and abort.
	io err { io puts $::errorInfo }
	::exit 1
    }

    return
}

# # ## ### ##### ######## ############# #####################
return
