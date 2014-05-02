## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - User names within an space.
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate
package require stackato::mgr::client
package require stackato::mgr::cspace
package require stackato::validate::common

debug level  validate/username-space
debug prefix validate/username-space {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export username
    namespace ensemble create
}

namespace eval ::stackato::validate::username-space {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-unknown-thing
    namespace import ::stackato::mgr::client
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::validate::common::refresh-client
    namespace import ::stackato::v2
}

proc ::stackato::validate::username-space::default  {p}   { return {} }
proc ::stackato::validate::username-space::release  {p x} { return }
proc ::stackato::validate::username-space::complete {p x} {
    # We cannot do completion because at the time the user name is
    # entered the space context is not known (argument comes later).
    return {}
}

proc ::stackato::validate::username-space::validate {p x} {
    debug.validate/username-space {}

    $p config @organization ;# force validation and setup
    $p config @space        ;# force validation and setup
    # The (un)link operations have this declared after the username.
    # Without the above the 'cspace' will not have the proper information.

    set c [refresh-client $p]

    # TODO FUTURE: val/username-space -- mgr/client, v2/client -- consolidate in client class.

    set thespace [cspace get]

    # We have to look for the user in all possible relations as none
    # of them is required for the others, unlike for orgs, where
    # everybody must be developer before they can be anything else.
    foreach relation {
	@developers
	@managers
	@auditors
    } {
	set matches [$thespace $relation get* [list q username:$x]]
	if {[llength $matches] == 1} {
	    set x [lindex $matches 0]
	    debug.validate/username-space {OK/canon/$relation = $x}
	    return $x
	}
    }

    # Last attempt, try the global information
    if {![catch {
	set x [v2 user find-by-name $x]
    } e o]} {
	debug.validate/username-space {OK/canon/global = $x}
	return $x
    }

    debug.validate/username-space {FAIL}
    fail-unknown-thing $p USERNAME "A user" $x " in space '[$thespace @name]'"
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::username-space 0
