## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Client debug levels.

## To avoid having to load all packages and then query the debug
## package for the registered levels/tags this validation type loads
## the information from a generated file.
##
## TODO: Add the commands to generate/update this file to the wrapper
##       build code.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::validate
package require fileutil
package require stackato::mgr::self
package require stackato::validate::common

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export debug
    namespace ensemble create
}

namespace eval ::stackato::validate::debug {
    namespace export default validate complete release levels
    namespace ensemble create
    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-unknown-simple-msg
    namespace import ::stackato::mgr::self
}

proc ::stackato::validate::debug::default  {p}   { error {No default} }
proc ::stackato::validate::debug::release  {p x} { return }
proc ::stackato::validate::debug::complete {p x} {
    return [complete-enum [levels] 0 $x]
}

proc ::stackato::validate::debug::validate {p x} {
    if {$x in [levels]} { return $x }
    fail-unknown-simple-msg \
	"[self please debug-options Run] to see list of debug levels" \
	$p DEBUG-LEVEL "debug level" $x
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::validate::debug::levels {} {
    variable levels
    if {![llength $levels]} {
	set dltext [file join [self topdir] config debug-levels.txt]
	set levels [split [string trim [fileutil::cat $dltext]] \n]
    }
    return $levels
}

namespace eval ::stackato::validate::debug {
    variable levels {}
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::debug 0
