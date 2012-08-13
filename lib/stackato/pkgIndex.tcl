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
