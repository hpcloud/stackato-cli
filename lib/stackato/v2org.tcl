# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Organization entity definition

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::v2::base

# # ## ### ##### ######## ############# #####################

debug level  v2/organization
debug prefix v2/organization {[debug caller] | }

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::v2::organization {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	debug.v2/organization {}

	my Attribute name             string	  
	my Attribute quota_definition &quota_definition
	my Attribute billing_enabled  boolean	  

	my Many spaces
	my Many domains
	my Many users
	my Many managers         user
	my Many billing_managers user
	my Many auditors         user

	my SearchableOn space
	my SearchableOn user
	my SearchableOn manager
	my SearchableOn billing_manager
	my SearchableOn auditor

	next $url
	debug.v2/organization {/done}
    }

    # TODO: It is possible to filter the @spaces by name, when retrieving them.

    # # ## ### ##### ######## #############
    # SearchableOn name -- In essence class-level forwards.

    classmethod list-by-name  {name {depth 0}} { my list-filter name $name $depth }
    classmethod first-by-name {name {depth 0}} { lindex [my list-by-name $name $depth] 0 }
    classmethod find-by-name  {name {depth 0}} { my find-by name $name $depth }

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::organization 0
return
