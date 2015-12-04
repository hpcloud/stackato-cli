
# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP @date@

#checker -scope global exclude warnUndefinedVar
# var in question is 'dir'.

package ifneeded restclient 0.1 [list source [file join $dir rest.tcl]]
