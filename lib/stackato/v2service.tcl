# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Service entity definition

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::v2::base

# # ## ### ##### ######## ############# #####################

debug level  v2/service
debug prefix v2/service {[debug caller] | }

# # ## ### ##### ######## ############# #####################

stackato v2 register service
oo::class create ::stackato::v2::service {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	my Attribute label        !string
	my Attribute provider     null|string
	my Attribute url          url    ; # TODO validator
	my Attribute description  string
	my Attribute version      null|string
	my Attribute info_url     url    ; # TODO validator
	my Attribute acls         dict    default {} ; # nil
	my Attribute timeout      integer default {} ; # nil
	my Attribute active       boolean default off
	my Attribute extra        string

	my Attribute service_broker &service_broker

	# acls - dict - restricted set of keys
	#   users, wildcards.
	#     each maps to (list of string)

	my Many service_plans

	my SearchableOn service_plan

	next $url
    }

    method purge! {} {
	my delete purge true
	my commit
    }

    forward @name my @label
    export  @name

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::service 0
return
