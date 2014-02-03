# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## (DEA distribution) Zone entity, aka placement zone

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::v2::base

# # ## ### ##### ######## ############# #####################

debug level  v2/zone
debug prefix v2/zone {[debug caller] | }

# # ## ### ##### ######## ############# #####################

stackato v2 register zone
oo::class create ::stackato::v2::zone {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	debug.v2/zone {}

	my Attribute name string

	# special: array of string (but not true reference)
	my Attribute deas list-string

	next $url

	debug.v2/zone {/done}
    }

    # # ## ### ##### ######## #############
    # SearchableOn name|organization|developer|app -- In essence class-level forwards.

    classmethod list-by-name  {name {depth 0}} { my list-filter name $name $depth }
    classmethod first-by-name {name {depth 0}} { lindex [my list-by-name $name $depth] 0 }
    classmethod find-by-name  {name {depth 0}} { my find-by name $name $depth }

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::zone 0
return
