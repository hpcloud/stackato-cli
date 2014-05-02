# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Servicebinding entity definition

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::v2::base

# # ## ### ##### ######## ############# #####################

debug level  v2/service_plan_visibility
debug prefix v2/service_plan_visibility {[debug caller] | }

# # ## ### ##### ######## ############# #####################

# no @name - stackato v2 register service_plan_visibility
oo::class create ::stackato::v2::service_plan_visibility {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	my Attribute organization &organization
	my Attribute service_plan &service_plan

	#my SearchableOn organization
	#my SearchableOn service_plan

	next $url
    }

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::service_plan_visibility 0
return
