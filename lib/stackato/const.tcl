# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5

namespace eval ::stackato::const {}

# # ## ### ##### ######## ############# #####################

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::const {
    variable  DEFAULT_TARGET       "http://api.stackato.local"
    variable  DEFAULT_LOCAL_TARGET "http://api.stackato.local"

    # General Paths
    variable  INFO_PATH            "/info"
    variable  GLOBAL_SERVICES_PATH "/info/services"
    variable  RESOURCES_PATH       "/resources"

    # Stackato specific APIs
    variable  STACKATO_PATH        "/stackato"

    # User specific paths
    variable  APPS_PATH            "/apps"
    variable  SERVICES_PATH        "/services"
    variable  USERS_PATH           "/users"
    variable  GROUPS_PATH          "/groups"
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::const 0
