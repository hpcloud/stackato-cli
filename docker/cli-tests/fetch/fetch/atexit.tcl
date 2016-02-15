# -*- tcl -*- Copyright (c) 2012 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## Application Shutdown Handlers

namespace eval ::atexit {}

# # ## ### ##### ######## ############# #####################
## API commands.

proc ::atexit {cmd} {
    variable ::atexit::handlers
    lappend handlers $cmd
    return
}

namespace eval ::atexit {
    variable handlers {}
}

rename ::exit ::atexit::exit
proc   ::exit {args} {
    variable ::atexit::handlers
    foreach cmd $handlers {
	uplevel \#0 $cmd
    }
    ::atexit::exit {*}$args
}

# # ## ### ##### ######## ############# #####################
return
