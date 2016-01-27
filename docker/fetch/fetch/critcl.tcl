# -*- tcl -*- Copyright (c) 2012 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## Handle critcl based packages.

namespace eval ::kettle { namespace export critcl3 }

kettle option define --target {
    Critcl build option. Overrides critcl's choice of target
    configuration.
}

# # ## ### ##### ######## ############# #####################
## Locate a suitable critcl package or application (3+),
## and prepare system for its use.

if {![catch {
    package require critcl::app 3

    proc ::critcl::print {args} {
	#puts <<<$args>>>
	#return

	# Intercept all critcl output.
	# Available since critcl 3.1.7.
	# No harm if not available.

	switch -exact -- [llength $args] {
	    1 {
		# print text
		set m [lindex $args 0]
		puts  stdout [::kettle::CI stdout $m 1]
		flush stdout
	    }
	    2 {
		lassign $args detail m
		if {$detail ne "-nonewline"} {
		    # print chan text
		    puts $detail [::kettle::CI $detail $m 1]
		} else {
		    # print -nonewline text
		    puts -nonewline stdout [::kettle::CI stdout $m 0]
		    flush stdout
		}
	    }
	    3 {
		# print -nonewline chan text
		lassign $args o chan m
		if {$o ne "-nonewline"} {
		    return -code error "wrong\#args, expected: ?-nonewline? ?chan? msg"
		}
		puts -nonewline $chan [::kettle::CI $chan $m 0]
		flush stdout
	    }
	    default {
		return -code error "wrong\#args, expected: ?-nonewline? msg"
	    }
	}
	return
    }

    # Actual transformer for the interceptor.
    set ::kettle::startofline { stdout 1 stderr 1 }
    proc ::kettle::CI {chan text newsol} {
	variable startofline ; # dict: chan -> flag
	set sol [dict get $startofline $chan]
	if {[string match *\n $text]} {
	    set newsol 1
	}
	set result {}
	foreach line [split $text \n] {
	    if {$sol && [string match Warning* $line]} {
		set line [io mmagenta $line]
	    }
	    #if {$sol} { set line "CRITCL: $line" }
	    lappend result $line
	    set sol 1
	}

	dict set startofline $chan $newsol
	return [join $result \n]
    }
}]} {
    kettle option set @critcl internal
} else {
    kettle option set @critcl external

    kettle tool declare {
	    critcl3 critcl3.kit critcl3.tcl critcl3.exe
	    critcl critcl.kit critcl.tcl critcl.exe
    } {
	# Implied argument: cmd
	# Implied argument: msgvar
	upvar 1 $msgvar msg

	# Proper native path needed, especially on windows. On windows
	# this also works (best) with a starpack for critcl, instead
	# of a starkit.

	#set cmd [file nativename [lindex $cmd 0]]
	# -- Apparently windows is ok with the path I have, and the
	# -- native path actually fails to be executed.
	set cmd [lindex $cmd 0]

	# Ignore applications which are too old to support
	# -v|--version, or are too old as per their returned
	# version.
	if {[catch {
	    set v [exec {*}$cmd --version]
	} msg]} { return 0 }
	if {[package vcompare $v 3] < 0} {
	    set msg "Have $v, require 3"
	    return 0
	}
	return 1
    }
}

# # ## ### ##### ######## ############# #####################
## API.

proc ::kettle::critcl3 {} {

    # Heuristic search for documentation, testsuites, benchmarks.
    doc
    testsuite
    benchmarks

    # Heuristic search for critcl packages to install, collect names,
    # versions, and files.  Aborts caller when nothing is found.
    lassign [path scan \
		 {critcl 3 packages}\
		 [path sourcedir] \
		 {path critcl3-package-file}] \
	root packages

    foreach {file pn pv} $packages {
	CritclSetup $root $file $pn $pv
    }
    return
}

# # ## ### ##### ######## ############# #####################
## Helper commands.

