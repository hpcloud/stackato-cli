# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Domain entity definition

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::v2::base

# # ## ### ##### ######## ############# #####################

debug level  v2/domain
debug prefix v2/domain {[debug caller] | }

# # ## ### ##### ######## ############# #####################

stackato v2 register domain
oo::class create ::stackato::v2::domain {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	debug.v2/domain {}

	my Attribute name                !string
	my Attribute wildcard            boolean
	my Attribute owning_organization &organization default {}

	my Many spaces

	next $url
	debug.v2/domain {/done}
    }

    # # ## ### ##### ######## #############
    # SearchableOn name|owning_organization|space -- In essence class-level forwards.

    classmethod list-by-name  {name {depth 0}} { my list-filter name $name $depth }
    classmethod first-by-name {name {depth 0}} { lindex [my list-by-name $name $depth] 0 }
    classmethod find-by-name  {name {depth 0}} { my find-by name $name $depth }

    classmethod list-by-owning_organization  {owning_organization {depth 0}} { my list-filter owning_organization $owning_organization $depth }
    classmethod first-by-owning_organization {owning_organization {depth 0}} { lindex [my list-by-owning_organization $owning_organization $depth] 0 }
    classmethod find-by-owning_organization  {owning_organization {depth 0}} { my find-by owning_organization $owning_organization $depth }

    classmethod list-by-space  {space {depth 0}} { my list-filter space $space $depth }
    classmethod first-by-space {space {depth 0}} { lindex [my list-by-space $space $depth] 0 }
    classmethod find-by-space  {space {depth 0}} { my find-by space $space $depth }

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::domain 0
return
