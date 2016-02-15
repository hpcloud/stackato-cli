# -*- tcl -*- Copyright (c) 2012 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## Handle a tclbench-based benchmarks

# # ## ### ##### ######## ############# #####################
## Repetition setting. Number of repeats (beyond the regular run)
## to perform. Default 0. Positive integer.
## Irrelevant to work database keying.

kettle option define --repeats {
    Number of repeats to perform per bench file.
    (Number of runs is 1 + repeats).
} 0 {range 0 Inf}
kettle option no-work-key --repeats

# # ## ### ##### ######## ############# #####################
## Iterations setting. Number of iterations to run for a benchmark, if
## not overriden by the benchmark itself. Default 1000. Positive,
## non-zero integer.
## Irrelevant to work database keying.

kettle option define --iters {
    Number of iterations to perform per benchmark.
} 1000 {range 1 Inf}
kettle option no-work-key --repeats

# # ## ### ##### ######## ############# #####################
## Collation setting. How to coalesce the data from several
## repeats into a single number.
## Irrelevant to work database keying.

kettle option define --collate {
    Method for coalescing the data from multiple runs (repeats > 0).
} min {enum {min max avg}}
kettle option no-work-key --collate

# # ## ### ##### ######## ############# #####################
## Filter settings to select which benchmarks to run.
## Irrelevant to work database keying.
#
# Note: If both --match and --rmatch are specified then _both_
# apply. I.e. a benchmark will be run if and only if it matches both
# patterns.

kettle option define --match {
    Run only benchmarks matching the glob pattern.
    Default is the empty string, disabling the filter.
} {} string
kettle option no-work-key --match

kettle option define --rmatch {
    Run only tests matching the regexp pattern.
    Default is the empty string, disabling the filter.
} {} string
kettle option no-work-key --rmatch

# # ## ### ##### ######## ############# #####################

namespace eval ::kettle { namespace export benchmarks }

# # ## ### ##### ######## ############# #####################
## API.

proc ::kettle::benchmarks {{benchsrcdir bench}} {
    # Overwrite self, we run only once for effect.
    proc ::kettle::benchmarks args {}

    # Heuristic search for benchmarks
    # Aborts caller when nothing is found.
   lassign [path scan \
		{tclbench benchmarks} \
		$benchsrcdir \
		{path bench-file}] \
	root benchmarks

    # Put the benchmarks into recipes.

    recipe define bench {
	Run the benchmarks
    } {benchsrcdir benchmarks} {
	# Note: We build and install the package under profiling (and
	# its dependencies) into a local directory (in the current
	# working directory). We try to install a debug variant first,
	# and if that fails a regular one.
	#
	# Note 2: If the user explicitly specified a location to build
	# to we use that, and do not clean it up aftre the test. This
	# makes it easy to investigate a core dump generated during
	# test.

	if {[option userdefined --prefix]} {
	    set tmp [option get --prefix]
	    set cleanup 0
	} else {
	    set tmp [path norm [path tmpfile bench_install_]]
	    path ensure-cleanup $tmp
	    set cleanup 1
	}

	try {
	    if {![invoke self debug   --prefix $tmp] &&
		![invoke self install --prefix $tmp]
	    } {
		status fail "Unable to generate local benchmark installation"
	    }

	    Bench::Run $benchsrcdir $benchmarks $tmp
	} finally {
	    if {$cleanup} {
		file delete -force $tmp
	    }
	}
    } $root $benchmarks

    return
}

# # ## ### ##### ######## ############# #####################
## Support code for the recipe.

namespace eval ::kettle::Bench {
    namespace import ::kettle::path
    namespace import ::kettle::io
    namespace import ::kettle::status
    namespace import ::kettle::option
    namespace import ::kettle::strutil
    namespace import ::kettle::stream
}

