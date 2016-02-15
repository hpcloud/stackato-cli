# -*- tcl -*- Copyright (c) 2012 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## Handle tklib/diagram figures (documentation)

namespace eval ::kettle { namespace export tclapp }

# # ## ### ##### ######## ############# #####################
## API.

proc ::kettle::tclapp {fname} {
    ## Recipe: Pure Tcl application installation.

    io trace {}
    io trace {DECLARE tcl application $fname @ [path sourcedir]}

    meta scan

    set src [path sourcedir $fname]

    if {![file exists $src]} {
	io trace {    NOT FOUND}
	return
    }

    set name [file rootname $fname]
    meta read-internal $src application $name

    io trace {    Accepted: $fname}

    recipe define install-app-$fname "Install application $fname" {name src} {
	path install-script \
	    $src [path bindir] [info nameofexecutable] \
	    [lambda {name dst} {
		kettle meta insert $dst application $name
	    } $name]
    } $name $src

    recipe define uninstall-app-$fname "Uninstall application $fname" {src} {
	path uninstall-application \
	    $src [path bindir]
    } $src

    recipe define reinstall-app-$fname "Reinstall application $fname" {fname} {
	invoke self uninstall-app-$fname
	invoke self install-app-$fname
    } $fname

    # Hook the application specific recipes into a hierarchy of more
    # general recipes.

    recipe parent install-app-$fname       install-tcl-applications
    recipe parent install-tcl-applications install-applications
    recipe parent install-applications     install

    recipe parent uninstall-app-$fname       uninstall-tcl-applications
    recipe parent uninstall-tcl-applications uninstall-applications
    recipe parent uninstall-applications     uninstall

    recipe parent reinstall-app-$fname       reinstall-tcl-applications
    recipe parent reinstall-tcl-applications reinstall-applications
    recipe parent reinstall-applications     reinstall

    # For applications without user-specified meta data we initialize
    # a recipe which allows the developer to quickly insert a basic
    # structure with standard keys, which can then be completed
    # manually.

    if {![meta defined? application $name]} {
	recipe define meta-generate-application-$fname "Generate empty data for application $fname" {root files pn pv} {

	    dict set m platform    tcl
	    dict set m author      ?
	    dict set m summary     ?
	    dict set m description ?
	    dict set m subject     ?
	    dict set m category    ?
	    dict set m require     ?

	    meta fix-location m
	    if {![dict exists $m location]} {
		dict set m location ?
	    }

	    set m [meta format-internal application $name ? $m]
	    path write-modify $src \
		[list kettle path add-top-comment $m]
	} $src

	recipe parent meta-generate-application-$fname  meta-generate-tcl-applications
	recipe parent meta-generate-tcl-applications    meta-generate-applications
	recipe parent meta-generate-applications        meta-generate
    }
    return
}

# # ## ### ##### ######## ############# #####################
return
