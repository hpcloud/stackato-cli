# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Servicebinding entity definition

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::v2::base

# # ## ### ##### ######## ############# #####################

debug level  v2/service_binding
debug prefix v2/service_binding {[debug caller] | }

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::v2::service_binding {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	my Attribute app              &app
	my Attribute service_instance &service_instance

	my SearchableOn app
	my SearchableOn service_instance

	next $url
    }

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::service_binding 0
return
