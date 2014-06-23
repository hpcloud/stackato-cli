## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - App Version Index
## Dependency: config @client, @application
## CFv2 specific, Stackato 3.4 specific.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate
package require stackato::log
package require stackato::mgr::client;# pulls v2 also
package require stackato::mgr::manifest
package require stackato::validate::common

debug level  validate/appversion
debug prefix validate/appversion {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export appversion
    namespace ensemble create
}

namespace eval ::stackato::validate::appversion {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-unknown-thing
    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::manifest
    namespace import ::stackato::v2
    namespace import ::stackato::validate::common::refresh-client
}

proc ::stackato::validate::appversion::default {p} {
    debug.validate/appversion {}
    return {}
}
proc ::stackato::validate::appversion::release  {p x} { return }
proc ::stackato::validate::appversion::complete {p x} {
    refresh-client $p

    manifest config= $p _
    manifest user_1app_do theapp {
	if {![$theapp @app_versions defined?]} {
	    err "The chosen target does not support application versioning"
	}

	set versions [$theapp @app_versions]
    }

    set candidates [struct::list map \
			$versions [lambda v {
			    return v[$v @version_count]
			}]]
    complete-enum $candidates 0 $x
}

proc ::stackato::validate::appversion::validate {p x} {
    debug.validate/appversion {}
    refresh-client $p

    # v2 -- query application entity for its appversions
    manifest config= $p _
    manifest user_1app_do theapp {
	set versions [$theapp @app_versions]
    }

    set map {}
    foreach v $versions {
	dict set map v[$v @version_count] $v
    }

    if {[dict exists $map $x]} {
	# Found, good. Translate into the object.
	set x [dict get $map $x]
	debug.validate/appversion {OK/canon = $x}
	return $x
    }
    debug.validate/appversion {FAIL}
    fail-unknown-thing $p APPVERSION "appversion index" $x " for application '[$theapp @name]'"
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::appversion 0
