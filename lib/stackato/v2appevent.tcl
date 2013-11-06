# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## App_Event entity definition

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::v2::base

# # ## ### ##### ######## ############# #####################

debug level  v2/app_event
debug prefix v2/app_event {[debug caller] | }

# # ## ### ##### ######## ############# #####################

# no @name - stackato v2 register app_event
oo::class create ::stackato::v2::app_event {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	my Attribute app              &app
	my Attribute timestamp        string
	my Attribute instance_guid    integer
	my Attribute instance_index   integer
	my Attribute exit_status      integer
	my Attribute exit_description string default {}

	next $url
    }

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::app_event 0
return
