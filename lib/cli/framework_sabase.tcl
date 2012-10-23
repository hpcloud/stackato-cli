# -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Framework storage class. Derived from the base class, i.e.
##  ::stackato::client::cli::framework::base
## Overides various query commands to provide special casing.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require try            ;# I want try/catch/finally
package require TclOO
package require dictutil
package require cd
package require zipfile::decode
package require fileutil::traverse

package require stackato::client::cli::framework::base

debug level  cli/framework/sabase
debug prefix cli/framework/sabase {[::debug::snit::call] | }

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::client::cli::framework::sabase {
    superclass ::stackato::client::cli::framework::base
    # # ## ### ##### ######## #############
    ## No separate constructor/destructor.

    # # ## ### ##### ######## #############
    ## API

    # overriding various base class methods.
    method require_url? {} {
	Debug.cli/framework/sabase {}
	return 0
    }
 
    # # ## ### ##### ######## #############
    ## State

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::client::cli::framework::sabase 0
