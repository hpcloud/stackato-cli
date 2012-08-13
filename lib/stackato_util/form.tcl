# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 20xx-2012 Unknown, Public domain or similar
## Taken from http://wiki.tcl.tk/13675
## and adapted by ActiveState Software Inc.

# # ## ### ##### ######## ############# #####################
# Provide multipart/formupload for http
# This is specialized (slimmed down and adapted) to VMC protocol
# idiosyncrasies.

package provide stackato::form 0

namespace eval ::stackato::form {}

proc ::stackato::form::compose {partv {type multipart/form-data}} {
    upvar 1 $partv parts

    #puts form/compose:[llength $parts]

    set boundary [clock seconds][clock clicks]
    set sep --$boundary\r\n

    set packaged $sep[join $parts \r\n$sep]\r\n$sep

    return [list "$type\; boundary=$boundary" $packaged]
}

proc ::stackato::form::zip {partv name filename value} {
    #puts form/+zip:$name

    upvar 1 $partv parts
    set disposition "form-data; name=\"${name}\"; filename=\"$filename\""

    set     lines {}
    lappend lines "Content-Disposition: $disposition"
    lappend lines "Content-type: application/zip"
    lappend lines {}
    lappend lines $value

    lappend parts [join $lines \r\n]
    return
}

proc ::stackato::form::field {partv name value} {
    #puts form/+field:$name

    upvar 1 $partv parts
    set disposition "form-data; name=\"${name}\""

    set     lines {}
    lappend lines "Content-Disposition: $disposition"
    lappend lines {}

    # Canonicalize the line-endings in the (text) value to CR+LF.
    foreach l [split $value \n] {
	set l [string trimright $l \r]
	lappend lines $l
    }

    lappend parts [join $lines \r\n]
    return
}

namespace eval ::stackato::form {
    namespace export compose zip field
    namespace ensemble create
}
