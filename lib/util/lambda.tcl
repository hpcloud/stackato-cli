# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

proc lambda {arguments body args} {
    return [list ::apply [list $arguments $body] {*}$args]
}

proc lambda@ {ns arguments body args} {
    return [list ::apply [list $arguments $body $ns] {*}$args]
}

package provide lambda 0

