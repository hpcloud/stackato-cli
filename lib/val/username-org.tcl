# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - User names within an org.
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate
package require stackato::mgr::client
package require stackato::mgr::corg
package require stackato::validate::common

debug level  validate/username-org
debug prefix validate/username-org {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export username
    namespace ensemble create
}

namespace eval ::stackato::validate::username-org {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-unknown-simple-msg
    namespace import ::stackato::mgr::client
    namespace import ::stackato::mgr::corg
    namespace import ::stackato::validate::common::refresh-client
    namespace import ::stackato::v2
}

proc ::stackato::validate::username-org::default  {p}   { return {} }
proc ::stackato::validate::username-org::release  {p x} { return }
proc ::stackato::validate::username-org::complete {p x} {
    # We cannot do completion because at the time the user name is
    # entered the org context is not known (argument comes later).
    return {}
}

proc ::stackato::validate::username-org::validate {p x} {
    debug.validate/username-org {}

    $p config @org ;# force validation and setup
    # The (un)link operations have this declared after the username.
    # Without the above the 'corg' will not have the proper information.

    set c [refresh-client $p]

    # TODO FUTURE: val/username-org -- mgr/client, v2/client -- consolidate in client class.

    # NOTE: We only have to look at the per-org users here instead of
    # all possible relations, as none of the other roles can be set without
    # user being a dev for the org.

    set theorg  [corg get]
    set matches [$theorg @users get* [list q username:$x]]

    if {[llength $matches] == 1} {
	set x [lindex $matches 0]
	debug.validate/username-org {OK/canon/@users = $x}
	return $x
    }

    # Last attempt, try the global information
    try {
	set x [v2 user find-by-name $x]
    } trap {STACKATO CLIENT V2 AUTHERROR}   {e o} - \
      trap {STACKATO CLIENT V2 TARGETERROR} {e o} {
	debug.validate/username-org {FAIL, permission denied}
	# rethrow
	return {*}$o $e
    } on ok {e o} {
	debug.validate/username-org {OK/canon/global = $x}
	return $x
    } on error {e o} {
	# capture and pass
    }

    debug.validate/username-org {FAIL}
    fail-unknown-simple-msg \
	"[self please [list org-users [$theorg @name]] Run] to see list of users" \
	$p USERNAME "A user" $x " in organization '[$theorg @name]'"
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::username-org 0
