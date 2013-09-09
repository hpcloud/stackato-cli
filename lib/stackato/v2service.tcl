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

oo::class create ::stackato::v2::service {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	my Attribute label        string
	my Attribute provider     string
	my Attribute url          url    ; # TODO validator
	my Attribute description  string
	my Attribute version      string
	my Attribute info_url     url    ; # TODO validator
	my Attribute acls         dict    default {} ; # nil
	my Attribute timeout      integer default {} ; # nil
	my Attribute active       boolean default off
	my Attribute extra        string

	# acls - dict - restricted set of keys
	#   users, wildcards.
	#     each maps to (list of string)

	my Many service_plans

	my SearchableOn service_plan

	next $url
    }

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::service 0
return
