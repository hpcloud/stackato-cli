# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

## Command implementations. Script execution.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require fileutil
package require stackato::color
package require stackato::mgr::exit

debug level  cmd/do
debug prefix cmd/do {[debug caller] | }

namespace eval ::stackato::cmd {
    namespace export do
    namespace ensemble create
}
namespace eval ::stackato::cmd::do {
    namespace export it
    namespace ensemble create

    namespace import ::stackato::color
    namespace import ::stackato::mgr::exit
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::do::it {config} {
    debug.cmd/do {}

    set trusted [$config @trusted]
    set verbose [$config @verbose]
    set script  [$config @script]

    if {$trusted} {
	set interp [interp create]
    } else {
	set interp [interp create -safe]
    }

    # Make all client commands available as Tcl script commands.
    # We need only the toplevel parts as anything else will then
    # be handled by the cmdr framework.

    foreach action [stackato-cli known] {
	interp alias $interp $action {} ::stackato::cmd::do::IT $verbose $action
    }

    interp alias $interp puts {} ::stackato::cmd::do::Puts

    interp eval $interp [fileutil::cat $script]
    return
}

proc ::stackato::cmd::do::IT {verbose args} {
    if {$verbose} {
	package require linenoise
	set c [linenoise columns]
	puts [color blue $args]
	puts [color blue [string repeat = $c]]
	# should limit by #columns.
    }

    stackato-cli do {*}$args

    if {$verbose} {
	puts [color blue [string repeat ^ $c]]
	# should limit by #columns.
    }
    return [expr {![exit state]}]
}

proc ::stackato::cmd::do::Puts {args} {
    # Limited, will work for std*, not others.
    puts {*}$args
}


# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::do 0

