# -*- tcl -*- Copyright (c) 2012 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## Benchmark Utilities.

namespace eval ::kb {
    namespace export {[a-z]*}
    namespace ensemble create

    # Directory the benchmark file is in.
    variable benchDirectory

    # Counter for 'bench_tmpfile'.
    variable uniqid 0

    # Global configuration settings for 'bench'.
    variable  config 
    array set config {
	ERRORS		1
	MATCH		{}
	RMATCH		{}
	FILES		{}
	ITERS		1000
    }

    # 'config' contents:
    #
    # - ERRORS  : Boolean flag. If set benchmark output mismatches are
    #             reported by throwing an error. Otherwise they are simply
    #             listed as BAD_RES. Default true. Can be set/reset via
    #             option -errors.
    #
    # - MATCH   : Match pattern, see -match, default empty, aka everything
    #             matches.
    #
    # - RMATCH  : Match pattern, see -rmatch, default empty, aka
    #             everything matches.
    #
    # - ITERS   : Number of iterations to run a benchmark body, default
    #             1000. Can be overridden by the individual benchmarks.
}

# # ## ### ##### ######## ############# #####################
## API. Use of files relative to the test directory.

proc ::kb::source {path} {
    variable benchDirectory
    uplevel 1 [list ::source [file join $benchDirectory $path]]
}

proc ::kb::find {pattern} {
    variable benchDirectory
    return [lsort -dict [glob -nocomplain -directory $benchDirectory $pattern]]
}

proc ::kb::source* {pattern} {
    foreach f [find $pattern] {
	uplevel 1 [list ::source $f]
    }
    return
}

# # ## ### ##### ######## ############# #####################
## Use of packages. Support, and under profiling.

proc ::kb::check {name version} {
    if {[package vsatisfies [package provide $name] $version]} {
	puts "SYSTEM - $name [package present $name]"
	return
    }

    puts "    Aborting the benchmarks found in \"[file tail [info script]]\""
    puts "    Requiring at least $name $version, have [package present $name]."

    # This causes a 'return' in the calling scope.
    return -code return
}

proc ::kb::require {type name args} {
    variable tag
    try {
	package require $name {*}$args
    } on error {e o} {
	puts "    Aborting the benchmarks found in \"[file tail [info script]]\""
	puts "    Required package $name not found: $e"
	return -code return
    }

    puts "SYSTEM [dict get $tag $type] $name [package present $name]"
    return
}

proc ::kb::local {type name args} {
    variable tag
    # Specialized package require. It is forced to search (via
    # forget), and its search is restricted to the local installation,
    # via a custom unknown handler temporarily replacing the regular
    # functionality.

    set saved [package unknown]
    try {
	package unknown ::kb::PU
	package forget  $name
	package require $name {*}$args
    } on error {e o} {
	puts "    Aborting the benchmarks found in \"[file tail [info script]]\""
	puts "    Required local package $name not found: $e"
	return -code return
    } finally {
	package unknown $saved
    }

    puts "LOCAL  [dict get $tag $type] $name [package present $name]"
    return
}

proc ::kb::PU {name args} {
    global   auto_path
    variable localprefix

    set saved $auto_path
    set auto_path [list $localprefix/lib]

    # Direct call into package scan, ignore modules.
    tclPkgUnknown __ignored__

    set auto_path $saved
    return
}

namespace eval ::kb {
    variable tag {
	support   -
	benchmark %
    }
}

# # ## ### ##### ######## ############# #####################
## Benchmark API. Taken out of libbench, more package like.

#
# It claims all procedures starting with bench*
#

# bench_tmpfile --
#
#   Return a temp file name that can be modified at will
#
# Arguments:
#   None
#
# Results:
#   Returns file name
#
proc bench_tmpfile {} {
    variable ::kb::uniqid
    global tcl_platform env

    set base "tclbench[pid].[incr uniqid].dat"

    if {$tcl_platform(platform) eq "unix"} {
	return "/tmp/$base"
    } elseif {$tcl_platform(platform) eq "windows"} {
	return [file join $env(TEMP) $base]
    } else {
	return $base
    }
}

# bench_rm --
#
#   Remove a file silently (no complaining)
#
# Arguments:
#   args	Files to delete
#
# Results:
#   Returns nothing
#

proc bench_rm {args} {
    foreach file $args {
	catch {
	    file delete $file
	}
    }
    return
}

proc bench_puts {args} {
    kb::Note Feedback $args
    return
}

# bench --
#
#   Main bench procedure.
#   The bench test is expected to exit cleanly.  If an error occurs,
#   it will be thrown all the way up.  A bench proc may return the
#   special code 666, which says take the string as the bench value.
#   This is usually used for N/A feature situations.
#
# Arguments:
#
#   -pre	script to run before main timed body
#   -body	script to run as main timed body
#   -post	script to run after main timed body
#   -ipre	script to run before timed body, per iteration of the body.
#   -ipost	script to run after timed body, per iteration of the body.
#   -desc	message text
#   -iterations	<#>
#
# Note:
#
#   Using -ipre and/or -ipost will cause us to compute the average
#   time ourselves, i.e. 'time body 1' n times. Required to ensure
#   that prefix/post operation are executed, yet not timed themselves.
#
# Results:
#
#   Returns nothing
#
# Side effects:
#
#   Sets up data in bench global array
#

