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

stackato v2 register quota_definition
oo::class create ::stackato::v2::quota_definition {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	my Attribute name                       string
	my Attribute non_basic_services_allowed boolean label {Paid Services Allowed      }
	my Attribute total_services             integer label {Max Number Of Services     }
	my Attribute memory_limit               integer label {Memory Limit               }
	my Attribute trial_db_allowed           boolean label {Trial Database Allowed     }
	my Attribute allow_sudo                 boolean label {Allow use of 'sudo' by Apps}

	# v3.2+
	my Attribute total_routes               integer label {Max Number of Routes       }

	#my SearchableOn name

	next $url
    }

    # # ## ### ##### ######## #############
    # SearchableOn name -- In essence class-level forwards.

    classmethod list-by-name  {name {depth 0}} { my list-filter name $name $depth }
    classmethod first-by-name {name {depth 0}} { lindex [my list-by-name $name $depth] 0 }
    classmethod find-by-name  {name {depth 0}} { my find-by name $name $depth }

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::quota_definition 0
return
