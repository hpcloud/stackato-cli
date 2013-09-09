# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

## This module contains common code pertaining to services
## and their management.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require dictutil
package require stackato::color
package require stackato::log
package require stackato::mgr::cspace
package require stackato::v2

namespace eval ::stackato::mgr {
    namespace export service
    namespace ensemble create
}

namespace eval ::stackato::mgr::service {
    namespace export random-name random-name-for map \
	create-with-banner bind-with-banner unbind-with-banner \
	delete-with-banner
    namespace ensemble create

    namespace import ::stackato::color
    namespace import ::stackato::log::display
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::v2
}

debug level  mgr/service
debug prefix mgr/service {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## API

proc ::stackato::mgr::service::random-name {p} {
    # generate callback for 'servicemgr create: name'.
    debug.mgr/service {}

    set vendor [$p config @vendor]
    if {[[$p config @client] isv2]} {
	set vendor [$vendor @label]
    }
    set name [random-name-for $vendor]
    debug.mgr/service {= $name}
    return $name
}

proc ::stackato::mgr::service::random-name-for {service} {
    # internal helper for name generation.
    debug.mgr/service {}
    set name ${service}-[format %04x [expr {int(0x0100000 * rand ())}]]
    debug.mgr/service {= $name}
    return $name
}

proc ::stackato::mgr::service::map {client} {
    debug.mgr/service {}

    # Get apps, and their services.
    set apps [$client apps]
    # Invert the app -> service mapping.
    set res {}
    foreach a $apps {
	foreach s [dict getit $a services] {
	    dict lappend res $s [dict getit $a name]
	}
    }
    # result = dict (service name -> app name)
    return $res
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::service::create-with-banner {client theplan name {display_name 0}} {
    debug.mgr/service {}

    # theplan = v1: vendor/service name
    #           v2: plan instance
    #
    # name = name of new service instance.

    set sn [expr {$display_name ? " \[$name\]" : ""}]
    display "Creating new service$sn ... " false

    if {[$client isv2]} {
	set theservice [v2 service_instance new]

	$the_service @name         set $name
	$the_service @service_plan set $theplan
	$the_service @space        set [cspace get]

	$theservice commit

    } else {
	$client create_service $theplan $name
	set theservice $name
    }

    display [color green OK]

    # result is name|instance (v1 vs v2)
    debug.cmd/app {==> ($theservice)}
    return $theservice
}

proc ::stackato::mgr::service::bind-with-banner {client theservice theapp {show_ok 1}} {
    debug.mgr/service {}

    if {[$client isv2]} {
	# theapp, theservice = entity instances, not! names.

	# Print a warning when app/service already bound together.
	if {[llength [$theapp @service_bindings filter [lambda {s b} {
	    [$b @service_instance] == $s
	} $theservice]]]} {
	    display "Binding [$theservice @name] to [$theapp @name] ... SKIPPED (already bound)"
	    return 0
	}

	set link [v2 service_binding new]
	$link @app              set $theapp
	$link @service_instance set $theservice

	display "Binding [$theservice @name] to [$theapp @name] ..." false
	$link commit
    } else {
	# theapp, theservice = entity names.

	display "Binding Service $theservice to $theapp ... " false
	$client bind_service $theservice $theapp
    }

    if {$show_ok} {
	display [color green OK]
    }

    return 1
}

proc ::stackato::mgr::service::unbind-with-banner {client theservice theapp {show_ok 1}} {
    debug.mgr/service {}

    if {[$client isv2]} {
	# theapp, theservice = entity instances, not! names.

	# Print a warning when app/service not bound bound together.

	set links [$theapp @service_bindings filter [lambda {s b} {
	    [$b @service_instance] == $s
	} $theservice]]

	if {![llength $links]} {
	    display "Unbinding [$theservice @name] from [$theapp @name] ... SKIPPED (not bound)"
	    return 0
	}

	display "Unbinding [$theservice @name] from [$theapp @name] ..." false
	foreach link $links {
	    $link delete
	    $link commit
	}

    } else {
	# theapp, theservice = entity names.

	display "Unbinding Service $theservice from $theapp ... " false
	$client unbind_service $theservice $theapp
    }

    if {$show_ok} {
	display [color green OK]
    }
    return 1
}

proc ::stackato::mgr::service::delete-with-banner {client service} {
    #err "v2 not yet supported"

    # Caller servicemgr - v1 only.
    # Caller usermgr - delete - TODO v1/v2

    set map      [map $client]
    set users    [dict get' $map $service {}]
    set numusers [llength $users]

    if {$numusers} {
	set plural [expr {$numusers > 1}]

	set    msg "Unable to delete service \[$service\], "
	append msg "as it is used by $numusers application[expr {$plural ? "s":""}]: "

	if {$plural} {
	    append msg "[linsert [join $users {, }] end-1 and]"
	} else {
	    append msg "[lindex $users 0]"
	}

	display [color red $msg]
	return
    }

    display "Deleting service \[$service\] ... " false
    $client delete_service $service
    display [color green OK]
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::service 0
