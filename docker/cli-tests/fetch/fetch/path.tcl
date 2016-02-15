# -*- tcl -*- Copyright (c) 2012-2013 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## Path utility commands.

namespace eval ::kettle::path {
    namespace export {[a-z]*}
    namespace ensemble create

    # unable to import kettle::option, circular dependency
    namespace import ::kettle::io
    namespace import ::kettle::status
}

# # ## ### ##### ######## ############# #####################
## API commands.

proc ::kettle::path::norm {path} {
    # full path normalization
    return [file dirname [file normalize $path/__]]
}

proc ::kettle::path::strip {path prefix} {
    return [file join \
		{*}[lrange \
			[file split [norm $path]] \
			[llength [file split [norm $prefix]]] \
			end]]
}

proc ::kettle::path::relativecwd {dst} {
    relative [pwd] $dst
}

proc ::kettle::path::relativesrc {dst} {
    relative [sourcedir] $dst
}

proc ::kettle::path::relative {base dst} {
    # Modified copy of ::fileutil::relative (tcllib)
    # Adapted to 8.5 ({*}).
    #
    #	Taking two _directory_ paths, a base and a destination, computes the path
    #	of the destination relative to the base.
    #
    # Arguments:
    #	base	The path to make the destination relative to.
    #	dst	The destination path
    #
    # Results:
    #	The path of the destination, relative to the base.

    # Ensure that the link to directory 'dst' is properly done relative to
    # the directory 'base'.

    if {[file pathtype $base] ne [file pathtype $dst]} {
	return -code error "Unable to compute relation for paths of different pathtypes: [file pathtype $base] vs. [file pathtype $dst], ($base vs. $dst)"
    }

    set base [norm $base]
    set dst  [norm $dst]

    set save $dst
    set base [file split $base]
    set dst  [file split $dst]

    while {[lindex $dst 0] eq [lindex $base 0]} {
	set dst  [lrange $dst  1 end]
	set base [lrange $base 1 end]
	if {![llength $dst]} {break}
    }

    set dstlen  [llength $dst]
    set baselen [llength $base]

    if {($dstlen == 0) && ($baselen == 0)} {
	# Cases:
	# (a) base == dst

	set dst .
    } else {
	# Cases:
	# (b) base is: base/sub = sub
	#     dst  is: base     = {}

	# (c) base is: base     = {}
	#     dst  is: base/sub = sub

	while {$baselen > 0} {
	    set dst [linsert $dst 0 ..]
	    incr baselen -1
	}
	set dst [file join {*}$dst]
    }

    return $dst
}

proc ::kettle::path::sourcedir {{path {}}} {
    return [norm [file join [kettle option get @srcdir] $path]]
}

proc ::kettle::path::script {} {
    return [norm [kettle option get @srcscript]]
}

proc ::kettle::path::libdir {{path {}}} {
    return [norm [file join [kettle option get --lib-dir] $path]]
}

proc ::kettle::path::bindir {{path {}}} {
    return [norm [file join [kettle option get --bin-dir] $path]]
}

proc ::kettle::path::incdir {{path {}}} {
    return [norm [file join [kettle option get --include-dir] $path]]
}

proc ::kettle::path::mandir {{path {}}} {
    return [norm [file join [kettle option get --man-dir] $path]]
}

proc ::kettle::path::htmldir {{path {}}} {
    return [norm [file join [kettle option get --html-dir] $path]]
}

proc ::kettle::path::set-executable {path} {
    io trace {	!chmod ugo+x   $path}
    dry-barrier
    catch {
	file attributes $path -permissions ugo+x
    }
    return
}

proc ::kettle::path::grep {pattern data} {
    return [lsearch -all -inline -glob [split $data \n] $pattern]
}

proc ::kettle::path::rgrep {pattern data} {
    return [lsearch -all -inline -regexp [split $data \n] $pattern]
}

