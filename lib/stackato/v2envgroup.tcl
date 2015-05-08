# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Environment variable groups entity definition

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::v2::base

# # ## ### ##### ######## ############# #####################

debug level  v2/envgroups
debug prefix v2/envgroups {[debug caller] | }

# # ## ### ##### ######## ############# #####################

stackato v2 register config/environment_variable_group
oo::class create ::stackato::v2::environment_variable_group {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	debug.v2/envgroups {}

	my Attribute env "json<dict>"

	next $url
	debug.v2/envgroups {/done}
    }

    # Override superclass to use proper urls for entity creation and deletion.
    # NOTE: EV-groups do not support creation/deletion in target.
    # We have only 2 ev-groups: "running" and "staging".
    method create-url {} {
	debug.v2/envgroups {}
	return config/environment_variable_groups
    }

    method delete-url {} {
	debug.v2/envgroups {}
	return config/environment_variable_groups
    }

    # Overide superclass. Transform the direct retrieved json into a fake entity structure.
    # Note, we detect, accept and pass entity structures (coming from list retrieval).
    method = {json} {
	debug.v2/envgroups {}
	# Rework the incoming json into something resembling an actual entity.
	if {![dict exists $json metadata]} {
	    dict set e entity   env $json ;# attribute
	    dict set e metadata guid [my id]
	    dict set e metadata url  [my url]
	} else {
	    set e $json
	}

	# And now we actually can run the standard json integration
	debug.v2/envgroups {==> ($e)}
	next $e
    }
    export =

    # pseudo attribute
    forward @name my id
    export  @name

    # Override to push only the relevant part of the pseudo-entity.
    method commit {} {
	set json [my @env]
	[authenticated] change-by-url [my url] $json
	return
    }

    # # ## ### ##### ######## #############
    # SearchableOn name|owning_organization|space -- In essence class-level forwards.

    # Override list hook to convert incoming json into proper standard list form, with entities.
    # Note, target currently does not support listing of available groups.
    classmethod list-transform {json} {
	debug.v2/envgroups {}
	# Wrap the json array into a standard list setup.

	dict set r total_results [llength $json]
	dict set r total_pages   1
	dict set r prev_url      null
	dict set r next_url      null

	# Convert the elements directly into regular entities too.
	foreach j $json {
	    dict set e entity   env $j
	    dict set e metadata guid ?
	    dict set e metadata url  ?
	    dict lappend r resources $e
	    unset e
	}

	debug.v2/envgroups {==> ($r)}
	return $r
    }

    # Override superclass to use proper url for feature list
    classmethod list {{depth 0} args} {
	# args = config
	debug.v2/envgroups {}

	set client [stackato::mgr client authenticated]
	if {$depth > 0} {
	    lappend args depth $depth
	}
	stackato::v2 deref* [$client list-of [self] config/environment_variable_groups $args]
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
package provide stackato::v2::environment_variable_group 0
return
