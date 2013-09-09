# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

## This module manages the exit state of the application.
## It also provides the wrapper trapping and converting
## various error conditions a command may throw.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require exec
package require fileutil
package require stackato::log
package require stackato::color
package require cmdr 0.4
package require stackato::mgr::auth
package require stackato::mgr::cgroup
package require stackato::mgr::client
package require stackato::mgr::corg
package require stackato::mgr::cspace
package require stackato::mgr::ctarget
package require stackato::mgr::manifest
package require stackato::mgr::self
package require stackato::mgr::targets

namespace eval ::stackato::mgr {
    namespace export exit
    namespace ensemble create
}

namespace eval ::stackato::mgr::exit {
    namespace export state fail ok exit quit done \
	attempt trap-term trap-term-silent
    namespace ensemble create

    namespace import ::stackato::log::*
    namespace import ::stackato::color
    namespace import ::stackato::mgr::auth
    namespace import ::stackato::mgr::cgroup
    namespace import ::stackato::mgr::client
    namespace import ::stackato::mgr::corg
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::mgr::ctarget
    namespace import ::stackato::mgr::manifest
    namespace import ::stackato::mgr::self
    namespace import ::stackato::mgr::targets
}

debug level  mgr/exit
debug prefix mgr/exit {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Trap API

proc ::stackato::mgr::exit::trap-term {} {
    debug.mgr/exit {}
    global tcl_platform

    if {$tcl_platform(platform) eq "windows"} {
	signal trap {TERM INT} {
	    if {[catch {
		::stackato::log::say! "\nInterrupted\n"
		::exec::clear
		exit 1
	    }]} {
		# A problem here indicates that the user managed to
		# trigger ^C while we are in a child interp. Rethrow
		# the signal as a regular error to be caught and
		# processed (See "attempt" in this file).
		error Interrupted error SIGTERM
	    }
	}
    } else {
	signal -restart trap {TERM INT} {
	    if {[catch {
		::stackato::log::say! "\nInterrupted\n"
		::exec::clear
		exit 1
	    }]} {
		# A problem here indicates that the user managed to
		# trigger ^C while we are in a child interp. Rethrow
		# the signal as a regular error to be caught and
		# processed (See "attempt" in this file).
		error Interrupted error SIGTERM
	    }
	}
    }
}

proc ::stackato::mgr::exit::trap-term-silent {} {
    debug.mgr/exit {}

    # Only for logging --follow (2.3+ log stream).

    # At that point we have no child interpreter around, so we can
    # call on various things without fear of them not defined. This
    # can happen for the "fulltrap" (see above), if the client gets
    # interupted during load and setup of command packages).

    global tcl_platform

    if {$tcl_platform(platform) eq "windows"} {
	signal trap {TERM INT} {
	    ::exec::clear
	    exit 1
	}
    } else {
	signal -restart trap {TERM INT} {
	    ::exec::clear
	    exit 1
	}
    }
}

# # ## ### ##### ######## ############# #####################
## API

proc ::stackato::mgr::exit::state {} {
    debug.mgr/exit {}
    variable status
    return  $status
}

proc ::stackato::mgr::exit::fail {{s 1}} {
    debug.mgr/exit {}
    variable status $s
    return
}

proc ::stackato::mgr::exit::ok {} {
    debug.mgr/exit {}
    variable status 0
    return
}

proc ::stackato::mgr::exit::exit {{s 0}} {
    debug.mgr/exit {}
    variable status $s
    quit "exit"
}

proc ::stackato::mgr::exit::quit {{message {}}} {
    debug.mgr/exit {}
    return -code error \
	-errorcode {STACKATO CLIENT CLI GRACEFUL-EXIT} \
	$message
}

proc ::stackato::mgr::exit::done {} {
    debug.mgr/exit {}
    variable status
    exec::clear
    ::exit $status
    return
}

proc ::stackato::mgr::exit::attempt {script} {
    debug.mgr/exit {}

    # Start out ok, for the new command (shell)
    ok

    # TODO: capture cmdr parsing errors, invoke cmdr help.

    try {
	uplevel 1 $script
    } trap {CMDR DO UNKNOWN}         {e o} - \
      trap {CMDR ACTION UNKNOWN}     {e o} - \
      trap {CMDR ACTION BAD}         {e o} - \
      trap {CMDR VALIDATE}           {e o} - \
      trap {CMDR PARAMETER LOCKED}   {e o} - \
      trap {CMDR CONFIG BAD OPTION}  {e o} - \
      trap {CMDR CONFIG COMMIT FAIL} {e o} - \
      trap {CMDR CONFIG WRONG-ARGS}  {e o} {
	  say! [color red $e]
	  # TODO: Invoke help (after message)
	  fail
    } trap {CMDR PARAMETER UNDEFINED} {e o} {
	say! [color red [string map {{Undefined: } {Missing definition for argument '}} $e]']
	fail
    } trap {SIGTERM} {e o} - trap {TERM INTERUPT} {e o} {
	say! "\nInterrupted\n"
	exec::clear
	fail

    } trap {ZIP ENCODE DUPLICATE PATH} {e o} {
	say! [color red $e]
	fail

    } trap {STACKATO SERVER DATA ERROR} {e} {

	say! [color red "Bad server response; $e"]
	fail

    }   trap {STACKATO CLIENT AUTHERROR}    {e} - \
	trap {STACKATO CLIENT V2 AUTHERROR} {e} {

	set me [self me]

	if {[auth get] eq {}} {
	    say! [color red "Login Required"]
	    say! "Please use '$me login'"
	} else {
	    say! [color red "Not Authorized"]
	    say! "You are using an expired or deleted login"
	    say! "Please use '$me login'"
	}
	fail

    }   trap {STACKATO CLIENT TARGETERROR}    {e} - \
	trap {STACKATO CLIENT NOTFOUND}       {e} - \
	trap {STACKATO CLIENT BADTARGET}      {e} - \
	trap {STACKATO CLIENT V2 TARGETERROR} {e} - \
	trap {STACKATO CLIENT V2 NOTFOUND}    {e} - \
	trap {STACKATO CLIENT V2 BADTARGET}   {e} {

	say! [color red "$e"]

	debug.mgr/exit {$e}
	debug.mgr/exit {$::errorCode}
	debug.mgr/exit {$::errorInfo}

	#ProcessInternalError $e $::errorCode $::errorInfo
	fail

    } trap {@todo@ http exception} e {

	say! [color red "$e"]
	fail

    } trap {STACKATO CLIENT CLI GRACEFUL-EXIT} e {
	# Redirected commands end up generating this exception (kind of goto)
    } trap {STACKATO CLIENT CLI} e - trap {BROWSE FAIL} e {
	if {$e ne {}} {
	    say! [color red "$e"]
	}
	fail

    } trap {REST HTTP} {e o} {

	say [color red "$e"]
	fail

    } trap {STACKATO CLIENT INTERNAL} {e o} {
	lassign $e msg trace code

	debug.mgr/exit {$e}
	debug.mgr/exit {$o}
	debug.mgr/exit {$code}
	debug.mgr/exit {$trace}

	ProcessInternalError $msg $code $trace
	fail

    } trap {POSIX EPIPE} {e o} {
	# Ignore (stdout was piped and aborted before we wrote all our output).
	debug.mgr/exit {$e}
	debug.mgr/exit {$o}
	debug.mgr/exit {$::errorCode}
	debug.mgr/exit {$::errorInfo}

    } trap {@todo@ syntax error} e {

	say! [color red "$e"]\n$::errorInfo
	fail

    } on error {e o} {
	debug.mgr/exit {$e}
	debug.mgr/exit {$o}
	debug.mgr/exit {$::errorCode}
	debug.mgr/exit {$::errorInfo}

	ProcessInternalError $e $::errorCode $::errorInfo
	fail

    } finally {
	debug.mgr/exit {/finally}
	#say ""

	# Reset internal state of various managers to clear temporary
	# settings.
	# - TODO: transient current group
	# - TODO: transient token(-file)
	# - Disabled prompting.
	cmdr interactive 1
	auth     reset
	cgroup   reset
	client   reset
	corg     reset
	cspace   reset
	ctarget  reset
	manifest reset
	targets  reset

	# TODO: Verbose
	if 0 {if {$myexitstatus eq {}} {
	    fail
	} ; if {$myoptions(verbose)} {
	    if {$myexitstatus} {
		puts [color green "\[$mynamespace:$myaction\] SUCCEEDED"]
	    } else {
		puts [color red   "\[$mynamespace:$myaction\] FAILED"]
	    }
	    say ""
	}}
    }
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::exit::ProcessInternalError {msg code trace} {
    debug.mgr/exit {}

    # Bug 90845.
    if {[string match {*stdin isn't a terminal*} $msg]} {
	say! "Error: [color red $msg]"
	say! "Try with --noprompt to suppress all user interaction requiring a proper terminal"
	return
    }

    say! [color red "The client has encountered an internal error."]

    set trace "TRACE:\t[join [split $trace \n] \nTRACE:\t]"

    set out ERROR:\t$msg\nECODE:\t$code\n$trace\n

    # TODO: Verbose
    if 0 {if {$myoptions(verbose)} {
	say! $out
	return
    }}

    say! "Error: [color red $msg]"

    set f [fileutil::tempfile stackato-]
    fileutil::writeFile $f $out

    say! "Full traceback stored at: [file nativename $f]"

    #say! "Please report this bug to ActiveState by attaching the above file at,"
    #say! "\thttp://bugs.activestate.com/"
    say! "Please report this bug to ActiveState by emailing the above file to"
    say! "stackato-support@activestate.com with a short description of what you"
    say! "were trying to do."
    return
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::mgr::exit {
    variable status 0
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::exit 0
