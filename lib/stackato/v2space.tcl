# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Space entity definition

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::v2::base

# # ## ### ##### ######## ############# #####################

debug level  v2/space
debug prefix v2/space {[debug caller] | }

# # ## ### ##### ######## ############# #####################

stackato v2 register space
oo::class create ::stackato::v2::space {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	debug.v2/space {}

	my Attribute name         string		 
	my Attribute organization &organization

	# Stackato v3.2 attribute
	my Attribute is_default       boolean

	my Many developers user
	my Many managers   user
	my Many auditors   user
	my Many apps
	my Many domains
	my Many service_instances
	my Many app_events

	my Summary \
	    services [mymethod S.services]

	# TODO scoped_to_organization

	next $url

	debug.v2/space {/done}
    }

    method full-name {} {
	debug.v2/space {}
	return [my @organization @name]::[my @name]
    }

    method usage {} {
	debug.v2/space {}
	return [[authenticated] usage-of [my url]]
    }

    # Overriden, to allow nice display on debugging.
    method summary {} {
	set json [next]
	debug.v2/space {[jmap v2-apps-summary $json]}
	return $json
    }

    method S.services {x} {
	debug.v2/space {}
	# The service instances in the space.

	# Note that the summary does not link apps and services.
	# If we need that the system will have to invoke regular REST
	# calls to get the connectivity.

	# This is a semi-replica of the code in the v2/base
	# 'summarize' method handling the 'many' relations of an
	# entity, if any.

	foreach item $x {
	    set uuid [dict get $item guid]
	    set obj [deref-type service_instance $uuid]
	    $obj summarize [list $item space]
	}
	return
    }

    # # ## ### ##### ######## #############
    # SearchableOn name|organization|developer|app -- In essence class-level forwards.

    classmethod list-by-name  {name {depth 0}} { my list-filter name $name $depth }
    classmethod first-by-name {name {depth 0}} { lindex [my list-by-name $name $depth] 0 }
    classmethod find-by-name  {name {depth 0}} { my find-by name $name $depth }

    classmethod list-by-organization  {organization {depth 0}} { my list-filter organization $organization $depth }
    classmethod first-by-organization {organization {depth 0}} { lindex [my list-by-organization $organization $depth] 0 }
    classmethod find-by-organization  {organization {depth 0}} { my find-by organization $organization $depth }

    classmethod list-by-developer  {developer {depth 0}} { my list-filter developer $developer $depth }
    classmethod first-by-developer {developer {depth 0}} { lindex [my list-by-developer $developer $depth] 0 }
    classmethod find-by-developer  {developer {depth 0}} { my find-by developer $developer $depth }

    classmethod list-by-app  {app {depth 0}} { my list-filter app $app $depth }
    classmethod first-by-app {app {depth 0}} { lindex [my list-by-app $app $depth] 0 }
    classmethod find-by-app  {app {depth 0}} { my find-by app $app $depth }

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::space 0
return
