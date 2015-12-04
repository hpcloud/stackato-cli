# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations. User management.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::ask
package require cmdr::color
package require stackato::jmap
package require stackato::mgr::context
package require stackato::log
package require stackato::v2
package require table

debug level  cmd/servicebroker
debug prefix cmd/servicebroker {[debug caller] | }

namespace eval ::stackato::cmd {
    namespace export servicebroker
    namespace ensemble create
}
namespace eval ::stackato::cmd::servicebroker {
    namespace export list add update remove show
    namespace ensemble create

    namespace import ::cmdr::ask
    namespace import ::cmdr::color
    namespace import ::stackato::jmap
    namespace import ::stackato::log::display
    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::context
    namespace import ::stackato::v2

    # Shared definition for add/update

    #   attr-config   attr-entity    label canbeempty always
    variable def {
	@newname      @name          {name    } 0 1
	@url          @broker_url    {url     } 0 1
	@username     @auth_username {user    } 1 1
	@password     @auth_password {password} 1 1
	@broker-token @token         {token   } 0 0
    }
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicebroker::list {config} {
    debug.cmd/servicebroker {}

    set thebrokers [v2 service_broker list]

    if {![$config @json]} {
	display "\nService brokers: [context format-target]"
    }

    if {[$config @json]} {
	set tmp {}
	foreach broker $thebrokers {
	    lappend tmp [$broker as-json]
	}
	display [json::write array {*}$tmp]
	return
    }

    if {![llength $thebrokers]} {
	display [color note "No service brokers"]
	debug.cmd/servicebroker {/done NONE}
	return
    }

    # Extract the information we wish to show.
    # Having it in list form makes sorting easier, later.

    foreach broker $thebrokers {
	set name [$broker @name]
	set url  [$broker @broker_url]

	lappend details $name $url
	lappend brokers $details
	unset details
    }

    # Now format and display the table
    [table::do t {Name Url} {
	foreach tok [lsort -dict $brokers] {
	    $t add {*}$tok
	}
    }] show display

    debug.cmd/servicebroker {/done OK}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicebroker::add {config} {
    debug.cmd/servicebroker {}
    # V2 only.
    variable def

    set broker [v2 service_broker new]
    # Note: We are ignoring the @token attribute of service broker
    # entities, as it is apparently not used anywhere taqrget-side.

    set post30 [package vsatisfies [[$config @client] server-version] 3.1]

    foreach {attrc attre label canbeempty always} $def {
	# Note: @broker-token is required for Stackato 3.0.
	# Anti-check for its presence against 3.2 is done by Cmdr.
	# Check if its missing for 3.0 is done here.
	if {$attrc eq "@newname"} { set attrc @name }

	set value [$config $attrc]
	if {$always || !$post30} {
	    if {![$config $attrc set?]} {
		$config $attrc undefined!
	    }
	    if {!$canbeempty && ($value eq {})} {
		err "An empty broker [string trim $label] is not allowed"
	    }
	}

	$broker $attre set $value
    }

    display "Creating new service broker \[[$config @name]\] ... " false

    $broker commit
    display [color good OK]

    if {![$config @public]} return

    # Pull the plans of the new broker and make them public. Prefetch
    # all brokers to ensure resolution in-client, avoiding a broken CC
    # endpoint.

    display "Make new plans public ..."

    lappend plans  {}
    lappend labels Vendor
    lappend names  Plan
    lappend sdesc  Description
    lappend pdesc  Details

    v2 service_broker list
    foreach plan [v2 service_plan list] {
	set service [$plan @service]

	if {![$service @service_broker defined?]} continue
	if {![$broker == [$service @service_broker]]} continue

	lappend plans  $plan
	lappend labels [$service @label]      
	lappend names  [$plan    @name]	      
	lappend sdesc  [$service @description]
	lappend pdesc  [$plan    @description]
    }

    if {[llength $plans] < 2} {
	display [color yellow {  No plans found}]
	return
    }

    foreach \
	plan  $plans  \
	label [PadR $labels] \
	name  [PadR $names]  \
	sd    [PadR $sdesc]  \
	pd    [PadR $pdesc] {

	display "  | $label | $name | $sd | $pd |" false
	if {$plan eq {}} { display " --" ; continue }

	display " " false

	$plan @public set yes
	$plan commit
	display [color green OK]
    }

    debug.cmd/servicebroker {/done}
    return
}

proc ::stackato::cmd::servicebroker::PadR {list} {
    if {[llength $list] <= 1} {
        return $list
    }
    set maxl 0
    foreach str $list {
        set l [string length $str]
        if {$l <= $maxl} continue
        set maxl $l
    }
    set res {}
    foreach str $list { lappend res [format "%-*s" $maxl $str] }
    return $res
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicebroker::remove {config} {
    debug.cmd/servicebroker {}
    # V2 only.
    # client v2 = @name is entity instance

    set broker [$config @name]
    if {![$config @name set?]} {
	$config @name undefined!
    }

    display "Deleting service broker \[[$broker @name]\] ... " false
    $broker delete
    $broker commit
    display [color good OK]

    debug.cmd/servicebroker {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicebroker::show {config} {
    debug.cmd/servicebroker {}
    # V2 only.
    # client v2 = @name is entity instance

    set broker [$config @name]
    if {![$config @name set?]} {
	$config @name undefined!
    }

    # Now format and display the table
    [table::do t {Key Value} {
	$t add Name     [$broker @name]
	$t add Location [$broker @broker_url]
    }] show display

    debug.cmd/servicebroker {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicebroker::update {config} {
    debug.cmd/servicebroker {}
    # V2 only.
    # client v2 = @name is entity instance
    variable def

    set broker [$config @name]
    if {![$config @name set?]} {
	$config @name undefined!
    }

    set changes 0
    set post30  [package vsatisfies [[$config @client] server-version] 3.1]

    display "Updating broker \[[$broker @name]\] ..."

    # Note: We are ignoring the @token attribute of service broker
    # entities, as it is apparently not used anywhere taqrget-side.

    set lines {}

    foreach {attrc attre label canbeempty always} $def {
	# Anti-check for presence of broker-token against 3.2 is done by Cmdr.
	# Check for missing for 3.0 is not required as this command allows changing
	# the definition in parts.

	if {![$config $attrc set?]} {
	    if {$always || !$post30} {
		# Fill per interaction.
		#$config $attrc interact "[string totitle [string trim $label]]: "
		# Note: Cmdr interact does not allow for a default.
		# More complicated by the fact that our defaults are dynamic.

		if {[$broker $attre defined?]} {
		    set current [$broker $attre]
		    set prompt  "[string totitle [string trim $label]] ([color yes $current]): "
		    set new [ask string $prompt $current]
		    if {$new eq $current} continue
		} else {
		    set prompt  "[string totitle [string trim $label]]: "
		    set new [ask string $prompt]
		}

		$config $attrc set $new
	    }
	}

	set value [$config $attrc]
	if {$always || !$post30} {
	    if {!$canbeempty && ($value eq {})} {
		err "An empty broker [string trim $label] is not allowed"
	    }
	}

	if {!$always && $post30 && ($value eq {})} continue

	$broker $attre set $value
	lappend lines "  Changed $label to \"$value\""
	incr changes
    }

    if {$changes} {
	display [join $lines \n]
	$broker commit
	display [color good OK]
    } else {
	display [color note "No changes made"]
    }

    debug.cmd/servicebroker {/done}
    return
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::servicebroker 0
return
