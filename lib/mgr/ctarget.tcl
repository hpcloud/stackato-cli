# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## This module manages the current (active) target, in-memory
## and persistent between cli invokations. The latter is done
## per target.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require stackato::mgr::cfile
package require fileutil
package require url

namespace eval ::stackato::mgr {
    namespace export ctarget
    namespace ensemble create
}

namespace eval ::stackato::mgr::ctarget {
    namespace export set get reset save suggest setc getc
    namespace ensemble create

    namespace import ::stackato::mgr::cfile
}

debug level  mgr/ctarget
debug prefix mgr/ctarget {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## API

proc ::stackato::mgr::ctarget::setc {p name} { set $name }
proc ::stackato::mgr::ctarget::getc {p} { get }

proc ::stackato::mgr::ctarget::set {name} {
    debug.mgr/ctarget {}
    variable current [url canon $name]
    debug.mgr/ctarget {:= $current}
    return
}

proc ::stackato::mgr::ctarget::get {} {
    debug.mgr/ctarget {}
    variable current

    if {![info exists current]} {
	global env
	debug.mgr/ctarget {fill cache}

	# Priority order (first to last taken):
	# (1) --target (via set)
	# (2) $STACKATO_TARGET
	# (3) $HOME/.stackato/client/target

	if {[info exists env(STACKATO_TARGET)] &&
	    ($env(STACKATO_TARGET) ne {})
	} {
	    ::set current [url canon $env(STACKATO_TARGET)]
	    debug.mgr/ctarget {env var   = $current}
	} else {
	    ::set current [url canon [Load]]
	    debug.mgr/ctarget {file/dflt = $current}
	}
    }

    debug.mgr/ctarget {==> $current}
    return $current
}

proc ::stackato::mgr::ctarget::reset {} {
    debug.mgr/ctarget {}
    variable current
    unset -nocomplain current
    return
}

proc ::stackato::mgr::ctarget::save {} {
    debug.mgr/ctarget {}
    variable current

    if {[info exists current] && ($current ne {})} {
	Store $current
    } else {
	Remove
    }

    debug.mgr/ctarget {OK}
    return
}

proc ::stackato::mgr::ctarget::suggest {} {
    debug.mgr/ctarget {}
    variable suggestion

    if {$suggestion eq {}} {
	::set suggestion [url base [get]]
    }
    return $suggestion
}

# # ## ### ##### ######## ############# #####################
## Low-level access to the configuration file.

proc ::stackato::mgr::ctarget::Load {} {
    debug.mgr/ctarget {}

    ::set path [cfile get target]
    if {![fileutil::test $path efr]} {
	variable default
	debug.mgr/ctarget {default = $default}
	return $default
    }

    ::set uri [string trim [fileutil::cat $path]]
    debug.mgr/ctarget {file    = $uri}
    return $uri
}

proc ::stackato::mgr::ctarget::Store {url} {
    debug.mgr/ctarget {}
    ::set path [cfile get target]
    fileutil::writeFile   $path $url\n
    cfile fix-permissions $path
    return
}

proc ::stackato::mgr::ctarget::Remove {} {
    file delete -force -- [cfile get target]
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::mgr::ctarget {
    # Configuration

    variable default api.stackato.local
    variable suggestion {}
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::ctarget 0
