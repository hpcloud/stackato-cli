# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

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

debug level  cli/framework/standalone
debug prefix cli/framework/standalone {[::debug::snit::call] | }

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::client::cli::framework::standalone {
    superclass ::stackato::client::cli::framework::base
    # # ## ### ##### ######## #############
    ## No separate constructor/destructor.

    # # ## ### ##### ######## #############
    ## API

    # overriding various base class methods.
    method require_url? {} {
	Debug.cli/framework/standalone {}
	return 0
    }
    method require_start_command? {} {
	Debug.cli/framework/standalone {}
	return 1
    }
    method prompt_for_runtime? {} {
	Debug.cli/framework/standalone {}
	return 1
    }

    method default_runtime {path} {
	Debug.cli/framework/standalone {}
	if {![file isdirectory $path]} {
	    set e [file extension $path]
	    if {$e in {.jar .class}} {
		return java
	    } elseif {$e eq ".rb"} {
		return ruby18
	    } elseif {$e eq ".zip"} {
		return [my detect_runtime_from_zip $path]
	    }

	} {
	    cd::indir $path {
		fileutil::traverse T .
		set contents [T files]
		T destroy

		if {[lsearch -glob $contents *.rb] >= 0} {
		    return ruby18
		}
		if {([lsearch -glob $contents *.class] >= 0) ||
		    ([lsearch -glob $contents *.jar] >= 0)
		} {
		    return java
		}
		set contents [glob -nocomplain *.zip]
		if {[llength $contents]} {
		    return [my detect_runtime_from_zip [lindex $contents 0]]
		}
	    }
	}

	return {}
    }

    method memory {{runtime {}}} {
	Debug.cli/framework/standalone {}
	if {$runtime in {java java7}}        { return 512M }
	if {$runtime eq "php"}               { return 128M }
	if {[string match "ruby*" $runtime]} { return 128M }
	return [next $runtime]
    }

    # # ## ### ##### ######## #############
    ## Internal commands.

    method detect_runtime_from_zip {zipfile} {
	Debug.cli/framework/standalone {}
	set contents [zipfile::decode::content $zipfile]
	if {[lsearch -glob $contents {*.jar}] >= 0} {
	    return "java"
	}
	return {}
    }

    # # ## ### ##### ######## #############
    ## State

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::client::cli::framework::standalone 0
