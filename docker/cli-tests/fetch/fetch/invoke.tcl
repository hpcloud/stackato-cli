# -*- tcl -*- Copyright (c) 2012 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## Invoke goals in other packages in related directories, including itself.

namespace eval ::kettle { namespace export invoke }

# # ## ### ##### ######## ############# #####################
## API.

proc ::kettle::recurse {} {
    # application replacement. looks for kettle build scripts in all
    # sub directories and invokes them with the current configuration
    # and goals.
    #
    # Note: By keeping the goals we are trying to run main recipes
    # also.

    lassign [path scan \
		 {kettle build scripts} \
		 [path sourcedir] \
		 {path kettle-build-file}] \
	root subbuilders

    set tmp {}

    set self [option get @srcscript]

    io trace {self = $self}

    foreach s $subbuilders {
	io trace {s... = $s}
	if {[path norm $s] eq $self} continue
	lappend tmp $s
    }

    # We now have a list of sub directories containing a kettle build
    # script we can use. Our next step is to query these build systems
    # for the supported recipes. This information is merged into a map
    # of recipes to supporting build systems from which we then create
    # our high-level recipes which invoke them as needed. The leave
    # the standard recipes out of that, because they query the recipe
    # database for their work, so don't have to go directly to the
    # builds.

    set map  {}
    set hmap {}
    foreach sub $tmp {
	set help [invoke-return $sub help-dump]
	foreach r [invoke-return $sub list-recipes] {
	    dict lappend map  $r $sub
	    dict lappend hmap $r [dict get $help $r]
	}
    }

    # XXX Pull the recipes to suppress directly out of the database
    # XXX somehow (tags?!). See also gui (ignore, special) for similar
    # XXX issues.
    foreach r {
	null gui
	help-recipes help-options help help-dump
	list-recipes list-options list
	show-configuration show-state show
    } {
	dict unset map  $r
	dict unset hmap $r
    }

    dict for {recipe builders} $map {
	option set @($recipe) $builders

	set help [join \
	      [lsort -dict [lsort -unique \
		[dict get $hmap $recipe]]] \
	      \n]

	recipe define $recipe $help {r} {
	    invoke @($r) $r
	} $recipe
    }

    return
}

proc ::kettle::invoke-return {args} {
    variable IRETURN 1
    try {
	set result [invoke {*}$args]
    } finally {
	unset IRETURN
    }
    return $result
}

proc ::kettle::invoke {other args} {
    variable IRETURN
    if {![info exists IRETURN]} { set IRETURN 0 }

    # Special syntax. Access to named lists of other packages in the
    # option database. Recurse call on each entry.
    if {[string match @* $other]} {
	# TODO: Catch cycles!
	foreach element [option get $other] {
	    invoke $element {*}$args
	}
	return
    }

    # Special syntax. Recursively call goals on self.
    #
    # Similar to recipes and parents, except here the connection is
    # dynamically made, and not statically build as part of the recipe
    # definition.
    #
    # Second difference, the sub-goal(s) run in a separate process,
    # protecting us somewhat, especially if we change the
    # configuration for the sub-goal. This part may not make sense,
    # and may be changed in the future to directly invoke 'recipe run'
    # (see kettle::Application).

    if {$other eq "self"} {
	set buildscript [path script]
	set other       [path sourcedir]
    } else {
	set other [path sourcedir $other]

	if {[file isfile $other]} {
	    # Assume that the provided file is the build script.
	    # Extract the source directory from it.

	    set buildscript $other
	    set other       [file dirname $other]

	} elseif {[file isdirectory $other]} {
	    # Search for a build script in the specified directory.
	    # Not using path scan as sub directories are not relevant,
	    # and we do our own check and stop.

	    set buildscript {}
	    foreach f [lsort -unique [lsort -dict [glob -nocomplain -type f -directory $other * .*]]] {
		if {![path kettle-build-file $f]} continue
		set buildscript $f
		break
	    }

	    if {$buildscript eq {}} {
		status fail "No build script found in $other"
	    }
	} else {
	    return -code error "Expected file or directory, got [file type $other] \"$other\""
	}
    }

    set rother [path relativesrc $other]

    # Filter goals against the global knowledge of those already
    # done. This is a bit more complex as the arguments may contain
    # options, these we do not filter. This is a small two-state
    # state-machine to separate options from goals. We need the
    # options first as they influence the search in the work database.

    set goals {}
    set overrides {}
    set skip 0
    foreach g $args {
	if {$skip} {
	    # option argument, keep, prepare for regular again
	    set skip 0
	    lappend overrides $g
	    continue
	} elseif {[string match --* $g]} {
	    # option, keep, and prepare to keep next argument, the
	    # option value
	    set skip 1
	    lappend overrides $g
	    continue
	}
	# goal
	lappend goals $g
    }

    # Step 2, filter goals, use the overrides as additional config
    # information...  Issue: This will not work as is, right now ... A
    # highlevel config change will here not do all the changes we see
    # from the command line, this the configs will not match properly
    # ... So, basic idea is ok, details buggy...

    set keep {}
    foreach g $goals {
	if {[status is $g $other {*}$overrides] ne "unknown"} {
	    # goal, already done, ignore (= filtered out)
	    continue
	}
	# goal, not done, keep
	lappend keep $g
    }
    set goals $keep

    # Ignore call if no goals to run are left.
    if {![llength $goals]} return

    io trace {entering $rother $goals $overrides}
    if {!$IRETURN} {
	io cyan { io puts "Enter \"$rother\": $goals ..." }
    }

    # The current configuration (options) is directly specified on the
    # command line, which then might be overridden by the goal's
    # arguments. The work state is transmitted through a temporary
    # file. This is also the one thing which gets loaded back after
    # the sub-process has completed, on account of the sub-process
    # extending it.

    # Notes:
    # - We use our tclsh to run the child.
    # - We use our kettle interpreter to run the child.

    set work   [status save]
    set config [option save]
    try {
	if {$IRETURN} {
	    set iresult [exec \
		[info nameofexecutable] \
		[option get @kettle] \
		-f $buildscript \
		--config $config --state $work {*}$overrides \
		--machine on {*}$goals]
	    set iresult [string trim $iresult]
	} else {
	    path exec \
		[info nameofexecutable] \
		[option get @kettle] \
		-f $buildscript \
		--config $config --state $work {*}$overrides \
		{*}$goals
	    status load $work
	}
    } finally {
	file delete $work
	file delete $config
    }

    if {$IRETURN} { return $iresult }

    # ok/fail is based on the work database we got back.
    # All goals must be ok.

    set ok 1
    foreach goal $goals {
	set state [status is $goal $other {*}$overrides]
	io trace {entry result $rother $goal = $state}
	if {$state eq "ok"} continue
	set ok 0
    }
    io cyan { io puts "Exit  \"$rother\" ($goals): $state\n" }
    return $ok
}