proc bench {args} {
    global errorInfo errorCode
    variable kb::config
    upvar 0 kb::config BENCH

    # -pre script
    # -body script
    # -desc msg
    # -post script
    # -ipre script
    # -ipost script
    # -iterations <#>

    array set opts {
	-pre	{}
	-body	{}
	-desc	{}
	-post	{}
	-ipre	{}
	-ipost	{}
    }
    set opts(-iter) $BENCH(ITERS)
    while {[llength $args]} {
	set key [lindex $args 0]
	set val [lindex $args 1]

	switch -glob -- $key {
	    -res*	{ set opts(-res)   $val }
	    -pr*	{ set opts(-pre)   $val }
	    -po*	{ set opts(-post)  $val }
	    -ipr*	{ set opts(-ipre)  $val }
	    -ipo*	{ set opts(-ipost) $val }
	    -bo*	{ set opts(-body)  $val }
	    -de*	{ set opts(-desc)  $val }
	    -it*	{
		# Only change the iterations when it is smaller than
		# the requested default
		if {$opts(-iter) > $val} { set opts(-iter) $val }
	    }
	    default {
		error "unknown option $key"
	    }
	}
	set args [lreplace $args 0 1]
    }

    bench_puts "Running <$opts(-desc)>"
    kb::Note StartBench [list $opts(-desc) $opts(-iter)]

    if {($BENCH(MATCH) ne "") && ![string match $BENCH(MATCH) $opts(-desc)]} {
	kb::Note Skipped $opts(-desc)
	return
    }

    if {($BENCH(RMATCH) ne "") && ![regexp $BENCH(RMATCH) $opts(-desc)]} {
	kb::Note Skipped $opts(-desc)
	return
    }

    if {$opts(-pre) ne ""} {
	uplevel \#0 $opts(-pre)
    }

    if {$opts(-body) ne ""} {
	# Always run it once to remove compile phase confusion
	if {$opts(-ipre) ne ""} {
	    uplevel \#0 $opts(-ipre)
	}
	set code [catch {
	    uplevel \#0 $opts(-body)
	} res]
	if {$opts(-ipost) ne ""} {
	    uplevel \#0 $opts(-ipost)
	}

	if {!$code && [info exists opts(-res)] && ($opts(-res) ne $res)} {
	    if {$BENCH(ERRORS)} {
		return -code error "Result was:\n$res\nResult\
			should have been:\n$opts(-res)"
	    } else {
		set res "BAD_RES"
	    }

	    kb::Note Result [list $opts(-desc) $res]

	} else {
	    if {($opts(-ipre) != "") || ($opts(-ipost) != "")} {
		# We do the averaging on our own, to allow untimed
		# pre/post execution per iteration. We catch and
		# handle problems in the pre/post code as if
		# everything was executed as one block (like it would
		# be in the other path). We are using floating point
		# to avoid integer overflow, easily happening when
		# accumulating a high number (iterations) of large
		# integers (microseconds).

		set total 0.0
		#set total +Inf

		for {set i 1} {$i <= $opts(-iter)} {incr i} {
		    kb::Note Progress [list $opts(-desc) $i]

		    set code 0
		    if {$opts(-ipre) != ""} {
			set code [catch {
			    uplevel \#0 $opts(-ipre)
			} res]
			if {$code} break
		    }
		    set code [catch {
			uplevel \#0 [list time $opts(-body) 1]
		    } res]
		    if {$code} break


		    set now [lindex $res 0]
		    #puts !!!Z|$now|$total|$opts(-desc)

		    set total [expr {$total + $now}]
		    #if {$now < $total} { set total $now }

		    if {$opts(-ipost) != ""} {
			set code [catch {
			    uplevel \#0 $opts(-ipost)
			} res]
			if {$code} break
		    }
		}
		# XXX Use 'min' instead of avg?
		if {!$code} {
		    #puts !!!A|$total|$opts(-iter)|[expr {$total/$opts(-iter)}]

		    set res [list [expr {$total/$opts(-iter)}] microseconds per iteration]
		    #set res $total
		}
	    } else {
		kb::Note Progress [list $opts(-desc) ----]

		set code [catch {
		    uplevel \#0 [list time $opts(-body) $opts(-iter)]
		} res]
		#puts !!!B|$res|
	    }

	    if {$code == 0} {
		# Get just the microseconds value from the time result
		set res [lindex $res 0]
	    } elseif {$code != 666} {
		# A 666 result code means pass it through to the bench
		# suite. Otherwise throw errors all the way out, unless
		# we specified not to throw errors (option -errors 0 to
		# libbench).
		if {$BENCH(ERRORS)} {
		    return -code $code -errorinfo $errorInfo \
			-errorcode $errorCode
		} else {
		    set res "ERR"
		}
	    }

	    kb::Note Result [list $opts(-desc) $res]
	}
    }

    if {($opts(-post) ne "") && [catch {
	uplevel \#0 $opts(-post)
    } err] && $BENCH(ERRORS)} {
	return -code error "post code threw error:\n$err"
    }
    return
}

# # ## ### ##### ######## ############# #####################
## Helper code.





# # ## ### ##### ######## ############# #####################
return
