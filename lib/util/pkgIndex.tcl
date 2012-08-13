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

# The package below is a backward compatible implementation of
# try/catch/finally, for use by Tcl 8.5 only. On 8.6 it does nothing.
package ifneeded try 0 [list source [file join $dir try.tcl]]

# Utility wrapper around ::apply for easier writing.
package ifneeded lambda   0 [list source [file join $dir lambda.tcl]]

# Wrapper around struct::matrix for quicker table creation.
package ifneeded table    0 [list source [file join $dir table.tcl]]

# Dict extension, like get/with-default-for-missing
package ifneeded dictutil 0 [list source [file join $dir dictutil.tcl]]

# OO extension, like easy specification of methods as callbacks.
package ifneeded ooutil   0 [list source [file join $dir ooutil.tcl]]

# Save 'cd' (on error returns to old pwd).
# @todo Should be put in fileutil.
package ifneeded cd 0 [list source [file join $dir cd.tcl]]

# Exec wrapper, capture child pids, for killing on parent exit.
package ifneeded exec 0 [list source [file join $dir exec.tcl]]

# Common code doing variable substitutions
# @todo Should be put into textutil
package ifneeded varsub 0 [list source [file join $dir varsub.tcl]]
