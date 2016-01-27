# -*- tcl -*- Copyright (c) 2012 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## Handle a tcltest-based testsuite

namespace eval ::kettle { namespace export testsuite }

kettle option define --constraints {
    Tcl list of constraints to activate.
} {} listsimple

kettle option define --file {
    Tcl list of glob patterns for test files to be run exclusively.
} * listsimple

kettle option define --limitconstraints {
    Contraint handling. When set run only tests with the active
    constraints (see -constraints).
} 0 boolean

kettle option define --tmatch {
    Tcl list of glob patterns.
    Run only the tests matching at least one of the patterns.
    Default is the * (match all), disabling the filter.
} * listsimple

kettle option define --notfile {
    Tcl list of glob patterns for test files to be skipped.
} {} listsimple

kettle option define --single {
    Run each test case completely independent.
} 0 boolean

kettle option define --tskip {
    Tcl list of glob patterns for tests to be skipped.
} {} listsimple

kettle option no-work-key --constraints
kettle option no-work-key --file
kettle option no-work-key --limitconstraints
kettle option no-work-key --tmatch
kettle option no-work-key --notfile
kettle option no-work-key --single
kettle option no-work-key --tskip

# # ## ### ##### ######## ############# #####################
## API.

proc ::kettle::testsuite {{testsrcdir tests}} {
    # Overwrite self, we run only once for effect.
    proc ::kettle::testsuite args {}

    # Heuristic search for testsuite
    # Aborts caller when nothing is found.
   lassign [path scan \
		{tcltest testsuite} \
		$testsrcdir \
		{path tcltest-file}] \
	root testsuite

    # Put the testsuite into recipes.

    recipe define test {
	Run the testsuite
    } {testsrcdir testsuite} {
	Test::SetupAnd Run $testsrcdir $testsuite
    } $root $testsuite

    recipe define testcases {
	Report the names of all test cases found in the testsuites.
    } {testsrcdir testsuite} {
	Test::SetupAnd Scan $testsrcdir $testsuite
    } $root $testsuite

    recipe define testcheck {
	Report all duplicate test case names.
    } {testsrcdir testsuite} {
	Test::SetupAnd Check $testsrcdir $testsuite
    } $root $testsuite

    return
}

# # ## ### ##### ######## ############# #####################
## Support code for the recipe.

namespace eval ::kettle::Test {
    namespace import ::kettle::path
    namespace import ::kettle::io
    namespace import ::kettle::status
    namespace import ::kettle::option
    namespace import ::kettle::strutil
    namespace import ::kettle::stream
    namespace import ::kettle::invoke

    # Map from testsuite states to readable labels. These include
    # trailing whitespace to align the following text vertically.
    variable statelabel {
	ok      {OK   }
	none    {None }
	aborted {Skip }
	error   {ERR  }
	fail    {FAILS}
    }
}

proc ::kettle::Test::SetupAnd {args} {
    # Note: We build and install the package under test (and its
    # dependencies) into a local directory (in the current working
    # directory). We try to install a debug variant first, and if that
    # fails a regular one.
    #
    # Note 2: If the user explicitly specified a location to build to
    # we use that, and do not clean it up aftre the test. This makes
    # it easy to investigate a core dump generated during test.

    if {[option userdefined --prefix]} {
	set tmp [option get --prefix]
	set cleanup 0
    } else {
	set tmp [path norm [path tmpfile test_install_]]
	path ensure-cleanup $tmp
	set cleanup 1
    }

    try {
	if {![invoke self debug   --prefix $tmp] &&
	    ![invoke self install --prefix $tmp]
	} {
	    status fail "Unable to generate local test installation"
	}

	{*}$args $tmp
    } finally {
	if {$cleanup} {
	    file delete -force $tmp
	}
    }

    return
}

