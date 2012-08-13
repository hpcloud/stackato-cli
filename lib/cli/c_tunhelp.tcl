# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require try            ;# I want try/catch/finally
package require TclOO
package require table
package require tunnel
package require varsub
package require stackato::client::cli::config
package require stackato::client::cli::command::ServiceHelp
package require stackato::client::cli::command::ManifestHelp

namespace eval ::stackato::client::cli::command::TunnelHelp {
    variable port_range 10
    variable helper [file join [stackato::client::cli::config topdir] tunnel]

    # Bump this AND the version info reported by HELPER/server.rb
    # Keep the helper in sync with any updates here
    variable helper_version 0.0.4
}

debug level  cli/tunnel/support
debug prefix cli/tunnel/support {[::debug::snit::call] | }

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::client::cli::command::TunnelHelp {
    superclass ::stackato::client::cli::command::ServiceHelp \
	::stackato::client::cli::command::ManifestHelp

    # # ## ### ##### ######## #############

    constructor {args} {
	Debug.cli/tunnel/support {}

	set mytunappinfo {}
	set mytunnelurl  {}
	set mytunnel     {}
	set myappcmd     {}
	next {*}$args
    }

    destructor {
	Debug.cli/tunnel/support {}
    }

    method tunnel_auth {} {
	set env  [dict get' [my tunnel_app_info] env {}]
	set item [lsearch -inline -glob $env TUNNEL_AUTH=*]
	regsub {^TUNNEL_AUTH=} $item {} uuid
	return $uuid
    }

    method tunnel_uniquename {} {
	Debug.cli/tunnel/support {}

	# This is the url the application will be mapped to and appear under.
	# Assuming that the user did not ask for a specific one. See method
	# 'push_tunnel_helper' and callers.
	return [my random_service_name [my tunnel_appname]]
    }

    method tunnel_appname {} {
	Debug.cli/tunnel/support {}

	# This is the application name. No randomization for it.
	return "tunnel"
    }

    method tunnel_app_info {} {
	Debug.cli/tunnel/support {}

	if {$mytunappinfo ne {}} { return $mytunappinfo }
	try {
	    set mytunappinfo [[my client] app_info [my tunnel_appname]]
	} on error {e} {
	    set mytunappinfo {}
	}
	return $mytunappinfo
    }

    method tunnel_url {} {
	Debug.cli/tunnel/support {}

	if {$mytunnelurl ne {}} { return $mytunnelurl }

	set tun_url [lindex [dict get [my tunnel_app_info] uris] 0]

	# Try multiple times (10 seconds) to wait out the period
	# between the application having started and actually becoming
	# visible under its url.

	display "Getting tunnel url: " 0

	for {set n 0} {$n < 10} {incr n} {

	    # Prevent use of http urls by default and prefer https
	    # over http even if --allow-http was set.
	    set     schemes {}
	    lappend schemes https
	    if {[config allow-http]} {
		lappend schemes http
	    }

	    foreach scheme $schemes {
		set url $scheme://$tun_url

		try {
		    # Raw http client.

		    Debug.cli/tunnel/support {Trying $url}
		    set token [http::geturl $url]
		    set code  [http::ncode $token]
		    http::cleanup $token

		    Debug.cli/tunnel/support {Trying $url ==> $code}
		    if {$code == 404} {
			# A 404 is expected since the request was without authentication
			set mytunnelurl $url

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
		    Debug.cli/tunnel/support {@refused}
		} on error {e o} {
		    # XXX ignore any failure
		    Debug.cli/tunnel/support {@E = '$e'}
		    Debug.cli/tunnel/support {@O = ($o)}

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

    method invalidate_tunnel_app_info {} {
	Debug.cli/tunnel/support {}

	set mytunnelurl  {}
	set mytunappinfo {}
	return
    }

    method tunnel_pushed? {} {
	Debug.cli/tunnel/support {}

	set res [expr {[my tunnel_app_info] ne {}}]

	Debug.cli/tunnel/support {=> $res}
	return $res
    }

    method tunnel_healthy? {token} {
	Debug.cli/tunnel/support {}

	variable ::stackato::client::cli::command::TunnelHelp::helper_version

	# Does the helper application exist, and is it running ?
	# Checked by asking the cloud controller.

	if {[dict get [my tunnel_app_info] state] ne "STARTED"} {
	    Debug.cli/tunnel/support {Helper present, not running}
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
	    Debug.cli/tunnel/support {Verify helper version}
	    set token [http::geturl [my tunnel_url]/info \
			   -headers [list Auth-Token $token]]
	    set response [http::data $token]
	    http::cleanup $token

	    Debug.cli/tunnel/support {Verify helper version ==> ($response)}

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
	    Debug.cli/tunnel/support {@E = '$e'}
	    Debug.cli/tunnel/support {@O = ($o)}

	    # Report any other issues as unhealthy and abort the
	    # helper app.
	    display [color red $e]
	    my stop_tunnel_helper
	    return 0
	}

	Debug.cli/tunnel/support {OK}
	return 1
    }

    method tunnel_bound? {service} {
	Debug.cli/tunnel/support {}

	# XXX check data structures
	set ps [dict get [my tunnel_app_info] services]

	Debug.cli/tunnel/support {Has   ($ps)}
	Debug.cli/tunnel/support {Needs ($service)}

	return [expr {$service in $ps}]
    }

    method tunnel_connection_info {type service token} {
	Debug.cli/tunnel/support {}

	display "Getting tunnel connection info: " 0

	Debug.cli/tunnel/support {@U [my tunnel_url]/services/$service}
	Debug.cli/tunnel/support {@T $type}

	set response {}
	for {set n 0} {$n < 10} {incr n} {
	    try {
		set token [http::geturl [my tunnel_url]/services/$service \
			       -headers [list Auth-Token $token]]
		set response [http::data  $token]
		set code     [http::ncode $token]
		http::cleanup $token
		if {$code == 200} break
		after 1000
	    } on error {e o} {
		Debug.cli/tunnel/support {@E = '$e'}
		Debug.cli/tunnel/support {@O = ($o)}

		after 1000
	    }
	    display "." 0
	}

	if {$response eq {}} {
	    err "Expected remote tunnel to know about $service, but it doesn't"
	}

	display [color green OK]

	Debug.cli/tunnel/support {R = ($code) <$response>}

	# Post processing ... JSON to dict.
	set info [json::json2dict $response]

	Debug.cli/tunnel/support {RawInfo = [dict printx \t $info]}

	# Post processing, specific to service (type).
	switch -exact -- $type {
	    rabbitmq {
		Debug.cli/tunnel/support {--> rabbitmq}

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
		Debug.cli/tunnel/support {--> mongo}

		# "db" is the "name", existing "name" is trash
		dict set info name [dict get $info db]
		dict unset info db
	    }
	    redis {
		Debug.cli/tunnel/support {--> redis}

		# name irrelevant
		dict unset info name
	    }
	    default {
		Debug.cli/tunnel/support {--> $type (nothing done)}
	    }
	}

	Debug.cli/tunnel/support {ProcessedInfo = [dict printx \t $info]}

	# Validation
	foreach k {hostname port password} {
	    if {![dict exists $info $k]} {
		err "Could not determine $k for $service"
	    }
	}

	return $info
    }

    method display_tunnel_connection_info info {
	Debug.cli/tunnel/support {}

	display ""
	display "Service connection info: "

	# Determine which keys to show, and ensure that the first
	# three are about user, password, and database.

        # TODO: modify the server services rest call to have explicit
        # knowledge about the items to return.  It should return all
        # of them if the service is unknown so that we don't have to
        # do this weird filtering.

	Debug.cli/tunnel/support {TunnelInfo = [dict print $info]}

	set to_show {{} {} {}}
	foreach k [dict keys $info] {
	    switch -exact -- $k {
		host - hostname - port - node_id {}
		user - username {
		    # prefer username, but get by if there is only user
		    if {[lindex $to_show 0] ne "username"} {
			lset to_show 0 $k
		    }
		}
		password { lset to_show 1 $k }
		name     { lset to_show 2 $k }
		default {
		    lappend to_show $k
		}
	    }
	}

	Debug.cli/tunnel/support {KeysToShow ($to_show)}

	table::do t {Key Value} {
	    foreach k $to_show {
		if {$k eq {}} continue
		$t add $k [dict get $info $k]
	    }
	}
	$t show display
	display ""
	return
    }

    method start_tunnel {mode service local_port connection auth} {
	Debug.cli/tunnel/support {}

	set once [expr {$mode eq "once"}]
	display "Starting [expr {$once ? "single-shot " : ""}]tunnel to [color bold $service] on port [color bold $local_port]."

	set mytunnel [tunnel new]
	$mytunnel start \
	    local_port $local_port \
	    tun_url    [my tunnel_url] \
	    dst_host   [dict get $connection hostname] \
	    dst_port   [dict get $connection port] \
	    auth_token $auth \
	    once       $once \
	    log        [config trace]
	# At this point the server socket for the local tunnel is
	# active and listening. The listener is autoamtically killed
	# when the first connection is made.
	return
    }

    method pick_tunnel_port {port} {
	Debug.cli/tunnel/support {}

	variable ::stackato::client::cli::command::TunnelHelp::port_range
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

	my ephemeral_port
    }

    method ephemeral_port {} {
	Debug.cli/tunnel/support {}

	set s [socket -server BOGUS -myaddr localhost 0]
	set port [lindex [fconfigure $s -sockname] 2]
	close $s
	return $port
    }

    method wait_for_tunnel_start {port} {
	Debug.cli/tunnel/support {}

	# start_tunnel has been called, which ran (mytunnel start), and
	# that means that the server socket is already listening.
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

    method wait_for_tunnel_end {} {
	Debug.cli/tunnel/support {}

	display "Open another shell to run command-line clients or"
	display "use a UI tool to connect using the displayed information."
	display "Press Ctrl-C to exit..."
	vwait forever
	return
    }

    method resolve_symbols {str info local_port} {
	Debug.cli/tunnel/support {}

	return [varsub::resolve $str \
		    [callback resolver $info $local_port]]
    }

    method resolver {info local_port varname} {
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

    # See also c_apps service_dbshell, and subordinate methods.
    #
    # Might be interesting to reuse this set of client information
    # instead of hardwiring the syntax and requirements.

    method start_local_prog {clients command info port} {
	Debug.cli/tunnel/support {}
	# command = client, name, or full path. First element of the
	# command line we are constructing.

	set client [dict get $clients [file root [file tail $command]]]

	set     cmdline $command
	lappend cmdline {*}[my resolve_symbols \
				[dict get $client command] \
				$info \
				$port]
	set theenv {}
	set printenv {}
	foreach item [dict get' $client environment {}] {
	    regexp {([^=]+)=(["']?)([^"']*)} $item -> key _ value
	    set value [my resolve_symbols $value $info $port]
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
	$mytunnel wait
	return 1
    }

    method push_tunnel_helper {token turl} {
	Debug.cli/tunnel/support {}

	variable ::stackato::client::cli::command::TunnelHelp::helper

	Debug.cli/tunnel/support {app = $helper}

	if {$turl eq {}} {
	    set turl [my tunnel_uniquename].[config suggest_url]
	}

	manifest setup [self] $helper {} reset
	manifest current@path

	# We know everything about the helper.
	[my client] create_app [my tunnel_appname] \
	    [dict create \
		 name [my tunnel_appname] \
		 staging {framework sinatra} \
		 uris [list $turl] \
		 instances 1 \
		 resources {memory 64} \
		 env [list TUNNEL_AUTH=$token]]

	my App upload_app_bits [my tunnel_appname] $helper
	my invalidate_tunnel_app_info
	return
    }

    method stop_tunnel_helper {} {
	Debug.cli/tunnel/support {}

	my App stop [my tunnel_appname]
	my invalidate_tunnel_app_info
	return
    }

    method start_tunnel_helper {} {
	Debug.cli/tunnel/support {}

	my App start [my tunnel_appname]
	my invalidate_tunnel_app_info
	return
    }

    method App {args} {
	Debug.cli/tunnel/support {}

	if {$myappcmd eq {}} {
	    set myappcmd [command::Apps new {*}[my options] tail 0]
	    $myappcmd client [my client]
	}
	return [$myappcmd {*}$args]
    }

    # # ## ### ##### ######## #############
    ## State

    variable mytunappinfo mytunnelurl mytunnel \
	myappcmd

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::client::cli::command::TunnelHelp 0
