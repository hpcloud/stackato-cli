# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

# -*- tcl -*-
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
package require cmdr::ask
package require cmdr::color
package require stackato::log
package require stackato::mgr::self
package require stackato::mgr::service
package require stackato::validate::appname

namespace eval ::stackato::mgr {
    namespace export tunnel
    namespace ensemble create
}

namespace eval ::stackato::mgr::tunnel {
    namespace import ::stackato::validate::appname
    rename appname appv

    namespace export \
	pick-port helper app appname uniquename \
	def invalidate-caches pushed? bound? url \
	healthy? auth connection-info \
	start wait-for-start wait-for-end \
	start-local-client

    namespace ensemble create

    namespace import ::cmdr::ask
    namespace import ::cmdr::color
    namespace import ::stackato::log::display
    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::self
    namespace import ::stackato::mgr::service
    namespace import ::stackato::v2
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

proc ::stackato::mgr::tunnel::def {version theapp} {
    debug.mgr/tunnel {}
    # v1: app name
    # v2: app uuid url
    variable thetv      $version
    variable theappref  $theapp ;# ok for v1, v2 correction below.
    # Start with empty caches.
    variable theappdata {}
    variable theurl     {}
    if {$version < 2} return
    set theappref [$theapp url]
    # flush the in-memory app entity to force reload later on.
    $theapp destroy
    return
}

proc ::stackato::mgr::tunnel::app {} {
    debug.mgr/tunnel {}

    variable thetv
    variable theappdata
    variable theappref

    if {$thetv < 2} {
	# v1
	debug.mgr/tunnel {/v1: $theappref}
	return $theappref
    } elseif {$theappdata ne {}} {
	# v2, data cached

	debug.mgr/tunnel {/v2 cached: $theappdata}
	return $theappdata
    } else {
	# v2, fill cache
	set theappdata [v2 deref $theappref]

	debug.mgr/tunnel {/v2 deref $theappref = $theappdata}
	return $theappdata
    }
}

proc ::stackato::mgr::tunnel::AppInfo {client} {
    debug.mgr/tunnel {}
    # assert: thetv == 1

    variable theappdata
    if {$theappdata ne {}} {
	debug.mgr/tunnel {/cached}
	return $theappdata
    }
    try {
	set theappdata [$client app_info [appname]]
    } on error {e} {
	set theappdata {}
    }
    return $theappdata
}

proc ::stackato::mgr::tunnel::invalidate-caches {} {
    debug.mgr/tunnel {}
    #variable theappref ;# primary reference, unchanged
    variable thetv      ;# target version, unchanged, needed
    variable theurl     ;# cache, clear
    variable theappdata ;# cache, clear - see below.

    set theurl {}
    if {($thetv == 2) && ($theappdata ne {})} {
	# flush entity, force reload on next use.
	catch { $theappdata destroy }
    }
    set theappdata {}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::tunnel::auth {client} {
    if {[$client isv2]} {
	set uuid [dict get' [[app] @environment_json] TUNNEL_AUTH {}]
    } else {
	set env  [dict get' [AppInfo $client] env {}]
	set item [lsearch -inline -glob $env TUNNEL_AUTH=*]
	regsub {^TUNNEL_AUTH=} $item {} uuid
    }
    return $uuid
}

proc ::stackato::mgr::tunnel::pushed? {config} {
    debug.mgr/tunnel {}
    set client [$config @client]
    set res [appv known $client [appname] theapp]
    debug.mgr/tunnel {=> $res}

    if {$res} {
	if {[$client isv2]} {
	    def 2 $theapp
	} else {
	    def 1 $theapp
	}
    }
    return $res
}

proc ::stackato::mgr::tunnel::url {allowhttp client} {
    debug.mgr/tunnel {}
    variable theurl

    if {$theurl ne {}} {
	debug.mgr/tunnel {/cached ==> $theurl}
	return $theurl
    }

    if {[$client isv2]} {
	set tun_url [[app] uri]
    } else {
	set tun_url [lindex [dict get [AppInfo $client] uris] 0]
    }

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
		lassign [$client http_get_raw $url] code _ _

		debug.mgr/tunnel {Trying $url ==> $code}

	    } trap {REST HTTP 404} {e o} {
		debug.mgr/tunnel {Trying $url ==> 404 (expected)}
		# A 404 is expected since the request was without authentication

		# Fill cache. See top of proc body for cache use.
		debug.mgr/tunnel {fill cache}
		set theurl $url

		if {$scheme eq "http"} {
		    display "[color warning UNSAFE], at $url"
		} else {
		    display "[color good OK], at $url"
		}

		debug.mgr/tunnel {/done ==> $url}
		return $url
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
		debug.mgr/tunnel {/@dns issue}
	    }
	}

	if {$code < 0} {
	    # DNS setup issue.
	    display [color bad FAILED]
	    err "$e\nPlease configure your DNS to ensure that either\n\thttps://$tun_url or\n\thttp://$tun_url\nare reachable."
	}

	if {$code != 502} break
	display "." 0
	after 1000
    }

    err "Cannot determine URL for $tun_url"
}

proc ::stackato::mgr::tunnel::active? {client} {
    debug.mgr/tunnel {}

    if {[$client isv2]} {
	debug.mgr/tunnel {/v2}

	set active [[app] started?]
    } else {
	debug.mgr/tunnel {/v1}

	set state [dict get' [AppInfo $client] state {}]
	set active [expr {$state eq "STARTED"}]
    }

    debug.mgr/tunnel {/done ==> $active}
    return $active
}

proc ::stackato::mgr::tunnel::healthy? {allowhttp client auth stopcmd} {
    debug.mgr/tunnel {}

    variable helper_version

    # Does the helper application exist, and is it running ?
    # Checked by asking the cloud controller.

    if {![active? $client]} {
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

    set theurl [url $allowhttp $client]/info

    try {
	debug.mgr/tunnel {Verify helper version}

	lassign [Get $client $theurl $auth] code response

	debug.mgr/tunnel {Verify helper version ==> ($response)}

	if {![string length $response]} {
	    err "Bad password, authentication to tunnel failed"
	}

	set info [json::json2dict $response]
	if {[package vcompare \
		 [dict get $info version] \
		 $helper_version] != 0} {
	    err "Version mismatch: [dict get $info version] != $helper_version"
	}

    } trap {REST HTTP 404} {e o} {
	# Something strongly broken. Stop and abort.
	debug.mgr/tunnel {Application not reachable (404)}

	display [color bad "Unable to reach application (404)"]
	{*}$stopcmd
	return 0

    } trap {STACKATO CLIENT CLI CLI-EXIT} {e o} {
	# Pass special error through instead of trying to go
	# forward
	return {*}$o $e

    } on error {e o} {
	debug.mgr/tunnel {@E = '$e'}
	debug.mgr/tunnel {@O = ($o)}

	# Report any other issues as unhealthy and abort the
	# helper app.
	display [color bad $e]
	{*}$stopcmd
	return 0
    }

    debug.mgr/tunnel {OK}
    return 1
}

proc ::stackato::mgr::tunnel::bound? {client service} {
    debug.mgr/tunnel {}

    # service : v1 = name
    #         : v2 = service_instance entity

    if {[$client isv2]} {
	debug.mgr/tunnel {/v2}

	set ps [[app] @service_bindings @service_instance]

	debug.mgr/tunnel {Has   ($ps)}
	debug.mgr/tunnel {Needs ($service)}

	return [llength [struct::list filter $ps [lambda {o x} {
	    $o == $x
	} $service]]]
    } else {
	debug.mgr/tunnel {/v1}
	# XXX check data structures
	set ps [dict get [AppInfo $client] services]

	debug.mgr/tunnel {Has   ($ps)}
	debug.mgr/tunnel {Needs ($service)}

	return [expr {$service in $ps}]
    }
}

proc ::stackato::mgr::tunnel::connection-info {allowhttp client type sname auth} {
    debug.mgr/tunnel {}

    # sname = service instance name

    display "Getting tunnel connection info: " 0

    set theurl [url $allowhttp $client]/services/$sname

    debug.mgr/tunnel {@service-url  $theurl}
    debug.mgr/tunnel {@service-type $type}

    set response {}
    for {set n 0} {$n < 10} {incr n} {
	try {
	    lassign [Get $client $theurl $auth] code response

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
	err "Expected remote tunnel to know about service $sname, but it doesn't"
    }

    display [color good OK]

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
	    err "Could not determine $k for service $sname"
	}
    }

    return $info
}

proc ::stackato::mgr::tunnel::start {allowhttp client trace mode sname local_port connection auth} {
    debug.mgr/tunnel {}
    variable thetunnel

    set once [expr {$mode eq "once"}]
    display "Starting [expr {$once ? "single-shot " : ""}]tunnel to [color {bold name} $sname] on port [color {bold name} $local_port]."

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
		set value [ask string "${varname}: "]
	    }
	}
    }
}

proc ::stackato::mgr::tunnel::Get {client theurl auth} {
    debug.mgr/tunnel {}

    set oldheaders [$client cget -headers]
    try {
	$client configure -headers [list Auth-Token $auth]
	lassign [$client http_get_raw $theurl] code response _
    } finally {
	$client configure -headers $oldheaders
    }

    debug.mgr/tunnel {/done ==> $code ($response)}
    return [list $code $response]
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::mgr::tunnel {
    # State

    variable thetv      0  ;# target version, 1|2, 0 = undefined
    variable theappref  {} ;# v1: app name, v2: app url
    variable theappdata {} ;# v1: app info, v2: entity
    variable theurl     {} ;# tunnel application base url
    variable thetunnel  {} ;# tunnel controller instance

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
