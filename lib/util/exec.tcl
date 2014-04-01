# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tclx
package require debug
package require try
package require fileutil

package provide exec 0

debug level  exec
debug prefix exec {[debug caller] | }

namespace eval ::exec {
    variable pids  {}
    variable files {}
}

proc ::exec::bgrun {args} {
    variable pids
    debug.exec {[info level 0]}

    set pid [exec {*}$args &]
    debug.exec {+ $pid}

    lappend pids $pid
    return $pid
}

proc ::exec::run {prefix args} {
    pipe line {
	# line ends in \n, except possibly at eof.
	puts -nonewline $prefix$line
    } {*}$args
    return
}

proc ::exec::pipe {lv script args} {
    variable files
    debug.exec {[info level 0]}

    set stderr [fileutil::tempfile pipe_stderr_]
    lappend files $stderr

    debug.exec {  PIPE: [T $args]}

    set err {}
    set pipe [open "|$args 2> $stderr" r]
    fconfigure $pipe -translation lf

    upvar 1 $lv line
    try {
	while {![eof $pipe]} {
	    if {[gets $pipe line] < 0} continue
	    if {![eof $pipe]} {
		append line \n
	    }
	    try {
		uplevel 1 $script
	    } on error {e o} {
	        puts $e
		break
	    }
	}
    } finally {
	try {
	    close $pipe
	} on error {e o} {
	    puts $e
	}

	set err [fileutil::cat $stderr]
	dropf $stderr
    }

    if {$err eq {}} return
    puts $err
    return
}

proc ::exec::clear {} {
    variable pids
    variable files
    debug.exec {[info level 0]}
    debug.exec {pids  = ($pids)}
    debug.exec {files = ($files)}

    foreach p $pids {
	catch {
	    debug.exec {[info level 0] kill $p}
	    kill $p
	}
    }
    set pids {}
    debug.exec {[info level 0] DONE}
    return
}

proc ::exec::drop {pid} {
    variable pids
    debug.exec {[info level 0]}
    debug.exec {pids = ($pids)}

    set loc [lsearch -exact $pids $pid]
    debug.exec {loc = $loc}

    if {$loc < 0} return
    set pids [lreplace $pids $loc $loc]
    if {[catch {
	kill $pid
    } msg]} {
	debug.exec {problem: $msg}
    }
    return
}

proc ::exec::dropf {path} {
    variable files
    debug.exec {[info level 0]}
    debug.exec {files = ($files)}

    set loc [lsearch -exact $files $path]
    debug.exec {loc = $loc}

    if {$loc < 0} return
    set files [lreplace $files $loc $loc]
    if {[catch {
	file delete -force $path
    } msg]} {
	debug.exec {problem: $msg}
    }
    return
}

namespace eval ::exec {
    namespace export bgrun run pipe clear drop dropf
    #namespace ensemble create
    # No ensemble, would smash builtin ::exec
}