proc ::kettle::path::fixhashbang {file shell} {
    dry-barrier

    set in [open $file r]
    gets $in line
    if {![string match "#!*tclsh*" $line]} {
	return -code error "No tclsh #! in $file"
    }

    io trace {	!fix hash-bang $shell}

    set   out [open ${file}.[pid] w]
    io puts $out "#!/usr/bin/env [norm $shell]"

    fconfigure $in  -translation binary -encoding binary
    fconfigure $out -translation binary -encoding binary
    fcopy $in $out
    close $in
    close $out

    file rename -force ${file}.[pid] $file
    return
}

proc ::kettle::path::add-top-comment {comment contents} {
    set r {}
    set done no
    foreach line [split $contents \n] {
	if {$done || [regexp "^\\s*\#.*$" $line]} {
	    lappend r $line
	    continue
	}
	lappend r $comment
	lappend r $line
	set done yes
    }
    join $r \n
}

proc ::kettle::path::tcl-package-file {file} {
    set contents   [cat $file]
    set provisions [grep {*package provide *} $contents]
    if {![llength $provisions]} {
	return 0
    }

    io trace {    Testing: [relativesrc $file]}

    foreach line $provisions {
	io trace {        Candidate |$line|}
	if {[catch {
	    lassign $line cmd method pn pv
	}]} {
	    io trace {        * Not a list}
	    continue
	}
	if {$cmd ne "package"} {
	    io trace {        * $cmd: Not a 'package' command}
	    continue
	}
	if {$method ne "provide"} {
	    io trace {        * $method: Not a 'package provide' command}
	    continue
	}
	if {[catch {package vcompare $pv 0}]} {
	    io trace {        * $pkgver: Not a version number}
	    continue
	}
	if {[llength [rgrep {package\s+require\s+critcl} $contents]]} {
	    io trace {        * critcl required: Not pure Tcl}
	    continue
	}

	io trace {    Accepted: $pn $pv @ [relativesrc $file]}

	lappend files [relativesrc $file]
	# Look for referenced dependent files.
	foreach line [grep {* @owns: *} $contents] {
	    if {![regexp {#\s+@owns:\s+(.*)$} $line -> path]} continue
	    lappend files $path
	}

	# For 'scan'.
	kettle option set @predicate [list $files $pn $pv]
	return 1
    }

    # No candidate satisfactory.
    return 0
}

proc ::kettle::path::critcl3-package-file {file} {
    set contents   [cat $file]
    set provisions [grep {*package provide *} $contents]
    if {![llength $provisions]} {
	return 0
    }

    io trace {    Testing: [relativesrc $file]}

    foreach line $provisions {
	io trace {        Candidate |$line|}
	if {[catch {
	    lassign $line cmd method pn pv
	}]} {
	    io trace {        * Not a list}
	    continue
	}
	if {$cmd ne "package"} {
	    io trace {        * $cmd: Not a 'package' command}
	    continue
	}
	if {$method ne "provide"} {
	    io trace {        * $method: Not a 'package provide' command}
	    continue
	}
	if {[catch {package vcompare $pv 0}]} {
	    io trace {        * $pkgver: Not a version number}
	    continue
	}

	# Nearly accepted. Now check if this file asks for critcl.

	if {![llength [rgrep {package\s+require\s+critcl\s+3} $contents]]} {
	    io trace {        * critcl 3: Not required}
	    continue
	}

	io trace {    Accepted: $pn $pv @ [relativesrc $file]}

	# For 'scan'.
	kettle option set @predicate [list $file $pn $pv]
	return 1
    }

    # No candidate satisfactory.
    return 0
}

proc ::kettle::path::doctools-file {path} {
    set test [cathead $path 1024 -translation binary]
    # anti marker
    if {[regexp -- {--- !doctools ---}            $test]} { return 0 }
    if {[regexp -- "!tcl\.tk//DSL doctools//EN//" $test]} { return 0 }
    # marker
    if {[regexp "\\\[manpage_begin "             $test]} { return 1 }
    if {[regexp -- {--- doctools ---}            $test]} { return 1 }
    if {[regexp -- "tcl\.tk//DSL doctools//EN//" $test]} { return 1 }
    # no usable marker
    return 0
}

proc ::kettle::path::diagram-file {path} {
    set test [cathead $path 1024 -translation binary]
    # marker
    if {[regexp {tcl.tk//DSL diagram//EN//1.0} $test]} { return 1 }
    # no usable marker
    return 0
}

proc ::kettle::path::tcltest-file {path} {
    set test [cathead $path 1024 -translation binary]
    # marker
    if {[regexp {tcl.tk//DSL tcltest//EN//} $test]} { return 1 }
    # no usable marker
    return 0
}

proc ::kettle::path::teapot-file {path} {
    set test [cathead $path 1024 -translation binary]
    # marker
    if {[regexp {tcl.tk//DSL teapot//EN//} $test]} { return 1 }
    # no usable marker
    return 0
}

proc ::kettle::path::bench-file {path} {
    set test [cathead $path 1024 -translation binary]
    # marker
    if {[regexp {tcl.tk//DSL tclbench//EN//} $test]} { return 1 }
    # no usable marker
    return 0
}

proc ::kettle::path::kettle-build-file {path} {
    set test [cathead $path 100 -translation binary]
    # marker (no anti-markers)
    if {[regexp {kettle -f} $test]} { return 1 }
    return 0
}

proc ::kettle::path::foreach-file {path pv script} {
    upvar 1 $pv thepath

    set ex [kettle option get --ignore-glob]

    set known {}
    lappend waiting $path
    while {[llength $waiting]} {
	set pending $waiting
	set waiting {}
	set at 0
	while {$at < [llength $pending]} {
	    set current [lindex $pending $at]
	    incr at

	    # Do not follow into parent.
	    if {[string match *.. $current]} continue

	    # Ignore what we have visited already.
	    set c [file dirname [file normalize $current/___]]
	    if {[dict exists $known $c]} continue
	    dict set known $c .

	    # Ignore non-development files.
	    if {[Ignore $ex $c]} continue

	    # Expand directories.
	    if {[file isdirectory $c]} {
		lappend waiting {*}[lsort -unique [glob -directory $c * .*]]
		continue
	    }

	    # Handle files as per the user's will.
	    set thepath $current
	    switch -exact -- [catch { uplevel 1 $script } result] {
		0 - 4 {
		    # ok, continue - nothing
		}
		2 {
		    # return, abort, rethrow
		    return -code return
		}
		3 {
		    # break, abort
		    return
		}
		1 - default {
		    # error, any thing else - rethrow
		    return -code error $result
		}
	    }
	}
    }
    return
}

proc ::kettle::path::scan {label root predicate} {
    set nroot [sourcedir $root]

    io trace {}
    io trace {SCAN $label @ [relativesrc $nroot]}

    if {![file exists $nroot]} {
	io trace {  NOT FOUND}
	return -code return
    }

    set result {}
    foreach-file $nroot path {
	set spath [strip $path $nroot]

	# General checking, outside of the custom predicates.
	# Skip core files: core, and core.\d+

	set n [file tail $spath]
	if {$n eq "core" || [regexp {^core\.\d+$} $n]} {
	    io trace {    SKIP core dump: $spath}
	    continue
	}

	try {
	    kettle option unset @predicate
	    if {![uplevel 1 [list {*}$predicate $path]]} continue

	    io trace {    Accepted: $spath}

	    if {[kettle option exists @predicate]} {
		lappend result {*}[kettle option get @predicate]
	    } else {
		lappend result $spath
	    }
	} on error {e o} {
	    io err { io puts "    Skipped: [relativesrc $path] @ $e" }
	} finally {
	    kettle option unset @predicate
	}
    }

    if {![llength $result]} { return -code return }

    return [list $nroot $result]
}

proc ::kettle::path::tmpfile {{prefix tmp_}} {
    global tcl_platform
    return .kettle_$prefix[pid]_[clock seconds]_[clock milliseconds]_[info hostname]_$tcl_platform(user)
}

proc ::kettle::path::tmpdir {} {
    # Taken from tcllib fileutil.
    global tcl_platform env

    set attempdirs [list]
    set problems   {}

    foreach tmp {TMPDIR TEMP TMP} {
	if { [info exists env($tmp)] } {
	    lappend attempdirs $env($tmp)
	} else {
	    lappend problems "No environment variable $tmp"
	}
    }

    switch $tcl_platform(platform) {
	windows {
	    lappend attempdirs "C:\\TEMP" "C:\\TMP" "\\TEMP" "\\TMP"
	}
	macintosh {
	    lappend attempdirs $env(TRASH_FOLDER)  ;# a better place?
	}
	default {
	    lappend attempdirs \
		[file join / tmp] \
		[file join / var tmp] \
		[file join / usr tmp]
	}
    }

    lappend attempdirs [pwd]

    foreach tmp $attempdirs {
	if { [file isdirectory $tmp] &&
	     [file writable $tmp] } {
	    return [file normalize $tmp]
	} elseif { ![file isdirectory $tmp] } {
	    lappend problems "Not a directory: $tmp"
	} else {
	    lappend problems "Not writable: $tmp"
	}
    }

    # Fail if nothing worked.
    return -code error "Unable to determine a proper directory for temporary files\n[join $problems \n]"
}

proc ::kettle::path::ensure-cleanup {path} {
    ::atexit [lambda {path} {
	file delete -force $path
    } [norm $path]]
}

proc ::kettle::path::cat {path args} {
    set c [open $path r]
    if {[llength $args]} { fconfigure $c {*}$args }
    set contents [read $c]
    close $c
    return $contents
}

proc ::kettle::path::cathead {path n args} {
    set c [open $path r]
    if {[llength $args]} { fconfigure $c {*}$args }
    set contents [read $c $n]
    close $c
    return $contents
}

proc ::kettle::path::write {path contents args} {
    set c [open $path w]
    if {[llength $args]} { fconfigure $c {*}$args }
    ::puts -nonewline $c $contents
    close $c
    return
}

proc ::kettle::path::write-append {path contents args} {
    set c [open $path a]
    if {[llength $args]} { fconfigure $c {*}$args }
    ::puts -nonewline $c $contents
    close $c
    return
}

proc ::kettle::path::write-prepend {path contents args} {
    set new [tmpfile tmp_prepend_]
    write-append $new $contents            {*}$args
    write-append $new [cat $path {*}$args] {*}$args

    file rename -force $new $path
    return
}

proc ::kettle::path::write-modify {path cmdprefix args} {
    set new [tmpfile tmp_modify_]
    write $new [{*}$cmdprefix [cat $path {*}$args]] {*}$args

    file rename -force $new $path
    return
}

proc ::kettle::path::copy-file {src dstdir} {
    # Copy single file into destination _directory_
    # Fails goal on an existing file.

    io puts -nonewline "\tInstalling file \"[file tail $src]\": "

    dry-barrier

    if {[catch {
	file mkdir $dstdir
	file copy $src $dstdir/[file tail $src]
    } msg]} {
	io err { io puts "FAIL ($msg)" }
	status fail "FAIL ($msg)"
    } else {
	io ok { io puts OK }
    }
}

proc ::kettle::path::copy-files {dstdir args} {
    # Copy multiple files into a destination _directory_
    # Fails goal on an existing file.
    foreach src $args {
	copy-file $src $dstdir
    }
    return
}

proc ::kettle::path::remove-path {base path} {
    # General uninstallation of a file or directory.

    io puts -nonewline "\tUninstalling \"[relative $base ${path}]\": "

    dry-barrier

    if {[catch {
	file delete -force $path
    } msg]} {
	io err { io puts "FAIL ($msg)" }
	status fail
    } else {
	io ok { io puts OK }
    }
}

proc ::kettle::path::remove-paths {base args} {
    # General uninstallation of multiple files.
    foreach path $args {
	remove-path $base $path
    }
    return
}

proc ::kettle::path::install-application {src dstdir} {
    # Install single-file application into destination _directory_.
    # a previously existing file is moved out of the way.

    set fname [file tail $src]
    io puts "Installing application \"$fname\""
    io puts "    Into [relativesrc $dstdir]"

    dry-barrier {
	# Simulated run, has its own dry-barrier.
	copy-file $src $dstdir
    }

    # Save existing file, if any.
    file delete -force $dstdir/${fname}.old
    catch {
	file rename $dstdir/${fname} $dstdir/${fname}.old
    }

    try {
	copy-file $src $dstdir
    } trap {KETTLE STATUS FAIL} {e o} {
	# Failed, restore previous, if any.
	catch {
	    file rename $dstdir/${fname}.old $dstdir/${fname}
	}
	return {*}$o $e
    }

    set-executable $dstdir/$fname
    return
}

proc ::kettle::path::install-script {src dstdir shell {cmd {}}} {
    # Install single-file script application into destination _directory_.
    # a previously existing file is moved out of the way.

    set fname [file tail $src]

    io puts "Installing script \"$fname\""
    io puts "    Into [relativesrc $dstdir]"

    dry-barrier {
	# Simulated run, has its own dry-barrier.
	copy-file $src $dstdir
    }

    # Save existing file, if any.
    file mkdir $dstdir
    file delete -force $dstdir/${fname}.old
    catch {
	file rename $dstdir/${fname} $dstdir/${fname}.old
    }

    try {
	copy-file $src $dstdir
    } trap {KETTLE STATUS FAIL} {e o} {
	# Failed, restore previous, if any.
	catch {
	    file rename $dstdir/${fname}.old $dstdir/${fname}
	}

	return {*}$o $e
    }

    if {[llength $cmd]} {
	{*}$cmd $dstdir/$fname
    }

    fixhashbang    $dstdir/$fname $shell
    set-executable $dstdir/$fname
    return
}

proc ::kettle::path::install-file-group {label dstdir args} {
    # Install multiple files into a destination directory.
    # The destination is created to hold the files. The files
    # are strongly coupled, i.e. belong together.

    io puts "Installing $label"
    io puts "    Into [relativesrc $dstdir]"

    dry-barrier {
	# Simulated installation (has its own dry-barrier).
	copy-files $dstdir {*}$args
    }

    set new ${dstdir}-new
    set old ${dstdir}-old

    # Clean temporary destination. Remove left-overs from previous runs.
    file delete -force $new
    file mkdir         $new

    try {
	copy-files $new {*}$args
    } trap {KETTLE STATUS FAIL} {e o} {
	file delete -force $new
	return {*}$o $e
    }

    # Now shuffle old and new things around to put the new into place.
    io puts -nonewline {    Commmit: }
    if {[catch {
	file delete -force $old
	catch { file rename $dstdir $old }
	file rename -force $new $dstdir
	file delete -force $old
    } msg]} {
	io err { io puts "FAIL ($msg)" }
	status fail
    } else {
	io ok { io puts OK }
    }
    return
}

proc ::kettle::path::install-file-set {label dstdir args} {
    # Install multiple files into a destination directory.
    # The destination has to exist. The files in the set
    # are only loosely coupled. Example: manpages.

    io puts "Installing $label"
    io puts "    Into [relativesrc $dstdir]"

    ## Consider removal of existing files ...
    ## Except, for manpages we want to be informed of clashes.
    ## for others it might make sense ...

    copy-files $dstdir {*}$args
    return
}

proc ::kettle::path::uninstall-application {src dstdir} {
    set fname [file tail $src]

    io puts "Uninstall application \"$fname\""
    io puts "    From [relativesrc $dstdir]"

    remove-path $dstdir $dstdir/$fname
    return
}

proc ::kettle::path::uninstall-file-group {label dstdir} {
    io puts "Uninstalling $label"
    io puts "    From [relativesrc [file dirname $dstdir]]"

    remove-path [file dirname $dstdir] $dstdir
    return
}

proc ::kettle::path::uninstall-file-set {label dstdir args} {
    # Install multiple files into a destination directory.
    # The destination has to exist. The files in the set
    # are only loosely coupled. Example: manpages.

    io puts "Uninstalling $label"
    io puts "    From [relativesrc $dstdir]"

    ## Consider removal of existing files ...
    ## Except, for manpages we want to be informed of clashes.
    ## for others it might make sense ...

    foreach f $args {
	remove-path $dstdir $dstdir/$f
    }
    return
}

proc ::kettle::path::exec {args} {
    pipe line {
	# line ends in \n, except possibly at eof.
	io puts -nonewline $line
    } {*}$args
    return
}

proc ::kettle::path::pipe {lv script args} {
    upvar 1 $lv line
    set stderr [tmpfile pipe_stderr_]
    ensure-cleanup $stderr

    io trace {  PIPE: [T $args]}

    if {[kettle option get --dry]} return

    set err {}
    set pipe [open "|$args 2> $stderr" r]
    fconfigure $pipe -translation lf

    try {
	while {![eof $pipe]} {
	    if {[gets $pipe line] < 0} continue
	    if {![eof $pipe]} {
		append line \n
	    }
	    try {
		uplevel 1 $script
	    } trap {KETTLE} {e o} {
		# Rethrow internal signals.
		# No report, not a true error.
		return {*}$o $e
	    } on error {e o} {
		io err { io puts $e }
		break
	    }
	}
    } finally {
	try {
	    close $pipe
	} on error {e o} {
	    io err { io puts $e }
	}

	set err [cat $stderr]
	file delete $stderr
    }

    if {$err eq {}} return
    io err { io puts $err }
    return
}

proc ::kettle::path::in {path script} {
    set here [pwd]
    try {
	cd $path
	uplevel 1 $script
    } finally {
	cd $here
    }
}

proc ::kettle::path::scanup {path cmd} {
    io trace {scan up $path ($cmd)}

    set path [file normalize $path]
    while {1} {
	io trace {    testing $path}

	# Found the proper directory, per the predicate.
	if {[{*}$cmd $path]} { return $path }

	# Not found, walk to parent
	set new [file dirname $path]

	# Stop when reaching the root.
	if {$new eq $path} { return {} }
	if {$new eq {}} { return {} }

	# Ok, truly walk up.
	set path $new
    }
    return {}
}

# # ## ### ##### ######## ############# #####################
## Repository type detection, extraction of current revision, ...

proc ::kettle::path::find.git {path} {
    scanup $path ::kettle::path::is.git
}

proc ::kettle::path::find.fossil {path} {
    scanup $path ::kettle::path::is.fossil
}

proc ::kettle::path::revision.git {path} {
    in $path {
	set v [::exec {*}[auto_execok git] describe]
    }
    return [string trim $v]
}

proc ::kettle::path::revision.fossil {path} {
    in $path {
	set info [::exec {*}[auto_execok fossil] info]
    }
    return [lindex [grep {checkout:*} $info] 0 1]
}

proc ::kettle::path::is.git {path} {
    set control $path/.git
    expr {[file exists $control] && [file isdirectory $control]}
}

proc ::kettle::path::is.fossil {path} {
    foreach control {
	_FOSSIL_
	.fslckout
	.fos
    } {
	set control $path/$control
	if {[file exists $control] && [file isfile $control]} {return 1}
    }
    return 0
}

# # ## ### ##### ######## ############# #####################
## Internal

proc ::kettle::path::dry-barrier {{dryscript {}}} {
    if {![kettle option get --dry]} return
    # dry run: notify, ... 
    if {$dryscript eq {}} {
	io cyan { io puts {!dry run!} }
    } else {
	uplevel 1 $dryscript
    }
    # ... and abort caller.
    return -code return
}

proc ::kettle::path::T {words} {
    set r {}
    foreach w $words {
	if {[file exists $w]} {
	    set w [relativecwd [norm $w]]
	}
	lappend r $w
    }
    return $r
}

proc ::kettle::path::Ignore {patterns path} {
    set path [file tail $path]
    foreach p $patterns {
	if {[string match $p $path]} { return 1 }
    }
    return 0
}

# # ## ### ##### ######## ############# #####################
return
