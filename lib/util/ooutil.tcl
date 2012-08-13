# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 20xx-2012 Unknown, Public Domain or similar.
## Taken from http://wiki.tcl.tk/21595#pagetoc032fa399

# # ## ### ##### ######## ############# #####################

package require TclOO

# Easy callback support.
proc ::oo::Helpers::callback {method args} {
    list [uplevel 1 {namespace which my}] $method {*}$args
}

package provide ooutil 0
