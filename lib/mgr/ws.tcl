# -*- tcl -*-
# # ## ### ##### ######## ############# #####################
# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require websocket
package require dictutil
package require stackato::mgr::auth

# Default log level is 'warn'+. For regular operation we disable that.
::websocket::loglevel emergency
#::websocket::loglevel debug

namespace eval ::stackato::mgr {
    namespace export ws
    namespace ensemble create
}

namespace eval ::stackato::mgr::ws {
    namespace export open close wait stop error
    namespace ensemble create

    namespace import ::stackato::mgr::auth

    # event loop control variable
    variable sink

    # websocket handle
    variable sock

    # flag for local close
    variable close 0
}

debug level  mgr/ws
debug prefix mgr/ws {[debug caller] | }

debug level  mgr/ws/data
debug prefix mgr/ws/data {}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::ws::open {target url actions} {
    debug.mgr/ws {}
    debug.mgr/ws/data {[::websocket::loglevel debug]}
    variable sock
    # action = dict ( text|binary|error|close -> cmd )
    # text must be defined.
    # error, close have defaults.

    debug.mgr/ws {target = $target}
    debug.mgr/ws {url    = $url}

    lappend headers Origin        $target
    lappend headers AUTHORIZATION [auth get]

    set sock [websocket::open $target$url \
		  [namespace code [list WS $actions]] \
		  -headers $headers]
    return $sock
}

proc ::stackato::mgr::ws::close {} {
    debug.mgr/ws {}
    variable sock
    variable close 1 ;# prevent user callback on close
    websocket::close $sock
    return
}

proc ::stackato::mgr::ws::wait {} {
    debug.mgr/ws {}
    variable sink
    vwait [namespace current]::sink
    return {*}$sink
}

proc ::stackato::mgr::ws::stop {} {
    debug.mgr/ws {}
    variable sink
    # Abort event loop in 'wait', regular return
    set sink [list -code ok {}]
    return
}

proc ::stackato::mgr::ws::error {msg} {
    debug.mgr/ws {}
    variable sink
    # Abort the event loop in 'wait' and throw an error.
    set sink [list -code error \
		  -errorcode {STACKATO CLIENT CLI CLI-EXIT} \
		  "Error: $msg"]
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::ws::WS {actions sock type msg} {
    # Receiver for the websocket data stream.
    debug.mgr/ws/data {WS  ($sock $type)}
    #debug.mgr/ws/data {[http::Hexl {WSD } $msg]}
    debug.mgr/ws/data {WSD ($msg)}

    # type in
    # * binary     - data binary
    # * close      - connection close pending
    # * connect    - connection is open
    # * disconnect - connection closed by remote
    # * error      - general error
    # * ping       - liveness
    # * text       - data, text

    switch -exact -- $type {
	error {
	    # Default: Throw the error.
	    {*}[dict get' $actions error \
		    ::stackato::mgr::ws::error] \
		$msg
	}
	close {
	    # No callback if we are closing the connection on our own.
	    variable close
	    if {$close} return

	    # Default: Simply stop.
	    {*}[dict get' $actions close \
		    ::stackato::mgr::ws::stop]
	}
	binary {
	    if {[dict exists $actions binary]} {
		{*}[dict get $actions binary] $msg
		return
	    }
	    {*}[dict get' $actions error \
		    ::stackato::mgr::ws::error] \
		"Unexpected binary frame on websocket channel"
	}
	text {
	    # Data reception. No default.
	    {*}[dict get $actions text] $msg
	}
	connect {
	    if {![dict exists $actions connect]} return
	    {*}[dict get $actions connect]
	}
	disconnect -
	ping       {}
	default    {
	    {*}[dict get' $actions error \
		    ::stackato::mgr::ws::error] \
		"Unknown event $type for websocket channel"
	}
    }
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::ws 0
return
