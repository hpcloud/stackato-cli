# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Security_Group entity definition

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::v2::base

# # ## ### ##### ######## ############# #####################

debug level  v2/security_group
debug prefix v2/security_group {[debug caller] | }

# # ## ### ##### ######## ############# #####################

stackato v2 register security_group
oo::class create ::stackato::v2::security_group {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	debug.v2/security_group {}

	my Attribute name  !string	  
	my Attribute rules "json<array dict>"
	# The rules are a list of dicts. Dict keys are
	#   protocol    - string ("tcp", "udp", "icmp")
	#   destination - string (ip-address/mask)
	#   type        - numeric
	#   code        - numeric
	#   ports       - string (sets, ranges: "a-b", "a,b")

	my Attribute running_default boolean ;# Readonly attributes. Indicate if the group
	my Attribute staging_default boolean ;# is a default for staging and/or running

	my Many spaces

	my SearchableOn space

	next $url
	debug.v2/security_group {/done}
    }

    # TODO: It is possible to filter the @spaces by name, when retrieving them.

    # Special methods to (un)set the group as default for running|staging.
    # These go through new CC APIs instead of triggering on writing to the attributes.

    method run-default {flag} {
	set c [authenticated]
	if {$flag} {
	    $c change-by-url /v2/config/running_security_groups/[my id] {}
	} else {
	    $c delete-by-url /v2/config/running_security_groups/[my id]
	}
	return
    }

    method stager-default {flag} {
	set c [authenticated]
	if {$flag} {
	    $c change-by-url /v2/config/staging_security_groups/[my id] {}
	} else {
	    $c delete-by-url /v2/config/staging_security_groups/[my id]
	}
	return
    }

    # Special class-methods to get the list of s-groups set as default for
    # running|staging.

    classmethod run-defaults {} {
	stackato::v2 deref* [[stackato::mgr client authenticated] list-of [self] config/running_security_groups]
    }

    classmethod stager-defaults {} {
	stackato::v2 deref* [[stackato::mgr client authenticated] list-of [self] config/staging_security_groups]
    }

    # # ## ### ##### ######## #############
    # SearchableOn name -- In essence class-level forwards.

    classmethod list-by-name  {name {depth 0}} { my list-filter name $name $depth }
    classmethod first-by-name {name {depth 0}} { lindex [my list-by-name $name $depth] 0 }
    classmethod find-by-name  {name {depth 0}} { my find-by name $name $depth }

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::security_group 0
return