proc ::kettle::Bench::Run {srcdir benchfiles localprefix} {
    # We are running each bench file in a separate sub process, to
    # catch crashes, etc. ... We assume that the bench file is self
    # contained in terms of loading all its dependencies, like
    # tclbench itself, utility commands it may need, etc. This
    # assumption allows us to run it directly, using our own
    # tcl executable as interpreter.

    stream to log ============================================================

    set main [path norm [option get @kettledir]/benchmain.tcl]
    InitState

    # Generate map of padded bench file names to ensure vertical
    # alignment of output across them.

    foreach b $benchfiles {
	lappend short [file tail $b]
    }

    foreach b $benchfiles pb [strutil padr $short] {
	dict set state fmap $b $pb
    }

    set repeats [option get --repeats]

    # Filter and other settings for the child process.
    lappend bconfig MATCH    [option get --match]
    lappend bconfig RMATCH   [option get --rmatch]
    lappend bconfig ITERS    [option get --iters]
    lappend bconfig prefix   $localprefix

    path in $srcdir {
	foreach bench $benchfiles {
	    stream aopen

	    for {set round 0} {$round <= $repeats} {incr round} {
		dict set state round $round

		path pipe line {
		    io trace {BENCH: $line}
		    ProcessLine $line
		} [option get --with-shell] $main $bconfig [path norm $bench]
	    }
	}
    }

    # Summary results...
    stream to summary  {[FormatTimings $state]}

    set fr [FormatResults $state]\n
    stream term always  $fr
    stream to summary {$fr}

    # Report ok/fail
    status [dict get $state status]
    return
}

proc ::kettle::Bench::FormatTimings {state} {
    # Extract data ...
    set times [dict get $state times]

    # Sort by shell and benchmark, re-package into tuples.
    set tmp {}
    foreach k [lsort -dict [dict keys $times]] {
	lassign $k                   shell suite
	lassign [dict get $times $k] nbench sec usec
	lappend tmp [list $shell $suite $nbench $sec $usec]
    }

    # Sort tuples by time per benchmark, and transpose into
    # columns. Add the header and footer lines.

    lappend sh Shell      =====
    lappend ts Benchsuite ==========
    lappend nb Benchmarks ==========
    lappend ns Seconds    =======
    lappend us uSec/Bench ==========

    foreach item [lsort -index 4 -decreasing $tmp] {
	lassign $item shell suite nbench sec usec
	lappend sh $shell
	lappend ts $suite
	lappend nb $nbench
	lappend ns $sec
	lappend us $usec
    }

    lappend sh =====
    lappend ts ==========
    lappend nb ==========
    lappend ns =======
    lappend us ==========

    # Print the columns, each padded for vertical alignment.

    lappend lines \nTimings...
    foreach \
	shell  [strutil padr $sh] \
	suite  [strutil padr $ts] \
	nbench [strutil padr $nb] \
	sec    [strutil padr $ns] \
	usec   [strutil padr $us] {
	    lappend lines "$shell $suite $nbench $sec $usec"
	}

    return [join $lines \n]
}

proc ::kettle::Bench::FormatResults {state} {
    # Extract data ...
    set results [dict get $state results]

    # results = dict (key -> list(time))
    # key = list (shell ver benchfile description)
    # [no round information, implied in the list of results]

    # Sort by description, re-package into tuples.
    set tmp {}
    foreach k [lsort -dict -index 3 [dict keys $results]] {
	set d [lindex $k 3]
	set t [dict get $results $k]
	set t [Collate_[option get --collate] $t]
	lappend tmp [list $d $t]
    }

    # Transpose into columns. Add the header and footer lines.
    lappend ds Description ===========
    lappend ts Time        ====

    foreach item $tmp {
	lassign $item d t
	lappend ds $d
	lappend ts $t
    }

    lappend ds =========== Description
    lappend ts ====	   Time

    # Print the columns, each padded for vertical alignment.

    lappend lines \nResults...
    foreach \
	d  [strutil padr $ds] \
	t  [strutil padr $ts] {
	    lappend lines "$d $t"
	}

    return \t[join $lines \n\t]
}

proc ::kettle::Bench::Collate_min {times} {
    foreach v [lassign $times min] {
	# TODO: skip non-numeric times
	if {$v >= $min} continue
	set min $v
    }
    return $min
}

proc ::kettle::Bench::Collate_max {times} {
    foreach v [lassign $times max] {
	# TODO: skip non-numeric times
	if {$v <= $max} continue
	set max $v
    }
    return $max
}

proc ::kettle::Bench::Collate_avg {times} {
    set total 0.0
    foreach v $times {
	# TODO: skip non-numeric times
	set total [expr {$total + $v}]
	incr n
    }
    return [expr { $total / $n }]
}

