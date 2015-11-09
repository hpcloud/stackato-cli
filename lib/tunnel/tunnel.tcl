# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
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
package require debug

# # ## ### ##### ######## ############# #####################

debug level  tunnel
debug prefix tunnel {}

debug level  tunnel/data
debug prefix tunnel/data {}

# # ## ### ##### ######## ############# #####################

oo::class create ::tunnel {
    # - -- --- ----- -------- -------------
    constructor {} {
	array set myconn     {} ; # sock -> connection controller object
	set mylistener       {}
	set mynumconnections 0

	debug.tunnel {[self] born}
	return
    }

    destructor {
	debug.tunnel {[self] dies}
	return
    }

    # Wait for all connections to become inactive before returning.
    # Inner event-loop handling the whole of tunnel management.

    method wait {{first 1}} {
	debug.tunnel {[self] waiting-on-stop $first}

	while {$first || $mynumconnections} {
	    set first 0
	    vwait [namespace which -variable mynumconnections]
	    debug.tunnel {[self] waiting-on-stop CHECK}
	}

	debug.tunnel {[self] waiting-on-stop OK}
	return
    }

    # Start the listener for local connections.

    method start {args} {
	debug.tunnel {[self] start ($args)}
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
	# - log        /ignored/

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
	debug.tunnel {[self] stop[expr {$conn ? " + connections" : ""}]}

	close $mylistener
	set mylistener {}

	if {!$conn} return

	debug.tunnel {[self] stop connections...}

	foreach sock [array names myconn] {
	    $myconn($sock) close
	    # Indirectly later reaches --> TunnelClose 
	}

	my wait 0
	::exit
	return
    }

    method sanitize {url} {
	set ourl $url
	#checker -scope local exclude warnArgWrite
	if {![regexp {^(https|http|ws)?} $url]} {
	    set url https://$url
	}
	set url [string trimright $url /]

	debug.tunnel {[self] sanitize $ourl ==> '$url'}
	return $url
    }

    # - -- --- ----- -------- -------------

    method NewConnection {once tun_url dst_host dst_port auth_token sock host port} {
	# Local connection is up, start the tunnel, and do not forget
	# to configure the local connection for raw binary transfer,
	# which will be event-based.

	debug.tunnel {[self] new-connection $once $tun_url $dst_host $dst_port $auth_token $sock $host $port}

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

	debug.tunnel {[self] connection controller start...}

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

	debug.tunnel {[self] connection controller $myconn($sock) active...}
	return
    }

    method TunnelOpen {sock} {
	debug.tunnel {[self] tunnel-open $sock}

	# Now we can start reception of local events.
	fileevent $sock readable [callback LocalReceive $sock]
	return
    }

    method LocalReceive {sock} {
	if {[eof $sock]} {
	    debug.tunnel {[self] local-receive $sock /EOF}

	    # Stop local events immediately
	    close $sock
	    $myconn($sock) close
	    # Indirectly later reaches --> TunnelClose 
	    debug.tunnel {[self] local-receive $sock /DONE}
	    return
	}

	set data [read $sock]
	debug.tunnel      {[self] local-receive $sock [string length $data]}
	debug.tunnel/data {[my Hexl "[self] local-receive $sock" $data]}

	# Ignore empty reads.
	if {![string length $data]} return
	$myconn($sock) send $data
	return
    }

    method TunnelReceive {sock data} {
	debug.tunnel      {[self] tunnel-receive $sock [string length $data]}
	debug.tunnel/data {[my Hexl "[self] tunnel-receive $sock" $data]}

	puts -nonewline $sock $data
	return
    }

    method TunnelClose {sock} {
	# Comes from either the tunnel closing due to errors, or
	# explicitly through ---> stop (s.a.).

	debug.tunnel {[self] tunnel-close}

	catch { close $sock }
	$myconn($sock) destroy
	unset myconn($sock)

	debug.tunnel {[self] tunnel-closed}

	incr mynumconnections -1
	return
    }

    # - -- --- ----- -------- -------------

    method Hexl {prefix data} {
	set r {}

        # Convert the data to hex and to characters.
	binary scan $data H*@0a* hexa asciia
	# Replace non-printing characters in the data.
	regsub -all -- {[^[:graph:] ]} $asciia {.} asciia

	# pad with spaces to full block of 32/16.
	set n [expr {[string length $hexa] % 32}]
	if {$n < 32} { append hexa   [string repeat { } [expr {32-$n}]] }
	#debug.tunnel {pad H [expr {32-$n}]}

	set n [expr {[string length $asciia] % 32}]
	if {$n < 16} { append asciia [string repeat { } [expr {16-$n}]] }
	#debug.tunnel {pad A [expr {32-$n}]}

	# Reassemble formatted, in groups of 16 bytes.
	# Hex part is chunks of 32 nibbles.
	while {[string length $hexa]} {
	    # Get front group of 16 bytes each.
	    set hex    [string range $hexa   0 31]
	    set ascii  [string range $asciia 0 15]
	    # Prep for next iteration
	    set hexa   [string range $hexa   32 end]  
	    set asciia [string range $asciia 16 end]

	    # Convert the hex to pairs of hex digits
	    regsub -all -- {..} $hex {& } hex

	    # Put the hex and Latin-1 data to the result
	    append r $prefix { | } $hex { | } $ascii |\n
	}

	return $r
    }

    # - -- --- ----- -------- -------------

    variable mylistener myconn mynumconnections

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
    if {0} {if {$_(scheme) eq "ws"} {
	return [tunnel::ws new {*}$args]
    }}
    return -code error "Invalid url"
}

# # ## ### ##### ######## ############# #####################
package provide tunnel 0
