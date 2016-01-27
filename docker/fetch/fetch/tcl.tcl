# -*- tcl -*- Copyright (c) 2012 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## Handle pure tcl packages.

namespace eval ::kettle { namespace export tcl }

# # ## ### ##### ######## ############# #####################
## API.

proc ::kettle::tcl {} {

    # Heuristic search for documentation, testsuites, benchmarks.
    doc
    testsuite
    benchmarks

    # Heuristic processing of external teapot meta data files.
    meta scan

    # Heuristic search for packages to install, collect names, versions, and files.
    # Aborts caller when nothing is found.
    lassign [path scan \
		 {tcl packages}\
		 [path sourcedir] \
		 {path tcl-package-file}] \
	root packages

    foreach {files pn pv} $packages {
	TclSetup $root $files $pn $pv
    }
    return
}

proc ::kettle::TclSetup {root files pn pv} {
    set pkgdir [path libdir [string map {:: _} $pn]$pv]

    # Process any teapot meta data stored within the main package file
    # itself.

    set adjunct [lassign $files primary]
    meta read-internal $root/$primary package $pn
    set primary [file tail $primary]

    meta add package $pn entrysource $primary
    meta add package $pn included    [list $primary {*}$adjunct]
    meta add package $pn version $pv
    meta add package $pn name    $pn
    meta add package $pn entity  package

    recipe define install-package-$pn "Install package $pn $pv" {pkgdir root files pn pv} {
	if {[option exists @dependencies]} {
	    invoke @dependencies install
	}

	path in $root {
	    try {
		set tmpdir [path tmpfile tclindex_]
		file mkdir    $tmpdir
		set indexfile $tmpdir/pkgIndex.tcl
		set mdfile    $tmpdir/teapot.txt

		path ensure-cleanup $tmpdir

		set primary [lindex $files 0]
		path write $indexfile \
		    "package ifneeded [list $pn] $pv \[list source \[file join \$dir [file tail $primary]]]"

		set mdfile [meta write $mdfile package $pn $pv]

		path install-file-group \
		    "package $pn $pv" \
		    $pkgdir {*}$files $indexfile {*}$mdfile

	    } finally {
		file delete $indexfile
		file delete $mdfile
		file delete -force $tmpdir
	    }
	}
    } $pkgdir $root $files $pn $pv

    recipe define uninstall-package-$pn "Uninstall package $pn $pv" {pkgdir pn pv} {
	path uninstall-file-group "package $pn $pv" $pkgdir
    } $pkgdir $pn $pv

    recipe define reinstall-package-$pn "Reinstall package $pn $pv" {pn} {
	invoke self uninstall-package-$pn
	invoke self install-package-$pn
    } $pn

    # Hook the package specific recipes into a hierarchy of more
    # general recipes.

    recipe parent install-package-$pn  install-tcl-packages
    recipe parent install-tcl-packages install-packages
    recipe parent install-packages     install

    recipe parent uninstall-package-$pn  uninstall-tcl-packages
    recipe parent uninstall-tcl-packages uninstall-packages
    recipe parent uninstall-packages     uninstall

    recipe parent install-package-$pn debug-package-$pn  
    recipe parent debug-package-$pn   debug-tcl-packages
    recipe parent debug-tcl-packages  debug-packages
    recipe parent debug-packages      debug

    recipe parent reinstall-package-$pn  reinstall-tcl-packages
    recipe parent reinstall-tcl-packages reinstall-packages
    recipe parent reinstall-packages     reinstall

    # For packages without user-specified meta data we initialize a
    # recipe which allows the developer to quickly insert a basic
    # structure with standard keys which, can then be completed
    # manually.

    if {![meta defined? package $pn]} {
	recipe define meta-generate-package-$pn "Generate empty data for package $pn $pv" {root files pn pv} {
	    path in $root {
		set primary [lindex $files 0]

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

		set m [meta format-internal package $pn $pv $m]
		#path write-prepend $primary $m
		path write-modify $primary \
		    [list kettle path add-top-comment $m]
	    }

	} $root $files $pn $pv

	recipe parent meta-generate-package-$pn  meta-generate-tcl-packages
	recipe parent meta-generate-tcl-packages meta-generate-packages
	recipe parent meta-generate-packages     meta-generate
    }

    return
}

# # ## ### ##### ######## ############# #####################
return
