# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tclx
package require debug

package provide exec 0

debug level  exec
debug prefix exec {}

namespace eval ::exec {
    variable pids {}
}

proc ::exec::bgrun {args} {
    variable pids
    Debug.exec {[info level 0]}

    set pid [exec {*}$args &]
    Debug.exec {+ $pid}

    lappend pids $pid
    return $pid
}

proc ::exec::clear {} {
    variable pids
    Debug.exec {[info level 0]}
    Debug.exec {pids = ($pids)}

    foreach p $pids {
	catch { kill $p }
    }
    set pids {}
    return
}

proc ::exec::drop {pid} {
    variable pids
    Debug.exec {[info level 0]}
    Debug.exec {pids = ($pids)}

    set loc [lsearch -exact $pids $pid]
    Debug.exec {loc = $loc}

    if {$loc < 0} return
    set pids [lreplace $pids $loc $loc]
    catch { kill $pid }
    return
}

namespace eval ::exec {
    namespace export bgrun clear drop
    #namespace ensemble create
    # No ensemble, would smash builtin ::exec
}