proc ::kettle::Test::Run {srcdir testfiles localprefix} {
    # We are running each test file in a separate sub process, to
    # catch crashes, etc. ... We assume that the test file is self
    # contained in terms of loading all its dependencies, like
    # tcltest itself, utility commands it may need, etc. This
    # assumption allows us to run it directly, using our own
    # tcl executable as interpreter.

    # Translate kettle test options into tcltest options.
    set options {}
    foreach {o v} {
	constraints      constraints
	limitconstraints limitconstraints
	tmatch		 match		 
	tskip		 skip
	file		 file
	notfile		 notfile
    } {
	lappend options -$v [option get --$o]
    }

    stream to log ============================================================

    set main [path norm [option get @kettledir]/testmain.tcl]
    InitState

    # Generate map of padded test file names to ensure vertical
    # alignment of output across them.

    foreach t $testfiles {
	lappend short [file tail $t]
    }

    foreach t $testfiles pt [strutil padr $short] {
	dict set state fmap $t             $pt
	dict set state fmap [file tail $t] $pt
    }

    path in $srcdir {
	if {[option get --single]} {
	    dict set state singled 1 ;# Test::Summary

	    foreach test $testfiles {
		# change next to log/log
		#io note { io puts ${test}... }

		set cases [ScanFile $main $localprefix $test]

		# Per file initialization...
		dict set state suite/status ok
		#dict set state 

		dict set state numcases [llength $cases]
		dict set state xtotal   0
		dict set state xpassed  0
		dict set state xskipped 0
		dict set state xfailed  0

		foreach testcase $cases {
		    dict set state summary 0
		    dict incr state numcases -1

		    stream aopen
		    path pipe line {
			io trace {TEST: $line}
			ProcessLine $line
		    } [option get --with-shell] $main $localprefix \
			$test run {*}$options -match $testcase
		}
	    }
	} else {
	    dict set state singled 0 ;# Test::Summary

	    foreach test $testfiles {
		# change next to log/log
		#io note { io puts ${test}... }

		stream aopen

		# Per file initialization...
		dict set state summary 0
		dict set state suite/status ok
		#dict set state 

		path pipe line {
		    io trace {TEST: $line}
		    ProcessLine $line
		} [option get --with-shell] $main $localprefix \
		    $test run {*}$options
	    }
	}
    }

    # Summary results...
    # ... the numbers
    set fn [dict get $state cfailed]
    set en [dict get $state cerrors]
    set tn [dict get $state ctotal]
    set pn [dict get $state cpassed]
    set sn [dict get $state cskipped]

    # ... formatted
    set t $tn;#[format %6d $tn]
    set p [format %6d $pn]
    set s [format %6d $sn]
    set f [format %6d $fn]
    set e [format %6d $en]

    # ... and colorized where needed.
    if {$pn} { set p [io mgreen   $p] }
    if {$sn} { set s [io mblue    $s] }
    if {$fn} { set f [io mred     $f] }
    if {$en} { set e [io mmagenta $e] }

    # Show in terminal, always...
    stream term always "\nPassed  $p of $t"
    stream term always "Skipped $s of $t"
    stream term always "Failed  $f of $t"
    stream term always "#Errors $e"

    # And in the main stream...
    stream to log {Passed  $p of $t}
    stream to log {Skipped $s of $t}
    stream to log {Failed  $f of $t}
    stream to log {#Errors $e}

    stream to summary {[FormatTimings $state]}

    # Report ok/fail
    status [dict get $state status]
    return
}

proc ::kettle::Test::Scan {srcdir testfiles localprefix} {
    stream to log ============================================================

    set main [path norm [option get @kettledir]/testmain.tcl]

    # Generate map of padded test file names to ensure vertical
    # alignment of output across them.

    foreach t $testfiles {
	lappend short [file tail $t]
    }

    foreach t $testfiles pt [strutil padr $short] {
	dict set state fmap $t $pt
    }

    dict set state suite/status ok ;# for aclose
    set testcases {}
    path in $srcdir {
	foreach test $testfiles {
	    # change next to log/log
	    #io note { io puts ${test}... }

	    set cases [ScanFile $main $localprefix $test]

	    dict set state file $test ;# for aclose
	    set msg   "~~ [llength $cases]"
	    set test  [dict get $state fmap $test]
	    stream aopen
	    stream aextend "$test "
	    stream aclose $msg
	    stream to log {$test $msg}

	    lappend testcases {*}$cases
	}
    }

    set tn [llength $testcases]
    stream to log {\#Testcases $tn}

    # Report the found tests.    
    set testcases [join [lsort -dict $testcases] \n]

    if {![stream active]} {
	stream term always \n$testcases
    }
    stream to log       {$testcases}
    stream to testcases {$testcases}

    status ok
    return
}


proc ::kettle::Test::Check {srcdir testfiles localprefix} {
    stream to log ============================================================

    set main [path norm [option get @kettledir]/testmain.tcl]

    # Generate map of padded test file names to ensure vertical
    # alignment of output across them.

    foreach t $testfiles {
	lappend short [file tail $t]
    }

    foreach t $testfiles pt [strutil padr $short] {
	dict set state fmap $t $pt
    }

    dict set state suite/status ok ;# for aclose

    set testcases {}
    path in $srcdir {
	foreach test $testfiles {
	    # change next to log/log
	    #io note { io puts ${test}... }

	    set cases [ScanFile $main $localprefix $test]

	    dict set state file $test ;# for aclose
	    set msg   "~~ [llength $cases]"
	    set test  [dict get $state fmap $test]
	    stream aopen
	    stream aextend "$test "
	    stream aclose $msg
	    stream to log {$test $msg}

	    foreach c $cases {
		dict lappend testcases $c $test
	    }
	}
    }

    # Drop unique names, compress files recorded for duplicates
    dict for {c files} $testcases {
	if {[llength $files] < 2} {
	    dict unset testcases $c
	} else {
	    dict set testcases $c [lsort -unique $files]
	}
    }

    # Show the duplicates

    if {![stream active]} {
	stream term always "Duplicates: [dict size $testcases]"
    } 
    stream to log {Duplicates: [dict size $testcases]}

    if {[dict size $testcases]} {
	dict for {c files} $testcases {
	    if {![stream active]} { stream term always ${c}: }
	    stream to duplicates {$c}
	    stream to dupmap {$c}
	    foreach f $files {
		if {![stream active]} { stream term always "\t$f" }
		stream to dupmap {	$f}
	    }
	}
    }

    status ok
    return
}

proc ::kettle::Test::ScanFile {main localprefix testfile} {
    set tests {}
    path pipe line {
	set line [string trimright $line]
	io trace {TEST: $line}
	if {![string match {---- * DECL} $line]} continue
	set testname [string range $line 5 end-5]
	lappend tests $testname
    } [option get --with-shell] $main $localprefix $testfile scan
    return $tests
}

proc ::kettle::Test::FormatTimings {state} {
    # Extract data ...
    set times [dict get $state times]

    # Sort by shell and testsuite, re-package into tuples.
    set tmp {}
    foreach k [lsort -dict [dict keys $times]] {
	lassign $k                   shell suite
	lassign [dict get $times $k] ntests sec usec
	lappend tmp [list $shell $suite $ntests $sec $usec]
    }

    # Sort tuples by time per test, and transpose into
    # columns. Add the header and footer lines.

    lappend sh Shell     =====
    lappend ts Testsuite =========
    lappend nt Tests     =====
    lappend ns Seconds   =======
    lappend us uSec/Test =========

    foreach item [lsort -index 4 -decreasing $tmp] {
	lassign $item shell suite ntests sec usec
	lappend sh $shell
	lappend ts $suite
	lappend nt $ntests
	lappend ns $sec
	lappend us $usec
    }

    lappend sh =====
    lappend ts =========
    lappend nt =====
    lappend ns =======
    lappend us =========

    # Print the columns, each padded for vertical alignment.

    lappend lines \nTimings...
    foreach \
	shell  [strutil padr $sh] \
	suite  [strutil padr $ts] \
	ntests [strutil padr $nt] \
	sec    [strutil padr $ns] \
	usec   [strutil padr $us] {
	    lappend lines "$shell $suite $ntests $sec $usec"
	}

    return [join $lines \n]
}

proc ::kettle::Test::ProcessLine {line} {
    stream to rawlog {[string range $line 0 end-1]}

    # Counters and other state in the calling environment.
    upvar 1 state state

    # Capture of test failure in progress.
    # Take all lines, unprocessed.
    CaptureFailureSync            ; # cap/state: sync     => body
    CaptureFailureCollectBody     ; # cap/state: body     => actual|error|setup|cleanup|normal
    CaptureFailureCollectSetup    ; # cap/state: setup    => none
    CaptureFailureCollectCleanup  ; # cap/state: cleanup  => none
    CaptureFailureCollectActual   ; # cap/state: actual   => expected
    CaptureFailureCollectExpected ; # cap/state: expected => none
    CaptureFailureCollectError    ; # cap/state: error    => expected
    CaptureFailureCollectNormal   ; # cap/state: normal   => none

    # Capture of Tcl stack trace in progress.
    # Take all lines, unprocessed.
    CaptureStack

    # Start processing the input line for easier matching, and to
    # reduce the log.

    set line [string trimright $line]

    stream term full $line
    stream to log   {$line}

    set line [string trim $line]
    if {[string equal $line ""]} return

    # Recognize various parts written by the sub-shell and act on
    # them. If a line is recognized and acted upon the remaining
    # matchers are _not_ executed.

    Host;Platform;Cwd;Shell;Tcl
    Start;End
    Testsuite;NoTestsuite
    Support;Testing
    Summary

    TestStart;TestSkipped;TestPassed
    TestFailed        ; # cap/state => sync, see CaptureFailure* above
    CaptureStackStart ; # cap/stack => on,   see CaptureStaCK ABOVE

    Aborted
    AbortCause

    Match||Skip||Sourced

    # Unknown lines are simply shown (disturbing the animation, good
    # for this situation, actually), also saved for review.
    stream term compact !$line
    stream to unprocessed {$line}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::kettle::Test::InitState {} {
    upvar 1 state state
    # The counters are all updated in ProcessLine.
    # The status may change to 'fail' in ProcessLine.
    set state {
	ctotal   0
	cpassed  0
	cskipped 0
	cfailed  0
	cerrors  0

	status   ok

	host     {}
	platform {}
	cwd      {}
	shell    {}
	file     {}
	test     {}
	start    {}
	times    {}

	suite/status ok

	cap/state none
	cap/stack off
    }
    return
}

proc ::kettle::Test::Host {} {
    upvar 1 line line state state
    if {![regexp "^@@ Host (.*)$" $line -> host]} return
    #stream aextend $host
    #stream term compact "Host     $host"
    dict set state host $host
    # FUTURE: Write tests results to a storage back end for analysis.
    return -code return
}

proc ::kettle::Test::Platform {} {
    upvar 1 line line state state
    if {![regexp "^@@ Platform (.*)$" $line -> platform]} return
    #stream term compact "Platform $platform"
    dict set state platform $platform
    #stream aextend ($platform)
    return -code return
}

proc ::kettle::Test::Cwd {} {
    upvar 1 line line state state
    if {![regexp "^@@ TestCWD (.*)$" $line -> cwd]} return
    #stream term compact "Cwd      [path relativecwd $cwd]"
    dict set state cwd $cwd
    return -code return
}

proc ::kettle::Test::Shell {} {
    upvar 1 line line state state
    if {![regexp "^@@ Shell (.*)$" $line -> shell]} return
    #stream term compact "Shell    $shell"
    dict set state shell $shell
    #stream aextend [file tail $shell]
    return -code return
}

proc ::kettle::Test::Tcl {} {
    upvar 1 line line state state
    if {![regexp "^@@ Tcl (.*)$" $line -> tcl]} return
    #stream term compact "Tcl      $tcl"
    dict set state tcl $tcl
    stream aextend "\[$tcl\] "
    return -code return
}

proc ::kettle::Test::Match||Skip||Sourced {} {
    upvar 1 line line state state
    if {[string match "@@ TestDir*"               $line]} {return -code return}
    if {[string match "@@ LocalDir*"              $line]} {return -code return}
    if {[string match "@@ Skip*"                  $line]} {return -code return}
    if {[string match "@@ Match*"                 $line]} {return -code return}
    if {[string match "Sourced * Test Files."     $line]} {return -code return}
    if {[string match "Files with failing tests*" $line]} {return -code return}
    if {[string match "Number of tests skipped*"  $line]} {return -code return}
    if {[string match "\[0-9\]*"                  $line]} {return -code return}
    if {[string match "*error: test failed:*"     $line]} {return -code return}
    return
}

proc ::kettle::Test::Start {} {
    upvar 1 line line state state
    if {![regexp "^@@ Start (.*)$" $line -> start]} return
    #stream term compact "Start    [clock format $start]"
    dict set state start $start

    # Counters per test file. We use them in End to fake reasonable
    # summary information if the test file itself did not provide that
    # information.
    dict set state testnum  0
    dict set state testskip 0
    dict set state testpass 0
    dict set state testfail 0
    return -code return
}

proc ::kettle::Test::End {} {
    upvar 1 line line state state
    if {![regexp "^@@ End (.*)$" $line -> end]} return

    set start [dict get $state start]
    set shell [dict get $state shell]
    set file  [dict get $state file]
    set num   [dict get $state testnum]

    #stream term compact "Started  [clock format $start]"
    #stream term compact "End      [clock format $end]"

    set delta [expr {$end - $start}]
    if {$num == 0} {
	set score $delta
    } else {
	# Get average number of microseconds per test.
	set score [expr {int(($delta/double($num))*1000000)}]
    }

    set key [list $shell $file]
    dict lappend state times $key [list $num $delta $score]
    stream to timings {[list TIME $key $num $delta $score]}
    #variable xshell
    #sak::registry::local set $xshell End $end

    if {![dict get $state summary]} {
	 # We have to fake a summary, as the test file did not
	 # generate one. We use our own per-file counters to make a
	 # reasonable guess of the values. The code below works
	 # because the Summary processing in the caller, ProcessLine,
	 # is done this procedure. We manipulate the current line and
	 # then proceed as if we had not captured the current line,
	 # letting the Summary processing capture it.

	set t [dict get $state testnum]
	set s [dict get $state testskip]
	set p [dict get $state testpass]
	set f [dict get $state testfail]
	set line "Total $t Passed $p Skipped $s Failed $f"
	return
    }

    return -code return
}

proc ::kettle::Test::Testsuite {} {
    upvar 1 line line state state ; variable xfile
    if {![regexp "^@@ Testsuite (.*)$" $line -> file]} return
    #stream term compact "Test $file"
    dict set state file $file
    # map from full path to short, and padded for alignment.
    set padded [dict get $state fmap $file]
    stream aextend "$padded "
    return -code return
}

proc ::kettle::Test::NoTestsuite {} {
    upvar 1 line line state state
    if {![string match "Error:  No test files remain after*" $line]} return
    dict set state suite/status none
    stream aclose {No tests}
    return -code return
}

proc ::kettle::Test::Support {} {
    upvar 1 line line state state
    #stream awrite "S $package" /when caught
    #if {[regexp "^SYSTEM - (.*)$" $line -> package]} {stream term compact "Ss $package";return -code return}
    #if {[regexp "^LOCAL  - (.*)$" $line -> package]} {stream term compact "Sl $package";return -code return}
    if {[regexp "^SYSTEM - (.*)$" $line -> package]} {return -code return}
    if {[regexp "^LOCAL  - (.*)$" $line -> package]} {return -code return}
    return

}

proc ::kettle::Test::Testing {} {
    upvar 1 line line state state
    #stream awrite "T $package" /when caught
    #if {[regexp "^SYSTEM % (.*)$" $line -> package]} {stream term compact "Ts $package";return -code return}
    #if {[regexp "^LOCAL  % (.*)$" $line -> package]} {stream term compact "Tl $package";return -code return}
    if {[regexp "^SYSTEM % (.*)$" $line -> package]} {return -code return}
    if {[regexp "^LOCAL  % (.*)$" $line -> package]} {return -code return}
    return
}

proc ::kettle::Test::Summary {} {
    upvar 1 line line state state
    variable statelabel
    #stream term compact S?$line
    if {![regexp "(Total(.*)Passed(.*)Skipped(.*)Failed(.*))$" $line -> line]} return

    lassign [string trim $line] _ total _ passed _ skipped _ failed
    dict set state summary 1

    if {[dict get $state singled]} {
	set skipped 0
	if {!$passed && !$failed} { set skipped 1 }
	set total   1

	dict incr state xtotal   $total
	dict incr state xpassed  $passed
	dict incr state xskipped $skipped
	dict incr state xfailed  $failed

	set last [expr {[dict get $state numcases] == 0}]
	if {!$last} {
	    return -code return
	}

	set total   [dict get $state xtotal]
	set passed  [dict get $state xpassed]
	set skipped [dict get $state xskipped]
	set failed  [dict get $state xfailed]
    }

    dict incr state ctotal   $total
    dict incr state cpassed  $passed
    dict incr state cskipped $skipped
    dict incr state cfailed  $failed

    set total   [format %5d $total]
    set passed  [format %5d $passed]
    set skipped [format %5d $skipped]
    set failed  [format %5d $failed]

    set thestate [dict get $state suite/status]

    if {!$total && ($thestate eq "ok")} {
	dict set state suite/status none
	set thestate         none
    }

    set st [dict get $statelabel $thestate]

    if {$thestate eq "ok"} {
	# Quick return for ok suite.
	stream aclose "~~ [io mgreen $st] T $total P $passed S $skipped F $failed"
	return -code return
    }

    # Clean out progress display using a non-highlighted string.
    # Prevents the char count from being off. This is followed by
    # construction and display of the highlighted version.

    #stream awrite "   $st T $total P $passed S $skipped F $failed"
    switch -exact -- $thestate {
	none    { stream aclose "~~ [io myellow "$st T $total"] P $passed S $skipped F $failed" }
	aborted { stream aclose "~~ [io mwhite   $st] T $total P $passed S $skipped F $failed" }
	error   { stream aclose "~~ [io mmagenta $st] T $total P $passed S $skipped F $failed" }
	fail    { stream aclose "~~ [io mred     $st] T $total P $passed S $skipped [io mred "F $failed"]" }
    }

    if {$thestate eq "error"} { dict incr state cerrors }
    return -code return
}

proc ::kettle::Test::TestStart {} {
    upvar 1 line line state state
    if {![string match {---- * start} $line]} return
    set testname [string range $line 5 end-6]
    stream awrite "---- $testname"
    dict set state test $testname
    dict incr state testnum
    return -code return
}

proc ::kettle::Test::TestSkipped {} {
    upvar 1 line line state state
    if {![string match {++++ * SKIPPED:*} $line]} return
    regexp {^[^ ]* (.*)SKIPPED:.*$} $line -> testname
    set testname [string trim $testname]
    stream awrite "SKIP $testname"
    dict set state test {}
    dict incr state testskip
    return -code return
}

proc ::kettle::Test::TestPassed {} {
    upvar 1 line line state state
    if {![string match {++++ * PASSED} $line]} return
    set testname [string range $line 5 end-7]
    stream awrite "PASS $testname"
    dict set state test {}
    dict incr state testpass
    return -code return
}

proc ::kettle::Test::TestFailed {} {
    upvar 1 line line state state
    if {![string match {==== * FAILED} $line]} return
    set testname [lindex [split [string range $line 5 end-7]] 0]
    stream awrite "FAIL $testname"
    dict set state suite/status fail
    dict incr state testfail

    if {![dict exists $state test] ||
	([dict get $state test] eq {})} {
	# Required for tests which fail during -setup. These are not
	# reported as started, and TestStart above is never run for
	# them.
	dict set state test $testname
    }

    CaptureInit
    return -code return
}

proc ::kettle::Test::CaptureFailureSync {} {
    upvar 1 state state
    if {[dict get $state cap/state] ne "sync"} return
    upvar 1 line line
    if {![string match {==== Contents*} $line]} return
    CaptureNext body
    return -code return
}

proc ::kettle::Test::CaptureFailureCollectBody {} {
    upvar 1 state state
    if {[dict get $state cap/state] ne "body"} return

    upvar 1 line line
    if {[string match {---- Result was*} $line]} {
	CaptureNext actual
	return -code return
    } elseif {[string match {---- Test setup failed:*} $line]} {
	CaptureNext setup
	return -code return
    } elseif {[string match {---- Test cleanup failed:*} $line]} {
	CaptureNext cleanup
	return -code return
    } elseif {[string match {---- Test generated error*} $line]} {
	CaptureNext error
	return -code return
    } elseif {[string match {---- Test completed normally*} $line]} {
	CaptureNext normal
	return -code return
    }

    if {[string trim $line] ne {}} {
	dict update state cap c {
	    dict append c body $line
	}
    }

    return -code return
}

proc ::kettle::Test::CaptureFailureCollectSetup {} {
    upvar 1 state state
    if {[dict get $state cap/state] ne "setup"} return

    upvar 1 line line

    if {![string match {==== *} $line]} {
	dict update state cap c {
	    dict append c setup $line
	}
	return -code return
    }

    CaptureStop
    return -code return
}

proc ::kettle::Test::CaptureFailureCollectCleanup {} {
    upvar 1 state state
    if {[dict get $state cap/state] ne "cleanup"} return

    upvar 1 line line

    if {![string match {==== *} $line]} {
	dict update state cap c {
	    dict append c cleanup $line
	}
	return -code return
    }

    CaptureStop
    return -code return
}

proc ::kettle::Test::CaptureFailureCollectActual {} {
    upvar 1 state state
    if {[dict get $state cap/state] ne "actual"} return

    upvar 1 line line
    if {[string match {---- Result should*} $line]} {
	CaptureNext expected
	return -code return
    }

    dict update state cap c {
	dict append c actual $line
    }

    return -code return
}

proc ::kettle::Test::CaptureFailureCollectExpected {} {
    upvar 1 state state
    if {[dict get $state cap/state] ne "expected"} return

    upvar 1 line line
    if {![string match {==== *} $line]} {
	dict update state cap c {
	    dict append c expected $line
	}
	return -code return
    }

    CaptureStop
    return -code return
}

proc ::kettle::Test::CaptureFailureCollectNormal {} {
    upvar 1 state state
    if {[dict get $state cap/state] ne "normal"} return

    upvar 1 line line
    if {![string match {==== *} $line]} {
	dict update state cap c {
	    dict append c normal $line
	}
	return -code return
    }

    CaptureStop
    return -code return
}

proc ::kettle::Test::CaptureFailureCollectError {} {
    upvar 1 state state
    if {[dict get $state cap/state] ne "error"} return

    upvar 1 line line
    if {[string match {---- errorCode*} $line]} {
	CaptureNext expected
	return -code return
    }

    dict update state cap c {
	dict append c actual $line
    }
    return -code return
}

proc ::kettle::Test::CaptureInit {} {
    #upvar 1 line line ; stream to captrace {CAP/sync: $line}
    upvar 1 state state
    ## Initialize state machine to capture the test result.
    ## states: none, sync, body, actual, expected, done, error
    dict set state cap/state    sync
    dict set state cap actual   {}
    dict set state cap body     {}
    dict set state cap cleanup  {}
    dict set state cap expected {}
    dict set state cap setup    {}
    dict set state cap normal   {}
    return
}

proc ::kettle::Test::CaptureNext {new} {
    #upvar 1 line line ; stream to captrace {CAP/$new: $line}
    upvar 1 state state
    dict set state cap/state $new
    return
}

proc ::kettle::Test::CaptureStop {} {
    #upvar 1 line line ; stream to captrace {CAP/stop: $line}
    upvar 1 state state

    if {[stream active]} {
	set test     [dict get $state test]
	set body     [dict get $state cap body]
	set setup    [dict get $state cap setup]
	set cleanup  [dict get $state cap cleanup]
	set actual   [dict get $state cap actual]
	set expected [dict get $state cap expected]
	set normal   [dict get $state cap normal]

	stream to faildetails {}
	stream to faildetails {[string repeat = 60]}
	stream to faildetails {==== [lrange $test end-1 end]}
	stream to faildetails {==== Contents of test case:\n}
	stream to faildetails {$body}

	if {$actual ne {}} {
	    stream to faildetails {---- Result was:}
	    stream to faildetails {[string range $actual 0 end-1]}
	    stream to faildetails {---- Result should have been:}
	    stream to faildetails {[string range $expected 0 end-1]}
	    stream to faildetails {---- End\n}

	    set fname [string map {
		/ %2f
		: %3a
	    } $test]

	    stream to result.${fname}.expected {$expected}
	    stream to result.${fname}.actual   {$actual}
	}

	if {$setup ne {}} {
	    stream to faildetails {---- Test setup failed:}
	    stream to faildetails {[string range $setup 0 end-1]}
	}

	if {$cleanup ne {}} {
	    stream to faildetails {---- Test cleanup failed:}
	    stream to faildetails {[string range $cleanup 0 end-1]}
	}

	if {$normal ne {}} {
	    stream to faildetails {---- Test completed normally, expected error:}
	    stream to faildetails {[string range $normal 0 end-1]}
	}

	stream to faildetails {[string repeat = 60]}
    }

    dict unset state cap
    dict set   state cap/state none
    dict set   state test {}
    return
}

proc ::kettle::Test::CaptureStackStart {} {
    upvar 1 line line state state
    if {![string match {@+*} $line]} return

    dict set state cap/stack    on
    dict set state stack        {}
    dict set state suite/status error
    dict incr state cerrors

    stream aextend "[io mred {Caught Error}] "
    return -code return
}

proc ::kettle::Test::CaptureStack {} {
    upvar 1 state state
    if {![dict get $state cap/stack]} return
    upvar 1 line line

    if {![string match {@-*} $line]} {
	dict append state stack [string range $line 2 end]
	return -code return
    }

    if {[stream active]} {
	stream aextend ([io mblue {Stacktrace saved}])

	set file  [dict get $state file]
	set stack [dict get $state stack]

	stream to stacktrace {[lindex $file end] StackTrace}
	stream to stacktrace ========================================
	stream to stacktrace {$stack}
	stream to stacktrace ========================================\n\n
    } else {
	stream aextend "([io mred {Stacktrace not saved}]. [io mblue {Use --log}])"
    }

    dict set   state cap/stack off
    dict unset state stack

    stream aclose ""
    return -code return
}

proc ::kettle::Test::Aborted {} {
    upvar 1 line line state state
    if {![string match {Aborting the tests found *} $line]} return
    # Ignore aborted status if we already have it, or some other error
    # status (like error, or fail). These are more important to show.
    if {[dict get $state suite/status] eq "ok"} {
	dict set state suite/status aborted
    }
    stream aextend "[io mred Aborted:] "
    return -code return
}

proc ::kettle::Test::AbortCause {} {
    upvar 1 line line state state
    if {
	![string match {Requir*}    $line] &&
	![string match {Error in *} $line]
    } return ; # {}

    stream aclose $line
    return -code return
}

# # ## ### ##### ######## ############# #####################
return
