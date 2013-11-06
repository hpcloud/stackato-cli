# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## This module manages the current (active) group, in-memory
## and persistent between cli invokations. The latter is done
## per target.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require stackato::mgr::cfile
package require stackato::mgr::ctarget
package require fileutil
package require json
package require dictutil
package require stackato::jmap

namespace eval ::stackato::mgr {
    namespace export cgroup
    namespace ensemble create
}

namespace eval ::stackato::mgr::cgroup {
    namespace export set get reset save setc getc
    namespace ensemble create

    namespace import ::stackato::mgr::cfile
    namespace import ::stackato::mgr::ctarget
}

# # ## ### ##### ######## ############# #####################

debug level  mgr/cgroup
debug prefix mgr/cgroup {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## API

proc ::stackato::mgr::cgroup::setc {p name} { set $name }
proc ::stackato::mgr::cgroup::getc {p} { get }

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::cgroup::set {name} {
    debug.mgr/cgroup {}
    variable current $name
    return
}

proc ::stackato::mgr::cgroup::get {} {
    debug.mgr/cgroup {}
    variable current

    if {![info exists current]} {
	global env
	debug.mgr/cgroup {fill cache}

	# Priority order (first to last taken):
	# (1) --group (via set)
	# (2) $STACKATO_GROUP
	# (3) $HOME/.stackato/client/group

	if {[info exists env(STACKATO_GROUP)]} {
	    ::set current $env(STACKATO_GROUP)
	    debug.mgr/cgroup {env var   = $current}
	} else {
	    #checker -scope line exclude badOption
	    ::set current [dict get' [Load] [ctarget get] {}]
	    debug.mgr/cgroup {file/dflt = $current}
	}
    }
    return $current
}

proc ::stackato::mgr::cgroup::reset {} {
    debug.mgr/cgroup {}
    variable current
    unset -nocomplain current
    return
}

proc ::stackato::mgr::cgroup::save {} {
    debug.mgr/cgroup {}
    variable current

    ::set groups [Load]
    ::set target [ctarget get]

    if {[info exists current] && ($current ne {})} {
	dict set groups $target $current
    } else {
	dict unset groups $target
    }

    Store $groups
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::cgroup::Load {} {
    debug.mgr/cgroup {}

    ::set path [cfile get group]
    if {![fileutil::test $path efr]} {
	return {}
    }
    return [json::json2dict \
		[string trim \
		     [fileutil::cat $path]]]
}

proc ::stackato::mgr::cgroup::Store {groups} {
    debug.mgr/cgroup {}
    ::set path [cfile get group]
    fileutil::writeFile   $path [stackato::jmap tgroups $groups]\n
    cfile fix-permissions $path
    return
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::cgroup 0
