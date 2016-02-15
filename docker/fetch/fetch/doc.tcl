# -*- tcl -*- Copyright (c) 2012-2013 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## Handle tcllib/doctools documentation files

namespace eval ::kettle {
    namespace export doc doc-destination gh-pages
}

kettle option define --with-doc-destination {
    Documentation option. Path to the directory the generated
    documentation is placed in. If a relative path is specified it is
    taken relative to the overall source directory.
} embedded directory

kettle option no-work-key --with-doc-destination

kettle tool declare {
    git
}

if {![catch {
    package require dtplite 1.0.5
    # dtplite as package
}]} {
    kettle option set @dtplite internal
} else {
    kettle option set @dtplite external

    kettle tool declare {
	dtplite dtplite.kit dtplite.tcl dtplite.exe
    }
}

# # ## ### ##### ######## ############# #####################
## API.

proc ::kettle::doc-destination {dstdir} {
    # NOTE: Both absolute paths and paths outside of the source
    # directory have sensible use-cases, hence my choice to not reject
    # them here.
    #
    # (1) The package in question may be part of a larger structure,
    # with a consolidated hierarchy for doc results
    #
    # (2) The user may wish to redirect the generated documenation
    # somewhere else.

    option set-default --with-doc-destination $dstdir
    return
}

proc ::kettle::doc {{docsrcdir doc}} {
    # Overwrite self, we run only once for effect.
    proc ::kettle::doc args {}

    # Heuristic search for figures
    figures $docsrcdir/figures

    # Heuristic search for documentation files.
    # Aborts caller when nothing is found.
    lassign [path scan \
		 tcllib/doctools \
		 $docsrcdir \
		 {path doctools-file}] \
	root manpages

    # Put the documentation into recipes.

    set dd      [path sourcedir [option get --with-doc-destination]]
    set mansrc  $dd/man/files
    set htmlsrc $dd/www

    set mandst  [path mandir  mann]
    set htmldst [path htmldir [file tail [path sourcedir]]]

    set isfossil [expr {[path find.fossil [path sourcedir]] ne {}}]

    recipe define doc {
	(Re)generate the documentation embedded in the repository.
    } {root dst isfossil} {
	if {[option get @dtplite] eq "external"} {
	    # Validate tool presence before actually doing anything
	    tool get dtplite
	}
	DtpliteDo $root $dst $isfossil
    } $root $dd $isfossil

    recipe define validate-doc {
	Validate the documentation.
    } {root} {
	io puts "Validate documentation"
	path exec dtplite validate .
    } $root

    recipe define install-doc-manpages {
	Install manpages
    } {src dst} {
	path install-file-set \
	    "manpages" \
	    $dst {*}[glob -directory $src *.n]
	return
    } $mansrc $mandst

    recipe define install-doc-html {
	Install HTML documentation
    } {src dst} {
	path install-file-group \
	    "HTML documentation" \
	    $dst {*}[glob -directory $src *]
	return
    } $htmlsrc $htmldst

    recipe define uninstall-doc-manpages {
	Uninstall manpages
    } {src dst} {
	path uninstall-file-set \
	    "manpages" \
	    $dst {*}[glob -directory $src -tails *.n]
	return
    } $mansrc $mandst

    recipe define uninstall-doc-html {
	Uninstall HTML documentation
    } {dst} {
	path uninstall-file-group \
	    "HTML documentation" \
	    $dst
    } $htmldst

    recipe define reinstall-doc-manpages {
	Reinstall manpages
    } {} {
	invoke self uninstall-doc-manpages
	invoke self install-doc-manpages
    }

    recipe define reinstall-doc-html {
	Reinstall HTML documentation
    } {} {
	invoke self uninstall-doc-html
	invoke self install-doc-html
    }

    recipe parent install-doc-html     install-doc
    recipe parent install-doc-manpages install-doc
    recipe parent install-doc          install

    recipe parent uninstall-doc-html     uninstall-doc
    recipe parent uninstall-doc-manpages uninstall-doc
    recipe parent uninstall-doc          uninstall

    recipe parent reinstall-doc-html     reinstall-doc
    recipe parent reinstall-doc-manpages reinstall-doc
    recipe parent reinstall-doc          reinstall

    recipe parent validate-doc validate
    return
}

# # ## ### ##### ######## ############# #####################

