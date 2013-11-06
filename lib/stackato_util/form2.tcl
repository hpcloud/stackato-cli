# Provide multipart/form-data upload for http
# This is specialized (slimmed down and adapted) to VMC protocol
# idiosyncrasies. This variant is for CFv2.
# Easier to make a variant than havign to test if this would work
# with CFv1/stackato servers also. I.e. keep things separate

package require tcl::chan::string 1.0.1 ; # need constructor/next bug fix.
package require tcl::chan::cat    1.0.2 ; # read method bug fixes

#puts [package ifneeded tcl::chan::string [package present tcl::chan::string]]
#puts [package ifneeded tcl::chan::cat    [package present tcl::chan::cat]]

package provide stackato::form2 0

namespace eval ::stackato::form2 {}

proc ::stackato::form2::start {partv {type multipart/form-data}} {
    upvar 1 $partv form

    set boundary [clock seconds][clock clicks]

    dict set form type "$type\; boundary=$boundary"
    dict set form sep  [set sep "--$boundary"]
    dict set form length 0

    AddSeparator form
    return
}

proc ::stackato::form2::compose {partv} {
    upvar 1 $partv form

    AddString form eof -- ;# rack parser
    AddEOL    form
    AddEOL    form

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
    #puts form2/+zip:$name

    upvar 1 $partv form

    set disposition "form-data; name=\"${name}\"; filename=\"$filename\""

    AddEOL       form
    AddHeader    form Content-Disposition       $disposition
    AddHeader    form Content-Length            [string length $value]
    AddHeader    form Content-Type              application/zip
    AddHeader    form Content-Transfer-Encoding binary
    AddEOL       form
    AddString    form $name $value
    AddEOL       form
    AddSeparator form
    return
}

proc ::stackato::form2::zipfile {partv name path} {
    #puts form2/+zip:$name

    upvar 1 $partv form

    set disposition "form-data; name=\"${name}\"; filename=\"[file tail $path]\""

    AddEOL       form
    AddHeader    form Content-Disposition       $disposition
    AddHeader    form Content-Length            [file size $path]
    AddHeader    form Content-Type              application/zip
    AddHeader    form Content-Transfer-Encoding binary
    AddEOL       form
    AddFile      form $name $path
    AddEOL       form
    AddSeparator form
    return
}

proc ::stackato::form2::field {partv name value} {
    #puts form2/+field:$name

    upvar 1 $partv form
    set disposition "form-data; name=\"${name}\""

    AddEOL    form
    AddHeader form Content-Disposition $disposition
    AddEOL    form

    # Canonicalize the line-endings in the (text) value to CR+LF.
    foreach l [split $value \n] {
	set l [string trimright $l \r]
	AddLine form $name $l
    }

    AddSeparator form
    return
}

# # ## ### ##### ######## #############
##

proc ::stackato::form2::Import {partv} {
    uplevel 1 [list upvar 1 $partv form]
    return
}

proc ::stackato::form2::AddHeader {partv key value} {
    upvar 1 $partv form
    AddLine form $key "$key: $value"
    return
}

proc ::stackato::form2::AddLine {partv id line} {
    upvar 1 $partv form
    AddString form $id $line\r\n
    return
}

proc ::stackato::form2::AddEOL {partv} {
    upvar 1 $partv form
    AddString form eol \r\n
    return
}

proc ::stackato::form2::AddSeparator {partv} {
    upvar 1 $partv form
    AddString form sep [dict get $form sep]
    return
}

proc ::stackato::form2::AddString {partv id buffer} {
    upvar 1 $partv form

    dict lappend form parts  [list string $buffer]
    dict incr    form length [string length $buffer]

    #puts FORM2++AS|$id|[string length $buffer]=[dict get $form length]
    return
}

proc ::stackato::form2::AddFile {partv id path} {
    upvar 1 $partv form

    set c [open $path r]
    fconfigure $c -translation binary

    dict lappend form parts  [list chan $c]
    dict incr    form length [file size $path]

    #puts FORM2++AF|$id|[file size $path]=[dict get $form length]
    return
}

# # ## ### ##### ######## #############

namespace eval ::stackato::form2 {
    namespace export start compose zipvalue zipfile field
    namespace ensemble create
}


# # ## ### ##### ######## #############
return
