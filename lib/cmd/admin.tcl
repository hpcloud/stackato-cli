# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations.
## Administrative commands.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require base64
package require dictutil
package require fileutil
package require lambda
package require cmdr::color
package require stackato::jmap
package require stackato::log
package require stackato::mgr::client
package require stackato::mgr::ctarget
package require struct::list
package require table

namespace eval ::stackato::cmd {
    namespace export admin
    namespace ensemble create
}
namespace eval ::stackato::cmd::admin {
    namespace export report grant revoke list \
	default-report grant-core
    namespace ensemble create

    namespace import ::cmdr::color
    namespace import ::stackato::jmap
    namespace import ::stackato::log::display
    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::client
    namespace import ::stackato::mgr::ctarget
    namespace import ::stackato::v2
}

debug level  cmd/admin
debug prefix cmd/admin {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Command implementations.

proc ::stackato::cmd::admin::report {config} {
    debug.cmd/admin {}

    set destination [$config @destination]
    set client      [$config @client]

    display "Generating report $destination ..."

    set thereport [$client report]

    debug.cmd/admin {size: [string length $thereport]}

    fileutil::writeFile -translation binary \
	$destination $thereport
	

    display [color good OK]
    return
}

proc ::stackato::cmd::admin::default-report {p} {
    # generate callback.
    debug.cmd/admin {}

    set target [ctarget get]
    regsub {^[^/]*//}  $target {} target
    append target -report.tgz

    debug.cmd/admin {= $target}
    return $target
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::admin::grant {config} {
    debug.cmd/admin {}

    set email  [$config @email]
    set client [$config @client]

    grant-core $client $email
    return
}

proc ::stackato::cmd::admin::grant-core {client email} {
    debug.cmd/admin {}
    if {[$client isv2]} {
	GrantV2 $client $email
    } else {
	GrantV1 $client $email
    }
    return
}

proc ::stackato::cmd::admin::GrantV1 {client email} {
    debug.cmd/admin {}

    set users [struct::list map [$client users] [lambda x {
	dict getit $x email
    }]]

    if {$email ni $users} {
	err "Unable to grant administrator privileges to unknown user \[$email\]"
    }

    set admins [dict get' [$client cc_config_get ] admins {}]

    if {$email ni $admins} {
	display "Granting administrator privileges to \[$email\] ... " false
	lappend admins $email
	$client cc_config_set [dict create admins $admins]
	display [color good OK]
    } else {
	display "User \[$email\] already has administrator privileges"
    }

    return
}

proc ::stackato::cmd::admin::GrantV2 {client theuser} {
    debug.cmd/admin {}

    set email [$theuser email]
    if {[$theuser @admin]} {
	display "User \[$email\] already has administrator privileges"
    } else {
	display "Granting administrator privileges to \[$email\] ... " false

	$theuser admin! yes
    }
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::admin::revoke {config} {
    debug.cmd/admin {}

    set email  [$config @email]
    set client [$config @client]

    if {[$client isv2]} {
	RevokeV2 $client $email
    } else {
	RevokeV1 $client $email
    }
    return
}

proc ::stackato::cmd::admin::RevokeV1 {client email} {
    debug.cmd/admin {}

    set users [struct::list map [$client users] [lambda x {
	dict getit $x email
    }]]

    if {$email ni $users} {
	err "Unable to revoke administrator privileges from unknown user \[$email\]"
    }

    set admins [dict get' [$client cc_config_get] admins {}]

    if {[set pos [lsearch -exact $admins $email]] >= 0} {
	display "Revoking administrator privileges from \[$email\] ... " false
	set admins [lreplace $admins $pos $pos]
	$client cc_config_set [dict create admins $admins]
	display [color good OK]
    } else {
	display "User \[$email\] is already a regular user"
    }

    return
}

proc ::stackato::cmd::admin::RevokeV2 {client theuser} {
    debug.cmd/admin {}

    set email [$theuser email]
    if {![$theuser @admin]} {
	display "User \[$email\] is already a regular user"
    } else {
	if {$email eq [$client current_user_mail]} {
	    err "Forbidden to revoke your own administrator privileges"
	}

	display "Revoking administrator privileges from \[$email\] ... " false

	$theuser admin! no
    }
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::admin::list {config} {
    debug.cmd/admin {}
    set client [$config @client]
    if {[$client isv2]} {
	set admins [ListV2 $config]
    } else {
	set admins [ListV1 $config $client]
    }

    set admins [lsort -dict $admins]

    if {[$config @json]} {
	display [jmap map array $admins]
	return
    }

    [table::do t {Email} {
	foreach u $admins { $t add $u }
    }] show display
    return
}

proc ::stackato::cmd::admin::ListV1 {config client} {
    debug.cmd/admin {}
    return [dict get' [$client cc_config_get] admins {}]
}

proc ::stackato::cmd::admin::ListV2 {config} {
    debug.cmd/admin {}
    set admins {}
    foreach theuser [v2 user list] {
	if {![$theuser @admin]} continue
	lappend admins [$theuser email]
    }
    return $admins
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::admin 0
