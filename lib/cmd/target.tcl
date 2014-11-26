# -*- tcl -*-
# # ## ### ##### ######## ############# #####################
# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require table
package require url
package require cmdr::ask
package require cmdr::color
package require stackato::client
package require stackato::jmap
package require stackato::log
package require stackato::client
package require stackato::mgr::client
package require stackato::mgr::context
package require stackato::mgr::corg
package require stackato::mgr::cspace
package require stackato::mgr::ctarget
package require stackato::mgr::tadjunct
package require stackato::mgr::exit
package require stackato::mgr::targets
package require stackato::validate::orgname
package require stackato::validate::spacename

debug level  cmd/target
debug prefix cmd/target {[debug caller] | }

namespace eval ::stackato::cmd {
    namespace export target
    namespace ensemble create
}
namespace eval ::stackato::cmd::target {
    namespace export list getorset show-token
    namespace ensemble create

    namespace import ::cmdr::ask
    namespace import ::cmdr::color
    namespace import ::stackato::jmap
    namespace import ::stackato::log::err
    namespace import ::stackato::log::say
    namespace import ::stackato::log::display
    namespace import ::stackato::mgr::client
    namespace import ::stackato::mgr::context
    namespace import ::stackato::mgr::corg
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::mgr::ctarget
    namespace import ::stackato::mgr::exit
    namespace import ::stackato::mgr::tadjunct
    namespace import ::stackato::mgr::targets
    namespace import ::stackato::validate::orgname
    namespace import ::stackato::validate::spacename
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::target::show-token {config} {
    debug.cmd/target {}

    set ct [ctarget get]
    set td [targets known]

    if {![dict exists $td $ct]} {
	err "Not logged into target $ct, no token known"
    }

    puts [dict get $td $ct]
    return
}


proc ::stackato::cmd::target::list {config} {
    # (cmdr::)config -- (--token-file), (--json)
    debug.cmd/target {}

    # Implied use of --token-file when present.
    set targets [targets known]

    debug.cmd/target {list targets = $targets}

    if {[$config @json]} {
	puts [jmap targets $targets]
	return
    }

    if {![llength $targets]} {
	say "None specified"
	return
    }

    set ct [ctarget get]

    table::do t {{} Target Authorization} {
	foreach {target token} $targets {
	    #set token [string length $token]
	    if {[string length $token] > 64} {
		set tl {}
		while {[string length $token] > 64} {
		    lappend tl [string range $token 0 63]
		    set token [string range $token 64 end]
		}
		if {$token ne {}} { lappend tl $token }

		set token [join $tl \n]
	    }
	    $t add \
		[expr {($ct ne {}) && ($ct eq $target) ? "x" : ""}] \
		$target \
		$token
	}
    }

    puts ""
    $t show puts
    return
}


proc ::stackato::cmd::target::getorset {config} {
    # (cmdr::)config -- (--json), (--allow-http), (url)
    debug.cmd/target {}

    if {[$config @url set?]} {
	Set $config
    } else {
	Show $config
    }

    debug.cmd/target {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::target::Set {config} {
    debug.cmd/target {set}

    set target [url canon [$config @url]]

    if {![$config @allow-http] &&
	[regexp {^http:} $target]} {
	err "Illegal use of $target.\nEither re-target to use https, or force acceptance via --allow-http"
    }

    # Note: Using a raw client here, not via manager. The
    # manager-returned client uses in-memory url and we have not
    # committed our argument to that yet.

    set client [client restlog [stackato::client new $target]]
    set emessage "Host is not valid: '$target'"
    set valid  [$client target_valid? newtarget emessage]
    # valid in
    # 0 - Invalid target
    # 1 - Target ok, save
    # 2 - Target redirects to 'newtarget'.

    switch -exact -- $valid {
	0 {
	    # Fail. Report.
	    puts [color bad $emessage]

	    if {![regexp {^https?://api\.} $target]} {
		set guess [GuessUrl $target]
		puts [color warning \
			  "Maybe try to target \[$guess\] instead."]
	    }

	    if {[$config @verbose] ||
		([cmdr interactive?] &&
		 [ask yn "Would you like to see the response returned by '[color name $target]' ? " no])} {
		ShowRawTargetResponse $client
	    }
	    exit fail
	}
	1 {
	    # Ok. Save.
	    ctarget set $target
	    ctarget save
	    say [color good "Successfully targeted to \[$target\]"]

	    if {[[client plain] isv2]} {
		Switch $config
		display [context format-large]
		client license-status $client 0
	    }

	    debug.cmd/target {skip set = [$config @skip-ssl-validation set?]}
	    if {[$config @skip-ssl-validation set?]} {
		# Make explicitly chosen skip setting sticky
		set value [$config @skip-ssl-validation]
		debug.cmd/target {skip value = $value}

		if {$value} {
		    tadjunct add $target skip-ssl-validation 1
		} else {
		    # Remove, same as hardwired default.
		    tadjunct remove $target skip-ssl-validation
		}
		# See cmdr global option --skip-ssl-validation for
		# where this information is queried.
	    }
	}
	2 {
	    # Redirection. Recurse to new target.
	    puts [color note "Host redirects to: '$newtarget'"]
	    $config @url set $newtarget
	    Set $config
	}
    }
    return
}

proc ::stackato::cmd::target::Show {config} {
    debug.cmd/target {}

    set target [ctarget get]

    debug.cmd/target {target = $target}

    try {
	set client [client plain]
    } trap {STACKATO CLIENT BADTARGET} {e o} {
	if {![$config @json]} {
	    set e [string map [::list "'$target' " {}] $e]
	    display "\n\[$target\] ([color bad "Note: $e"])"
	    return
	}
	set client {}
    }

    if {[$config @json]} {
	dict set D target       $target
	dict set D organization {}
	dict set D space        {}

	set s [cspace get]
	if {$s ne {}} {
	    dict set D space id   [$s id]
	    set sname [context get-name $s serror]
	    if {$sname ne {}} {
		dict set D space name $sname
	    }
	    if {$serror ne {}} {
		dict set D space error $serror
	    }
	} else {
	    dict set D space error {not defined}
	}

	set o [corg get]
	if {$o ne {}} {
	    dict set D organization id   [$o id]
	    set oname [context get-name $o oerror]
	    if {$oname ne {}} {
		dict set D organization name $oname
	    }
	    if {$oerror ne {}} {
		dict set D organization error $oerror
	    }
	} else {
	    dict set D organization error {not defined}
	}

	if {($client ne {}) && ![$client isv2]} {
	    dict unset D space
	    dict unset D organization
	}

	puts [jmap target $D]
	return
    }

    if {[$client isv2]} {
	Switch $config
	display [context format-large]
	client license $client 0
    } else {
	display "\n\[$target\]"
    }

    debug.cmd/target {/done}
    return
}

proc ::stackato::cmd::target::Switch {config} {
    debug.cmd/target {}

    # Check for org/space settings.
    # 1. None defined => do nothing
    # 2. Space defined, but no org   => interactively set org.
    # 3. Org   defined, but no space => interactively set space.
    # 4. Both defined => set both, properly validated.

    debug.cmd/target {context org?[$config @organization set?] / space?[$config @space set?]}

    if {![$config @organization set?] && ![$config @space set?]} {
	# Neither org nor space specified. Do nothing.
	debug.cmd/target {nothing}
	return
    }

    # Make a proper client available to the following commands.
    # Must be in the cmd configuration.
    # Implied check for v2 API
    debug.cmd/target {auth client}

    $config @client set [client authenticated]

    debug.cmd/target {do}
    switch -exact -- [$config @organization set?]/[$config @space set?] {
	no/yes - 0/1 {
	    debug.cmd/target {auto-select org, set space}

	    # Space defined, but no org. Auto-select org, then set space.
	    corg get-auto [$config @organization self]

	    set space [spacename validate [$config @space self] [$config @space]]

	    display "Switching to space [$space @name] ... " false
	    cspace set $space
	    cspace save
	    display [color good OK]
	}
	yes/no - 1/0 {
	    debug.cmd/target {set org, auto-select space}

	    # Org defined, but no space. Auto-select space.
	    set org [orgname validate [$config @organization self] [$config @organization]]

	    context 2org $config $org
	}
	yes/yes - 1/1 {
	    # Both defined. Set both, properly validated.
	    debug.cmd/target {set org, set space}

	    set org [orgname validate [$config @organization self] [$config @organization]]

	    display "Switching to organization [$org @name] ... " false
	    corg set $org
	    corg save
	    display [color good OK]

	    set space [spacename validate [$config @space self] [$config @space]]

	    display "Switching to space [$space @name] ... " false
	    cspace set $space
	    cspace save
	    display [color good OK]
	}
    }

    debug.cmd/target {/done}
    return
}


proc ::stackato::cmd::target::GuessUrl {url} {
    debug.cmd/target {}
    if {![regexp {^https?://} $url]} {
	return https://api.$url
    }
    regsub {^(https?://)} $url {\1api.} newurl
    return $newurl
}

proc ::stackato::cmd::target::ShowRawTargetResponse {client} {
    debug.cmd/target {}

    # Have to capture errors, like target_valid? does.
    try {
	set raw [$client raw_info]
    } on error e {
	set raw $e
    }
    puts "\n<<<\n$raw\n>>>\n"
    return
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::target 0

