# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations. Management of envirnment variable groups.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::color
package require stackato::jmap
package require stackato::log
package require stackato::mgr::context
package require stackato::v2
package require table
package require try

debug level  cmd/envgroups
debug prefix cmd/envgroups {[debug caller] | }

namespace eval ::stackato::cmd {
    namespace export envgroups
    namespace ensemble create
}
namespace eval ::stackato::cmd::envgroups {
    namespace export show assign
    namespace ensemble create

    namespace import ::cmdr::color
    namespace import ::stackato::jmap
    namespace import ::stackato::log::display
    namespace import ::stackato::mgr::context
    namespace import ::stackato::v2
}

# # ## ### ##### ######## ############# #####################
# S3.6 commands

proc ::stackato::cmd::envgroups::show {config} {
    debug.cmd/envgroups {}

    if {![$config @json]} {
	display \n[context format-target]
    }

    set envg [$config @envg]
    # name, uuid

    set eg [v2 deref-type config/environment_variable_group $envg]
    # pseudo entity.

    if {[$config @json]} {
	display [$eg as-json]
	return
    }

    set theenv [$eg @env]

    try {
	set theenv [json::json2dict $theenv]
    } trap {JSON} {e o} {
	err "Bad json data from target: $e"
    }

    [table::do t {Name Value} {
	dict for {n v} [dict sort $theenv] {
	    $t add $n $v
	}
    }] show display
    return
}

proc ::stackato::cmd::envgroups::assign {config} {
    debug.cmd/envgroups {}

    display [context format-target]

    set envg [$config @envg]
    # name, uuid

    set eg [v2 deref-type config/environment_variable_group $envg]
    # pseudo entity.

    set theenv [$config @env]
    # list(pair)

    set denv {}
    foreach item [$config @env] {
	lassign $item k v
	dict set denv $k $v
    }
    # dict

    set jenv [jmap map dict $denv]
    # env settings as json.

    debug.cmd/envgroups { envg = $envg }
    debug.cmd/envgroups { eg   = $eg }
    debug.cmd/envgroups { env  = $theenv }
    debug.cmd/envgroups { env' = $denv }
    debug.cmd/envgroups { jenv = $jenv }

    $eg @env set $jenv

    display "Setting env group \"[color name [$eg @name]]\" ... " false
    $eg commit
    display [color good OK]
    return
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::envgroups 0

