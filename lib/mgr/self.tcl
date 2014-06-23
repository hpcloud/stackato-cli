# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## This module manages information about the client itself.
## - Location
## - Name
## - Revision

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cd
package require struct::list
package require lambda

namespace eval ::stackato::mgr {
    namespace export self
    namespace ensemble create
}

namespace eval ::stackato::mgr::self {
    namespace export topdir me revision exe plain-revision \
	please wrapped packages
    namespace ensemble create
}

debug level  mgr/self
debug prefix mgr/self {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## API

proc ::stackato::mgr::self::packages {} {
    variable wrapped
    if {$wrapped} {
	# wrapped, deliver exact set known.
	catch { package require bogus }
	return [struct::list filter [package names] [lambda {x} {
	    expr {
		  ![string match stackato::* $x] &&
		  ![string match vfs* $x]
	    }
	}]]
    } else {
	# unwrapped, fixed set.
	return {
	    ActiveTcl
	    Tcl
	    TclOO
	    Tclx
	    Trf
	    autoproxy
	    base64
	    clock::iso8601
	    cmdline
	    cmdr
	    cmdr::actor
	    cmdr::config
	    cmdr::help
	    cmdr::help::json
	    cmdr::officer
	    cmdr::pager
	    cmdr::parameter
	    cmdr::private
	    cmdr::tty
	    cmdr::util
	    cmdr::validate
	    cmdr::validate::common
	    control
	    crc32
	    debug
	    debug::caller
	    dictutil
	    fileutil
	    fileutil::decode
	    fileutil::magic::mimetype
	    fileutil::magic::rt
	    fileutil::traverse
	    http
	    json
	    json::write
	    linenoise
	    linenoise::facade
	    linenoise::repl
	    logger
	    md5
	    ncgi
	    oo::util
	    platform
	    report
	    s-http
	    sha1
	    string::token
	    string::token::shell
	    struct::list
	    struct::matrix
	    struct::queue
	    struct::set
	    tar
	    tcl::chan::cat
	    tcl::chan::core
	    tcl::chan::events
	    tcl::chan::string
	    tcllibc
	    tclyaml
	    term::ansi::code
	    term::ansi::code::attr
	    term::ansi::code::ctrl
	    term::ansi::ctrl::unix
	    textutil::adjust
	    textutil::repeat
	    textutil::string
	    tls
	    try
	    uri
	    url
	    uuid
	    zipfile::decode
	    zipfile::encode
	    zlibtcl
	}
    }
}

proc ::stackato::mgr::self::wrapped {} {
    debug.mgr/self {}
    variable wrapped

    debug.mgr/self {= $wrapped}
    return $wrapped
}

proc ::stackato::mgr::self::topdir {} {
    debug.mgr/self {}
    variable topdir

    debug.mgr/self {= $topdir}
    return $topdir
}

proc ::stackato::mgr::self::please {cmd {prefix {Please use}}} {
    set msg "$prefix '"
    if {![stackato-cli exists *in-shell*] ||
	![stackato-cli get    *in-shell*]} {
	# Not in a shell, full message.
	append msg [me] " "
    }
    append msg $cmd '
    return $msg
}

proc ::stackato::mgr::self::me {} {
    debug.mgr/self {}
    variable me
    if {[info exists me]} {
	debug.mgr/self {= $me}
	return $me
    }

    variable wrapped

    debug.mgr/self {fill cache, wrapped=$wrapped}
    if {$wrapped} {
	set base [info nameofexecutable]
    } else {
	global argv0
	set base $argv0
    }

    set me [file tail $base]
    debug.mgr/self {= $me}
    return $me
}

proc ::stackato::mgr::self::revision {} {
    debug.mgr/self {}

    set revfile [topdir]/revision.txt
    debug.mgr/self {revfile = $revfile}

    if {![file exists $revfile]} {
	debug.mgr/self {revfile does not exist, assume unwrapped and ask git}
	cd::indir [topdir] {
	    set rev "local: [exec git describe]"
	}
    } else {
	debug.mgr/self {revfile found, read and show contents}
	set rev "wrapped: [fileutil::cat $revfile]"
    }

    debug.mgr/self {= $rev}
    return $rev
}

proc ::stackato::mgr::self::plain-revision {} {
    debug.mgr/self {}

    set revfile [topdir]/revision.txt
    debug.mgr/self {revfile = $revfile}

    if {![file exists $revfile]} {
	debug.mgr/self {revfile does not exist, assume unwrapped and ask git}
	cd::indir [topdir] {
	    set rev [exec git describe]
	}
    } else {
	debug.mgr/self {revfile found, read and show contents}
	set rev [fileutil::cat $revfile]
    }

    debug.mgr/self {= $rev}
    return $rev
}

proc ::stackato::mgr::self::exe {} {
    debug.mgr/self {}
    variable wrapped

    debug.mgr/self {wrapped=$wrapped}
    set noe [info nameofexecutable]

    if {$wrapped} {
	set exe [list $noe]
    } else {
	global argv0
	set exe [list $noe $argv0]
    }
    debug.mgr/self {= $exe}
    return $exe
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::mgr::self {
    variable self    [file normalize [info script]]
    variable topdir  [file dirname [file dirname [file dirname $self]]]
    variable wrapped [expr {[lindex [file system [info script]] 0] ne "native"}]
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::self 0
