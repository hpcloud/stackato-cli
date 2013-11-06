## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Paths of various kinds.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::validate ;# fail utility command.

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export path
    namespace ensemble create
}

namespace eval ::stackato::validate::path {
    namespace export rfile rwfile rdir
    namespace ensemble create
}

debug level  validate/path
debug prefix validate/path {[debug caller] | }

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::validate::path::rfile {
    namespace export default validate complete release
    namespace ensemble create
    namespace import ::cmdr::validate::common::fail
}

proc ::stackato::validate::path::rfile::default  {p}   { return {} }
proc ::stackato::validate::path::rfile::release  {p x} { return }
proc ::stackato::validate::path::rfile::complete {p x} {
    return [struct::list filter [glob ${x}*] [lambda {x} {
	if {![file exists   $x]} {return 0}
	if {![file isfile   $x]} {return 0}
	if {![file readable $x]} {return 0}
	return
    }]]
}

proc ::stackato::validate::path::rfile::validate {p x} {
    debug.validate/path {}
    if {
	[file exists   $x] &&
	[file isfile   $x] &&
	[file readable $x]
    } { return $x }
    fail $p RFILE "an existing readable file" $x
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::validate::path::rwfile {
    namespace export default validate complete release
    namespace ensemble create
    namespace import ::cmdr::validate::common::fail
}

proc ::stackato::validate::path::rwfile::default  {p}   { return {} }
proc ::stackato::validate::path::rwfile::release  {p x} { return }
proc ::stackato::validate::path::rwfile::complete {p x} {
    return [struct::list filter [glob ${x}*] [lambda {x} {
	if {![file exists   $x]} {return 0}
	if {![file isfile   $x]} {return 0}
	if {![file readable $x]} {return 0}
	if {![file writable $x]} {return 0}
	return
    }]]
}

proc ::stackato::validate::path::rwfile::validate {p x} {
    debug.validate/path {}
    if {
	[file exists   $x] &&
	[file isfile   $x] &&
	[file readable $x] &&
	[file writable $x]
    } { return $x }
    fail $p RWFILE "an existing read/writable file" $x
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::validate::path::rdir {
    namespace export default validate complete release
    namespace ensemble create
    namespace import ::cmdr::validate::common::fail
}

proc ::stackato::validate::path::rdir::default  {p}   { return {} }
proc ::stackato::validate::path::rdir::release  {p x} { return }
proc ::stackato::validate::path::rdir::complete {p x} {
    return [struct::list filter [glob ${x}*] [lambda {x} {
	if {![file exists      $x]} {return 0}
	if {![file isdirectory $x]} {return 0}
	if {![file readable    $x]} {return 0}
	return
    }]]
}

proc ::stackato::validate::path::rdir::validate {p x} {
    debug.validate/path {}
    if {
	[file exists      $x] &&
	[file isdirectory $x] &&
	[file readable    $x]
    } { return $x }
    fail $p RDIR "an existing readable file" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::path 0
