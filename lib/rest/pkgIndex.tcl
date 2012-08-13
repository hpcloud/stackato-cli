#checker -scope global exclude warnUndefinedVar
# var in question is 'dir'.

package ifneeded restclient 0.1 [list source [file join $dir rest.tcl]]
