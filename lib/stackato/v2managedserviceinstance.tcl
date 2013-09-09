# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Service instance entity definition

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::v2::base

# # ## ### ##### ######## ############# #####################

debug level  v2/managed_service_instance
debug prefix v2/managed_service_instance {[debug caller] | }

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::v2::managed_service_instance {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	my Attribute name          string
	my Attribute dashboard_url string
	my Attribute space         &space
	my Attribute service_plan  &service_plan

	my Many service_bindings

	my SearchableOn name
	my SearchableOn space
	my SearchableOn service_plan
	my SearchableOn service_binding

	# TODO scoped_to_space

	next $url
    }

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::managed_service_instance 0
return
