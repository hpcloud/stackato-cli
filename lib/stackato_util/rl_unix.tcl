# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require ooutil
package require try
package require term::ansi::ctrl::unix ; # ANSI terminal, mode control, stty based.
package require term::ansi::code::ctrl ; # ANSI terminal control (cursor)

namespace eval ::stackato::readline {
    ::term::ansi::code::ctrl::import
    #puts P\t[join [info procs ctrl::*] \nP\t]
}

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::readline::I {
    constructor {{in stdin} {out stdout}} {
	# Namespace import, sort of.
	namespace path [linsert [namespace path] end ::stackato::readline]
	set mycstate [list [fconfigure $in] [fconfigure $out]]
	set myin  $in
	set myout $out
	set mystate off
	set myhide 0
	return
    }

    destructor {
	catch {my Disconnect}
	return
    }

    # # ## ### ##### ######## #############
    ## Public API


    method hide {} {
	set myhide 1
    }

    method gets* {} {
	my hide
	return [my gets]
    }

    method gets {} {
	# Initialize
	set myat       0 ; # location of next char.
	set myover     0 ; # flag: insert (0), overwrite (1)
	set mybuf      {}
	set mywritebuf {}
	set myreadbuf  {}
	set mystate    char

	# Run the eventloop handling I/O
	if {[catch {
	    my Connect
	} msg] && [string match *stty* $msg]} {
	    # stty issues imply non-interactive use of the client with
	    # stdin being a pipe, socket, etc. Instead of failing we
	    # simply read and return a single line from that input,
	    # not allowing any interactive editing at all.

	    return [::gets $myin]
	}

	upvar 0 [self namespace]::stop stop
	set stop {}
	try {
	    vwait [self namespace]::stop
	} finally {
	    my Disconnect
	}

	my destroy

	# Rethrow abnormal conditions, if any.
	if {$stop ne {}} {
	    return {*}$stop
	}

	# Suicide and return the entered line.
	return [join $mybuf {}]
    }

    # # ## ### ##### ######## #############
    ## Internals: Channel connectivity

    method Connect {} {
	term::ansi::ctrl::unix::raw

	fconfigure $myin  -blocking 0
	fconfigure $myout -blocking 0
	fileevent  $myin  readable [callback CRead]
	return
    }

    method Disconnect {} {
	fileevent $myin  readable {}
	fileevent $myout writable {}

	term::ansi::ctrl::unix::cooked

	lassign $mycstate i o
	fconfigure $myin  {*}$i
	fconfigure $myout {*}$o
	return
    }

    method CRead {} {
	if {$mystate eq "off"} return

	if {[eof $myin]} {
	    my Disconnect
	    my Interrupt
	    return
	}

	#my Write *
	lappend myreadbuf {*}[split [read $myin] {}]
	#my Write %
	try {
	    my Process
	} on error {e o} {
	    # Cleanup tty state
	    my Disconnect
	    # Rethrow error through inner event-loop
	    my Stop {*}$o $e
	}
	return
    }

    method CWrite {} {
	if {$mystate eq "off"} return
	if {$mywritebuf eq {}} return
	puts -nonewline $myout $mywritebuf
	flush $myout
	set mywritebuf {}
	fileevent $myout writable {}
	return
    }

    # # ## ### ##### ######## #############
    ## Internals: Character processing (Entry, and commands).

    method Process {} {
	#my Write L[llength $myreadbuf].

	while {[llength $myreadbuf]} {
	    set c         [lindex $myreadbuf 0]
	    set myreadbuf [lrange $myreadbuf 1 end]

	    #scan $c %c i
	    #my Write " |$c [format %03o $i]@$mystate|"

	    # 003 - ETX - ^C
	    # 004 - EOT - ^D
	    # 177 - DEL - \b, Backspace
	    # 012 - \n, Enter
	    # 033 - ESC - Begin of escape sequences (cursor commands).

	    switch -exact -- $mystate {
		char {
		    switch -exact -- $c {
			\001 { my CursorHome }
			\005 { my CursorEnd }
			\003 { my Interupt ; break }
			\004 -
			\012 { my Done ; break }
			\033 {
			    # Escape aka control sequnce has begun.
			    #my Write .ESC
			    set mystate esc
			}
			\177 {
			    my DeleteBeforeCursor
			}
			default {
			    my InsertCharacterAtCursor $c
			}
		    }
		}
		esc {
		    set trace {}
		    lappend trace $c
		    switch -exact -- $c {
			\133 {
			    #my Write .ESC/2
			    set mystate esc2
			}
			O {
			    # F1-F4, ignore next character
			    set mystate ignore1
			}
			default {
			    my Rewind
			}
		    }
		}
		esc2 {
		    lappend trace $c
		    switch -exact -- $c {
			C { my CursorRight ; set mystate char }
			D { my CursorLeft  ; set mystate char }
			A -
			B {
			    # cursor up (A) / down (B), ignore
			    # future: could be history scrolling.
			    set mystate char
			}
			2 { set mystate esc4.2 }
			3 { my DeleteUnderCursor ; set mystate esc3 }
			1 { set mystate esc4.1 }
			4 { my CursorEnd         ; set mystate esc3 }
			5 -
			6 {
			    # page up/down, ignore
			    set mystate esc3
			}
			default {
			    my Rewind
			}
		    }
		}
		esc3 {
		    lappend trace $c
		    switch -exact -- $c {
			~ {
			    # ignore closing ~ of the escape sequence
			    set mystate char
			}
			default {
			    # ignore any other char as well. at this
			    # point we have already committed to the
			    # operation.
			    set mystate char
			}
		    }
		}
		esc4.1 {
		    lappend trace $c
		    switch -exact -- $c {
			~ {
			    my CursorHome
			    set mystate char
			}
			9 - 8 - 7 - 5 {
			    # ignore, F5-F9
			    set mystate esc3
			}
			default { my Rewind }
		    }
		}
		esc4.2 {
		    lappend trace $c
		    switch -exact -- $c {
			~ {
			    my ToggleInsert
			    set mystate char
			}
			0 - 1 - 3 - 4 {
			    # ignore, F10-F12
			    set mystate esc3
			}
			default { my Rewind }
		    }
		}
		ignore1 {
		    # ignore and return to regular processing.
		    set mystate char
		}
		default { my StateError $c }
	    }
	}
	set myreadbuf {}
	return
    }

    method Rewind {} {
	# Ignore a faulty escape, and proceed to handle the specified
	# characters as they are. To do this we break back to the
	# loop, with the characters reinserted at the front for
	# another round.

	upvar 1 trace trace myreadbuf myreadbuf mystate mystate
	set mystate char
	set myreadbuf [linsert $myreadbuf 0 {*}$trace]
	set trace {}
	return -code continue
    }

    method Write {args} {
	append mywritebuf [join $args {}]
	fileevent $myout writable [callback CWrite]
	return
    }

    method Done {} {
	my Write \n
	my Stop
	return
    }

    method FlushWriteBuffer {stop} {
	my CWrite
	my Stop {*}$stop
	return
    }

    method Interupt {} {
	set mybuf {}
	my Stop -code error -errorcode {TERM INTERUPT} Interupted
	return
    }

    method Stop {args} {
	if {$mywritebuf ne {}} {
	    fileevent $myout writable [callback FlushWriteBuffer $args]
	} else {
	    set [self namespace]::stop $args
	}
	return
    }

    method StateError {c} {
	scan $c %c i
	my Stop -code error \
	    -errorcode {TERM STATE ERROR} \
	    "(Unknown combination $mystate,$c 0d$i)"
    }

    method Bell {} {
	my Write \7
    }

    method CursorHome {} {
	# cursor home
	if {$myat == 0} { my Bell ; return }

	my Write [ctrl::cb $myat]
	set myat 0
	return
    }

    method CursorEnd {} {
	# cursor end
	set n [llength $mybuf]

	if {$myat == $n} { my Bell ; return }

	my Write [ctrl::cf [expr {$n - $myat}]]
	set myat $n
	return
    }

    method CursorLeft {} {
	# cursor left
	if {$myat > 0} {
	    incr myat -1
	    my Write [ctrl::cb]
	} else {
	    my Bell
	}
	return
    }

    method CursorRight {} {
	# cursor right
	if {$myat < [string length $mybuf]} {
	    incr myat
	    my Write [ctrl::cf]
	} else {
	    my Bell
	}
	return			    
    }

    method ToggleInsert {} {
	# toggle insertion/overwrite mode.
	set myover [expr {!$myover}]
	return		    
    }

    method DeleteUnderCursor {} {
	# DEL. Remove character at/under cursor

	# Save cursor, delete line
	# to end, write old remainder, restore cursor

	if {$myat < [llength $mybuf]} {
	    set mybuf [lreplace $mybuf $myat $myat]

	    my Write [ctrl::sca] [ctrl::eeol]
	    my Echo $myat
	    my Write [ctrl::rca]
	} else {
	    my Bell
	}
	return
    }

    method DeleteBeforeCursor {} {
	# Backspace. Remove character before cursor.

	# Move cursor left. Save cursor, delete line
	# to end, write old remainder, restore cursor

	if {$myat > 0} {
	    my Write [ctrl::cb] [ctrl::sca] [ctrl::eeol]
	    my Echo $myat
	    my Write [ctrl::rca]

	    incr myat -1
	    set mybuf [lreplace $mybuf $myat $myat]
	} else {
	    my Bell
	}
	return
    }

    method InsertCharacterAtCursor {c} {
	# Add character.

	if {$myover} {
	    # Overwrite at current position.
	    set mybuf [lreplace $mybuf $myat $myat $c]
	    my Echo $myat $myat
	    incr myat
	} else {
	    # Insert at current position, or append.

	    if {$myat == [llength $mybuf]} {
		# Append
		lappend mybuf $c
		incr myat
		my Echo end
	    } else {
		# Insert: Save cursor, delete line
		# to end, write new char, write
		# old remainder, restore cursor.

		set mybuf [linsert $mybuf $myat $c]

		my Write [ctrl::sca] [ctrl::eeol]
		my Echo $myat end
		my Write [ctrl::rca] [ctrl::cf]
		incr myat
	    }
	}
	return
    }

    # Write buffer contents. These may need camouflage
    method Echo {{from 0} {to end}} {
	set buf [join [lrange $mybuf $from $to] {}]
	if {$myhide} { set buf [regsub -all -- . $buf *] }
	my Write $buf
	return
    }

    # # ## ### ##### ######## #############
    ## State

    variable mycstate myin myout mywritebuf myreadbuf mybuf mystate myat myover myhide

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::readline::tty {} {
    return [fstat stdout tty]
}

proc ::stackato::readline::gets {} {
    return [[I new] gets]
}

proc ::stackato::readline::gets* {} {
    return [[I new] gets*]
}

proc ::stackato::readline::platform-columns {} {

    # Use the most reliable way of getting the information (stty -a),
    # and parse out what we need: Split into fields, look for field
    # containing the 'columns' value and return the number. Note how
    # the code does not care whether the keywords is before or after
    # the value, and what other non-numeric stuff might be present
    # (assignment character, etc.). This flexibility deals with all
    # outputs of stty -a seen so far on various platforms:
    #
    # linux:        "... columns 205 ..."
    # aix/os x:     "... 205 columns ..."
    # hpux/solaris: "... columns = 205 ..."

    regexp {([0-9]+)} \
	[lsearch -inline -glob \
	     [split [exec stty -a] ";\n"] \
	     *columns*] \
	-> c

    # Some situations, like an emacs subshell cause stty to provide us
    # with bogus information. We try a few other ways before going to
    # a fixed default.

    if {($c <= 0) && [info exists ::env(COLUMNS)]} {
	set c $::env(COLUMNS)
    }
    if {$c <= 0} {
	set c 80
    }

    return $c
}

# # ## ### ##### ######## ############# #####################
## Ready: Caller creates ensemble and package declaration.
return
