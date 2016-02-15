# -*- tcl -*- Copyright (c) 2012 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## Manage tool requirements

# # ## ### ##### ######## ############# #####################
## Export (internals)

namespace eval ::kettle::tool {
    namespace export {[a-z]*}
    namespace ensemble create

    namespace import ::kettle::io
    namespace import ::kettle::option
    namespace import ::kettle::status

    # Dictionary. Error information for tools which were not found.
    variable err {}
}

# # ## ### ##### ######## ############# #####################
## API.

proc ::kettle::tool::declare {names {validator {}}} {
    variable err

    set primary [lindex $names 0]
    dict set err primary {}

    option define --with-$primary [subst {
	Path to the tool '$primary'.
	Overides kettle's search on the PATH.
    }] {} readable.file
    option no-work-key --with-$primary

    set sep [expr {$::tcl_platform(platform) eq "windows" ? ";" : ":"}]
    foreach p [split $::env(PATH) $sep] {
	dict lappend err $primary "Searching $p"
    }

    foreach name $names {

	# TODO : Use our own search command here, switch to the next
	# name only if the list of paths is exhausted. Right now a
	# validation failure immediately switches to the next name,
	# cutton of possible instances of the failing name in
	# not-yet-searched paths of the list.

	set cmd [auto_execok $name]
	option set-default --with-$primary $cmd

	# Do not try to validate applications which were not found.
	# Continue search.
	if {![llength $cmd]} continue

	# Do not try to validate if we have no validation code.
	# Assume ok, stop search.
	if {$validator eq ""} break

	# Validate. If ok, stop search.
	set msg {}
	if {[apply [list {cmd msgvar} $validator] $cmd msg]} break

	dict lappend err $primary "Rejected: $cmd ($msg)"

	# Validation failed, revert, continue search.
	option set-default --with-$primary {}
    }
    return
}

proc ::kettle::tool::get {name} {
    set cmd [option get --with-$name]
    if {![llength $cmd]} {
	variable err
	io err {
	    io puts "Tool $name required, but not found in PATH"
	    io puts "Please specify its location through option --with-$name"
	    io puts \n[join [dict get $err $name] \n]
	}
	status fail
    }
    return $cmd
}

# # ## ### ##### ######## ############# #####################
return

