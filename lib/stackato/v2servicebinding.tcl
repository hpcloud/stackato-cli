# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

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

# no @name - stackato v2 register service_binding
oo::class create ::stackato::v2::service_binding {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	my Attribute app              &app
	my Attribute service_instance &service_instance

	# Attributes apparently copied from the referenced service-instance.
	my Attribute credentials     dict   ; # copied from service-instance
	#my Attribute gateway_data    dict   ; # copied from service-instance
	#my Attribute gateway_name    string ; # copied from service-instance
	#my Attribute binding_options dict   ; # copied from service-instance

	my SearchableOn app
	my SearchableOn service_instance

	next $url
    }

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::service_binding 0
return
