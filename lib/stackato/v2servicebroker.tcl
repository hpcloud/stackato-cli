# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Serviceauthtoken entity definition

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::v2::base

# # ## ### ##### ######## ############# #####################

debug level  v2/service_broker
debug prefix v2/service_broker {[debug caller] | }

# # ## ### ##### ######## ############# #####################

stackato v2 register service_broker
oo::class create ::stackato::v2::service_broker {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	my Attribute name       string
	my Attribute broker_url string
	my Attribute token      string

	next $url
    }

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::service_broker 0
return
