# -*- tcl -*- Copyright (c) 2006-2012 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## Testsuite Utilities. Started in tcllib, snarfed for kettle.

namespace eval ::kt {
    namespace export {[a-z]*}
    namespace ensemble create
}

# # ## ### ##### ######## ############# #####################
## API. Use of files relative to the test directory.

proc ::kt::source {path} {
    variable ::tcltest::testsDirectory
    uplevel 1 [list ::source [file join $testsDirectory $path]]
}

proc ::kt::find {pattern} {
    return [lsort -dict [glob -nocomplain -directory $::tcltest::testsDirectory $pattern]]
}

proc ::kt::source* {pattern} {
    foreach f [find $pattern] {
	uplevel 1 [list ::source $f]
    }
    return
}

# # ## ### ##### ######## ############# #####################
## Use of packages. Support, and under test.

proc ::kt::check {name version} {
    if {[package vsatisfies [package provide $name] $version]} {
	puts "SYSTEM - $name [package present $name]"
	return
    }

    puts "    Aborting the tests found in \"[file tail [info script]]\""
    puts "    Requiring at least $name $version, have [package present $name]."

    # This causes a 'return' in the calling scope.
    return -code return
}

proc ::kt::require {type name args} {
    variable tag
    try {
	package require $name {*}$args
    } on error {e o} {
	puts "    Aborting the tests found in \"[file tail [info script]]\""
	puts "    Required package $name not found: $e"
	return -code return
    }

    puts "SYSTEM [dict get $tag $type] $name [package present $name]"
    return
}

proc ::kt::local {type name args} {
    variable tag
    # Specialized package require. It is forced to search (via
    # forget), and its search is restricted to the local installation,
    # via a custom unknown handler temporarily replacing the regular
    # functionality.

    set saved [package unknown]
    try {
	package unknown ::kt::PU
	package forget  $name
	package require $name {*}$args
    } on error {e o} {
	puts "    Aborting the tests found in \"[file tail [info script]]\""
	puts "    Required local package $name not found: $e"
	return -code return
    } finally {
	package unknown $saved
    }

    puts "LOCAL  [dict get $tag $type] $name [package present $name]"
    return
}

proc ::kt::PU {name args} {
    global   auto_path
    variable localprefix

    set saved $auto_path
    set auto_path [list $localprefix/lib]

    # Direct call into package scan, ignore modules.
    tclPkgUnknown __ignored__

    set auto_path $saved
    return
}

namespace eval ::kt {
    variable tag {
	support -
	testing %
    }
}

# # ## ### ##### ######## ############# #####################
## General utilities

# - dictsort -
#
#  Sort a dictionary by its keys. I.e. reorder the contents of the
#  dictionary so that in its list representation the keys are found in
#  ascending alphabetical order. In other words, this command creates
#  a canonical list representation of the input dictionary, suitable
#  for direct comparison.
#
# Arguments:
#	dict:	The dictionary to sort.
#
# Result:
#	The canonical representation of the dictionary.

proc ::kt::dictsort {dict} {
    array set a $dict
    set out [list]
    foreach key [lsort -dict [array names a]] {
	lappend out $key $a($key)
    }
    return $out
}

# # ## ### ##### ######## ############# #####################
## Tcltest extensions ...
#
## We can assume to have tcltest 2, or higher
## (We assume Tcl 8.5 or higher)

## Standard constraints.

::tcltest::testConstraint tcl8.5plus [expr {[package vsatisfies [package provide Tcl] 8.5]}]
::tcltest::testConstraint tcl8.6plus [expr {[package vsatisfies [package provide Tcl] 8.6]}]

## Commands generating the proper wrong#args message from a command
## syntax description. Core version dependent.

if {[package vsatisfies [package provide Tcl] 8.6]} {
    # 8.6+
    proc ::tcltest::wrongNumArgs {functionName argList missingIndex} {
	if {[lindex $argList end] eq "args"} {
	    set argList [lreplace $argList end end ?arg ...?]
	}
	if {$argList != {}} {set argList " $argList"}
	set msg "wrong # args: should be \"$functionName$argList\""
	return $msg
    }

    proc ::tcltest::tooManyArgs {functionName argList} {
	# create a different message for functions with no args
	if {[llength $argList]} {
	    if {[lindex $argList end] eq "args"} {
		set argList [lreplace $argList end end ?arg ...?]
	    }
	    set msg "wrong # args: should be \"$functionName $argList\""
	} else {
	    set msg "wrong # args: should be \"$functionName\""
	}
	return $msg
    }
} else {
    # 8.5
    proc ::tcltest::wrongNumArgs {functionName argList missingIndex} {
	if {[lindex $argList end] eq "args"} {
	    set argList [lreplace $argList end end ?argument ...?]
	}
	if {$argList != {}} {set argList " $argList"}
	set msg "wrong # args: should be \"$functionName$argList\""
	return $msg
    }

    proc ::tcltest::tooManyArgs {functionName argList} {
	# create a different message for functions with no args
	if {[llength $argList]} {
	    if {[lindex $argList end] eq "args"} {
		set argList [lreplace $argList end end ...]
	    }
	    set msg "wrong # args: should be \"$functionName $argList\""
	} else {
	    set msg "wrong # args: should be \"$functionName\""
	}
	return $msg
    }
}

## Creation of transient binary files.
## Easy access to the temp directory.

proc ::tcltest::makeBinaryFile {data f} {
    set path [makeFile {} $f]
    set ch   [open $path w]
    fconfigure $ch -translation binary
    puts -nonewline $ch $data
    close $ch
    return $path
}

proc ::tcltest::tempPath {path} {
    variable temporaryDirectory
    return [file join $temporaryDirectory $path]
}

namespace eval ::tcltest {
    namespace export wrongNumArgs tooManyArgs
    namespace export makeBinaryFile tempPath
}

# ### ### ### ######### ######### #########
return
