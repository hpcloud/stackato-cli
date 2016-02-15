# -*- tcl -*- Copyright (c) 2012 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## Recipe management commands. Core definition and execution.

# # ## ### ##### ######## ############# #####################
## Export (internals - recipe definition code, higher control).

namespace eval ::kettle::recipe {
    namespace export {[a-z]*}
    namespace ensemble create

    namespace import ::kettle::strutil
    namespace import ::kettle::path
    namespace import ::kettle::option
}

# # ## ### ##### ######## ############# #####################
## System state

namespace eval ::kettle::recipe {
    # Dictionary of recipe definitions.
    # name -> dict (
    #      script -> list ( tcl scripts )
    #      help   -> list ( help strings )
    #      parent -> parent recipe, if any. empty if there is none.
    # )

    variable recipe {}

    # Import the supporting utilities used here.
    namespace import ::kettle::io
    namespace import ::kettle::status
}

# # ## ### ##### ######## ############# #####################
## Management API commands.

proc ::kettle::recipe::define {name description arguments script args} {
    variable recipe

    # Note! The scripts are evaluated in the context of namespace
    # ::kettle. This provide access to various internal commands
    # without making them visible to the user/DSL.

    set description [strutil reflow $description]
    io trace {DEF $name}

    Init $name
    dict update recipe $name def {
	dict lappend def script \
	    [lambda@ ::kettle $arguments $script {*}$args]
	dict lappend def help   $description
    }
    return
}

proc ::kettle::recipe::parent {name parent} {
    variable recipe

    Init $name
    Init $parent
    dict update recipe $name def {
	dict lappend def parent $parent
    }

    #io trace {PARENTS $name = [dict get $recipe $name parent]}
    return
}

proc ::kettle::recipe::exists {name} {
    variable recipe
    return [dict exists $recipe $name]
}

proc ::kettle::recipe::names {} {
    variable recipe
    return [dict keys $recipe]
}

proc ::kettle::recipe::help {prefix} {
    global   argv0
    variable recipe
    append prefix $argv0 " -f " [path relativecwd [path script]] " "

    foreach goal [lsort -dict [dict keys $recipe]] {
	io puts ""
	io note { io puts $prefix${goal} }

	set children [Children $goal]
	set help     [dict get $recipe $goal help]

	if {[llength $children]} {
	    io puts "\t==> [join [lsort -dict $children] "\n\t==> "]"
	}
	if {[llength $help]} {
	    io puts [join $help \n]
	}
    }
    io puts ""
    return
}

proc ::kettle::recipe::help-dump {} {
    variable recipe
    foreach goal [lsort -dict [dict keys $recipe]] {
	set children [Children $goal]
	set help     [dict get $recipe $goal help]

	set lines {}
	if {[llength $children]} {
	    lappend lines "\t==> [join [lsort -dict $children] "\n\t==> "]"
	}
	if {[llength $help]} {
	    lappend lines [join $help \n]
	}

	lappend result $goal [join $lines \n]
    }

    io puts $result
    return
}

proc ::kettle::recipe::run {args} {
    io trace {}
    foreach goal $args {
	try {
	    Run $goal
	}
    }
    return
}

# # ## ### ##### ######## ############# #####################
## Internal support.

proc ::kettle::recipe::Init {name} {
    variable recipe
    if {[dict exists $recipe $name]} return
    dict set recipe $name {
	script {}
	help   {}
	parent {}
    }
    return
}

proc ::kettle::recipe::Run {name} {
    variable recipe
    upvar 1 done done

    status begin $name

    if {![dict exists $recipe $name]} {
	status fail "No definition for recipe \"$name\""
    }

    # Determine the recipe's children and run them first.
    foreach c [Children $name] {
	Run $c
	if {[status is $c] ne "ok"} {
	    io trace {RUN ($name) ... FAIL (inherited)}
	    catch { status fail "Sub-goal \"$c\" failed" }
	    return
	}
    }

    # Now run the recipe itself
    io trace {RUN ($name) ... BEGIN}

    set commands [dict get $recipe $name script]
    if {![llength $commands]} {
	io trace {RUN ($name) ... OK (nothing)}
	catch { status ok }
	return
    }

    foreach cmd $commands {
	if {![option get --machine]} {
	    io note { io puts -nonewline "\n${name}: " }
	}
	try {
	    eval $cmd
	    status ok
	} trap {KETTLE STATUS OK}   {e o} {
	    io trace {RUN ($name) ... OK}
	    # nothing - implied continue
	} trap {KETTLE STATUS FAIL} {e o} {
	    io trace {RUN ($name) ... FAIL}
	    break
	}
    }
    return
}

proc ::kettle::recipe::Children {name} {
    # Determine the recipe's children
    variable recipe
    set result {}
    dict for {c v} $recipe {
	if {$name ni [dict get $v parent]} continue
	lappend result $c
    }
    return $result
}

# # ## ### ##### ######## ############# #####################
return
