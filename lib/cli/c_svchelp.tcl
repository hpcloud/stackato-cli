# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require try            ;# I want try/catch/finally
package require TclOO
package require table
package require tclyaml
package require stackato::client::cli::command::Base
package require stackato::client::cli::manifest

namespace eval ::stackato::client::cli::command::ServiceHelp {}

debug level  cli/services/support
debug prefix cli/services/support {[::debug::snit::call] | }

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::client::cli::command::ServiceHelp {
    superclass ::stackato::client::cli::command::Base

    # # ## ### ##### ######## #############

    constructor {args} {
	Debug.cli/services/support {}

	# Namespace import, sort of.
	namespace path [linsert [namespace path] end \
			    ::stackato ::stackato::log ::stackato::client::cli]
	next {*}$args
	return
    }

    destructor {
	Debug.cli/services/support {}
    }

    # # ## ### ##### ######## #############
    ## API

    method FixCredentials {s} {
	Debug.cli/services/support {}
	# HACK. If the hostname in the credentials is 127.0.0.1, and
	# the target url in use is of the form api.<hostname>, then we
	# fix the hostname.

	foreach key {hostname host} {
	    if {![dict exists $s credentials $key]} continue
	    if {[dict getit $s credentials $key] eq "127.0.0.1"} {
		set target [my target_url]
		regsub -nocase {^http(s*)://} $target {} target
		if {[string match {api.*} $target]} {
		    set target [join [lrange [split $target .] 1 end] .]
		    dict set s credentials $key $target
		}
	    }
	}

	return $s
    }

    method health {d} {
	Debug.cli/services/support {}
	#checker -scope line exclude badOption
	if {($d eq {}) || ([dict get' $d state {}] eq {})} { return N/A }
	if {[dict get $d state] eq "STOPPED"}              { return STOPPED }

	set healthy_instances [dict getit $d runningInstances]
	set expected_instance [dict getit $d instances]
	set health 0

	# Hack around wierd server response.
	if {$healthy_instances eq "null"} {
	    set healthy_instances 0
	}

	if {([dict get $d state] eq "STARTED") &&
	    ($expected_instance > 0) &&
	    $healthy_instances
	} {
	    set health [expr {(1000 * $healthy_instances) /
			      $expected_instance}]
	}

	if {$health == 1000} { return RUNNING }

	return [expr {round($health / 10.)}]
	#return N/A
    }

    method display_system_services {{services {}}} {
	Debug.cli/services/support {}

	if {[llength [info level 0]] < 3} {
	    set services [[my client] services_info]
	}

	display "\n============== System Services ==============\n"

	if {![llength $services]} {
	    display "No system services available"
	    return
	}

	# Using a temp list to so that we can sort the table.
	# Alt: Build sorting into the table object.
	set tmp {}
	foreach {service_type value} $services {
	    foreach {vendor version} $value {
		foreach {version_str service} $version {
		    lappend tmp \
			[list \
			     $vendor \
			     $version_str \
			     [dict getit $service description]]
		}
	    }
	}

	table::do t {Service Version Description} {
	    foreach item [lsort -index 0 $tmp] {
		$t add {*}$item
	    }
	}
	$t show display
	return
    }

    method display_provisioned_services {{services {}}} {
	Debug.cli/services/support {}

	if {[llength [info level 0]] < 3} {
	    set services [[my client] services]
	}

	display "\n=========== Provisioned Services ============\n"
	my display_provisioned_services_table $services
	return
    }

    method display_provisioned_services_table {services} {
	Debug.cli/services/support {}

	if {$services eq {}} return

	table::do t {Name Service} {
	    foreach service $services {
		$t add \
		    [dict getit $service name] \
		    [dict getit $service vendor]
	    }
	}

	#display "\n"
	$t show display
	return
    }

    method create_service_banner {service name {display_name 0}} {
	Debug.cli/services/support {}

	set sn [expr {$display_name ? " \[$name\]" : ""}]
	display "Creating Service$sn: " false
	[my client] create_service $service $name
	display [color green OK]
	return
    }

    method bind_service_banner {service appname {check_restart 1}} {
	Debug.cli/services/support {}

	display "Binding Service: " false
	[my client] bind_service $service $appname
	display [color green OK]
	if {!$check_restart} return
	my check_app_for_restart $appname 
	return
    }

    method unbind_service_banner {service appname {check_restart 1}} {
	Debug.cli/services/support {}

	display "Unbinding Service: " false
	[my client] unbind_service $service $appname
	display [color green OK]
	if {!$check_restart} return
	my check_app_for_restart $appname 
	return
    }

    method random_service_name {service} {
	Debug.cli/services/support {}
	return $service-[format %04x [expr {int(0x0100000 * rand ())}]]
    }

    method check_app_for_restart {appname} {
	Debug.cli/services/support {}

	set app [[my client] app_info $appname]
	if {[dict getit $app state] ne "STARTED"} return

	set cmd [command::Apps new {*}[my options]]
	$cmd restart $appname
	$cmd destroy
	return
    }

    method service_map {} {
	Debug.cli/services/support {}

	# Get apps, and their services.
	set apps [[my client] apps]
	# Invert the app -> service mapping.
	set res {}
	foreach a $apps {
	    foreach s [dict getit $a services] {
		dict lappend res $s [dict getit $a name]
	    }
	}
	# And return resulting service -> app mapping to caller.
	return $res
    }

    # # ## ### ##### ######## #############
    ## Internal commands.

    method app_exists? {appname} {
	Debug.cli/services/support {}

	try {
	    set app [[my client] app_info $appname]
	    return [expr {$app ne {}}]
	} trap {STACKATO CLIENT NOTFOUND} {} {
	    return 0
	}
    }

    method MinVersionChecks {} {
	# Check client and server version requirements, if there are
	# any. Note that that manifest(s) have been read and processed
	# already, by the base class constructor.

	# Note: The requirements come from the manifest, and have been
	# check for proper syntax already. The have's should be ok.

	if {[manifest minVersionClient require]} {
	    set have [package present stackato::client::cli]

	    Debug.cli/services/support { client require = $require}
	    Debug.cli/services/support { client have    = $have}

	    if {[package vcompare $have $require] < 0} {
		err "version conflict for client: have $have, need at least $require"
	    }
	}
	if {[manifest minVersionServer require]} {
	    set have [my ServerVersion]

	    Debug.cli/services/support { server require = $require}
	    Debug.cli/services/support { server have    = $have}

	    if {[package vcompare $have $require] < 0} {
		err "version conflict for server: have $have, need at least $require"
	    }
	}

	return
    }

    method AppName {appname {update 0}} {
	# See also manifest.tcl, command '1app'.

	Debug.cli/services/support {}

	# Appname directly specified has precedence.

	# (1) appname from the options...
	if {$appname eq {}} {
	    set appname [dict get' [my options] name {}]
	    Debug.cli/services/support { name/option      = $appname}
	}

	# (2) configuration files (stackato.yml, manifest.yml)
	set mname [manifest name]
	Debug.cli/services/support { manifest = $mname}

	if {$appname eq {}} {
	    set name $mname
	    Debug.cli/services/support { name/manifest   = $appname}
	}

	# (3) May ask the user, use deployment path as default ...
	if {$appname eq {}} {
	    set maybe [file tail [manifest current]]
	    if {[my promptok]} {
		set proceed [term ask/yn "Would you like to use '$maybe' as application name ? "]
		if {$proceed} {
		    set appname $maybe
		    Debug.cli/services/support { name/usr/default = $appname}
		} else {
		    set appname [term ask/string "Application Name: "]
		    Debug.cli/services/support { name/usr/entry   = $appname}
		}
	    } else {
		set appname $maybe
		Debug.cli/services/support { name/default     = $appname}
	    }
	}

	# Fail without name
	if {$appname eq {}} {
	    err "Application Name required."
	}

	if {$update} {
	    # Check for existence, talking to something which should be present.
	    if {![my app_exists? $appname]} {
		err "Application '$appname' could not be found"
	    }
	} else {
	    # Check for duplicates, if we are pushing something new.

	    if {[my app_exists? $appname]} {
		err "Application '$appname' already exists, use update" 
	    }

	    # This is truly a new application.
	    # Must have space for such on the target.
	    my check_app_limit
	}

	manifest name= $appname

	Debug.cli/services/support {= $appname}

	if {$mname ne $appname} {
	    Debug.cli/services/support {Reload using new name...}

	    # Bug 93955. Force a full reload of the manifest. This is
	    # required to ensure that all name-dependent parts use the
	    # user's chosen name instead of whatever definition is
	    # found in the manifest itself.
	    #
	    # We optimize a bit by doing this only if the chosen name
	    # actually differs from the name in the manifest.

	    manifest setup [self] \
		[dict get' [my options] path [pwd]] \
		{} reset

	    manifest recurrent
	}

	return $appname
    }

    # # ## ### ##### ######## #############
    ## State

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::client::cli::command::ServiceHelp 0
