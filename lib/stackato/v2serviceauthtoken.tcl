# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Serviceauthtoken entity definition

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::v2::base

# # ## ### ##### ######## ############# #####################

debug level  v2/service_auth_token
debug prefix v2/service_auth_token {[debug caller] | }

# # ## ### ##### ######## ############# #####################

stackato v2 register service_auth_token
oo::class create ::stackato::v2::service_auth_token {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	my Attribute label    string
	my Attribute provider string
	my Attribute token    string

	next $url
    }

    # Pseudo attribute name (guid command support).
    forward @name my @label
    export  @name

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::service_auth_token 0
return
