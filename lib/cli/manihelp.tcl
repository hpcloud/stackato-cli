# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::client::cli::command::Base
package require stackato::client::cli::manifest

debug level  cli/manifest/support
debug prefix cli/manifest/support {[::debug::snit::call] | }

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::client::cli::command::ManifestHelp {
    superclass ::stackato::client::cli::command::Base

    # # ## ### ##### ######## #############

    constructor {args} {
	Debug.cli/manifest/support {}
	next {*}$args

	manifest setup [self] \
	    [dict get' [my options] path [pwd]] \
	    [dict get' [my options] manifest {}]

	return
    }

    destructor {
	Debug.cli/manifest/support {}
    }

    # # ## ### ##### ######## #############

    # # ## ### ##### ######## #############
    ## State

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::client::cli::command::ManifestHelp 0
