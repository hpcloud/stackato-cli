## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Instance Index
## Dependency: config @client, @application
## Full check is done only for v2.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate
package require stackato::mgr::client;# pulls v2 also
package require stackato::mgr::manifest
package require stackato::validate::common
package require stackato::validate::integer0

debug level  validate/instance
debug prefix validate/instance {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export instance
    namespace ensemble create
}

namespace eval ::stackato::validate::instance {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-unknown-thing
    namespace import ::stackato::mgr::manifest
    namespace import ::stackato::v2
    namespace import ::stackato::validate::common::refresh-client
    namespace import ::stackato::validate::integer0
}

proc ::stackato::validate::instance::default {p}   {
    debug.validate/instance {}

    # Used as 'generate' callback, defering use from cli declaration to ''completion''.
    if {[[refresh-client $p] isv2]} {
	debug.validate/instance {/v2}

	manifest config= $p _

	# See also '::stackato::cmd::app::files'.
	if {[$p config @application set?] && ([$p config @application] eq ".")} {
	    # Fake 'undefined' for 'user_all' below.
	    $p config @application reset
	}

	manifest user_1app_do theapp {
	    if {$theapp ni {api {}}} {
		set imap [$theapp instances]
	    }
	} keep
	if {$theapp in {api {}}} { return 0 }

	debug.validate/instance {$theapp ([$theapp @name]) ==> ($imap)}

	if {[dict exists $imap 0]} {
	    # Found first instance, good. Translate into the object.
	    set x [dict get $imap 0]
	    debug.validate/instance {first = $x}
	    return $x
	}

	# No instances, abort.
	fail-unknown-thing $p INSTANCE "instance index" 0 " for application '[$theapp @name]'"

    } else {
	debug.validate/instance {/v1 = 0}
	# v1, just an instance number
	return 0
    }
}
proc ::stackato::validate::instance::release  {p x} { return }
proc ::stackato::validate::instance::complete {p x} {
    if {[[refresh-client $p] isv2]} {
	# v2 - query application for instances
	set theapp [$p config @application]
	set candidates [dict keys [$theapp instances]]
	complete-enum $candidates 0 $x
    } else {
	# v1 - no completion
	return {}
    }
}

proc ::stackato::validate::instance::validate {p x} {
    debug.validate/instance {}

    if {[[refresh-client $p] isv2]} {
	# v2 -- query application entity for its instances

	manifest config= $p _

	# See also '::stackato::cmd::app::files'.
	if {[$p config @application set?] && ([$p config @application] eq ".")} {
	    # Fake 'undefined' for 'user_all' below.
	    $p config @application reset
	}

	manifest user_1app_do theapp {
	    if {$theapp ne "api"} {
		set imap [$theapp instances]
	    }
	}

	if {$theapp eq "api"} {
	    # Accept anything, does not matter for ssh to CC
	    debug.validate/instance {OK/ssh-CC allow anything, irrelevant}
	    return $x
	}

	if {[dict exists $imap $x]} {
	    # Found, good. Translate into the object.
	    set x [dict get $imap $x]
	    debug.validate/instance {OK/canon = $x}
	    return $x
	}

	set idx [lsort -dict [dict keys $imap]]
	set min [lindex $idx 0]
	set max [lindex $idx end]

	if {$min == $max} {
	    set note "!= $min"
	} else {
	    set note "outside ${min}-$max"
	}

	debug.validate/instance {FAIL}
	fail-unknown-thing $p INSTANCE "instance index" $x " for application '[$theapp @name]' ($note)"
    } else {
	# v1 ... Validate as plain integer0
	integer0 validate $p $x
    }
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::instance 0
