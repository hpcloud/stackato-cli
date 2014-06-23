# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Route entity definition

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::v2::base

# # ## ### ##### ######## ############# #####################

debug level  v2/route
debug prefix v2/route {[debug caller] | }

# # ## ### ##### ######## ############# #####################

stackato v2 register route
oo::class create ::stackato::v2::route {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	my Attribute host   !string ;# TODO: proper host name validator required
	my Attribute domain &domain ;# TODO: validates_presence_of
	my Attribute space  &space  ;# TODO: validates_presence_of

	my Many apps

	next $url
    }

    method name {} {
	return [my @host].[my @domain @name]
    }

    # Pseudo attribute 'name' (guid support).
    forward @name my @host
    export  @name

    # # ## ### ##### ######## #############

    classmethod list-by-host  {host {depth 0} {config {}}} { my list-filter host $host $depth $config }
    classmethod first-by-host {host {depth 0} {config {}}} { lindex [my list-by-host $host $depth $config] 0 }
    classmethod find-by-host  {host {depth 0} {config {}}} { my find-by host $host $depth $config }

    classmethod list-by-domain  {domain {depth 0} {config {}}} { my list-filter domain $domain $depth $config }
    classmethod first-by-domain {domain {depth 0} {config {}}} { lindex [my list-by-domain $domain $depth $config] 0 }
    classmethod find-by-domain  {domain {depth 0} {config {}}} { my find-by domain $domain $depth $config }

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::route 0
return
