# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 20xx-2012 Unknown, Public domain or similar
## Taken from http://wiki.tcl.tk/13675
## and adapted by ActiveState Software Inc.

# # ## ### ##### ######## ############# #####################
# Provide multipart/formupload for http
# This is specialized (slimmed down and adapted) to VMC protocol
# idiosyncrasies.

package require tcl::chan::string 1.0.1 ; # need constructor/next bug fix.
package require tcl::chan::cat    1.0.2 ; # read method bug fixes

#puts [package ifneeded tcl::chan::string [package present tcl::chan::string]]
#puts [package ifneeded tcl::chan::cat    [package present tcl::chan::cat]]

package provide stackato::form 0

namespace eval ::stackato::form {}

proc ::stackato::form::start {partv {type multipart/form-data}} {
    upvar 1 $partv form

    set boundary [clock seconds][clock clicks]

    dict set form type "$type\; boundary=$boundary"
    dict set form sep  [set sep "--$boundary\r\n"]
    dict set form length 0

    dict lappend form parts  [list string $sep]
    dict incr    form length [string length $sep]

    #puts FORM++[string length $sep]=[dict get $form length]
    return
}

proc ::stackato::form::compose {partv} {
    upvar 1 $partv form

    set parts [dict get $form parts]
    set haschan 0
    foreach p $parts {
	if {[lindex $p 0] ne "chan"} continue
	set haschan 1
	break
    }

    if {$haschan} {
	# Iteration to convert everything into channels, merging strings.
	set buffer ""
	set chans {}
	foreach p $parts {
	    lassign $p tag value
	    if {$tag eq "string"} {
		append buffer $value
		continue
	    }
	    if {$buffer ne ""} {
		lappend chans [tcl::chan::string $buffer]
		set buffer ""
	    }
	    lappend chans $value
	}
	if {$buffer ne ""} {
	    lappend chans [tcl::chan::string $buffer]
	    set buffer ""
	}
	set buffer [tcl::chan::cat {*}$chans]
	fconfigure $buffer -translation binary
    } else {
	set buffer ""
	foreach p $parts { append buffer [lindex $p 1] }
    }

    set type [dict get $form type]
    set len  [dict get $form length]
    unset form

    return [list $type $buffer $len]
}

proc ::stackato::form::zipvalue {partv name filename value} {
    #puts form/+zip:$name

    upvar 1 $partv form

    set disposition "form-data; name=\"${name}\"; filename=\"$filename\""

    set     lines {}
    lappend lines "Content-Disposition: $disposition"
    lappend lines "Content-type: application/zip"
    lappend lines {}
    lappend lines $value

    set    buffer [join $lines \r\n]
    append buffer \r\n[dict get $form sep]

    dict lappend form parts  [list string $buffer]
    dict incr    form length [string length $buffer]

    #puts FORM++[string length $buffer]=[dict get $form length]
    return
}

proc ::stackato::form::zipfile {partv name path} {
    #puts form/+zip:$name

    upvar 1 $partv form

    set disposition "form-data; name=\"${name}\"; filename=\"[file tail $path]\""

    set     lines {}
    lappend lines "Content-Disposition: $disposition"
    lappend lines "Content-type: application/zip"
    lappend lines {}
    lappend lines {}

    dict incr form length [file size $path]
    #puts FORM++[file size $path]=[dict get $form length]

    set c [open $path r]
    fconfigure $c -translation binary

    set    buffer [join $lines \r\n]
    append buffer \r\n[dict get $form sep]
    dict incr form length [string length $buffer]
    #puts FORM++[string length $buffer]=[dict get $form length]

    dict lappend form parts [list string [join $lines \r\n]]
    dict lappend form parts [list chan $c]
    dict lappend form parts [list string \r\n[dict get $form sep]]

    return
}

proc ::stackato::form::field {partv name value} {
    #puts form/+field:$name

    upvar 1 $partv form
    set disposition "form-data; name=\"${name}\""

    set     lines {}
    lappend lines "Content-Disposition: $disposition"
    lappend lines {}

    # Canonicalize the line-endings in the (text) value to CR+LF.
    foreach l [split $value \n] {
	set l [string trimright $l \r]
	lappend lines $l
    }

    set    buffer [join $lines \r\n]
    append buffer \r\n[dict get $form sep]

    dict lappend form parts  [list string $buffer]
    dict incr    form length [string length $buffer]
    #puts FORM++[string length $buffer]=[dict get $form length]
    return
}

namespace eval ::stackato::form {
    namespace export start compose zipvalue zipfile field
    namespace ensemble create
}
