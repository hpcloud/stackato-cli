# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require twapi
package require try

# # ## ### ##### ######## ############# #####################

proc ::stackato::readline::CONTROL {e} {
    if {$e ne "ctrl-c"} { return 0 }
    variable RESULT
    set RESULT {-code error -errorcode {TERM INTERUPT} Interupted}
    return 1
}

proc ::stackato::readline::GET {} {
    variable RESULT
    if {[eof stdin]} {
	Disconnect
	set RESULT {}
	return
    }

    if {[::gets stdin line] < 0} return

    Disconnect
    set RESULT [list $line]
    return
}

proc ::stackato::readline::Connect {} {
    twapi::set_console_control_handler [namespace current]::CONTROL
    fconfigure stdin -blocking 0
    fileevent stdin readable [namespace current]::GET
    return
}

proc ::stackato::readline::Disconnect {} {
    fileevent stdin readable {}
    fconfigure stdin -blocking 1
    twapi::set_console_control_handler {}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::readline::tty {} {
    # Output colorization is disabled on windows.
    return 0
}

proc ::stackato::readline::gets {} {
    variable RESULT
    Connect

    set RESULT {}
    vwait [namespace current]::RESULT

    Disconnect
    return {*}$RESULT
}

proc ::stackato::readline::gets* {} {
    set s [twapi::get_console_handle stdin]
    twapi::modify_console_input_mode $s -echoinput 0 
    try {
	set line [gets]
	puts "";# visible newline
    } finally {
	twapi::modify_console_input_mode $s -echoinput 1
    }
    return $line
}

proc ::stackato::readline::platform-columns {} {
    set s [twapi::get_console_handle stdout]
    set cr [lindex [twapi::get_console_screen_buffer_info $s -windowsize] end]
    lassign $cr c r
    return $c
}

# # ## ### ##### ######## ############# #####################
## Ready: Caller creates ensemble and package declaration.
return
