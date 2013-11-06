# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## user-provided Serviceinstance entity definition

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::v2::base

# # ## ### ##### ######## ############# #####################

debug level  v2/user_provided_service_instance
debug prefix v2/user_provided_service_instance {[debug caller] | }

# # ## ### ##### ######## ############# #####################

stackato v2 register user_provided_service_instance
oo::class create ::stackato::v2::user_provided_service_instance {
    superclass ::stackato::v2::service_instance
    #superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	# Extend base class.

	my Attribute credentials   dict

	# Note how this class of service-instances does not have a
	# plan associated with them.
	next $url
    }

    # ATTENTION :: HACK :: Partial masquerade as SI (for type-checks)
    method typeof {} {
	return service_instance
    }
    # And undo the masquerade for the actual operations, using the UPSI endpoints.
    method create-url {} {
	return user_provided_service_instances
    }
    method delete-url {} {
	return user_provided_service_instances
    }

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::user_provided_service_instance 0
return
