# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Serviceinstance entity definition

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::v2::base

# # ## ### ##### ######## ############# #####################

debug level  v2/service_instance
debug prefix v2/service_instance {[debug caller] | }

# # ## ### ##### ######## ############# #####################

stackato v2 register service_instance
oo::class create ::stackato::v2::service_instance {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    ## Replicate the v2::base class methods, apparently they are not
    ## inherited by sub classes of this class, i.e. over to steps in
    ## the chain. Need to be in the immediate superclass to be
    ## visible. This is very likely a bug in the definition of class
    ## method.
    classmethod list {{depth 0} args} {
	debug.v2/base {}
	set type   [namespace tail [self]]s
	set client [stackato::mgr client authenticated]
	if {$depth > 0} {
	    lappend args depth $depth
	}
	stackato::v2 deref* [$client list-of $type $args]
    }

    classmethod list-filter {key value {depth 0}} {
	debug.v2/base {}
	set type   [namespace tail [self]]s
	set client [stackato::mgr client authenticated]
	stackato::v2 deref* [$client filtered-of $type $key $value $depth]
    }

    classmethod find-by {key value {depth 0}} {
	debug.v2/base {}
	set matches [my list-filter $key $value $depth]
	switch -exact -- [llength $matches] {
	    0       { my NotFound  $key $value }
	    1       { return [lindex $matches 0] }
	    default { my Ambiguous $key $value }
	}
    }

    classmethod NotFound {key value} {
	set type [namespace tail [self]]
	return -code error \
	    -errorcode [list STACKATO CLIENT V2 [string toupper $type] [string toupper $key] NOTFOUND $value] \
	    "[string totitle $type] $key \"$value\" not found"
    }

    classmethod Ambiguous {key value} {
	set type [namespace tail [self]]
	return -code error \
	    -errorcode [list STACKATO CLIENT V2 [string toupper $type] [string toupper $key] AMIGUOUS $value] \
	    "Ambiguous $type $key \"$value\""
    }

    # # ## ### ##### ######## #############

    constructor {{url {}}} {
	my Attribute name          string
	my Attribute space         &space

	my Many service_bindings

	# These attributes went into the derived classes
	# (=> managed, user-provided).
	#my Attribute dashboard_url string
	#my Attribute service_plan  &service_plan
	#my Attribute credentials   dict
	#my Attribute type          string
	#my Attribute gateway_data  dict

	my SearchableOn name
	my SearchableOn space
	my SearchableOn service_plan
	my SearchableOn service_binding

	# TODO scoped_to_space

	next $url
    }

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::service_instance 0
return
