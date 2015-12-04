# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations. User management.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr
package require dictutil
package require cmdr::ask
package require cmdr::color
package require stackato::cmd::app
package require stackato::jmap
package require stackato::log
package require stackato::mgr::context
package require stackato::mgr::cspace
package require stackato::mgr::ctarget
package require stackato::mgr::logstream
package require stackato::mgr::manifest
package require stackato::mgr::service
package require stackato::mgr::tclients
package require stackato::mgr::tunnel
package require stackato::misc
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
    ::rename tunnel tunnelmgr

    namespace export \
	list-instances list-plans market show tunnel \
	bind unbind clone create delete rename \
	select-for-create select-for-delete \
	select-for-change select-plan-for-create \
	update-plan link-plan-org unlink-plan-org \
	show-plan purge-service-type update-upsi
    namespace ensemble create

    namespace import ::cmdr::ask
    namespace import ::cmdr::color
    namespace import ::stackato::cmd::app
    namespace import ::stackato::jmap
    namespace import ::stackato::log::display
    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::context
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::mgr::ctarget
    namespace import ::stackato::mgr::logstream
    namespace import ::stackato::mgr::manifest
    namespace import ::stackato::mgr::service
    namespace import ::stackato::mgr::tclients
    namespace import ::stackato::misc
    namespace import ::stackato::v2
    namespace import ::stackato::validate::appname
    namespace import ::stackato::validate::servicetype

    #   attr-config   attr-entity    label canbeempty
    variable def {
	@newname      @name          {name       } 0
	@description  @description   {description} 1
	@public       @public        {public     } 0
	@free         @free          {free       } 0
    }
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicemgr::purge-service-type {config} {
    debug.cmd/servicemgr {}

    set theservice [$config @service]
    set name       [$theservice @name]

    display "Purging service type $name and all its offerings ... " false
    $theservice purge!
    display [color good OK]
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicemgr::show-plan {config} {
    debug.cmd/servicemgr {}

    set theplan [$config @name]

    if {[$config @json]} {
	display [$theplan as-json]
	return
    }

    # Determine all linked orgs (= orgs the plan is visible in).
    # code below can make use of.

    set orgs [struct::list filter [v2 service_plan_visibility list] [lambda {p link} {
	[$link @service_plan] == $p
    } $theplan]]

    display \n[$theplan name]
    [table::do t {What Value} {

	set kind [$theplan @service]
	set p    [$kind @provider]
	set v    [$kind @version]

	$t add Type [$kind @label]

	if {$p ne {}} { $t add Provider $p }
	if {$v ne {}} { $t add Version  $v }

	$t add "Description" [$theplan @description]

	if {[$theplan @free defined?]} {
	    $t add "Free" [$theplan @free]
	}
	if {[$theplan @public defined?]} {
	    $t add "Public" [$theplan @public]
	}
	$t add {Visible In}  [join $orgs \n]

    }] show display

    debug.cmd/servicemgr {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicemgr::update-plan {config} {
    debug.cmd/servicemgr {}

    # V2 only.
    # client v2 = @name is service plan entity
    variable def

    set theplan [$config @name]
    if {![$config @name set?]} {
	$config @name undefined!
    }

    set changes 0

    display "Updating service plan \[[$theplan name]\] ..."

    set lines {}

    foreach {attrc attre label canbeempty} $def {
	if {![$config $attrc set?]} {
	    # Fill per interaction.
	    #$config $attrc interact "[string totitle [string trim $label]]: "
	    # Note: Cmdr interact does not allow for a default.
	    # More complicated by the fact that our defaults are dynamic.

	    if {[$theplan $attre defined?]} {
		set current [$theplan $attre]
		set prompt  "[string totitle [string trim $label]] ([color yes $current]): "
		set new [ask string $prompt $current]
		if {$new eq $current} continue
	    } else {
		set prompt  "[string totitle [string trim $label]]: "
		set new [ask string $prompt]
	    }

	    $config $attrc set $new
	}

	set value [$config $attrc]
	if {!$canbeempty && ($value eq {})} {
	    err "An empty plan [string trim $label] is not allowed"
	}

	$theplan $attre set $value
	lappend lines "  Changed $label to \"$value\""
	incr changes
    }

    if {$changes} {
	display [join $lines \n]
	$theplan commit
	display [color good OK]
    } else {
	display "No changes made."
    }

    debug.cmd/servicemgr {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicemgr::link-plan-org {config} {
    debug.cmd/servicemgr {}

    set theplan [$config @name]
    set theorg  [$config @organization]

    # Print a warning when plan/org already bound together.
    set msg "Making [$theplan name] visible to [$theorg @name] ..."

    if {[llength [struct::list filter [v2 service_plan_visibility list] [lambda {p o link} {
	expr {[[$link @service_plan] == $p] &&
	      [[$link @organization] == $o]}
    } $theplan $theorg]]]} {
	display "${msg} SKIPPED (already done)"

	debug.cmd/servicemgr {/skipped}
	return
    }

    set link [v2 service_plan_visibility new]

    $link @service_plan set $theplan
    $link @organization set $theorg

    display $msg false
    $link commit
    display [color good " OK"]

    debug.cmd/servicemgr {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicemgr::unlink-plan-org {config} {
    debug.cmd/servicemgr {}

    set theplan [$config @name]
    set theorg  [$config @organization]

    # Print a warning when plan/org not bound bound together.
    set msg "Hiding [$theplan name] from [$theorg @name] ..."

    set links [struct::list filter [v2 service_plan_visibility list] [lambda {p o link} {
	expr {[[$link @service_plan] == $p] &&
	      [[$link @organization] == $o]}
    } $theplan $theorg]]

    if {![llength $links]} {
	display "$msg  SKIPPED (already hidden)"
	debug.cmd/servicemgr {/skipped}
	return 0
    }

    display $msg false
    foreach link $links {
	$link delete
	$link commit
    }

    display [color good " OK"]
    debug.cmd/servicemgr {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicemgr::list-plans {config} {
    debug.cmd/servicemgr {}

    set theplans [v2 service_plan list 1 include-relations service]
    # chosen depth delivers plans, services, and service instances.
    # include-relations drops the unwanted latter.

    DisplayServicePlans $config $theplans no
    return
}

proc ::stackato::cmd::servicemgr::market {config} {
    debug.cmd/servicemgr {}

    set theplans [struct::list flatten \
		      [struct::list map \
			   [[cspace get] @services get* {depth 1 include-relations service_plan}] \
			   [lambda s {
			       $s @service_plans
			   }]]]

    # chosen depth delivers plans, services, and service instances.
    # include-relations drops the unwanted latter.

    display [context format-short]
    DisplayServicePlans $config $theplans no
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
    # Note: The global query does not handle the user-provided flag,
    # requiring us to perform a second call to get the user provided
    # instances as well.
    # [bug 104423 - new maximum depth is 2 - would like to have 3 here]
    set     provisioned [v2 service_instance list 2 \
			     include-relations space,organization,service_bindings,app]
    lappend provisioned {*}[v2 user_provided_service_instance list]

    # And the plans, plus their underlying service(-type)s.
    set supported [v2 service_plan list 1 include-relations service]

    if {[$config @json]} {
	set tmpp {}
	foreach p $provisioned {
	    lappend tmpp [$p as-json]
	}
	set tmps {}
	foreach s $supported {
	    lappend tmps [$s as-json]
	}

	display [json::write object \
		     system      [json::write array {*}$tmps] \
		     provisioned [json::write array {*}$tmpp]]
	return
    }

    DisplayServicePlans          $config $supported
    DisplayProvisionedServicesV2 $provisioned

    debug.cmd/servicemgr {/done}
    return
}

proc ::stackato::cmd::servicemgr::DisplayServicePlans {config theplans {header yes}} {
    debug.cmd/servicemgr {}

    if {[$config @json]} {
	set tmp {}
	foreach s $theplans {
	    lappend tmp [$s as-json]
	}
	display [json::write array {*}$tmp]
	return
    }

    if {$header} {
	display "\n============== Service Plans ================\n"
    }
    if {![llength $theplans]} {
	display "No service plans available"
	debug.cmd/servicemgr {/done NONE}
	return
    }

    # Prefetch all service brokers so that we can resolve their uuids
    # in the service plans. This is a workaround to the fact that you
    # can ask for a list of brokers, but the entity url given is not
    # working (404).
    try {
	v2 service_broker list
    } trap {STACKATO CLIENT AUTHERROR}    {e} - \
      trap {STACKATO CLIENT V2 AUTHERROR} {e} {
	# ignore authorization issues. Degrade gracfully later below.
	debug.cmd/servicemgr {no authorization for broker data/names}
	set brokernames no
    } on ok {e o} {
	set brokernames yes
    }

    # Pull the plan <-> org linkage and convert into a map the table
    # code below can make use of.
    set vis {}
    foreach link [v2 service_plan_visibility list] {
	dict lappend vis [$link @service_plan] 	[$link @organization @name]
    }


    # Extract the information we wish to show.
    # Having it in list form makes sorting easier, later.
    set plans {}
    foreach plan $theplans {
	set service [$plan @service]
	# plan    -> name, description, extra, &service
	# service -> label, provider, url, description, version, info url, extra

	# Do not show plans depending on inactive services.
	if {![$service @active]} continue

	set p [$service @provider]
	set v [$service @version]

	#lappend details $bits
	lappend details [$service @label]
	lappend details [$plan    @name]
	lappend details [$service @description]
	lappend details [$plan    @description]

	# Permission bits (free, public).
	foreach {a l} {
	    @free   F
	    @public P
	} {
	    if {![$plan $a defined?]} {
		lappend details n/a
	    } else {
		#append bits [expr {[$plan $a] ? "$l" : "-"}]
		lappend details [expr {[$plan $a] ? "yes" : "no"}]
	    }
	}

	lappend details $p
	lappend details $v

	if {[$service @service_broker defined?]} {
	    if {$brokernames} {
		lappend details [$service @service_broker @name]
	    } else {
		# No auth for broker data, just list the uuid
		lappend details [$service @service_broker id]
	    }
	} else {
	    lappend details {}
	}

	# Orgs the plan is visible to.
	lappend details [join [dict get' $vis $plan {}] \n]

	lappend plans $details
	unset details
    }

    # Now format and display the table
    [table::do t {Vendor Plan Description Details Free Public Provider Version Broker Orgs} {
	foreach plan [lsort -dict -index 1 [lsort -dict $plans]] {
	    $t add {*}[lreplace $plan 1 1 [color name [lindex $plan 1]]]
	}
    }] show display

    debug.cmd/servicemgr {/done OK}
    return
}

proc ::stackato::cmd::servicemgr::DisplayProvisionedServicesV2 {services} {
    debug.cmd/servicemgr {}

    display "\n=========== Provisioned Services ============\n"
    if {$services eq {}} return

    set services [v2 sort @name $services -dict]

    [table::do t {Space Name Service Provider Version Plan Applications State} {
	foreach service $services {
	    set space [$service @space]
	    set name  [$service @name]

	    if {[catch {
		set plan [$service @service_plan]
	    }]} {
		set label    "user-provided"
		set provider "n/a"
		set version  "n/a"
		set pname    "n/a"
	    } else {
		set kind     [$plan @service]
		set label    [$kind @label]
		set provider [$kind @provider]
		set version  [$kind @version]
		set pname    [$plan @name]
	    }

	    $t add \
		[$space full-name] \
		[color name $name] \
		$label $provider $version $pname \
		[join [$service @service_bindings @app @name] \n] \
		[TheState $service]
	}
    }] show display

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

    set provisioned [misc sort-aod name [$client services] -dict]
    #@type provisioned = list (services?)

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

    if {![$config @name set?]} {
	$config @name undefined!
    }
    if {$new eq {}} {
	err "An empty service name is not allowed"
    }

    display "Renaming service \[[$service @name]\] to $new ... " false
    $service @name set $new
    $service commit
    display [color good OK]

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

    debug.cmd/servicemgr {src $srcapp}
    debug.cmd/servicemgr {dst $dstapp}

    if {[$srcapp == $dstapp]} {
	err {Source and destination are the same application}
    }

    set services [$srcapp @service_bindings @service_instance]

    if {![llength $services]} {
	err {No services to clone}
    }

    foreach service $services {
	debug.cmd/servicemgr {srv $service : [$service @name]}
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

    if {[cspace get] eq {}} {
	err "Unable to create a service. No space specified."
    }

    # @provider already processed (validate, generate)
    # @version  already processed (validate, generate)
    # @name   always defined (generate (select-for-create)).
    # @plan   always defined (generate (select-plan-for-create)).

    # Pull the relevant arguments...
    set vendor [$config @vendor]
    set plan   [$config @plan]
    set name   [$config @name]
    set picked [expr {![$config @name set?]}]

    if {[$vendor @label] eq "user-provided"} {
	# user-defined service. No actual plan.
	# Ask user for the credential keys, then the credentials,
	# and save these directly.

	if {[$config @tag set?]} {
	    err "Option --tag not allowed for user-provided service."
	}
	if {[$config @parameters set?]} {
	    err "Option --parameters not allowed for user-provided service."
	}

	set creds  [CollectCredentials $config]

	set service [service create-udef-with-banner $client $creds $name $picked]
    } else {
	if {[$config @credentials set?]} {
	    err "Option --credentials not allowed for non-user-provided service."
	}

	set tags [$config @tag]
	set asp  [GetASP $config]

	set service [service create-with-banner $client $plan $name $tags $asp $picked]
    }

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

proc ::stackato::cmd::servicemgr::update-upsi {config} {
    debug.cmd/servicemgr {}

    set theservice [$config @service]
    if {[namespace tail [info object class $theservice]] ne "user_provided_service_instance"} {
	err "Service instance \"[$theservice @name]\" is not user provided."
    }

    set creds [CollectCredentials $config]

    display "Updating user-provided service [$theservice @name] ... "
    display "From ..."
    ShowCreds $theservice
    display "To ..."
    $theservice @credentials set $creds
    ShowCreds $theservice
    display "Committing ..." false
    $theservice commit
    display [color good OK]

    debug.cmd/servicemgr {/done}
    return
}

proc ::stackato::cmd::servicemgr::ShowCreds {theservice} {
    set creds [$theservice @credentials]
    [table::do t {Key Value} {
	foreach k [lsort -dict [dict keys $creds]] {
	    set vx [dict get $creds $k]
	    if {$k in {created updated}} {
		set vx [clock format $vx]
	    }
	    $t add $k $vx
	}
    }] show {::stackato::cmd::servicemgr::ShowI {    }}
}

proc ::stackato::cmd::servicemgr::ShowI {prefix text} {
    lappend map \n \n$prefix
    display $prefix[string map $map $text]
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

	set todelete [[cspace get] @service_instances get* {user-provided true}]
    } else {
	debug.cmd/servicemgr {some, by user}

	set todelete [$config @service]
    }

    # Deletion loop.
    set unbind [$config @unbind]

    foreach service $todelete {
	set name [$service @name]

	set bindings [$service @service_bindings get* {depth 1 include-relations app}]
	set nbounds  [llength $bindings]

	if {$nbounds && !$unbind} {
	    display "Deleting service $name ... SKIPPED (bound to $nbounds application[expr {$nbounds != 1 ? "s" : ""}])"
	    continue
	}

	if {[cmdr interactive?] &&
	    ![ask yn \
		  "\nReally delete service \"[color name $name]\" ? " \
		  no]} continue

	if {$nbounds} {
	    # Implied that unbind is set.
	    foreach link $bindings {
		display "Unbinding [color name [$service @name]] from [color name [$link @app @name]] ... " false
		$link delete
		$link commit
		display [color good OK]
	    }
	}

	display "Deleting service [color name $name] ... " false
	$service delete
	$service commit
	display [color good OK]
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

    if {![$config @json]} {
	display \n[context format-short \
		     " -> [color name [$service @name]]"]
    } else {
	display [$service as-json]
	return
    }

    [table::do t {What Value} {
	$t add State [TheState $service]

	if {[catch {
	    set plan [$service @service_plan]
	}]} {
	    $t add Type         user-provided
	} else {
	    set kind [$plan @service]
	    set p    [$kind @provider]
	    set v    [$kind @version]

	    $t add Type         [$kind @label]

	    if {$p ne {}} { $t add Provider $p }
	    if {$v ne {}} { $t add Version  $v }

	    ## Note: Not getting tags and parameters back from the target.
	    ## Might need a newer build.
	    #   $t add Tags       [join [$service @tags] {, }]
	    #   $t add Parameters [$service @parameters]

	    $t add Plan            [color name [$plan @name]]
	    $t add "- Description" [$plan @description]
	    if {[$plan @free defined?]} {
		$t add "- Free" [$plan @free]
	    }
	    if {[$plan @public defined?]} {
		$t add "- Public" [$plan @public]
	    }
	    $t add Dashboard [$service @dashboard_url]
	}

	$t add Space [color name [$service @space full-name]]

	set creds [$service @credentials]
	if {[dict size $creds]} {
	    $t add Credentials {}
	    foreach k [lsort -dict [dict keys $creds]] {
		set vx [dict get $creds $k]
		if {$k in {created updated}} {
		    set vx [clock format $vx]
		}
		$t add " - $k" $vx
	    }
	}

	# Create data structure to map app name to credentials from binding.
	set tmp {}
	foreach binding [$service @service_bindings] {
	    lappend tmp [list \
			     [$binding @app @name] \
			     [$binding @credentials]]
	}

	$t add Applications {}
	foreach item [lsort -dict -index 0 $tmp] {
	    lassign $item app creds

	    $t add "- $app" {}
	    foreach k [lsort -dict [dict keys $creds]] {
		set vx [dict get $creds $k]
		if {$k in {created updated}} {
		    set vx [clock format $vx]
		}
		$t add "  - $k" $vx
	    }
	}

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

proc ::stackato::cmd::servicemgr::TheState {service} {
    debug.cmd/servicemgr {}
    if {![catch {
	array set st [$service @last_operation]
    }]} {
	append state $st(type) " "
	set los $st(state)
	switch -glob -- $los {
	    succ* {
		append state [color good $los]
	    }
	    {in pro*} {
		append state [color note $los]
	    }
	    default {
		append state [color bad $los]
	    }
	}
    } else {
	set state "no data"
    }
    return $state
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicemgr::tunnel {config} {
    debug.cmd/servicemgr {}

    set client [$config @client]
    Tunnel $config $client

    debug.cmd/servicemgr {/done}
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
	set vendor [SelectCreateV2 $client $p]
    } else {
	set vendor [SelectCreateV1 $client]
    }

    debug.cmd/servicemgr {==> $vendor}
    return $vendor
}

proc ::stackato::cmd::servicemgr::SelectCreateV2 {client p} {
    debug.cmd/servicemgr {}

    # Get possibilities, already filtered per @provider, @vendor
    set services [servicetype get-candidates $p]

    # See also servicetype::validate
    # "user-provided" pseudo service-type.
    # No plans (none required).
    set up [v2 service new]
    $up @label    set user-provided
    $up @version  set {}
    $up @provider set {}

    lappend services $up

    if {![llength $services]} {
	err {No services matching the filter criteria found.}
    }

    # Generate labels for the interaction and keep mapping to
    # originating object.
    foreach s $services {
	set l [$s @label]
	set v [$s @version]
	set p [$s @provider]

	set label $l
	if {$v ne {}} { append label { } $v }
	if {$p ne {}} { append label ", by " $p }

	dict set map $label $s
	lappend choices $label
    }

    # Talk with the user.
    set vendorlabel [ask menu "" \
			 "Which kind to provision: " \
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

    set vendor [ask menu "" \
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

    set vendor [$p config @vendor]
    if {[$vendor @label] eq "user-provided"} {
	# No plan required.
	return {}
    }

    if {![cmdr interactive?]} {
	$p undefined!
	# implied return/failure
    }

    # See serviceplan validation type for similar.
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
    set planlabel [ask menu "" \
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

    set services [[cspace get] @service_instances get* {user-provided true}]

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
    set servicelabel [ask menu "" \
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
    set service [list [ask menu "" \
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

    set services [[cspace get] @service_instances get* {user-provided true}]

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
    set servicelabel [ask menu "" \
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
    set service [list [ask menu "" \
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

    logstream start   $config                  $theapp
    BindServiceBanner $config $client $service $theapp
    logstream stop    $config
    return
}

proc ::stackato::cmd::servicemgr::Unbind {config theapp} {
    debug.cmd/servicemgr {}

    set client  [$config @client]
    set service [$config @service]

    logstream start     $config                  $theapp
    UnbindServiceBanner $config $client $service $theapp
    logstream stop      $config
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

proc ::stackato::cmd::servicemgr::Tunnel {config client} {
    debug.cmd/servicemgr {}

    set service   [$config @service] ;# :: string
    set tclient   [$config @tunnelclient]
    set turl      [$config @url]
    set allowhttp [$config @allow-http]
    set trace     [$config @trace]
    set port      [$config @port]

    # tclient = name of the command to run. May have a path.

    if {[$client isv2]} {
	lassign [ProcessService2 $service] service sname vendor
	# service = service entity
	# sname   = service name
    } else {
	lassign [ProcessService1 $client $service] service sname vendor
	# service = sname = the service name
    }

    # TODO: rather than default to a particular port, we should get
    # the defaults based on the service name.. i.e. known services
    # should have known local default ports for this side of the
    # tunnel.

    set port [tunnelmgr pick-port $port]

    # We need the tunnel helper application on the server side.
    # We create and push it on the first use of a tunnel.

    if {![tunnelmgr pushed? $config]} {
	display "Deploying helper application '[tunnelmgr appname]'."

	set auth [uuid::uuid generate]

	PushBindStart $config $auth $service $turl
    } else {
	# pushed? implied a 'tunnelmgr def' when found.

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

	display "Redeploying helper application '[tunnelmgr appname]'."

	DeleteTunnelHelper $config
	PushBindStart      $config $auth $service $turl
    }

    # XXX XXX TESTED TO HERE
    # While start above fails, health check is possible with the pushed/broken helper
    # Stalled...

    # Make really sure that the service to talk to has a connection to
    # the helper application.

    if {![tunnelmgr bound? $client $service]} {
	service bind-with-banner $client $service [tunnelmgr app]
	app check-app-for-restart $config [tunnelmgr app]
    }

    set connection [tunnelmgr connection-info \
			$allowhttp $client \
			$vendor \
		        $sname \
			$auth]

    DisplayTunnelConnectionInfo $connection

    lassign [ProcessClient $tclient $sname $vendor] tclient clients

    # Start tunnel and run client, or wait while external clients use
    # the tunnel.

    if {$tclient eq "none"} {
	tunnelmgr start $allowhttp $client $trace many $sname $port $connection $auth
	tunnelmgr wait-for-end
    } else {
	tunnelmgr start $allowhttp $client $trace once $sname $port $connection $auth
	tunnelmgr wait-for-start $port

	if {![tunnelmgr start-local-client $clients $tclient $connection $port]} {
	    err "'$tclient' execution failed; is it in your \$PATH?"
	}
    }
    return
}

proc ::stackato::cmd::servicemgr::PushBindStart {config auth service turl} {
    debug.cmd/servicemgr {}

    set client [$config @client]

    PushTunnelHelper         $config $auth $turl
    service bind-with-banner $client $service [tunnelmgr app]
    StartTunnelHelper        $config

    debug.cmd/servicemgr {/done}
}

proc ::stackato::cmd::servicemgr::StartTunnelHelper {config} {
    debug.cmd/servicemgr {}

    app start-single $config [tunnelmgr app]
    tunnelmgr invalidate-caches
    return
}

proc ::stackato::cmd::servicemgr::StopTunnelHelper {config} {
    debug.cmd/servicemgr {}

    app stop1 $config [tunnelmgr app]
    tunnelmgr invalidate-caches
    return
}

proc ::stackato::cmd::servicemgr::DeleteTunnelHelper {config} {
    debug.cmd/servicemgr {}

    # validation takes care of v1/v2 differences
    # v1: app name, v2: app instance
    # Using 'known' instead of 'validate' forces us to throw the error on our own.
    # It also avoids superfluous client refreshes now.


    app delete1 $config [tunnelmgr app]
    tunnelmgr invalidate-caches
    FlushSpace $config
    return
}

proc ::stackato::cmd::servicemgr::PushTunnelHelper {config token turl} {
    debug.cmd/servicemgr {}
    debug.cmd/servicemgr {app = [tunnelmgr helper]}

    set client [$config @client]

    if {$turl eq {}} {
	set turl [tunnelmgr uniquename].[ctarget suggest]
    }

    foreach mbase {
	stackato.yml
	manifest.yml
    } {
	set mfile [tunnelmgr helper]/$mbase
	if {[file exist $mfile]} break
	set mfile {}
    }

    manifest config= [$config @client self] _
    manifest setup 1 [tunnelmgr helper] $mfile reset
    set appname [tunnelmgr appname]

    manifest current= $appname 1

    # We know everything about the helper.
    # See also cmd/app: Create(AppV[12]).

    if {[$client isv2]} {
	set theapp [v2 app new]
	$theapp @name             set $appname
	$theapp @space            set [cspace get]
	$theapp @environment_json set [dict create TUNNEL_AUTH $token]
	$theapp @memory           set 128
	$theapp @total_instances  set 1

	$theapp commit
	app map-urls $config $theapp [list $turl] 1
	# note re above: app-creation is rolled back in case of url
	# mapping issues.

	tunnelmgr def 2 $theapp
	#stack/framework/buildpack/...
    } else {
	$client create_app [tunnelmgr appname] \
	    [dict create \
		 name $appname \
		 staging {framework sinatra} \
		 uris [list $turl] \
		 instances 1 \
		 resources {memory 72} \
		 env [list TUNNEL_AUTH=$token]]
	set theapp $appname
	tunnelmgr def 1 $theapp
    }

    app upload-files $config [tunnelmgr app] $appname [tunnelmgr helper]

    FlushSpace $config
    debug.cmd/servicemgr {/done}
    return
}

proc ::stackato::cmd::servicemgr::FlushSpace {config} {
    debug.cmd/servicemgr {}
    if {[[$config @client] isv2]} {
	debug.cmd/servicemgr {/go}
	# flush in-memory space and its cached lists (apps, service instances)
	[cspace get] destroy
	cspace reset ; # and tell mgr that its handle is gone.
    }
    debug.cmd/servicemgr {/done}
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

    # Special sorting, with User, Password, and Name at the top, in
    # this order.
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

proc ::stackato::cmd::servicemgr::ProcessService2 {service} {
    # service = string.
    debug.cmd/servicemgr {}

    set thespace [cspace get]
    if {$thespace eq {}} {
	err "Need a current space to in."
    }

    # Immediately pull in the related entitities for quick
    # dereferencing of relations below.
    set services [$thespace @service_instances get 2]
    ## Note: UPSI not taken here, cannot be tunneled to anyway.

    if {![llength $services]} {
	err "No services available to tunnel to"
    }

    if {$service eq {}} {
	# select service among those which accept tunnels.

	set choices {}
	foreach s $services {
	   set vendor [$s @service_plan @service @label]
	    # (x$x)
	    if {![AcceptTunnel $vendor]} continue
	    dict set choices [$s @name] $s
	}

	if {![dict size $choices]} {
	    err "No services available to tunnel to"
	}
	set service [ask menu "" \
			 "Which service to tunnel to: " \
			 [lsort -dict [dict keys $choices]]]
	set service [dict get $choices $service]
    } else {
	# Convert from name to entity.
	set matches [$thespace @service_instances filter-by @name $service]
	## Note: UPSI not taken here, cannot be tunneled to anyway.
	if {[llength $matches] != 1} {
	    err "Unknown service '$service'."
	}
	set service [lindex $matches 0]
    }

    # Check that the specified service accepts a tunnel.
    set vendor [$service @service_plan @service @label]
    # (x$x)
    if {![AcceptTunnel $vendor]} {
	err "Service '$service' does not accept tunnels."
    }

    # entity
    return [list $service [$service @name] $vendor]
}

proc ::stackato::cmd::servicemgr::ProcessService1 {client service} {
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
	    if {![AcceptTunnel $vendor]} continue
	    lappend choices [dict getit $s name]
	}

	if {![llength $choices]} {
	    err "No services available to tunnel to"
	}
	set service [ask menu "" \
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
    if {![AcceptTunnel $vendor]} {
	err "Service '$service' does not accept tunnels."
    }

    # end XXX

    return [list $service $service $vendor]
}

proc ::stackato::cmd::servicemgr::AcceptTunnel {vendor} {
    # See also ::stackato::cmd::app::AcceptDbshell, consolidate
    expr {$vendor in {
	oracledb mysql redis mongodb postgresql mssql2012 mssql2014
    }}
}

proc ::stackato::cmd::servicemgr::ProcessClient {tclient servicename vendor} {
    debug.cmd/servicemgr {}
    # tclient = name of the command to run. May have a path.

    set clients [GetClientsFor $vendor]

    if {![llength $clients]} {
	if {$tclient eq {}} {
	    set tclient none
	}
    } else {
	if {$tclient eq {}} {
	    set tclient [ask menu "" \
			     "Which client would you like to start? " \
			     [concat none [dict keys $clients]]]
	}
    }

    set basecmd [file root [file tail $tclient]]
    set names   [linsert [dict keys $clients] end none]
    if {$basecmd ni $names} {
	err "Unknown client \[$basecmd\] for \[$servicename\], please choose one of [linsert '[join $names {', '}]' end-1 or]."
    }

    return [list $tclient $clients]
}

proc ::stackato::cmd::servicemgr::GetClientsFor {vendor} {
    debug.cmd/servicemgr {}
    return [dict get' [tclients get] $vendor {}]
}

proc ::stackato::cmd::servicemgr::CollectCredentials {config} {
    debug.cmd/servicemgr {}

    if {![cmdr interactive?] && ![$config @credentials set?]} {
	err "Need --credentials"
    }

    if {![$config @credentials set?]} {
	# Go interactive

	set keys [ask string "Which credentials to use for connections \[hostname, port, password\]: "]
	if {$keys eq {}} {
	    set keys {hostname port password}
	} else {
	    set keys [struct::list map [split $keys ,] {string trim}]
	}
	foreach k $keys {
	    dict set creds $k [ask string "$k: "]
	}
    } else {
	# Take from option - Treat input as Tcl dictionary.
	foreach kv [$config @credentials] {
	    dict set creds {*}$kv
	}
    }

    return $creds
}

proc ::stackato::cmd::servicemgr::GetASP {config} {
    debug.cmd/servicemgr {}

    # Bail out quickly if nothing got specified
    if {![$config @parameters set?]} { return {} }

    # Read and validate the asp a bit.
    set asp [fileutil::cat [$config @parameters]]
    try {
	json::json2dict $asp
    } trap {JSON} {e o} {
	err "Bad json data for arbitrary service parameters: $e"
    }
    return $asp
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::servicemgr 0
return
