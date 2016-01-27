# -*- tcl -*- Copyright (c) 2013 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## Manipulate the list of ignore patterns.

namespace eval ::kettle {
    namespace export ignore
    namespace eval ignore {
	namespace export += = reset
	namespace ensemble create

	namespace import ::kettle::path
    }
}

# # ## ### ##### ######## ############# #####################
## API.

proc ::kettle::ignore::+= {args} {
    path ignore-add {*}$args
    return
}

proc ::kettle::ignore::= {args} {
    path ignore-reset
    if {![llength $args]} return
    path ignore-add {*}$args
    return
}

# # ## ### ##### ######## ############# #####################
return
