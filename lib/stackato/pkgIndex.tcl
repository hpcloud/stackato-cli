# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################
#checker -scope global exclude warnUndefinedVar
# var in question is 'dir'.
if {![package vsatisfies [package provide Tcl] 8.5]} {
    # PRAGMA: returnok
    return
}

# The version number of package "stackato::client::cli" (see sibling
# directory 'cli') is the release version number reported for
# stackato, the client app.  The internal STACKATO version number is
# coded as the version of package 'stackato::client', see below.

package ifneeded stackato::client 0.3.2 [list source [file join $dir client.tcl]]
package ifneeded stackato::const  0     [list source [file join $dir const.tcl]]

# Support for the cloudfoundry v2 API.
# - client doing the main REST calls.
# - entity classes operating through the client, via the base
# - base entity containing most of the logic
# - A global layer holding helper commands for the base.

package ifneeded stackato::v2::client                  0 [list source [file join $dir v2client.tcl]]
#------
package ifneeded stackato::v2::app                     0 [list source [file join $dir v2app.tcl]]
package ifneeded stackato::v2::app_event               0 [list source [file join $dir v2appevent.tcl]]
package ifneeded stackato::v2::buildpack               0 [list source [file join $dir v2buildpack.tcl]]
package ifneeded stackato::v2::domain                  0 [list source [file join $dir v2domain.tcl]]
package ifneeded stackato::v2::organization            0 [list source [file join $dir v2org.tcl]]
package ifneeded stackato::v2::quota_definition        0 [list source [file join $dir v2quota.tcl]]
package ifneeded stackato::v2::route                   0 [list source [file join $dir v2route.tcl]]
package ifneeded stackato::v2::service                 0 [list source [file join $dir v2service.tcl]]
package ifneeded stackato::v2::service_auth_token      0 [list source [file join $dir v2serviceauthtoken.tcl]]
package ifneeded stackato::v2::service_binding         0 [list source [file join $dir v2servicebinding.tcl]]
package ifneeded stackato::v2::service_broker          0 [list source [file join $dir v2servicebroker.tcl]]
package ifneeded stackato::v2::service_instance        0 [list source [file join $dir v2serviceinstance.tcl]]
package ifneeded stackato::v2::service_plan            0 [list source [file join $dir v2serviceplan.tcl]]
package ifneeded stackato::v2::service_plan_visibility 0 [list source [file join $dir v2serviceplanvisibility.tcl]]
package ifneeded stackato::v2::space                   0 [list source [file join $dir v2space.tcl]]
package ifneeded stackato::v2::stack                   0 [list source [file join $dir v2stack.tcl]]
package ifneeded stackato::v2::user                    0 [list source [file join $dir v2user.tcl]]
package ifneeded stackato::v2::zone                    0 [list source [file join $dir v2zone.tcl]]

package ifneeded stackato::v2::managed_service_instance       0 [list source [file join $dir v2managedserviceinstance.tcl]]
package ifneeded stackato::v2::user_provided_service_instance 0 [list source [file join $dir v2userprovidedserviceinstance.tcl]]
#------
package ifneeded stackato::v2::base               0 [list source [file join $dir v2base.tcl]]
package ifneeded stackato::v2                     0 [list source [file join $dir v2.tcl]]

