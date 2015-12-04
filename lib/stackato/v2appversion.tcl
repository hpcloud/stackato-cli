# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## App_Version entity definition

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::v2::base

# # ## ### ##### ######## ############# #####################

debug level  v2/app_version
debug prefix v2/app_version {[debug caller] | }

# # ## ### ##### ######## ############# #####################

# no @name - stackato v2 register app_version
oo::class create ::stackato::v2::app_version {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	my Attribute app              &app
	my Attribute description      string
	my Attribute instances        integer
	my Attribute memory           integer
	my Attribute version_count    integer

	next $url
    }

    method name {} {
	debug.v2/app_version {}
	return v[my @version_count]
    }

    method activate {codeonly} {
	debug.v2/app_version {}
	set payload  [dict create code_only $codeonly]
	set payload  [jmap map {dict {code_only bool}} $payload]
	set endpoint [my url]/rollback
	[authenticated] http_post $endpoint $payload application/json
    }

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::app_version 0
return
