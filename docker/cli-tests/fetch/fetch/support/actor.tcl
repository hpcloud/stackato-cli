## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## CMDR - Actor - Command execution. Base.
##                Actors know how to do something.

# @@ Meta Begin
# Package cmdr::actor 0
# Meta author   {Andreas Kupries}
# Meta location https://core.tcl.tk/akupries/cmdr
# Meta platform tcl
# Meta summary     Internal. Base class for officers and privates.
# Meta description Internal. Base class for officers and privates.
# Meta subject {command line}
# Meta require {Tcl 8.5-}
# Meta require debug
# Meta require debug::caller
# Meta require TclOO
# @@ Meta End

## Two types:
## - Privates know to do one thing, exactly, and nothing more.
##   They can process their command line to extract/validate
##   the inputs they need for their action from the arguments.
#
## - Officers can learn to do many things, by delegating things to the
##   actors actually able to perform it.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require debug
package require debug::caller
package require TclOO

# # ## ### ##### ######## ############# #####################

debug define cmdr/actor
debug level  cmdr/actor
debug prefix cmdr/actor {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition - Single purpose command.

oo::class create ::cmdr::actor {
    # # ## ### ##### ######## #############
    ## Lifecycle

    constructor {} {
	debug.cmdr/actor {}
	set myname        {}
	set mydescription {}
	set mydocumented  yes
	set mysuper       {}
	set mystore       {}
	return
    }

    # # ## ### ##### ######## #############
    ## Public API: Common actor attributes and behaviour
    ## - Name.
    ## - Description (help information).
    ## - Chain of command.
    ## - Associative data store

    method name {} {
	return $myname
    }

    method dname {} {
	::list {*}[my get *prefix*] $myname
    }

    method fullname {} {
	set result {}
	if {$mysuper ne {}} {
	    lappend result {*}[$mysuper fullname]
	}
	lappend result $myname
	return $result
    }

    method name: {thename} {
	debug.cmdr/actor {}
	set myname $thename
	return
    }

    method description {} {
	my Setup ; # Calls into the derived class
	return $mydescription
    }

    method description: {text} {
	debug.cmdr/actor {}
	set mydescription [string trim $text]
	return
    }

    method documented {} {
	debug.cmdr/actor {}
	my Setup ; # Calls into the derived class
	return $mydocumented
    }

    method undocumented {} {
	debug.cmdr/actor {}
	set mydocumented no
	return
    }

    method super {} {
	return $mysuper
    }

    method super: {thesuper} {
	set mysuper $thesuper
	return
    }

    method root {} {
	if {$mysuper ne {}} {
	    return [$mysuper root]
	}
	return [self]
    }

    method keys {} {
	debug.cmdr/actor {}
	my Setup
	set result [dict keys $mystore]
	if {$mysuper ne {}} {
	    lappend result {*}[$mysuper keys]
	    set result [lsort -unique $result]
	}
	return $result
    }

    method exists {key} {
	debug.cmdr/actor {}
	my Setup
	set ok [dict exists $mystore $key]
	if {!$ok && ($mysuper ne {})} {
	    return [$mysuper exists $key]
	}
	return $ok
    }

    method get {key} {
	debug.cmdr/actor {}
	my Setup ; # Call into derived class.

	# Satisfy from local store first ...
	if {[dict exists $mystore $key]} {
	    return [dict get $mystore $key]
	}
	# ... then ask in the chain of command ...
	if {$mysuper ne {}} {
	    return [$mysuper get $key]
	}
	# ... and fail if we are at the top.
	return -code error -errorcode {CMDR STORE UNKNOWN} \
	    "Expected known key for get, got \"$key\""
    }

    method set {key data} {
	debug.cmdr/actor {}
	dict set mystore $key $data
	return
    }

    method lappend {key data} {
	debug.cmdr/actor {}
	catch { set value [my get $key] }
	lappend value $data
	dict set mystore $key $value
	return
    }

    method unset {key} {
	debug.cmdr/actor {}
	dict unset mystore $key
	return
    }

    # # ## ### ##### ######## #############
    ## Public APIs:
    ## Overridden by sub-classes.

    # - Perform an action.
    # - Return help information about the action.

    method do   {args} {}
    method help {{prefix {}}} {}

    ##
    # # ## ### ##### ######## #############

    variable myname mydescription mydocumented mysuper mystore

    # # ## ### ##### ######## #############
    ## Helper methods common to command completion in actors.

    method Quote {word} {
	# Check if word contains special characters, and quote it to
	# prevent special interpretation of these characters, if so.
	if {
	    [string match "*\[ \"'()\$\|\{\}\]*" $word] ||
	    [string match "*\]*"                 $word] ||
	    [string match "*\[\[\]*"             $word]
	} {
	    set map [list \" \\\"]
	    return \"[string map $map $word]\"
	} else {
	    return $word
	}
    }

    method completions {parse cmdlist} {
	debug.cmdr/actor {} 10
	# Quick exit if there is nothing to complete.
	if {![llength $cmdlist]} {
	    return $cmdlist
	}

	dict with parse {}
	# -> line, words (ignored: ok, nwords, at, doexit)

	# The -> cmd is a valid completion of the line.  The actual
	# completion is the line itself, plus the command.  Note that
	# we have to chop off the incomplete part of cmd in the line
	# before adding the complete command.
	#
	# Example:
	# line       = "foo b"
	# cmd            = "bar"
	# completion = "foo bar"

	# Determine the chop point, then chop: Just before the first
	# character of the last word. Which is a prefix to all
	# commands in the list.
	set  chop [lindex $words end 1]
	incr chop -1
	set line [string range $line 0 $chop]

	set completions {}
	foreach cmd $cmdlist {
	    set cmd [my Quote $cmd]
	    # Chop and complete.
	    lappend completions $line$cmd
	}
	return $completions
    }

    # Could possibly use 'struct::list filter', plus a lambda.
    method match {parse cmdlist} {
	debug.cmdr/actor {} 10
	# Quick exit if nothing can match.
	if {![llength $cmdlist]} {
	    return $cmdlist
	}

	dict with parse {}
	# -> words, at (ignored: ok, nwords, line, doexit)

	# We need just the text of the current word.
	set current [lindex $words $at end]

	set filtered {}
	foreach cmd $cmdlist {
	    if {![string match ${current}* $cmd]} continue
	    lappend filtered $cmd
	}
	return $filtered
    }

    method parse-line {line} {
	debug.cmdr/actor {} 10
	set ok    1
	set words {}

	try {
	    set words [string token shell -partial -indices $line]
	} trap {STRING TOKEN SHELL BAD} {e o} {
	    set ok 0
	}

	set len [string length $line]

	if {$ok} {
	    # last word, end index
	    set lwe [lindex $words end 2]
	    # last word ends before end of line -> trailing whitespace
	    # add the implied empty word for the completion processing.
	    if {$lwe < ($len-1)} {
		lappend words [list PLAIN $len $len {}]
	    }
	}
	set parse [dict create \
		       doexit 1 \
		       at     0 \
		       line   $line \
		       ok     $ok \
		       words  $words \
		       nwords [llength $words]]

	return $parse
    }

    ##
    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide cmdr::actor 1.0
