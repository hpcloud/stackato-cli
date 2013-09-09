# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Stack entity definition

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::v2::base

# # ## ### ##### ######## ############# #####################

debug level  v2/stack
debug prefix v2/stack {[debug caller] | }

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::v2::stack {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	my Attribute name        string
	my Attribute description string

	next $url
    }

    # # ## ### ##### ######## #############
    # SearchableOn name|owning_organization|space -- In essence class-level forwards.

    classmethod list-by-name  {name {depth 0}} { my list-filter name $name $depth }
    classmethod first-by-name {name {depth 0}} { lindex [my list-by-name $name $depth] 0 }
    classmethod find-by-name  {name {depth 0}} { my find-by name $name $depth }

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::stack 0
return
