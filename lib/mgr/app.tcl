# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## This module manages application related constants and support
## procedures.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require cmdr
package require dictutil
package require stackato::log
package require stackato::color
package require stackato::term
package require stackato::mgr::client
package require stackato::mgr::ctarget
package require stackato::mgr::service

namespace eval ::stackato::mgr {
    namespace export app
    namespace ensemble create
}
namespace eval ::stackato::mgr::app {
    namespace export \
	base ticker health tail timeout \
	min-memory hasharbor delete
    namespace ensemble create

    namespace import ::stackato::color
    namespace import ::stackato::log::display
    namespace import ::stackato::log::err
    namespace import ::stackato::term
    namespace import ::stackato::mgr::client
    namespace import ::stackato::mgr::ctarget
    namespace import ::stackato::mgr::service
}

debug level  mgr/app
debug prefix mgr/app {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## API for the user visible commands.

proc ::stackato::mgr::app::delete {config client theapp force {rollback 0}} {
    debug.mgr/app {}

    if {[$client isv2]} {
	DeleteV2 $config $client $theapp $force $rollback
    } else {
	DeleteV1 $client $theapp $force $rollback
    }

    debug.mgr/app {/done}
}

proc ::stackato::mgr::app::DeleteV2 {config client theapp force {rollback 0}} {
    debug.mgr/app {}
    set appname [$theapp @name]

    if {$rollback} {
	display [color red "Rolling back application \[$appname\] ... "] false
    }

    set services_to_delete [ServicesToDelete $theapp $force $rollback]
    if {$rollback || ![$config has @routes] || [$config @routes]} {
	set routes_to_delete [RoutesToDelete $theapp $rollback]
    } else {
	set routes_to_delete {}
    }

    if {!$rollback} {
	display "Deleting application \[$appname\] ... " false
    }

    $theapp delete!
    display [color green OK]

    foreach s $services_to_delete {
	display "Deleting service \[[$s @name]\] ... " false
	$s delete
	$s commit
	display [color green OK]
    }

    foreach r $routes_to_delete {
	display "Deleting route \[[$r name]\] ... " false
	$r delete
	$r commit
	display [color green OK]
    }

    debug.mgr/app {/done}
    return
}

proc ::stackato::mgr::app::DeleteV1 {client appname force {rollback 0}} {
    debug.mgr/app {}

    set bling $rollback ;# will be reset in the loop, diverging
    if {$rollback} {
	display [color red "Rolling back application \[$appname\] ... "] false
    }

    set service_map        [service map $client]
    set app                [$client app_info $appname]
    set services_to_delete {}
    set app_services       [dict getit $app services]
    set promptok           [cmdr interactive?]

    foreach service $app_services {
	#checker -scope line exclude badOption
	set multiuse [expr {[llength [dict get' $service_map $service {}]] > 1}]

	set del_service [expr {!$multiuse && ($force && !$promptok)}]
	if                    {!$multiuse && (!$force && $promptok)} {
	    if {$bling} {
		display ""
		set bling 0
	    }
	    set del_service \
		[term ask/yn "Provisioned service \[$service\] detected would you like to delete it ?: " no]
	}

	if {!$del_service} continue
	lappend services_to_delete $service
    }

    if {!$rollback} {
	display "Deleting application \[$appname\] ... " false
    }

    $client delete_app $appname
    display [color green OK]

    foreach s $services_to_delete {
	display "Deleting service \[$s\] ... " false
	$client delete_service $s
	display [color green OK]
    }

    debug.mgr/app {/done}
    return
}

proc ::stackato::mgr::app::RoutesToDelete {theapp bling} {
    set bound     [$theapp @routes]
    set to_delete {}
    set promptok  [cmdr interactive?]

    foreach route $bound {
	#checker -scope line exclude badOption
	set multiuse [expr {[llength [$route @apps]] > 1}]

	set del_route [expr {!$multiuse && !$promptok}]
	if                  {!$multiuse &&  $promptok} {
	    if {$bling} {
		display ""
		set bling 0
	    }
	    set del_route \
		[term ask/yn "Exclusive route \[[$route name]\] detected. Would you like to delete it ?: " no]
	}

	if {!$del_route} continue
	lappend to_delete $route
    }

    return $to_delete
}

proc ::stackato::mgr::app::ServicesToDelete {theapp force bling} {
    set bound [$theapp @service_bindings @service_instance]
    set services_to_delete {}
    set promptok           [cmdr interactive?]

    foreach service $bound {
	#checker -scope line exclude badOption
	set multiuse [expr {[llength [$service @service_bindings]] > 1}]

	set del_service [expr {!$multiuse && ( $force && !$promptok)}]
	if                    {!$multiuse && (!$force &&  $promptok)} {
	    if {$bling} {
		display ""
		set bling 0
	    }
	    set del_service \
		[term ask/yn "Provisioned service \[[$service @name]\] detected. Would you like to delete it ?: " no]
	}

	if {!$del_service} continue
	lappend services_to_delete $service
    }

    return $services_to_delete
}

proc ::stackato::mgr::app::base       {} { debug.mgr/app {} ; variable base   ; return $base    }
proc ::stackato::mgr::app::ticker     {} { debug.mgr/app {} ; variable ticker ; return $ticker  }
proc ::stackato::mgr::app::health     {} { debug.mgr/app {} ; variable health ; return $health  }
proc ::stackato::mgr::app::tail       {} { debug.mgr/app {} ; variable tail   ; return $tail    }
#proc ::stackato::mgr::app::timeout    {} { debug.mgr/app {} ; variable timeout; return $timeout }
proc ::stackato::mgr::app::min-memory {} { debug.mgr/app {} ; variable minmem ; return $minmem }

proc ::stackato::mgr::app::hasharbor {p x} {
    # when-set callback of the -d option (cmdr.tcl).
    # dependencies: @client (implied @target)
    set client [$p config @client]
    set harbor [expr {
      (![$client isv2] && [package vsatisfies [$client server-version] 2.7]) ||
      ( [$client isv2] && [$client is-stackato])
    }]

    if {!$harbor} {
	err "This option requires a target version 2.8 or higher"
    }
    if {![regexp {https://.*} [ctarget get]]} {
	err "This option requires a target using HTTPS"
    }
    return
}

# # ## ### ##### ######## ############# #####################
## Low level access to the client's persistent state for appes.

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::mgr::app {
    variable base    1 ; # seconds
    variable ticker  [expr { 25 / $base}]
    variable health  [expr {  5 / $base}]
    variable tail    [expr { 45 / $base}]
    #variable timeout [expr {120 / $base}]
    variable minmem  20
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::mgr::app {}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::app 0
