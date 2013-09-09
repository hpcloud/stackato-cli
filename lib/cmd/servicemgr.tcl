# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

## Command implementations. User management.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr 0.4
package require dictutil
package require stackato::cmd::app
package require stackato::color
package require stackato::jmap
package require stackato::log
package require stackato::mgr::cspace
package require stackato::mgr::ctarget
package require stackato::mgr::logstream
package require stackato::mgr::manifest
package require stackato::mgr::service
package require stackato::mgr::tclients
package require stackato::mgr::tunnel
package require stackato::term
package require stackato::v2
package require stackato::validate::appname
package require stackato::validate::servicetype
package require table
package require uuid

debug level  cmd/servicemgr
debug prefix cmd/servicemgr {[debug caller] | }

namespace eval ::stackato::cmd {
    namespace export servicemgr
    namespace ensemble create
}
namespace eval ::stackato::cmd::servicemgr {
    namespace import ::stackato::mgr::tunnel
    rename tunnel tunnelmgr

    namespace export \
	list-instances list-plans show tunnel \
	bind unbind clone create delete rename \
	select-for-create select-for-delete \
	select-for-change select-plan-for-create
    namespace ensemble create

    namespace import ::stackato::cmd::app
    namespace import ::stackato::color
    namespace import ::stackato::jmap
    namespace import ::stackato::log::display
    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::mgr::ctarget
    namespace import ::stackato::mgr::logstream
    namespace import ::stackato::mgr::manifest
    namespace import ::stackato::mgr::service
    namespace import ::stackato::mgr::tclients
    namespace import ::stackato::term
    namespace import ::stackato::v2
    namespace import ::stackato::validate::appname
    namespace import ::stackato::validate::servicetype
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicemgr::list-plans {config} {
    debug.cmd/servicemgr {}

    set theplans [v2 service_plan list 1]
    # chosen depth delivers plans and referenced services.

    if {![llength $theplans]} {
	display "No service plans."
	return
    }

    # Extract the information we wish to show.
    # Having it in list form makes sorting easier, later.
    foreach plan $theplans {
	set service [$plan @service]
	# plan    -> name, description, extra, &service
	# service -> label, provider, url, description, version, info url, extra

	lappend details [$service @label]
	lappend details [$service @description]
	lappend details [$service @provider]
	lappend details [$service @version]
	lappend details [$plan    @name]
	lappend details [$plan    @description]

	lappend plans $details
	unset details
    }

    # Now format and display the table
    [table::do t {Name Description Provider Version Plan Details} {
	foreach plan [lsort -dict $plans] {
	    $t add {*}$plan
	}
    }] show display

    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicemgr::list-instances {config} {
    debug.cmd/servicemgr {}

    set client [$config @client]
    if {[$client isv2]} {
	ListInstancesV2 $config $client
    } else {
	ListInstancesV1 $config $client
    }

    debug.cmd/servicemgr {/done}
    return
}

proc ::stackato::cmd::servicemgr::ListInstancesV2 {config client} {
    debug.cmd/servicemgr {}

    # Retrieve data (3 deep to capture the associated plans and
    # service on one side, and the bindings plus applications on the
    # other).
    set services [[cspace get] @service_instances get 3]

    # Map for sorting by name.
    set map {}
    foreach s $services {
	dict set map [$s @name] $s
    }

    [table::do t {Name Service Provider Version Plan Applications} {
	dict for {name service} [dict sort $map] {
	    set plan [$service @service_plan]
	    set kind [$plan    @service]

	    $t add \
		$name \
		[$kind @label] \
		[$kind @provider] \
		[$kind @version] \
		[$plan @name] \
		[join [$service @service_bindings @app @name] \n]
	}
    }] show display

    debug.cmd/servicemgr {/done}
    return
}

proc ::stackato::cmd::servicemgr::ListInstancesV1 {config client} {
    debug.cmd/servicemgr {}
    # --token, --token-file, --target, --group handled
    # by cmdr framework through when-defined and force.

    set supported [$client services_info]
    #@type supported = dict (database, key-value /DESC)
    #@type DESC      = dict (<any-name>/dict (<any-version>/VERSION)
    #@type VERSION

    set provisioned [$client services]
    #@type provisioned = list (services?)

    set provisioned [lsort -command [lambda {a b} {
	string compare [dict getit $a name] [dict getit $b name]
    }] $provisioned]

    if {[$config @json]} {
	display [jmap services \
		     [dict create \
			  system      $supported \
			  provisioned $provisioned]]
	return
    }

    DisplaySystemServices      $supported
    DisplayProvisionedServices $provisioned

    debug.cmd/servicemgr {/done}
    return
}

proc ::stackato::cmd::servicemgr::DisplaySystemServices {services} {
    debug.cmd/servicemgr {}

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

    [table::do t {Service Version Description} {
	foreach item [lsort -index 0 $tmp] {
	    $t add {*}$item
	}
    }] show display
    return
}

proc ::stackato::cmd::servicemgr::DisplayProvisionedServices {services} {
    debug.cmd/servicemgr {}

    display "\n=========== Provisioned Services ============\n"
    if {$services eq {}} return

    [table::do t {Name Service} {
	foreach service $services {
	    $t add \
		[dict getit $service name] \
		[dict getit $service vendor]
	}
    }] show display
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicemgr::bind {config} {
    debug.cmd/servicemgr {}
    manifest user_1app each $config ::stackato::cmd::servicemgr::Bind
    return
}

proc ::stackato::cmd::servicemgr::unbind {config} {
    debug.cmd/servicemgr {}
    manifest user_1app each $config ::stackato::cmd::servicemgr::Unbind
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicemgr::rename {config} {
    debug.cmd/servicemgr {}
    # V2 only.
    # client v2 = @service is entity instance

    set service [$config @service]
    set new     [$config @name]

    display "Renaming service \[[$service @name]\] to $new ... " false
    $service @name set $new
    $service commit
    display [color green OK]

    debug.cmd/servicemgr {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicemgr::clone {config} {
    debug.cmd/servicemgr {}

    set client [$config @client]
    if {[$client isv2]} {
	CloneV2 $config $client
    } else {
	CloneV1 $config $client
    }

    debug.cmd/servicemgr {/done}
    return
}

proc ::stackato::cmd::servicemgr::CloneV2 {config client} {
    debug.cmd/servicemgr {}

    set srcapp [$config @source]
    set dstapp [$config @application]

    if {[$srcapp == $dstapp]} {
	err {Source and destination are the same application}
    }

    set services [$srcapp @service_bindings @app]

    if {![llength $services]} {
	err {No services to clone}
    }

    foreach service $services {
	dict set map [$service @name] $service
    }

    set restart 0
    dict for {_ service} [dict sort $map] {
	if {[service bind-with-banner $client $service $dstapp 0]} {
	    set restart 1
	}
    }

    if {!$restart} {
	debug.cmd/servicemgr {/done, no restart required}
	return
    }

    app check-app-for-restart $config $dstapp

    debug.cmd/servicemgr {/done}
    return
}

proc ::stackato::cmd::servicemgr::CloneV1 {config client} {
    debug.cmd/servicemgr {}

    set srcname [$config @source]
    set dstname [$config @application]

    if {$srcname eq $dstname} {
	err {Source and destination are the same application}
    }

    set src      [$client app_info $srcname]
    set services [dict getit $src services]

    if {![llength $services]} {
	err {No services to clone}
    }

    foreach service $services {
	service bind-with-banner $client $service $dstname 0
    }

    app check-app-for-restart $config $dstname

    debug.cmd/servicemgr {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicemgr::create {config} {
    debug.cmd/servicemgr {}

    set client [$config @client]
    if {[$client isv2]} {
	CreateV2 $config $client
    } else {
	CreateV1 $config $client
    }

    debug.cmd/servicemgr {/done}
    return
}

proc ::stackato::cmd::servicemgr::CreateV2 {config client} {
    debug.cmd/servicemgr {}

    # @provider already processed (validate, generate)
    # @version  already processed (validate, generate)
    # @name   always defined (generate (select-for-create)).
    # @plan   always defined (generate (select-plan-for-create)).

    # Pull the relevant arguments...
    set plan   [$config @plan]
    set name   [$config @name]
    set picked [expr {![$config @name set?]}]

    service create-with-banner $client $plan $name $picked

    if {[$config @application set?]} {
	set theapp [$config @application]
	BindServiceBanner $config $client $service $theapp
    }

    debug.cmd/servicemgr {/done}
    return
}

proc ::stackato::cmd::servicemgr::CreateV1 {config client} {
    debug.cmd/servicemgr {}

    if {![cmdr interactive?] && ![$config @vendor set?]} {
	# Not enough arguments. This can happen if and only if
	# interactive entry was disabled.
	err "Need a valid service type"
    }

    set service [$config @vendor]
    set name    [$config @name]
    set picked  [expr {![$config @name set?]}]

    service create-with-banner $client $service $name $picked

    if {[$config @application set?]} {
	set appname [$config @application]
	BindServiceBanner $config $client $name $appname
    }

    debug.cmd/servicemgr {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicemgr::delete {config} {
    debug.cmd/servicemgr {}

    set client [$config @client]
    if {[$client isv2]} {
	DeleteV2 $config $client
    } else {
	DeleteV1 $config $client
    }

    debug.cmd/servicemgr {/done}
    return
}

proc ::stackato::cmd::servicemgr::DeleteV2 {config client} {
    debug.cmd/servicemgr {}

    if {[$config @all]} {
	debug.cmd/servicemgr {all}

	set todelete [[cspace get] @service_instances]

    } else {
	debug.cmd/servicemgr {some, by user}

	set todelete [$config @service]
    }

    # Deletion loop.
    set unbind [$config @unbind]

    foreach service $todelete {
	set name [$service @name]

	set bindings [$service @service_bindings get 1]
	set nbounds  [llength $bindings]

	if {$nbounds && !$unbind} {
	    display "Deleting service $name ... SKIPPED (bound to $nbounds application[expr {$nbounds != 1 ? "s" : ""}])"
	    continue
	}

	if {[cmdr interactive?] &&
	    ![term ask/yn \
		  "\nReally delete service \"$name\" ? " \
		  no]} continue

	if {$nbounds} {
	    # Implied that unbind is set.
	    foreach link $bindings {
		display "Unbinding [$service @name] from [$link @app @name] ..." false
		$link delete
		$link commit
		display [color green OK]
	    }
	}

	display "Deleting service $name ... " false
	$service delete
	$service commit
	display [color green OK]
    }

    debug.cmd/servicemgr {/done}
    return
}

proc ::stackato::cmd::servicemgr::DeleteV1 {config client} {
    debug.cmd/servicemgr {}

    if {[$config @all]} {
	debug.cmd/servicemgr {all}

	set todelete {}
	foreach s [$client services] {
	    lappend todelete [dict getit $s name]
	}
    } elseif {![$config @service set?]} {
	debug.cmd/servicemgr {none, stop}
	# Nothing to delete.
	return
    } else {
	debug.cmd/servicemgr {some, by user}

	set todelete [$config @service]
    }

    foreach service $todelete {
	service delete-with-banner $client $service
    }

    debug.cmd/servicemgr {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicemgr::show {config} {
    debug.cmd/servicemgr {}

    set client [$config @client]
    if {[$client isv2]} {
	ShowV2 $config
    } else {
	ShowV1 $config $client
    }

    debug.cmd/servicemgr {/done}
    return
}

proc ::stackato::cmd::servicemgr::ShowV2 {config} {
    debug.cmd/servicemgr {}

    set service [$config @name]

    if {[$config @json]} {
	display [$service as-json]
	return
    }

    set plan [$service @service_plan]
    set kind [$plan    @service]

    display \n[$service @name]
    [table::do t {What Value} {
	$t add Type         [$kind @label]
	$t add Provider     [$kind @provider]
	$t add Version      [$kind @version]
	$t add Plan         [$plan @name]
	$t add Description  [$plan @description]
	$t add Dashboard    [$service @dashboard_url]
	$t add Space        [$service @space full-name]

	$t add {} {}
	$t add Credentials
	set creds [$service @credentials]
	foreach k [lsort -dict [dict keys $creds]] {
	    set vx [dict get $creds $k]
	    if {$k in {created updated}} {
		set vx [clock format $vx]
	    }
	    $t add "- $k" $vx
	}
	$t add {} {}

	$t add Applications [join [$service @service_bindings @app @name] \n]
    }] show display

    debug.cmd/servicemgr {/done}
    return
}

proc ::stackato::cmd::servicemgr::ShowV1 {config client} {
    debug.cmd/servicemgr {}

    set name   [$config @name]
    set sinfo  [$client get_service $name]

    if {[$config @json]} {
	display [jmap service $sinfo]
	return
    }

    display \n$name
    [table::do t {What Value} {
	foreach k [lsort -dict [dict keys $sinfo]] {
	    set v [dict get $sinfo $k]

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
    }] show display

    debug.cmd/servicemgr {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicemgr::tunnel {config} {
    debug.cmd/servicemgr {}

    set service   [$config @service]
    set tclient   [$config @tunnelclient]
    set client    [$config @client]
    set turl      [$config @url]
    set allowhttp [$config @allow-http]
    set trace     [$config @trace]
    set port      [$config @port]

    # tclient = name of the command to run. May have a path.

    lassign [ProcessService $client $service] service info

    # TODO: rather than default to a particular port, we should get
    # the defaults based on the service name.. i.e. known services
    # should have known local default ports for this side of the
    # tunnel.

    set port [tunnelmgr pick-port $port]

    # We need the tunnel helper application on the server side.
    # We create and push it on the first use of a tunnel.

    set tunnel_appname [tunnelmgr appname]

    if {![tunnelmgr pushed? $client]} {
	display "Deploying helper application '$tunnel_appname'."

	set auth [uuid::uuid generate]

	PushTunnelHelper         $config $auth $turl
	service bind-with-banner $client $service $tunnel_appname 0
	StartTunnelHelper        $config

    } else {
	set auth [tunnelmgr auth $client]
    }

    # It is unxpected for the tunnel helper application to not be
    # running. Given that the most aggressive method for restarting it
    # is used: delete it and then fully push again.

    set stopcmd [list ::stackato::cmd::servicemgr::StopTunnelHelper $config]
    if {![tunnelmgr healthy? $allowhttp $client $auth $stopcmd]} {
	#
	# XXX XXX XXXX

	# A bad password from the user will arrive here as well, kill
	# the old app and re-deploy it with the new password.  This is
	# a security leak. The bad password does not cause rejection,
	# only overwriting of the old password with the new.
	#

	display "Redeploying helper application '$tunnel_appname'."

	$client delete_app $tunnel_appname
	tunnelmgr invalidate-appinfo

	PushTunnelHelper         $config $auth $turl
	service bind-with-banner $client $service $tunnel_appname 0
	StartTunnelHelper        $config
    }

    # Make really sure that the service to talk to has a connection to
    # the helper application.

    if {![tunnelmgr bound? $client $service]} {
	service bind-with-banner $client $service $tunnel_appname
    }

    set connection [tunnelmgr connection-info \
			$allowhttp $client \
			[dict get $info vendor] \
			$service \
			$auth]

    DisplayTunnelConnectionInfo $connection

    lassign [ProcessClient $tclient $service $info] tclient clients

    # Start tunnel and run client, or wait while external clients use
    # the tunnel.

    if {$tclient eq "none"} {
	tunnelmgr start $allowhttp $client $trace many $service $port $connection $auth
	tunnelmgr wait-for-end
    } else {
	tunnelmgr start $allowhttp $client $trace once $service $port $connection $auth
	tunnelmgr wait-for-start $port

	if {![tunnelmgr start-local-client $clients $tclient $connection $port]} {
	    err "'$tclient' execution failed; is it in your \$PATH?"
	}
    }
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicemgr::select-for-create {p} {
    # generate callback for 'servicemgr create: vendor'.
    debug.cmd/servicemgr {}

    if {![cmdr interactive?]} {
	$p undefined!
    }

    set client [$p config @client]
    if {[$client isv2]} {
	set vendor [SelectCreateV2 $client]
    } else {
	set vendor [SelectCreateV1 $client]
    }

    debug.cmd/servicemgr {==> $vendor}
    return $vendor
}

proc ::stackato::cmd::servicemgr::SelectCreateV2 {client} {
    debug.cmd/servicemgr {}

    # Get possibilities, already filtered per @provider, @vendor
    set services [servicetype get-candidates]

    if {![llength $services]} {
	err {No services matching the filter criteria found.}
    }

    # Generate labels for the interaction and keep mapping to
    # originating object.
    foreach s $services {
	set label "[$s @label] [$s @version], by [$s @provider]"
	dict set map $label $s
	lappend choices $label
    }

    # Talk with the user.
    set vendorlabel [term ask/menu "" \
			 "Please select one you wish to provision: " \
			 [lsort -dict $choices]]

    # Map the chosen label back to the service in question.
    set vendor [dict get $map $vendorlabel]

    debug.cmd/servicemgr {= $vendor ($vendorlabel)}
    return $vendor
}

proc ::stackato::cmd::servicemgr::SelectCreateV1 {client} {
    debug.cmd/servicemgr {}

    set services [$client services_info]

    if {![llength $services]} {
	err {No services available to provision}
    }

    set choices {}
    foreach {service_type value} $services {
	foreach {vendor version} $value {
	    lappend choices $vendor
	}
    }
    set choices [lsort -dict $choices]

    set vendor [term ask/menu "" \
		    "Please select the service you wish to provision: " \
		    $choices]

    debug.cmd/servicemgr {= $vendor}
    return $vendor
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicemgr::select-plan-for-create {p} {
    # generate callback for 'servicemgr create: vendor'.
    debug.cmd/servicemgr {}

    set client [$p config @client]

    if {![$client isv2]} {
	# v1 client, plan is irrelevant.
	return {}
    }

    if {![cmdr interactive?]} {
	$p undefined!
	# implied return/failure
    }

    # See serviceplan validation type for similar.

    set vendor [$p config @vendor]
    set plans [$vendor @service_plans]

    if {![llength $plans]} {
	err "No service plans found for [$vendor @label]"
    }

    # Generate labels for the interaction and keep mapping to
    # originating object.
    foreach p $plans {
	set label "[$p @name]: [$p @description]"
	dict set map $label $p
	lappend choices $label
    }

    # Talk with the user.
    set planlabel [term ask/menu "" \
		       "Please select the service plan to enact: " \
		       [lsort -dict $choices]]

    # Map the chosen label back to the service in question.
    set plan [dict get $map $planlabel]

    debug.cmd/servicemgr {= $plan ($planlabel)}
    return $plan
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicemgr::select-for-delete {p} {
    debug.cmd/servicemgr {}

    # generate callback for 'servicemgr delete: service'.
    if {[$p config @all]} {
	debug.cmd/servicemgr {excluded by --all}
	return {}
    }

    if {![cmdr interactive?]} {
	debug.cmd/servicemgr {no interaction}
	return {}
    }

    set client [$p config @client]
    if {[$client isv2]} {
	set service [SelectDeleteV2 $client]
    } else {
	set service [SelectDeleteV1 $client]
    }

    debug.cmd/servicemgr {==> $service}
    return $service

}

proc ::stackato::cmd::servicemgr::SelectDeleteV2 {client} {
    debug.cmd/servicemgr {}

    set services [[cspace get] @service_instances]

    if {![llength $services]} {
	err {No services available to delete}
    }

    # Generate labels for the interaction and keep mapping to
    # originating object.
    foreach s $services {
	set label [$s @name]
	dict set map $label $s
	lappend choices $label
    }

    # Talk with the user.
    set servicelabel [term ask/menu "" \
			  "Please select one you wish to delete: " \
			  [lsort -dict $choices]]

    # Map the chosen label back to the service in question.
    set service [dict get $map $servicelabel]

    debug.cmd/servicemgr {==> $service ($servicelabel)}
    return $service
}

proc ::stackato::cmd::servicemgr::SelectDeleteV1 {client} {
    debug.cmd/servicemgr {}

    set user_services [$client services]

    if {![llength $user_services]} {
	err {No services available to delete}
    }

    set choices {}
    foreach s $user_services {
	lappend choices [dict getit $s name]
    }
    set choices [lsort -dict $choices]

    debug.cmd/servicemgr {interact}
    set service [list [term ask/menu "" \
		      "Please select one you wish to delete: " \
		      $choices]]

    debug.cmd/servicemgr {==> $service}
    return $service
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicemgr::select-for-change {operation p} {
    debug.cmd/servicemgr {}

    # generate callback for 'servicemgr (un)bind: service'.

    if {![cmdr interactive?]} {
	$p undefined!
	# implied return/failure
    }

    set client [$p config @client]
    if {[$client isv2]} {
	set service [SelectChangeV2 $client $operation]
    } else {
	set service [SelectChangeV1 $client $operation]
    }

    debug.cmd/servicemgr {==> $service}
    return $service

}

proc ::stackato::cmd::servicemgr::SelectChangeV2 {client operation} {
    debug.cmd/servicemgr {}

    set services [[cspace get] @service_instances]

    if {![llength $services]} {
	err "No services available to $operation"
    }

    # Generate labels for the interaction and keep mapping to
    # originating object.
    foreach s $services {
	set label [$s @name]
	dict set map $label $s
	lappend choices $label
    }

    # Talk with the user.
    set servicelabel [term ask/menu "" \
			  "Please select one you wish to $operation: " \
			  [lsort -dict $choices]]

    # Map the chosen label back to the service in question.
    set service [dict get $map $servicelabel]

    debug.cmd/servicemgr {==> $service ($servicelabel)}
    return $service
}

proc ::stackato::cmd::servicemgr::SelectChangeV1 {client operation} {
    debug.cmd/servicemgr {}

    set user_services [$client services]

    if {![llength $user_services]} {
	err "No services available to $operation"
    }

    set choices {}
    foreach s $user_services {
	lappend choices [dict getit $s name]
    }
    set choices [lsort -dict $choices]

    debug.cmd/servicemgr {interact}
    set service [list [term ask/menu "" \
		      "Please select one you wish to $operation: " \
		      $choices]]

    debug.cmd/servicemgr {==> $service}
    return $service
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicemgr::Bind {config theapp} {
    debug.cmd/servicemgr {}

    set client  [$config @client]
    set service [$config @service]

    logstream start           $config $theapp
    BindServiceBanner $config $client $service $theapp
    logstream stop            $config $theapp
    return
}

proc ::stackato::cmd::servicemgr::Unbind {config theapp} {
    debug.cmd/servicemgr {}

    set client  [$config @client]
    set service [$config @service]

    logstream start             $config $theapp
    UnbindServiceBanner $config $client $service $theapp
    logstream stop              $config $theapp
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicemgr::BindServiceBanner {config client service theapp {check_restart 1}} {
    debug.cmd/servicemgr {}

    set ok [service bind-with-banner $client $service $theapp [expr {!$check_restart}]]

    if {!$ok || !$check_restart} return

    app check-app-for-restart $config $theapp
    return
}

proc ::stackato::cmd::servicemgr::UnbindServiceBanner {config client service theapp {check_restart 1}} {
    debug.cmd/servicemgr {}

    set ok [service unbind-with-banner $client $service $theapp [expr {!$check_restart}]]

    if {!$ok || !$check_restart} return

    app check-app-for-restart $config $theapp 
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicemgr::StartTunnelHelper {config} {
    debug.cmd/servicemgr {}

    # validation takes care of v1/v2 differences
    # v1: app name, v2: app instance

    app start1 $config [appname validate [tunnelmgr appname]]
    tunnelmgr invalidate-appinfo
    return
}

proc ::stackato::cmd::servicemgr::StopTunnelHelper {config} {
    debug.cmd/servicemgr {}

    # validation takes care of v1/v2 differences
    # v1: app name, v2: app instance

    app stop1 $config [appname validate [tunnelmgr appname]]
    tunnelmgr invalidate-appinfo
    return
}

proc ::stackato::cmd::servicemgr::PushTunnelHelper {config token turl} {
    debug.cmd/servicemgr {}
    debug.cmd/servicemgr {app = [tunnelmgr helper]}

    set client [$config @client]

    if {$turl eq {}} {
	set turl [tunnelmgr uniquename].[ctarget suggest]
    }

    manifest setup [tunnelmgr helper] {} reset
    set appname [tunnelmgr appname]

    manifest current= $appname

    # We know everything about the helper.
    # See also cmd/app: Create(AppV[12]).

    if {[$client isv2]} {
	set theapp [v2 app new]
	$theapp @name             set $appname
	$theapp @space            set [cspace get]
	$theapp @environment_json set [dict create TUNNEL_AUTH $token]
	@theapp @memory           set 72
	@theapp @total_instances  set 1

	$theapp commit
	app map-urls $theapp [list $turl]
	#stack/framework/buildpack/...
    } {
	$client create_app [tunnelmgr appname] \
	    [dict create \
		 name $appname \
		 staging {framework sinatra} \
		 uris [list $turl] \
		 instances 1 \
		 resources {memory 72} \
		 env [list TUNNEL_AUTH=$token]]
	set theapp $appname
    }

    app upload-files $config $theapp $appname [tunnelmgr helper]
    tunnelmgr invalidate-appinfo
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicemgr::DisplayTunnelConnectionInfo {info} {
    debug.cmd/servicemgr {}

    display ""
    display "Service connection info: "

    # Determine which keys to show, and ensure that the first
    # three are about user, password, and database.

    # TODO: modify the server services rest call to have explicit
    # knowledge about the items to return.  It should return all
    # of them if the service is unknown so that we don't have to
    # do this weird filtering.

    debug.cmd/servicemgr {TunnelInfo = [dict print $info]}

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

    debug.cmd/servicemgr {KeysToShow ($to_show)}

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

proc ::stackato::cmd::servicemgr::ProcessService {client service} {
    debug.cmd/servicemgr {}

    set services [$client services]
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
		oracledb mysql redis mongodb postgresql
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

proc ::stackato::cmd::servicemgr::ProcessClient {tclient service info} {
    debug.cmd/servicemgr {}
    # tclient = name of the command to run. May have a path.

    set vendor  [dict get $info vendor]
    set clients [GetClientsFor $vendor]

    if {![llength $clients]} {
	if {$tclient eq {}} {
	    set tclient none
	}
    } else {
	if {$tclient eq {}} {
	    set tclient [term ask/menu "" \
			     "Which client would you like to start? " \
			     [concat none [dict keys $clients]]]
	}
    }

    set basecmd [file root [file tail $tclient]]
    set names   [linsert [dict keys $clients] end none]
    if {$basecmd ni $names} {
	err "Unknown client \[$basecmd\] for \[$service\], please choose one of [linsert '[join $names {', '}]' end-1 or]."
    }

    return [list $tclient $clients]
}

proc ::stackato::cmd::servicemgr::GetClientsFor {vendor} {
    debug.cmd/servicemgr {}
    return [dict get' [tclients get] $vendor {}]
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::servicemgr 0
return
