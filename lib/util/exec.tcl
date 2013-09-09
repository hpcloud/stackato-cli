# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tclx
package require debug

package provide exec 0

debug level  exec
debug prefix exec {[debug caller] | }

namespace eval ::exec {
    variable pids {}
}

proc ::exec::bgrun {args} {
    variable pids
    debug.exec {[info level 0]}

    set pid [exec {*}$args &]
    debug.exec {+ $pid}

    lappend pids $pid
    return $pid
}

proc ::exec::clear {} {
    variable pids
    debug.exec {[info level 0]}
    debug.exec {pids = ($pids)}

    foreach p $pids {
	catch { kill $p }
    }
    set pids {}
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

namespace eval ::exec {
    namespace export bgrun clear drop
    #namespace ensemble create
    # No ensemble, would smash builtin ::exec
}
