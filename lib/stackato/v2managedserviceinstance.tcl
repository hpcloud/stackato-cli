# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Service instance entity definition

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::v2::base
package require stackato::v2::service_instance

# # ## ### ##### ######## ############# #####################

debug level  v2/managed_service_instance
debug prefix v2/managed_service_instance {[debug caller] | }

# # ## ### ##### ######## ############# #####################

stackato v2 register managed_service_instance
oo::class create ::stackato::v2::managed_service_instance {
    superclass ::stackato::v2::service_instance
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	# Extend base class.

	my Attribute dashboard_url string
	my Attribute credentials   dict
	my Attribute service_plan  &service_plan
	my Attribute gateway_data  dict

	next $url
    }

    # ATTENTION :: HACK :: MSI masquerade as SI, and go thorugh the SI endpoints still.
    method typeof {} {
	return service_instance
    }

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::managed_service_instance 0
return
