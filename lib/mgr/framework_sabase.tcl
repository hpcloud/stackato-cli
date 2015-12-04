# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

# -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Framework storage class. Derived from the base class, i.e.
##  ::stackato::mgr::framework::base
## Overides various query commands to provide special casing.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::mgr::framework::base

debug level  mgr/framework/sabase
debug prefix mgr/framework/sabase {[debug caller] | }

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::mgr::framework::sabase {
    superclass ::stackato::mgr::framework::base
    # # ## ### ##### ######## #############
    ## No separate constructor/destructor.

    # # ## ### ##### ######## #############
    ## API

    # overriding various base class methods.
    method require_url? {} {
	debug.mgr/framework/sabase {}
	return 0
    }
 
    # # ## ### ##### ######## #############
    ## State

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::framework::sabase 0