proc ::kettle::CritclSetup {root file pn pv} {

    set pkgdir [path libdir [string map {:: _} $pn]$pv]

    recipe define install-package-$pn "Install package $pn $pv" {pkgdir root file pn pv} {

	if {[option exists @dependencies]} {
	    invoke @dependencies install
	}

	set t [option get --target]
	if {$t ne {}} { lappend cmd -target $t }

	lappend cmd -includedir [path incdir]
	lappend cmd -pkg $file

	set pnc [file rootname [file tail $file]]

	CritclDo $pkgdir $root $pnc $pn $pv {*}$cmd
    } $pkgdir $root $file $pn $pv

    recipe define debug-package-$pn "Install debug-built package $pn $pv" {pkgdir root file pn pv} {
	if {[option exists @dependencies]} {
	    invoke @dependencies debug
	}

	set t [option get --target]
	if {$t ne {}} { lappend cmd -target $t }

	lappend cmd -debug      all
	lappend cmd -keep
	lappend cmd -includedir [path incdir]
	lappend cmd -pkg $file

	set pnc [file rootname [file tail $file]]

	CritclDo $pkgdir $root $pnc $pn $pv {*}$cmd
    } $pkgdir $root $file $pn $pv

    recipe define uninstall-package-$pn "Uninstall package $pn $pv" {pkgdir pn pv} {
	path uninstall-file-group "package $pn $pv" $pkgdir
    } $pkgdir $pn $pv

    recipe define reinstall-package-$pn "Reinstall package $pn $pv" {pn} {
	invoke self uninstall-package-$pn
	invoke self install-package-$pn
    } $pn

    recipe parent install-package-$pn     install-binary-packages
    recipe parent install-binary-packages install-packages
    recipe parent install-packages        install

    recipe parent debug-package-$pn     debug-binary-packages
    recipe parent debug-binary-packages debug-packages
    recipe parent debug-packages        debug

    recipe parent uninstall-package-$pn     uninstall-binary-packages
    recipe parent uninstall-binary-packages uninstall-packages
    recipe parent uninstall-packages        uninstall

    recipe parent reinstall-package-$pn     reinstall-binary-packages
    recipe parent reinstall-binary-packages reinstall-packages
    recipe parent reinstall-packages        reinstall

    # critcl specific target
    # - Wrap the critcl package into a regular TEA-based buildsystem.

    set pkgdir [path norm [string map {:: _} $pn]$pv-tea]

    recipe define wrap4tea-$pn "Wrap TEA around package $pn $pv" {pkgdir root file pn pv} {
	set pnc [file rootname [file tail $file]]

	CritclDo $pkgdir $root $pnc $pn $pv -tea $file
    } $pkgdir $root $file $pn $pv

    recipe parent wrap4tea-$pn wrap4tea
    return
}

proc ::kettle::CritclDo {pkgdir root pnc pn pv args} {
    set cache [path norm BUILD-$pnc$pv]
    set tmp   [path norm TMP-$pnc$pv/lib]

    file delete -force $cache
    set args [list -cache $cache -libdir $tmp {*}$args]

    path in $root {
	try {
	    CritclRun $args
	} on ok {e o} {
	    if {![option get --dry]} {
		if {![file exists $tmp/$pnc]} {
		    status fail
		} else {
		    path install-file-group "package $pn $pv" \
			$pkgdir \
			{*}[glob -directory $tmp/$pnc *]
		}
	    }
	} finally {
	    if {![option get --dry]} {
		file delete -force [file dirname $tmp]
	    }
	}
    }
    return
}

proc ::kettle::CritclRun {cmd} {
    io trace {  critcl [path::T $cmd]}
    if {[option get --dry]} return

    io puts {}
    if {[option get @critcl] eq "internal"} {
	io trace {  critcl: internal}
	io trace {[package ifneeded critcl::app [package present critcl::app]]}

	critcl::app::main $cmd
    } else {
	io trace {  critcl: external}
	path pipe line {
	    if {[string match Warning* $line]} {
		set line [io mmagenta $line]
	    }
	    # line ends in \n, except possibly at eof.
	    io puts -nonewline $line
	} {*}[tool get critcl3] {*}$cmd
    }
    return
}

# # ## ### ##### ######## ############# #####################
return
