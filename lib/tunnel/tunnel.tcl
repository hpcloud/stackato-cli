# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################
## Tunneling. Instances open a tunnel specified by url and manage the
## flow of data through it.
#
## This is sort of an bidirectional 'fcopy' merged with a socket
## listener. As the tunnel is not a proper Tcl channel we have to do
## everything manually.

package require Tcl 8.5
package require TclOO
package require ooutil
package require uri
package require tunnel::http ; # Actual tunnel implementation.

# # ## ### ##### ######## ############# #####################

oo::class create ::tunnel {
    # - -- --- ----- -------- -------------
    constructor {} {
	array set myconn     {} ; # sock -> connection controller object
	set mylistener       {}
	set mynumconnections 0
	set mylog            0

	my log {[self] LISTEN born}
	return
    }

    destructor {
	my log {[self] LISTEN dies}
	return
    }

    # Wait for all connections to become inactive before returning.
    # Inner event-loop handling the whole of tunnel management.

    method wait {{first 1}} {
	my log {[self] LISTEN waiting-on-stop}

	while {$first || $mynumconnections} {
	    set first 0
	    vwait [namespace which -variable mynumconnections]
	    my log {[self] LISTEN waiting-on-stop CHECK}
	}

	my log {[self] LISTEN waiting-on-stop OK}
	return
    }

    # Start the listener for local connections.

    method start {args} {
	# args = options = dictionary.

	# Terminal interupts shutting down the application are
	# intercepted and kill both listener and active connections.

	if {$::tcl_platform(platform) eq "windows"} {
	    signal          trap {TERM INT} [callback stop 1]
	} else {
	    signal -restart trap {TERM INT} [callback stop 1]
	}

	dict with args {} ; # Unpack dictionary into the
	# local scope, leaves the local variables behind.
	# - local_port (int)
	# - tun_url    (string)
	# - dst_host   (string)
	# - dst_port   (int)
	# - auth_token (string)
	# - once       (boolean)
	# - log

	set mylog $log
	if {$mylog eq {}} { set mylog 0 }

	my log {[self] LISTEN start $args}

	set tun_url [my sanitize $tun_url]

	set mylistener [socket -server \
			    [callback NewConnection $once $tun_url \
				 $dst_host $dst_port $auth_token] \
			    $local_port]

	# Wait until the tunnel done.
	# vwait myflag
	return
    }

    # Stop the listener for local connection and all active
    # connections. The latter only if so specified.

    method stop {{conn 0}} {
	my log {[self] LISTEN stop[expr {$conn ? " + connections" : ""}]}

	close $mylistener
	set mylistener {}

	if {!$conn} return

	my log {[self] LISTEN stop connections...}

	foreach sock [array names myconn] {
	    $myconn($sock) close
	    # Indirectly later reaches --> TunnelClose 
	}

	my wait 0
	::exit
	return
    }

    method sanitize {url} {
	my log* {[self] LISTEN sanitize '$url' ==> }

	#checker -scope local exclude warnArgWrite
	if {![regexp {^(https|http|ws)?} $url]} {
	    set url https://$url
	}
	set url [string trimright $url /]

	my log {'$url'}
	return $url
    }

    # - -- --- ----- -------- -------------

    method NewConnection {once tun_url dst_host dst_port auth_token sock host port} {
	# Local connection is up, start the tunnel, and do not forget
	# to configure the local connection for raw binary transfer,
	# which will be event-based.

	my log {[self] LISTEN $sock new-connection}

	incr mynumconnections

	# Stop listening to prevent multiple local connections, if so
	# specified.

	if {$once} {
	    my stop
	}

	# Initialize the data socket for raw, event-based transfer
	fconfigure $sock \
	    -blocking    0 \
	    -buffering   none \
	    -translation binary

	my log {[self] LISTEN $sock controller ...}

	# And construct the connection controller
	set myconn($sock) \
	    [tunnel::Tunnel \
		 tun_url    $tun_url \
		 dst_host   $dst_host \
		 dst_port   $dst_port \
		 auth_token $auth_token \
		 onopen     [callback TunnelOpen    $sock] \
		 onreceive  [callback TunnelReceive $sock] \
		 onclose    [callback TunnelClose   $sock]]

	my log {[self] LISTEN $sock controller active...}
	return
    }

    method TunnelOpen {sock} {
	my log {[self] LISTEN $sock tunnel-open}

	# Now we can start reception of local events.
	fileevent $sock readable [callback LocalReceive $sock]
	return
    }

    method LocalReceive {sock} {
	if {[eof $sock]} {
	    my log {[self] LISTEN $sock local-receive EOF}

	    # Stop local events immediately
	    close $sock
	    $myconn($sock) close
	    # Indirectly later reaches --> TunnelClose 
	    return
	}

	set data [read $sock]
	my log {[self] LISTEN $sock local-receive [string length $data]}

	# Ignore empty reads.
	if {![string length $data]} return
	$myconn($sock) send $data
	return
    }

    method TunnelReceive {sock data} {
	my log {[self] LISTEN $sock tunnel-receive [string length $data]}

	puts -nonewline $sock $data
	return
    }

    method TunnelClose {sock} {
	# Comes from either the tunnel closing due to errors, or
	# explicitly through ---> stop (s.a.).

	my log {[self] LISTEN $sock tunnel-close}

	catch { close $sock }
	$myconn($sock) destroy
	unset myconn($sock)

	my log {[self] LISTEN $sock tunnel-closed}

	incr mynumconnections -1
	return
    }

    # - -- --- ----- -------- -------------

    method log {text} {
	if {!$mylog} return
	puts stderr [uplevel 1 [list subst $text]]
	return
    }

    method log* {text} {
	if {!$mylog} return
	puts -nonewline stderr [uplevel 1 [list subst $text]]
	return
    }

    # - -- --- ----- -------- -------------

    variable mylistener myconn mynumconnections mylog

    # - -- --- ----- -------- -------------
}

# # ## ### ##### ######## ############# #####################
## Tunnel factory

proc ::tunnel::Tunnel {args} {
    # args = options = dictionary.

    set url [dict get $args tun_url]

    array set _ [uri::split $url]

    if {$_(scheme) in {http https}} {
	return [tunnel::http new {*}$args]
    }
    if 0 {if {$_(scheme) eq "ws"} {
	return [tunnel::ws new {*}$args]
    }}
    return -code error "Invalid url"
}

# # ## ### ##### ######## ############# #####################
package provide tunnel 0
