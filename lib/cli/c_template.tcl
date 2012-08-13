# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require try            ;# I want try/catch/finally
package require TclOO
package require stackato::client::cli::command::Base

namespace eval ::stackato::client::cli::command::@@@ {}

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::client::cli::command::@@@ {
    superclass ::stackato::client::cli::command::Base

    # # ## ### ##### ######## #############

    constructor {args} {
	# Namespace import, sort of.
	namespace path [linsert [namespace path] end \
			    ::stackato ::stackato::log ::stackato::client::cli]
	next {*}$args
    }

    destructor {
    }

    # # ## ### ##### ######## #############
    ## API

    # # ## ### ##### ######## #############
    ## Internal commands.

    # # ## ### ##### ######## #############
    ## State

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::client::cli::command::@@@ 0
