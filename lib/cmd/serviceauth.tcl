# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations. User management.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr
package require stackato::color
package require stackato::jmap
package require stackato::log
package require stackato::term
package require stackato::v2
package require table

debug level  cmd/serviceauth
debug prefix cmd/serviceauth {[debug caller] | }

namespace eval ::stackato::cmd {
    namespace export serviceauth
    namespace ensemble create
}
namespace eval ::stackato::cmd::serviceauth {
    namespace export \
	create update delete list \
	select-for
    namespace ensemble create

    namespace import ::stackato::color
    namespace import ::stackato::jmap
    namespace import ::stackato::log::display
    namespace import ::stackato::log::err
    namespace import ::stackato::term
    namespace import ::stackato::v2
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::serviceauth::list {config} {
    debug.cmd/serviceauth {}

    set thetokens [v2 service_auth_token list]

    if {[$config @json]} {
	set tmp {}
	foreach atoken $thetokens {
	    lappend tmp [$atoken as-json]
	}
	display [json::write array {*}$tmp]
	return
    }

    if {![llength $thetokens]} {
	display "No service auth tokens available"
	debug.cmd/serviceauth {/done NONE}
	return
    }

    # Extract the information we wish to show.
    # Having it in list form makes sorting easier, later.

    foreach token $thetokens {
	set label    [$token @label]
	set provider [$token @provider]

	lappend details $label $provider
	lappend tokens $details
	unset details
    }

    # Now format and display the table
    [table::do t {Label Provider} {
	foreach tok [lsort -dict $tokens] {
	    $t add {*}$tok
	}
    }] show display

    debug.cmd/serviceauth {/done OK}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::serviceauth::update {config} {
    debug.cmd/serviceauth {}
    # V2 only.
    # client v2 = @label is entity instance

    set thetoken [$config @label]
    set tokenstr [$config @auth-token]

    if {![$config @auth-token set?]} {
	$config @auth-token undefined!
    }

    $thetoken @token set $tokenstr

    display "Updating token \[[$thetoken @label]\] ... " false
    $thetoken @token set $tokenstr
    $thetoken commit
    display [color green OK]

    debug.cmd/serviceauth {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::serviceauth::create {config} {
    debug.cmd/serviceauth {}

    set thetoken [$config @label]
    if {![$config @label set?]} {
	$config @label undefined!
    }

    set tokenstr [$config @auth-token]
    if {![$config @auth-token set?]} {
	$config @auth-token undefined!
    }

    # @label      string
    # @provider   string
    # @auth-token string

    set atoken [v2 service_auth_token new]

    display "Creating new service auth token \[[$config @label]\] ... " false

    $atoken @label    set $thetoken
    $atoken @provider set [$config @provider]
    $atoken @token    set $tokenstr

    $atoken commit
    display [color green OK]

    debug.cmd/serviceauth {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::serviceauth::delete {config} {
    debug.cmd/serviceauth {}

    # V2 only.
    # client v2 = @label is entity instance

    set atoken [$config @label]

    display "Deleting token \[[$atoken @label]\] ... " false
    $atoken delete
    $atoken commit
    display [color green OK]

    debug.cmd/serviceauth {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::serviceauth::select-for {what p} {
    debug.cmd/serviceauth {}
    # generate callback. interactive menu of all known auth tokens.

    if {![cmdr interactive?]} {
	$p undefined!
    }

    # Get possibilities
    set tokens [v2 service_auth_token list]
    if {![llength $tokens]} {
	err {No tokens defined.}
    }

    # Generate labels for the interaction and keep mapping to
    # originating object.
    foreach s $tokens {
	set label [$s @label]
	dict set map $label $s
	lappend choices $label
    }

    # Talk with the user.
    set choice [term ask/menu "" \
		    "Which token to $what: " \
		    [lsort -dict $choices]]

    # Map the chosen label back to the service in question.
    set atoken [dict get $map $choice]

    debug.cmd/serviceauth {= $atoken}
    return $atoken

}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::serviceauth 0
return
