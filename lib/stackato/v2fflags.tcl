# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Feature_Flags entity definition

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::v2::base

# # ## ### ##### ######## ############# #####################

debug level  v2/feature_flags
debug prefix v2/feature_flags {[debug caller] | }

# # ## ### ##### ######## ############# #####################

stackato v2 register feature_flag
oo::class create ::stackato::v2::feature_flag {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	debug.v2/feature_flags {}

	my Attribute name           !string
	my Attribute enabled        boolean
	my Attribute overridden     boolean
	my Attribute default_value  boolean
	my Attribute error_message  string
	#my Attribute url            string

	next $url
	debug.v2/feature_flags {/done}
    }

    # Override superclass to use proper urls for entity creation and deletion.
    # NOTE: Flags do not support creation/deletion in target.
    method create-url {} {
	return config/feature_flags
    }

    method delete-url {} {
	return config/feature_flags
    }


    # Overide superclass. Transform direct retrieved json to entity structure.
    # Note, accept and pass entity structures (coming from list retrieval).
    method = {json} {
	# Rework the incoming json into something resembling an actual entity.
	if {![dict exists $json metadata]} {
	    dict set e entity $json
	    dict set e metadata guid [dict get $json name]
	    dict set e metadata url  [dict get $json url]
	    dict unset e entity url
	} else {
	    set e $json
	}

	# And now we actully can run the standard json integration
	next $e
    }
    export =

    # # ## ### ##### ######## #############
    # SearchableOn name|owning_organization|space -- In essence class-level forwards.

    # Override list hook to convert incoming json into proper standard list form, with entities.
    classmethod list-transform {json} {
	debug.v2/feature_flags {}
	# Wrap the json array into a standard list setup.

	dict set r total_results [llength $json]
	dict set r total_pages   1
	dict set r prev_url      null
	dict set r next_url      null

	# Convert the elements directly into regular entities too.
	foreach j $json {
	    dict set e entity $j
	    dict set e metadata guid [dict get $j name]
	    dict set e metadata url  [dict get $j url]
	    dict unset e entity url
	    dict lappend r resources $e
	    unset e
	}

	debug.v2/feature_flags {==> ($r)}
	return $r
    }

    # Override superclass to use proper url for feature list
    classmethod list {{depth 0} args} {
	# args = config
	debug.v2/feature_flags {}

	set client [stackato::mgr client authenticated]
	if {$depth > 0} {
	    lappend args depth $depth
	}
	stackato::v2 deref* [$client list-of [self] config/feature_flags $args]
    }

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
package provide stackato::v2::feature_flags 0
return