proc ::kettle::Bench::ProcessLine {line} {
    # Counters and other state in the calling environment.
    upvar 1 state state

    set line [string trimright $line]

    if {![string match {@@ Progress *} $line]} {
	stream term full $line
	stream to log   {$line}
    }

    set rline $line
    set line [string trim $line]
    if {[string equal $line ""]} return

    # Recognize various parts written by the sub-shell and act on
    # them. If a line is recognized and acted upon the remaining
    # matchers are _not_ executed.

    Host;Platform;Cwd;Shell;Tcl
    Start;End;Benchmark
    Support;Benching

    CaptureStackStart
    CaptureStack

    BenchLog;BenchSkipped;BenchStart;BenchTrack;BenchResult

    Aborted
    AbortCause

    Misc

    # Unknown lines are simply shown (disturbing the animation, good
    # for this situation, actually), also saved for review.
    stream term compact !$line
    stream to unprocessed {$line}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::kettle::Bench::InitState {} {
    upvar 1 state state
    # The counters are all updated in ProcessLine.
    # The status may change to 'fail' in ProcessLine.
    set state {
	cerrors  0
	status   ok

	host     {}
	platform {}
	cwd      {}
	shell    {}
	file     {}
	bench    {}
	start    {}
	times    {}
	results  {}

	suite/status ok

	cap/state none
	cap/stack off
    }
    return
}

proc ::kettle::Bench::Host {} {
    upvar 1 line line state state
    if {![regexp "^@@ Host (.*)$" $line -> host]} return
    #stream aextend $host
    #stream term compact "Host     $host"
    dict set state host $host
    # FUTURE: Write bench results to a storage back end for analysis.
    return -code return
}

proc ::kettle::Bench::Platform {} {
    upvar 1 line line state state
    if {![regexp "^@@ Platform (.*)$" $line -> platform]} return
    #stream term compact "Platform $platform"
    dict set state platform $platform
    #stream aextend ($platform)
    return -code return
}

proc ::kettle::Bench::Cwd {} {
    upvar 1 line line state state
    if {![regexp "^@@ BenchCWD (.*)$" $line -> cwd]} return
    #stream term compact "Cwd      [path relativecwd $cwd]"
    dict set state cwd $cwd
    return -code return
}

proc ::kettle::Bench::Shell {} {
    upvar 1 line line state state
    if {![regexp "^@@ Shell (.*)$" $line -> shell]} return
    #stream term compact "Shell    $shell"
    dict set state shell $shell
    #stream aextend [file tail $shell]
    return -code return
}

proc ::kettle::Bench::Tcl {} {
    upvar 1 line line state state
    if {![regexp "^@@ Tcl (.*)$" $line -> tcl]} return
    #stream term compact "Tcl      $tcl"
    dict set state tcl $tcl
    stream aextend "\[$tcl\] "
    return -code return
}

proc ::kettle::Bench::Misc {} {
    upvar 1 line line state state
    if {[string match "@@ BenchDir*" $line]} {return -code return}
    if {[string match "@@ LocalDir*" $line]} {return -code return}
    if {[string match "@@ Match*"    $line]} {return -code return}
    return
}

proc ::kettle::Bench::Start {} {
    upvar 1 line line state state
    if {![regexp "^@@ Start (.*)$" $line -> start]} return
    #stream term compact "Start    [clock format $start]"
    dict set state start $start
    dict set state benchnum 0
    dict set state benchskip 0
    return -code return
}

proc ::kettle::Bench::End {} {
    upvar 1 line line state state
    if {![regexp "^@@ End (.*)$" $line -> end]} return

    set start [dict get $state start]
    set shell [dict get $state shell]
    set file  [dict get $state file]
    set num   [dict get $state benchnum]
    set skip  [dict get $state benchskip]
    set err   [dict get $state cerrors]

    stream awrite "~~    $num SKIP $skip"
    if {$err} {
	stream aclose "~~ [io mred ERR] $num SKIP $skip"
    } else {
	stream aclose "~~ OK  $num SKIP $skip"
    }

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
    return -code return
}

proc ::kettle::Bench::Benchmark {} {
    upvar 1 line line state state ; variable xfile
    if {![regexp "^@@ Benchmark (.*)$" $line -> file]} return
    #stream term compact "Benchmark $file"
    dict set state file $file
    # map from full path to short, and padded for alignment.
    set padded [dict get $state fmap [file tail $file]]
    stream aextend "$padded "
    return -code return
}

proc ::kettle::Bench::Support {} {
    upvar 1 line line state state
    #stream awrite "S $package" /when caught
    #if {[regexp "^SYSTEM - (.*)$" $line -> package]} {stream term compact "Ss $package";return -code return}
    #if {[regexp "^LOCAL  - (.*)$" $line -> package]} {stream term compact "Sl $package";return -code return}
    if {[regexp "^SYSTEM - (.*)$" $line -> package]} {return -code return}
    if {[regexp "^LOCAL  - (.*)$" $line -> package]} {return -code return}
    return

}

proc ::kettle::Bench::Benching {} {
    upvar 1 line line state state
    #stream awrite "T $package" /when caught
    #if {[regexp "^SYSTEM % (.*)$" $line -> package]} {stream term compact "Bs $package";return -code return}
    #if {[regexp "^LOCAL  % (.*)$" $line -> package]} {stream term compact "Bl $package";return -code return}
    if {[regexp "^SYSTEM % (.*)$" $line -> package]} {return -code return}
    if {[regexp "^LOCAL  % (.*)$" $line -> package]} {return -code return}
    return
}

proc ::kettle::Bench::BenchLog {} {
    upvar 1 line line state state
    if {![string match {@@ Feedback *} $line]} return
    # Ignore unstructured feedback.
    return -code return
}

proc ::kettle::Bench::BenchSkipped {} {
    upvar 1 line line state state
    if {![regexp "^@@ Skipped (.*)$" $line -> data]} return
    lassign [lindex $data 0] description
    dict incr state benchskip
    dict set state bench {}
    stream awrite "SKIP $description"
    return -code return
}

proc ::kettle::Bench::BenchStart {} {
    upvar 1 line line state state
    if {![regexp "^@@ StartBench (.*)$" $line -> data]} return
    lassign [lindex $data 0] description iter
    dict set state bench $description
    dict incr state benchnum
    set w [string length $iter]
    dict set state witer $w
    dict set state iter  $iter
    stream awrite "\[[format %${w}s {}]\] $description"
    return -code return
}

proc ::kettle::Bench::BenchTrack {} {
    upvar 1 line line state state
    if {![regexp "^@@ Progress (.*)$" $line -> data]} return
    lassign [lindex $data 0] description at
    set w [dict get $state witer]
    stream awrite "\[[format %${w}s $at]\] $description"
    return -code return
}

proc ::kettle::Bench::BenchResult {} {
    upvar 1 line line state state
    if {![regexp "^@@ Result (.*)$" $line -> data]} return
    lassign [lindex $data 0] description time
    #stream awrite "$description = $time"

    set sh    [dict get $state shell]
    set ver   [dict get $state tcl]
    set file  [dict get $state file]
    set round [dict get $state round]

    set row [list $sh $ver $file $round $description $time]
    stream to results {"[join $row {","}]"}

    set key [list $sh $ver $file $description]
    dict update state results r {
	dict lappend r $key $time
    }

    dict set state bench {}
    dict set state witer {}
    return -code return
}

proc ::kettle::Bench::CaptureStackStart {} {
    upvar 1 line line state state
    if {![string match {@+*} $line]} return

    dict set state cap/stack    on
    dict set state stack        {}
    dict set state suite/status error
    dict incr state cerrors

    stream aextend "[io mred {Caught Error}] "
    return -code return
}

proc ::kettle::Bench::CaptureStack {} {
    upvar 1 state state
    if {![dict get $state cap/stack]} return
    upvar 1 line line

    if {![string match {@-*} $line]} {
	dict append state stack [string range $line 2 end] \n
	return -code return
    }

    if {[stream active]} {
	stream aextend ([io mblue {Stacktrace saved}])

	set file  [lindex [dict get $state file] end]
	set stack [dict get $state stack]

	stream to stacktrace {$file StackTrace}
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

proc ::kettle::Bench::Aborted {} {
    upvar 1 line line state state
    if {![string match {Aborting the benchmarks found *} $line]} return
    # Ignore aborted status if we already have it, or some other error
    # status (like error, or fail). These are more important to show.
    if {[dict get $state suite/status] eq "ok"} {
	dict set state suite/status aborted
    }
    stream aextend "[io mred Aborted:] "
    return -code return
}

proc ::kettle::Bench::AbortCause {} {
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
