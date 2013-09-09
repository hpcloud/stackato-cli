# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Quota_Definition entity definition

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::v2::base

# # ## ### ##### ######## ############# #####################

debug level  v2/quota_definition
debug prefix v2/quota_definition {[debug caller] | }

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::v2::quota_definition {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	my Attribute name                       string
	my Attribute non_basic_services_allowed boolean
	my Attribute total_services             integer
	my Attribute memory_limit               integer

	my SearchableOn name

	next $url
    }

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::quota_definition 0
return
