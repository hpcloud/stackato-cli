# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Service_Plan entity definition

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::v2::base

# # ## ### ##### ######## ############# #####################

debug level  v2/service_plan
debug prefix v2/service_plan {[debug caller] | }

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::v2::service_plan {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	debug.v2/service_plan {}

	my Attribute name        string
	my Attribute description string
	my Attribute extra       string
	my Attribute service     &service

	my Many service_instances

	my SearchableOn service
	my SearchableOn service_instance

	next $url
    }

    method name {} {
	debug.v2/service_plan {}
	return [my @name].[[my @service] @label]
    }

    method manifest-info {} {
	debug.v2/service_plan {}

	set service [my @service]

	dict set info plan     [my @name]
	dict set info label    [$service @label]
	dict set info provider [$service @provider]
	dict set info version  [$service @version]

	debug.v2/service_plan {==> ($info)}
	return $info
    }

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::service_plan 0
return
