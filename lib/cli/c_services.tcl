# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require try            ;# I want try/catch/finally
package require lambda
package require uuid
package require TclOO
package require stackato::client::cli::command::TunnelHelp
package require stackato::client::cli::command::Apps
package require stackato::client::cli::command::LogStream
package require stackato::jmap
package require stackato::term

namespace eval ::stackato::client::cli::command::Services {}

debug level  cli/services
debug prefix cli/services {[::debug::snit::call] | }

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::client::cli::command::Services {
    superclass ::stackato::client::cli::command::TunnelHelp \
	::stackato::client::cli::command::LogStream
    # tunnel-help inherits servicehelp

    # # ## ### ##### ######## #############

    constructor {args} {
	Debug.cli/services {}

	# Namespace import, sort of.
	namespace path [linsert [namespace path] end \
			    ::stackato ::stackato::log ::stackato::client::cli]
	next {*}$args

	# Make the current group available, if any, ensuring validity
	my confer-group
	return
    }

    destructor {
	Debug.cli/services {}
    }

    # # ## ### ##### ######## #############
    ## API

    method service {name} {
	Debug.cli/services {}

	set s [[my client] get_service $name]

	if {[my GenerateJson]} {
	    display [jmap service $s]
	    return
	}

	table::do t {What Value} {
	    foreach k [lsort -dict [dict keys $s]] {
		set v [dict get $s $k]

		if {$k eq "name"} continue
		if {$k in {meta credentials}} {
		    $t add $k {}

		    foreach k [lsort -dict [dict keys $v]] {
			set vx [dict get $v $k]
			if {$k in {created updated}} {
			    set vx [clock format $vx]
			}
			$t add "- $k" $vx
		    }
		    $t add {} {}
		    continue
		}
		$t add $k $v
	    }
	}

	display \n$name
	$t show display
	return
    }

    method create_service {{service {}} {name {}} {appname {}}} {
	Debug.cli/services {}

	if {[my promptok] && ($service eq {})} {
	    set services [[my client] services_info]

	    if {![llength $services]} { err {No services available to provision} }

	    set choices {}
	    foreach {service_type value} $services {
		foreach {vendor version} $value {
		    lappend choices $vendor
		}
	    }

	    set service [term ask/menu "" \
			     "Please select one you wish to provision: " \
			     $choices]
	}

	set picked_name 0
	if {$name eq {}} { set name [dict get [my options] name] }
	if {$name eq {}} {
	    set name [my random_service_name $service]
	    set picked_name 1
	}

	my create_service_banner $service $name $picked_name

	if {$appname eq {}} { set appname [dict get [my options] bind] }

	if {$appname ne {}} {
	    my bind_service_banner $name $appname
	}
	return
    }

    method delete_service {args} {
	Debug.cli/services {}

	if {[dict get [my options] all]} {
	    set args {}
	    foreach s [[my client] services] {
		lappend args [dict getit $s name]
	    }
	}

	if {[my promptok] && ![llength $args]} {
	    set user_services [[my client] services]

	    if {![llength $user_services]} {
		err {No services available to delete}
	    }

	    set choices {}
	    foreach s $user_services {
		lappend choices [dict getit $s name]
	    }

	    lappend args [term ask/menu "" \
				  "Please select one you wish to delete: " \
				  $choices]
	}

	if {![llength $args]} {
	    err "Service name required."
	}

	foreach service $args {
	    set using_apps [dict get' [my service_map] $service {}]
	    set count [llength $using_apps]

	    if {$count} {
		set plural [expr {$count > 1}]

		set msg "Unable to delete service \[$service\], "
		append msg "as it is used by $count application[expr {$plural ? "s":""}]: "

		if {$plural} {
		    append msg "[linsert [join $using_apps {, }] end-1 and]"
		} else {
		    append msg "[lindex $using_apps 0]"
		}

		display [color red $msg]
		continue
	    }

	    display "Deleting service \[$service\]: " false
	    [my client] delete_service $service
	    display [color green OK]
	}
	return
    }

    method bind_service {service {appname {}}} {
	Debug.cli/services {}
	manifest 1app $appname [callback bindit $service]
	return
    }

    method bindit {service appname} {
	my TailStart $appname
	my bind_service_banner $service $appname
	my TailStop $appname
	return
    }

    method unbind_service {service {appname {}}} {
	Debug.cli/services {}
	manifest 1app $appname [callback unbindit $service]
	return
    }

    method unbindit {service appname} {
	my TailStart $appname
	my unbind_service_banner $service $appname
	my TailStop $appname
	return
    }

    method clone_services {src_app dest_app} {
	Debug.cli/services {}

	set src  {}
	set dest {}

	try {
	    set src  [[my client] app_info $src_app]
	    set dest [[my client] app_info $dest_app]
	}

	if {$src  eq {}} { err "Application '$src_app' does not exist"  }
	if {$dest eq {}} { err "Application '$dest_app' does not exist" }

	set services [dict getit $src services]
	if {![llength $services]} { err {No services to clone} }

	foreach service $services {
	    my bind_service_banner $service $dest_app 0
	}

	my check_app_for_restart $dest_app
	return
    }

    method tunnel {{service {}} {client {}}} {
	Debug.cli/services {}
	# client = name of the command to run. May have a path.

	lassign [my ProcessService $service] service info

	# TODO: rather than default to a particular port, we should
	# get the defaults based on the service name.. i.e. known
	# services should have known local default ports for this side
	# of the tunnel.

	set port [my pick_tunnel_port [dict get' [my options] port 10000]]

	# Have to be properly logged into the target.
	my CheckLogin

	# We need the tunnel helper application on the server side. We
	# create and push it on the first use of a tunnel.

	set tunnel_appname [my tunnel_appname]

	if {![my tunnel_pushed?]} {

	    display "Deploying helper application '$tunnel_appname'."

	    set auth [uuid::uuid generate]

	    my push_tunnel_helper $auth [dict get' [my options] url {}]
	    my bind_service_banner $service $tunnel_appname 0
	    my start_tunnel_helper

	} else {
	    set auth [my tunnel_auth]
	}

	# It is unxpected for the tunnel helper application to not be
	# running. Given that the most aggressive method for
	# restarting it is used: delete it and then fully push again.

	if {![my tunnel_healthy? $auth]} {
	    #
	    # XXX XXX XXXX
	    # A bad password from the user will arrive here as well,
	    # kill the old app and re-deploy it with the new password.
	    # This is a security leak. The bad password does not cause
	    # rejection, only overwriting of the old password with the
	    # new.
	    #

	    display "Redeploying helper application '$tunnel_appname'."

	    [my client] delete_app $tunnel_appname
	    my invalidate_tunnel_app_info

	    my push_tunnel_helper $auth [dict get' [my options] url {}]
	    my bind_service_banner $service $tunnel_appname 0
	    my start_tunnel_helper
	}

	# Make really sure that the service to talk to has a
	# connection to the helper application.

	if {![my tunnel_bound? $service]} {
	    my bind_service_banner $service $tunnel_appname
	}

	set connection [my tunnel_connection_info \
			    [dict get $info vendor] \
			    $service \
			    $auth]
	my display_tunnel_connection_info $connection

	lassign [my ProcessClient $client $service $info] client clients

	# Start tunnel and run client, or wait while external
	# clients use the tunnel.

	if {$client eq "none"} {
	    my start_tunnel many $service $port $connection $auth
	    my wait_for_tunnel_end
	} else {
	    my start_tunnel once $service $port $connection $auth
	    my wait_for_tunnel_start $port

	    if {![my start_local_prog $clients $client $connection $port]} {
		err "'$client' execution failed; is it in your \$PATH?"
	    }
	}
	return
    }

    method ProcessService {service} {
	Debug.cli/services {}

	set services [[my client] services]
	#@type services = list (service)

	# XXX see also c_apps.tcl, method dbshellit. Refactor and share.

	# services - provisioned, array.
	# service - A service name.

	if {![llength $services]} {
	    err "No services available to tunnel to"
	}

	if {$service eq {}} {
	    set choices {}
	    foreach s $services {
		set vendor [dict get $s vendor]
		# (x$x)
		if {$vendor ni {
		    mysql redis mongodb postgresql
		}} continue
		lappend choices [dict getit $s name]
	    }

	    if {![llength $services]} {
		err "No services available to tunnel to"
	    }
	    set service [term ask/menu "" \
			     "Which service to tunnel to: " \
			     $choices]
	}

	set info {}
	foreach s $services {
	    if {[dict get $s name] ne $service} continue
	    set info $s
	    break
	}
	if {$info eq {}} {
	    err "Unknown service '$service'."
	}

	# Service is found. Now check if it supports tunneling.

	set vendor [dict get $info vendor]
	# (x$x)
	if {$vendor ni {
	    mysql redis mongodb postgresql
	}} {
	    err "Service '$service' does not accept tunnels."
	}

	# end XXX

	return [list $service $info]
    }

    method ProcessClient {client service info} {
	Debug.cli/services {}
	# client = name of the command to run. May have a path.

	set vendor [dict get $info vendor]
	set clients [my get_clients_for $vendor]

	if {![llength $clients]} {
	    if {$client eq {}} {
		set client none
	    }
	} else {
	    if {$client eq {}} {
		set client [term ask/menu "" \
				"Which client would you like to start? " \
				[concat none [dict keys $clients]]]
	    }
	}

	set basecmd [file root [file tail $client]]
	set names [linsert [dict keys $clients] end none]
	if {$basecmd ni $names} {
	    err "Unknown client \[$basecmd\] for \[$service\], please choose one of [linsert '[join $names {', '}]' end-1 or]."
	}

	return [list $client $clients]
    }

    method get_clients_for {vendor} {
	Debug.cli/services {}
	return [dict get' [config clients] $vendor {}]
    }

    # # ## ### ##### ######## #############
    ## Internal commands.

    # # ## ### ##### ######## #############
    ## State

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::client::cli::command::Services 0
