# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

## This module provides support functionality for service tunnels.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require dictutil
package require json
package require uri
package require tunnel
package require varsub
package require stackato::color
package require stackato::log
package require stackato::term
package require stackato::mgr::self
package require stackato::mgr::service

namespace eval ::stackato::mgr {
    namespace export tunnel
    namespace ensemble create
}

namespace eval ::stackato::mgr::tunnel {
    namespace export \
	pick-port helper appname uniquename \
	appinfo invalidate-appinfo pushed? \
	url bound? healthy? auth connection-info \
	start wait-for-start wait-for-end \
	start-local-client

    namespace ensemble create

    namespace import ::stackato::color
    namespace import ::stackato::term
    namespace import ::stackato::log::display
    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::self
    namespace import ::stackato::mgr::service
}

debug level  mgr/tunnel
debug prefix mgr/tunnel {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## API

proc ::stackato::mgr::tunnel::pick-port {port} {
    debug.mgr/tunnel {}

    variable port_range
    # XXX Possibly use port 0 to get any open port at random from OS ?

    set original $port
    for {set n 0} {$n < $port_range} {incr n; incr port} {
	try {
	    close [socket localhost $port]
	} on error {e o} {
	    # Could not connect, this port is free.
	    return $port
	}
    }

    return [Ephemeral]
}

proc ::stackato::mgr::tunnel::Ephemeral {} {
    debug.mgr/tunnel {}

    set s [socket -server BOGUS -myaddr localhost 0]
    set port [lindex [fconfigure $s -sockname] 2]
    close $s
    return $port
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::tunnel::helper {} {
    debug.mgr/tunnel {}
    variable helper
    return  $helper
}

proc ::stackato::mgr::tunnel::appname {} {
    debug.mgr/tunnel {}
    # This is the application name. No randomization for it.
    variable appname
    return  $appname
}

proc ::stackato::mgr::tunnel::uniquename {} {
    debug.mgr/tunnel {}

    # This is the url the application will be mapped to and appear
    # under.  Assuming that the user did not ask for a specific
    # one. See method 'PushTunnelHelper' and callers.
    return [service random-name-for [appname]]
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::tunnel::appinfo {client} {
    variable theappinfo
    debug.mgr/tunnel {}

    if {$theappinfo ne {}} { return $theappinfo }

    try {
	set theappinfo [$client app_info [appname]]
    } on error {e} {
	set theappinfo {}
    }
    return $theappinfo
}

proc ::stackato::mgr::tunnel::invalidate-appinfo {} {
    debug.mgr/tunnel {}
    variable theappinfo {}
    variable theurl  {}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::tunnel::auth {client} {
    set env  [dict get' [appinfo $client] env {}]
    set item [lsearch -inline -glob $env TUNNEL_AUTH=*]
    regsub {^TUNNEL_AUTH=} $item {} uuid
    return $uuid
}

proc ::stackato::mgr::tunnel::pushed? {client} {
    debug.mgr/tunnel {}
    set res [expr {[appinfo $client] ne {}}]
    debug.mgr/tunnel {=> $res}
    return $res
}

proc ::stackato::mgr::tunnel::url {allowhttp client} {
    debug.mgr/tunnel {}
    variable theurl

    if {$theurl ne {}} { return $theurl }

    set tun_url [lindex [dict get [appinfo $client] uris] 0]

    # Try multiple times (10 seconds) to wait out the period
    # between the application having started and actually becoming
    # visible under its url.

    display "Getting tunnel url: " 0

    for {set n 0} {$n < 10} {incr n} {
	# Prevent the use of http urls by default and prefer https
	# over http even if --allow-http was set.

	set     schemes {}
	lappend schemes https
	if {$allowhttp} {
	    lappend schemes http
	}

	foreach scheme $schemes {
	    set url $scheme://$tun_url

	    try {
		# Raw http client.

		debug.mgr/tunnel {Trying $url}
		set token [http::geturl $url]
		set code  [http::ncode $token]
		http::cleanup $token

		debug.mgr/tunnel {Trying $url ==> $code}
		if {$code == 404} {
		    # A 404 is expected since the request was without authentication
		    set theurl $url

		    if {$scheme eq "http"} {
			display "[color yellow UNSAFE], at $url"
		    } else {
			display "[color green OK], at $url"
		    }
		    return $url
		}
		#my get $url ; # Inherited rest client
	    } trap {POSIX ECONNREFUSED} {e o} {
		# XXX ignored total failure.
		debug.mgr/tunnel {@refused}
	    } on error {e o} {
		# XXX ignore any failure
		debug.mgr/tunnel {@E = '$e'}
		debug.mgr/tunnel {@O = ($o)}

		if {![string match {*couldn't open*} $e]} {
		    return {*}$o $e
		}
		# Fake code for when socket could not be opened,
		# indicating DNS issues with the setup.
		set code -999
	    }
	}

	if {$code < 0} {
	    # DNS setup issue.
	    display [color red FAILED]
	    err "$e\nPlease configure your DNS to ensure that either\n\thttps://$tun_url or\n\thttp://$tun_url\nare reachable."
	}

	if {$code != 502} break
	display "." 0
	after 1000
    }

    err "Cannot determine URL for $tun_url"
}

proc ::stackato::mgr::tunnel::healthy? {allowhttp client token stopcmd} {
    debug.mgr/tunnel {}

    variable helper_version

    # Does the helper application exist, and is it running ?
    # Checked by asking the cloud controller.

    if {[dict get [appinfo $client] state] ne "STARTED"} {
	debug.mgr/tunnel {Helper present, not running}
	return 0
    }

    # We know that the application is present and active. Now is
    # the time to check that our version of the protocol matches
    # with the helper itself. We expect to get proper responses
    # back, without errors.

    # The CLI-EXIT error indicates low-level socket trouble,
    # i.e. getting to the application through its url, and is
    # reported as is, plus a message to look into possible DNS
    # setup issues.

    # Anything else is reported as is and forces a complete
    # redeployment of the helper application as attempt to fix
    # whatever it is.

    # Now, an empty JSON response is not an error of the tunnel,
    # but more likely a bad password on our part. This is reported
    # as such and aborts the commands, instead of re-deploying the
    # helper and overwriting the authentication with the new
    # password.

    try {
	debug.mgr/tunnel {Verify helper version}
	set token [http::geturl [url $allowhttp $client]/info \
		       -headers [list Auth-Token $token]]
	set response [http::data $token]
	http::cleanup $token

	debug.mgr/tunnel {Verify helper version ==> ($response)}

	if {![string length $response]} {
	    err "Bad password, authentication to tunnel failed"
	}

	set info [json::json2dict $response]
	if {[package vcompare \
		 [dict get $info version] \
		 $helper_version] != 0} {
	    error "Version mismatch: [dict get $info version] != $helper_version"
	}
    } trap {STACKATO CLIENT CLI CLI-EXIT} {e o} {
	# Pass special error through instead of trying to go
	# forward
	return {*}$o $e

    } on error {e o} {
	debug.mgr/tunnel {@E = '$e'}
	debug.mgr/tunnel {@O = ($o)}

	# Report any other issues as unhealthy and abort the
	# helper app.
	display [color red $e]
	{*}$stopcmd
	return 0
    }

    debug.mgr/tunnel {OK}
    return 1
}

proc ::stackato::mgr::tunnel::bound? {client service} {
    debug.mgr/tunnel {}

    # XXX check data structures
    set ps [dict get [appinfo $client] services]

    debug.mgr/tunnel {Has   ($ps)}
    debug.mgr/tunnel {Needs ($service)}

    return [expr {$service in $ps}]
}

proc ::stackato::mgr::tunnel::connection-info {allowhttp client type service token} {
    debug.mgr/tunnel {}

    display "Getting tunnel connection info: " 0

    debug.mgr/tunnel {@U [url $allowhttp $client]/services/$service}
    debug.mgr/tunnel {@T $type}

    set response {}
    for {set n 0} {$n < 10} {incr n} {
	try {
	    set token [http::geturl [url $allowhttp $client]/services/$service \
			   -headers [list Auth-Token $token]]
	    set response [http::data  $token]
	    set code     [http::ncode $token]
	    http::cleanup $token
	    if {$code == 200} break
	    after 1000
	} on error {e o} {
	    debug.mgr/tunnel {@E = '$e'}
	    debug.mgr/tunnel {@O = ($o)}

	    after 1000
	}
	display "." 0
    }

    if {$response eq {}} {
	err "Expected remote tunnel to know about $service, but it doesn't"
    }

    display [color green OK]

    debug.mgr/tunnel {R = ($code) <$response>}

    # Post processing ... JSON to dict.
    set info [json::json2dict $response]

    debug.mgr/tunnel {RawInfo = [dict printx \t $info]}

    # Post processing, specific to service (type).
    switch -exact -- $type {
	rabbitmq {
	    debug.mgr/tunnel {--> rabbitmq}

	    if {[dict exists $info url]} {
		array set _ [uri::split [dict get $info url]]
		#parray _
		dict set info hostname $_(host)
		dict set info port     $_(port)
		dict set info vhost    $_(path);#XXX split further, see below
		dict set info user     $_(user)
		dict set info password $_(password)
		dict unset info url
		# XXX info["vhost"] = uri.path[1..-1], see above
	    }
	}
	mongodb {
	    debug.mgr/tunnel {--> mongo}

	    # "db" is the "name", existing "name" is trash
	    dict set info name [dict get $info db]
	    dict unset info db
	}
	redis {
	    debug.mgr/tunnel {--> redis}

	    # name irrelevant
	    dict unset info name
	}
	default {
	    debug.mgr/tunnel {--> $type (nothing done)}
	}
    }

    debug.mgr/tunnel {ProcessedInfo = [dict printx \t $info]}

    # Validation
    foreach k {hostname port password} {
	if {![dict exists $info $k]} {
	    err "Could not determine $k for $service"
	}
    }

    return $info
}

proc ::stackato::mgr::tunnel::start {allowhttp client trace mode service local_port connection auth} {
    debug.mgr/tunnel {}
    variable thetunnel

    set once [expr {$mode eq "once"}]
    display "Starting [expr {$once ? "single-shot " : ""}]tunnel to [color bold $service] on port [color bold $local_port]."

    set thetunnel [tunnel new]
    $thetunnel start \
	local_port $local_port \
	tun_url    [url $allowhttp $client] \
	dst_host   [dict get $connection hostname] \
	dst_port   [dict get $connection port] \
	auth_token $auth \
	once       $once \
	log       $trace
    # At this point the server socket for the local tunnel is active
    # and listening. The listener is automatically killed when the
    # first connection is made.
    return
}


proc ::stackato::mgr::tunnel::wait-for-start {port} {
    debug.mgr/tunnel {}

    # start has been called, which ran ($thetunnel start), and that
    # means that the server socket is already listening.
    return 1

    # XXX drop this.
    set first 1
    for {set n 0} {$n < 10} {incr n} {
	try {
	    close [socket localhost $port]
	    if {$n} { display "" }
	    return 1
	} on error {e o} {
	    if {$n == 0} {
		display "Waiting for local tunnel to become available" 0
	    }
	    display . 0
	    after 1000
	}
    }
    err "Could not connect to local tunnel."
}

proc ::stackato::mgr::tunnel::wait-for-end {} {
    debug.mgr/tunnel {}

    display "Open another shell to run command-line clients or"
    display "use a UI tool to connect using the displayed information."
    display "Press Ctrl-C to exit..."
    vwait forever
    return
}

# See also c_apps service_dbshell, and subordinate methods.
#
# Might be interesting to reuse this set of client information
# instead of hardwiring the syntax and requirements.

proc ::stackato::mgr::tunnel::start-local-client {clients command info port} {
    variable thetunnel

    debug.mgr/tunnel {}
    # command = client, name, or full path. First element of the
    # command line we are constructing.

    set client [dict get $clients [file root [file tail $command]]]

    set     cmdline $command
    lappend cmdline {*}[ResolveSymbols \
			    [dict get $client command] \
			    $info \
			    $port]
    set theenv {}
    set printenv {}
    foreach item [dict get' $client environment {}] {
	regexp {([^=]+)=(["']?)([^"']*)} $item -> key _ value
	set value [ResolveSymbols $value $info $port]
	lappend theenv $key $value
	lappend printenv "${key}='$value'"
    }
    set printenv "[join $printenv] "

    display "Launching '$printenv$cmdline'"
    display ""

    array set ::env $theenv
    if {[catch {
	# We are starting the command in the background (&)
	# to prevent exec from blocking the event-loop below.
	# The command is connected to the terminal channels, as
	# are we (logging). When the command ends it closes the
	# local socket, this destroys the tunnel and ends our
	# waiting as well.
	exec 2>@ stderr >@ stdout <@ stdin {*}$cmdline &
    }]} {
	return 0
    }
    # Here now waiting for the command to end and close
    # the tunnel.
    $thetunnel wait
    return 1
}

proc ::stackato::mgr::tunnel::ResolveSymbols {str info local_port} {
    debug.mgr/tunnel {}
    set callback [list ::stackato::mgr::tunnel::Resolver $info $local_port]
    return [varsub::resolve $str $callback]
}

proc ::stackato::mgr::tunnel::Resolver {info local_port varname} {
    dict with info {} ; # leave local variables behind.
    switch -- $varname {
	name     { set value $name }
	host     { set value localhost }
	port     { set value $local_port }
	password { set value $password }
	username -
	user     { set value [dict get' $info username {}] }
	default  {
	    # For non-standard variables, first look to the
	    # info dictionary for the value, and if that
	    # fails, ask the user interactively for it.
	    if {[dict exists $info $varname]} {
		set value [dict get $info $varname]
	    } else {
		set value [term ask/string "${varname}: "]
	    }
	}
    }
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::mgr::tunnel {
    # State

    variable theappinfo {}
    variable theurl     {}
    variable thetunnel  {}

    # Configuration

    variable port_range 10

    # Bump this AND the version info reported by HELPER/server.rb
    # Keep the helper in sync with any updates here
    variable helper_version 0.0.4
    variable helper         [file join [self topdir] tunnel]
    variable appname        tunnel
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::tunnel 0
