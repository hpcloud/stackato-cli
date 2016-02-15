## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## CMDR - Private - Command execution. Simple case.
##                  An actor.

## - Privates know to do one thing, exactly, and nothing more.
##   They can process their command line to extract/validate
##   the inputs they need for their action from the arguments.

# @@ Meta Begin
# Package cmdr::private 0
# Meta author   {Andreas Kupries}
# Meta location https://core.tcl.tk/akupries/cmdr
# Meta platform tcl
# Meta summary Single command handling, options, and arguments.
# Meta description 'cmdr::private's know to do one thing, exactly,
# Meta description and nothing more. They can process their command
# Meta description line to extract/validate the inputs they need
# Meta description for their action from the arguments.
# Meta subject {command line} arguments options
# Meta require TclOO
# Meta require cmdr::actor
# Meta require cmdr::config
# Meta require debug
# Meta require debug::caller
# Meta require {Tcl 8.5-}
# Meta require {oo::util 1.2}
# @@ Meta End

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require debug
package require debug::caller
package require TclOO
package require oo::util 1.2 ;# link helper
package require cmdr::actor
package require cmdr::config

# # ## ### ##### ######## ############# #####################

debug define cmdr/private
debug level  cmdr/private
debug prefix cmdr/private {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition - Single purpose command.

oo::class create ::cmdr::private {
    superclass ::cmdr::actor
    # # ## ### ##### ######## #############
    ## Lifecycle.

    # argument specification + callback performing the action.
    # callback takes dictionary containing the actual arguments
    constructor {super name arguments cmdprefix} {
	debug.cmdr/private {}
	next

	my super: $super
	my name:  $name

	set myarguments $arguments
	set mycmd       $cmdprefix
	set myinit      0
	set myhandler   {}
	return
    }

    # # ## ### ##### ######## #############

    method ehandler {cmd} {
	debug.cmdr/private {}
	set myhandler $cmd
	return
    }

    # # ## ### ##### ######## #############
    ## Internal. Argument processing. Defered until required.
    ## Core setup code runs only once.

    method Setup {} {
	# Process myarguments only once.
	if {$myinit} return
	debug.cmdr/private {}
	set myinit 1

	# Create and fill the parameter collection
	set myconfig [cmdr::config create config [self] $myarguments]
	return
    }

    # # ## ### ##### ######## #############

    method do {args} {
	debug.cmdr/private {}
	my Setup

	if {[llength $myhandler]} {
	    # The handler is expected to have a try/finally construct
	    # which captures all of interest.
	    {*}$myhandler {
		my Run $args
	    }
	} else {
	    my Run $args
	}
    }

    method Run {words} {
	debug.cmdr/private {}
	debug.cmdr/private {parse}
	try {
	    config parse {*}$words
	} trap {CMDR CONFIG WRONG-ARGS NOT-ENOUGH} {e o} {
	    # Prevent interaction if globally suppressed, or just for
	    # this actor.
	    if {![cmdr interactive?] ||
		![config interactive]} {
		return {*}$o $e
	    }
	    if {![config interact]} return
	}

	debug.cmdr/private {complete values}

	# Define all parameters now, resolving defaults, validating
	# the values, etc. Except for the 'defered' parameters. By
	# default this are only the 'state' parameters.
	config force

	debug.cmdr/private {execute}
	# Call actual command, hand it the filled configuration.
	{*}$mycmd $myconfig 
    }

    method help {{prefix {}}} {
	debug.cmdr/private {}
	my Setup
	# help    = dict (name -> command)
	# command = dict ('action'    -> cmdprefix
	#                 ... see config help ...)
	#if {![my documented]} { return {} }

	set help [linsert [config help] end action $mycmd]
	return [dict create $prefix $help]
    }

    method complete-words {parse} {
	debug.cmdr/private {} 10
	my Setup
	return [my completions $parse [config complete-words $parse]]
    }

    # Redirect anything not known to the parameter collection.
    method unknown {m args} {
	debug.cmdr/private {}
	my Setup
	config $m {*}$args
    }

    # # ## ### ##### ######## #############

    variable myarguments mycmd myinit myconfig myhandler

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide cmdr::private 1.0
