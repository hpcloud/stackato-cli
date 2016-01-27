# -*- tcl -*- Copyright (c) 2012 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## Special commands outside of goal processing.

# # ## ### ##### ######## ############# #####################
## Export (internals - recipe definitions, other utilities)

namespace eval ::kettle::special {
    namespace export {[a-z]*}
    namespace ensemble create

    # Import the supporting utilities used here.
    namespace import ::kettle::path
}

# # ## ### ##### ######## ############# #####################
## API

proc ::kettle::special::setup {args} {
    # Generate a basic build.tcl file in the current working
    # directory.

    if {![llength $args]} {
	lappend args tcl
    }

    lappend lines "#!/usr/bin/env kettle"
    lappend lines "# -*- tcl -*-"
    lappend lines "# For kettle sources, documentation, etc. see"
    lappend lines "# - http://core.tcl.tk/akupries/kettle"
    lappend lines "# - http://chiselapp.com/user/andreas_kupries/repository/Kettle"

    foreach code $args {
	lappend lines [list kettle {*}$code]
    }
    path write build.tcl [join $lines \n]\n
    return
}

# # ## ### ##### ######## ############# #####################
return
