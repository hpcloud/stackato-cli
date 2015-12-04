# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Space_Quota_Definition entity definition

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::v2::base

# # ## ### ##### ######## ############# #####################

debug level  v2/space_quota_definition
debug prefix v2/space_quota_definition {[debug caller] | }

# # ## ### ##### ######## ############# #####################

stackato v2 register space_quota_definition
oo::class create ::stackato::v2::space_quota_definition {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	my Attribute name                       !string
	my Attribute non_basic_services_allowed boolean label {Paid Services Allowed      }
	my Attribute total_services             integer label {Max Number Of Services     }
	my Attribute total_routes               integer label {Max Number of Routes       }
	my Attribute memory_limit               integer label {Memory Limit               }
	my Attribute instance_memory_limit      integer label {Instance Memory Limit      }

	my Attribute organization &organization         label {Owning Organization        }
	#            ^owner of the space quota
	my Many      spaces

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
package provide stackato::v2::space_quota_definition 0
return
