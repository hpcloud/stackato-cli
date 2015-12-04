# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Space names
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate
package require stackato::mgr::client;# pulls v2 also
package require stackato::mgr::corg
package require stackato::mgr::self
package require stackato::validate::common

debug level  validate/otherspacename
debug prefix validate/otherspacename {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export otherspacename
    namespace ensemble create
}

namespace eval ::stackato::validate::otherspacename {
    #namespace export default validate complete release
    #namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-unknown-simple-msg
    namespace import ::stackato::mgr::corg
    namespace import ::stackato::mgr::self
    namespace import ::stackato::v2
    namespace import ::stackato::validate::common::refresh-client
}

proc ::stackato::validate::otherspacename {o cmd args} {
    # Ensemble with parameterization, move parameter into correct position.
    ::stackato::validate::otherspacename::$cmd $o {*}$args
}

proc ::stackato::validate::otherspacename::default  {o p}   { return {} }
proc ::stackato::validate::otherspacename::release  {o p x} { return }
proc ::stackato::validate::otherspacename::complete {o p x} {
    refresh-client $p
    complete-enum [[$p config $o] @spaces @name] 0 $x
}

proc ::stackato::validate::otherspacename::validate {o p x} {
    debug.validate/otherspacename {}

    refresh-client $p

    # See also cspace::get.

    # find space by name in current organization
    set theorg  [$p config $o]
    set matches [$theorg @spaces get* [list q name:$x]]
    # NOTE: searchable-on in v2/otherspace should help
    # (in v2/org using it) to filter server side.

    if {[llength $matches] == 1} {
	# Found, good.
	set x [lindex $matches 0]
	debug.validate/otherspacename {OK/canon = $x}
	return $x
    }
    debug.validate/otherspacename {FAIL}
    fail-unknown-simple-msg \
	"[self please [list org [$theorg @name]] Run] to see list of spaces" \
	$p SPACENAME "space" $x " in organization '[$theorg @name]'"
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::otherspacename 0