proc ::kettle::DtpliteDo {root dst isfossil} {
    io trace {  do fossil=$isfossil}

    path in $root {

	io puts "Removing old documentation..."
	file delete -force $dst

	file mkdir $dst/man
	file mkdir $dst/www

	io puts "Generating man pages..."
	DtpliteRun -ext n -o $dst/man nroff .

	# Note: Might be better to run them separately.
	# Note @: Or we shuffle the results a bit more in the post processing stage.

	if {$isfossil} {
	    set cmd [list -nav Home ../../../../home -merge -o $dst/www html .]
	} else {
	    set cmd [list -merge -o $dst/www html .]
	}

	io puts "\nGenerating HTML... Pass 1, draft..."
	DtpliteRun {*}$cmd

	io puts "\nGenerating HTML... Pass 2, resolving cross-references..."
	DtpliteRun {*}$cmd

	# Remove some of the generated files, consider them transient.
	cd  $dst/man ; file delete -force .idxdoc .tocdoc
	cd  ../www   ; file delete -force .idxdoc .tocdoc
    }
}

proc ::kettle::DtpliteRun {args} {
    io trace { dtplite [path::T $args]}
    if {[option get --dry]} return

    io puts {}
    if {[option get @dtplite] eq "internal"} {
	io trace {  dtplite: internal}
	io trace {[package ifneeded dtplite [package present dtplite]]}

	dtplite::do $args
    } else {
	io trace {  dtplite: external}
	path exec {*}[tool get dtplite] {*}$args
    }
    return
}

# # ## ### ##### ######## ############# #####################
## Handle a github gh-pages branch.

proc ::kettle::gh-pages {} {
    # Overwrite self, we run only once for effect.
    proc ::kettle::gh-pages args {}

    doc

    io trace {Testing for gh-pages}

    # No need to handle a gh-pages documentation branch if there is no
    # documentation to work with.
    if {![recipe exists doc]} {
	io trace {  No gh-pages: No documentation}
	return
    }

    # Ditto if this is not a git-based project.
    if {[path find.git [path sourcedir]] eq {}} {
	io trace {  No gh-pages: Not git based}
	return
    }
 
    # Now we check if the branch we need is present. Note that if we
    # can't find the tool, i.e. "git", we assume that the branch is
    # present and let the recipe error out on the missing tool.

    if {![catch {
	path grep *gh-pages* [exec {*}[tool get git] branch -a]
    } res] && ![llength $res]} {
	io trace {  No gh-pages: branch not present}
	return
    }

    recipe define gh-pages {
	Install embedded documentation into a gh-pages
	branch of the local git repository.
    } {} {
	# Validate tool presence before actually doing anything
	tool get git

	# PWD is the local git checkout.

	# Determine git revision information, informational use only
	set commit  [exec {*}[tool get git] log -1 --pretty=format:%H]
	try {
	    set version [exec {*}[tool get git] describe]
	} on error {} {
	    set version unknown
	}
	regsub -- {^.*/} [string trim [path cat .git/HEAD]] {} branch

	io puts "\n  Commit:      $commit"
	io puts "  Branch:      $branch"
	io puts "  Version:     $version"

	set tmpdir [path tmpdir]/[path tmpfile ghp_]
	file mkdir $tmpdir
	path ensure-cleanup $tmpdir

	# Save the documentation outside of checkout ... ... ...
	set docs [option get --with-doc-destination]/www
	io puts "  Doc Origin:  $docs"
	io puts "  Saving to:   $tmpdir"
	file copy -force $docs $tmpdir/doc

	# Switch to gh-pages branch, i.e. the github website
	io puts {Switching to gh-pages...}
	path exec {*}[tool get git] checkout gh-pages

	# Place the saved documentation
	io puts {Updating documentation...}
	file delete -force doc
	file copy -force $tmpdir/doc doc
	file delete -force $tmpdir

	# Assumming doctools-originated files, remove various
	# irrelevant files.
	file delete doc/.idx doc/.toc doc/.xrf

	## Reminder ... ... ...
	io puts ""
	io puts "You are now in branch"
	io puts \t[io mred gh-pages]
	io puts "coming from commit"
	io puts \t[io mok $commit]
	io puts ""
	io puts "[io mnote Verify] the changes now,"
	io puts "then [io mnote {commit and push}] them,"
	io puts "and lastly [io mnote {switch back}] to where you were via"
	io puts \t[io mnote "git checkout $branch"]
	io puts ""
	return
    }

    return
}

# # ## ### ##### ######## ############# #####################
return
