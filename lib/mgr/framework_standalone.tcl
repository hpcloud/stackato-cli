# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################
## Framework storage class. Derived from the base class, i.e.
##  ::stackato::mgr::framework::base
## Overides various query commands to provide special casing.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require try            ;# I want try/catch/finally
package require TclOO
package require dictutil
package require cd
package require zipfile::decode
package require fileutil::traverse

package require stackato::mgr::framework::base

debug level  mgr/framework/standalone
debug prefix mgr/framework/standalone {[debug caller] | }

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::mgr::framework::standalone {
    superclass ::stackato::mgr::framework::base
    # # ## ### ##### ######## #############
    ## No separate constructor/destructor.

    # # ## ### ##### ######## #############
    ## API

    # overriding various base class methods.
    method require_url? {} {
	debug.mgr/framework/standalone {}
	return 0
    }
    method require_start_command? {} {
	debug.mgr/framework/standalone {}
	return 1
    }
    method prompt_for_runtime? {} {
	debug.mgr/framework/standalone {}
	return 1
    }

    method default_runtime {path} {
	debug.mgr/framework/standalone {}
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
	debug.mgr/framework/standalone {}
	if {$runtime in {java java7}}        { return 512M }
	if {$runtime eq "php"}               { return 128M }
	if {[string match "ruby*" $runtime]} { return 128M }
	return [next $runtime]
    }

    # # ## ### ##### ######## #############
    ## Internal commands.

    method detect_runtime_from_zip {zipfile} {
	debug.mgr/framework/standalone {}
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
package provide stackato::mgr::framework::standalone 0
