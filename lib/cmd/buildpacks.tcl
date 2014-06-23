# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations. Management of buildpacks.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require stackato::color
package require stackato::log
package require stackato::mgr::client
package require stackato::term
package require stackato::v2
package require table

debug level  cmd/buildpacks
debug prefix cmd/buildpacks {[debug caller] | }

namespace eval ::stackato::cmd {
    namespace export buildpacks
    namespace ensemble create
}
namespace eval ::stackato::cmd::buildpacks {
    namespace export \
	list create lock unlock rename update delete select-for
    namespace ensemble create

    namespace import ::stackato::color
    namespace import ::stackato::log::again+
    namespace import ::stackato::log::clearlast
    namespace import ::stackato::log::display
    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::client
    namespace import ::stackato::term
    namespace import ::stackato::v2
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::buildpacks::create {config} {
    debug.cmd/buildpacks {}

    set zip [$config @zip]
    set transient 0

    try {
	if {[file isfile $zip] && ![zipfile::decode::iszip $zip]} {
	    err "Input \"zip\" expected a zip archive, got \"$zip\""
	}

	set buildpack [v2 buildpack new]

	$buildpack @name set [$config @name]

	if {[$config @position set?]} {
	    $buildpack @position set [$config @position]
	}
	if {[$config @enabled set?]} {
	    $buildpack @enabled set [$config @enabled]
	}

	display "Creating new buildpack [$buildpack @name] ... " false
	$buildpack commit
	display [color green OK]

	set client [$config @client]
	lassign    [GetArchive $client $zip] transient zip
	if {![zipfile::decode::iszip $zip]} {
	    err "Input \"zip\" expected a zip archive, got \"$zip\""
	}

	display "Uploading buildpack bits ... " false
	$buildpack upload! $zip
	display [color green OK]

	# A lock request is done last, in case setting the flag as part of
	# buildpack creation will prevent the upload of the bits.
	if {[$config @locked set?] && [$config @locked]} {
	    display "Locking buildpack ... " false
	    $buildpack @locked set [$config @locked]
	    $buildpack commit
	    display [color green OK]
	}
    } finally {
	if {$transient} { file delete $zip }
    }
    debug.cmd/buildpacks {buildpack = $buildpack ([$buildpack @name])}
    return
}


proc ::stackato::cmd::buildpacks::GetArchive {client path} {
    debug.cmd/buildpacks {}

    if {[regexp {^https?://} $path]} {
	# Argument is url. Retrieve directly.
	return [GetUrl $client $path "Invalid url \"$path\"."]
    }
    if {![file exists $path]} {
	return [GetUrl $client $path "Invalid url \"$path\"."]
    }
    if {![file readable $path]} {
	err "Path $path is not readable."
    }
    if {![file isfile $path]} {
	err "Path $path is not a file."
    }

    return [::list 0 $path]
}

proc ::stackato::cmd::buildpacks::GetUrl {client url err} {
    # Note: We add the .zip extension to the file because the
    # receiving code of the CF target validates a archive by its
    # extension, not by its magic. No .zip => fail.
    set tmp [fileutil::tempfile stackato-buildpack-]
    file delete $tmp
    append tmp .zip

    debug.cmd/buildpacks {Tmp = $tmp}

    display "Downloading $url"

    # Allow redirections (github)
    # Drop stackato/cloudfoundry authorizations
    set saved [$client cget -follow-redirections]
    set hdrs  [$client cget -headers]
    set newhdrs $hdrs
    dict unset newhdrs AUTHORIZATION

    # Directly save to the temp file instead of through memory.
    set chan [open $tmp w]
    fconfigure $chan -translation binary

    $client configure \
	-follow-redirections 1 \
	-headers $newhdrs \
	-rblocksize 1024 \
	-rprogress ::stackato::cmd::buildpacks::Progress \
	-channel $chan

    try {
	display "Retrieving ... " false

	$client http_get_raw $url application/octet-stream

    } on error {e o} {
	close $chan
	# Ensure removal of the now unused tempfile
	file delete $tmp
	# Note: Exposes constructed url
	#err "Unable to retrieve $url: $e"
	err $err
    } finally {
	display " [color green OK]"
	clearlast

	# Restore original state (cf auth, no redirections).
	$client configure -follow-redirections $saved -headers $hdrs \
	    -rblocksize {} -rprogress {} -channel {}
    }

    close $chan
    return [::list 1 $tmp]
}

proc ::stackato::cmd::buildpacks::Progress {token total n} {
    # This code assumes that the last say* was the prefix
    # of the upload progress display.

    set p [expr {$n*100/$total}]
    again+ "${p}% ($n/$total)"
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::buildpacks::rename {config} {
    debug.cmd/buildpacks {}

    set buildpack [$config @name]
    set old [$buildpack @name]
    set new [$config @newname]

    if {![$config @newname set?]} {
	$config @newname undefined!
    }
    if {$new eq {}} {
	err "An empty buildpack name is not allowed"
    }

    $buildpack @name set $new

    display "Renaming buildpack \[$old\] to '$new' ... " false
    $buildpack commit
    display [color green OK]
    return
}

proc ::stackato::cmd::buildpacks::lock {config} {
    debug.cmd/buildpacks {}

    set buildpack [$config @name]

    $buildpack @locked set 1

    display "Locking buildpack \[[$buildpack @name]\] ... " false
    $buildpack commit
    display [color green OK]
    return
}

proc ::stackato::cmd::buildpacks::unlock {config} {
    debug.cmd/buildpacks {}

    set buildpack [$config @name]

    $buildpack @locked set 0

    display "Unlocking buildpack \[[$buildpack @name]\] ... " false
    $buildpack commit
    display [color green OK]
    return
}

proc ::stackato::cmd::buildpacks::update {config} {
    debug.cmd/buildpacks {}

    set buildpack [$config @name]
    debug.cmd/buildpacks {buildpack = $buildpack ([$buildpack @name])}

    display "Updating buildpack \[[$buildpack @name]\] ..."

    set changes 0
    foreach {attr label} {
	@position {Position}
	@enabled  {Enabled }
	@locked   {Locked  }
    } {
	display "  $label ... " false
	if {![$config $attr set?]} {
	    display [color blue Unchanged]
	    continue
	}
	display "Changed to [$config $attr]"
	$buildpack $attr set [$config $attr]
	incr changes
    }

    if {$changes} {
	$buildpack commit
	display [color green OK]
    }

    if {[$config @zip set?]} {
	display "Uploading new buildpack bits ... " false
	$buildpack upload! [$config @zip]
	display [color green OK]
    }
    return
}

proc ::stackato::cmd::buildpacks::delete {config} {
    debug.cmd/buildpacks {}
    # @name - buildpack name

    set buildpack [$config @name]
    debug.cmd/buildpacks {buildpack = $buildpack ([$buildpack @name])}

    if {[cmdr interactive?] &&
	![term ask/yn \
	      "\nReally delete \"[$buildpack @name]\" ? " \
	      no]} return

    $buildpack delete

    display "Deleting buildpack [$buildpack @name] ... " false
    $buildpack commit
    display [color green OK]
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::buildpacks::list {config} {
    debug.cmd/buildpacks {}
    # No arguments.

    try {
	set buildpacks [v2 buildpack list]
    } trap {STACKATO CLIENT V2 UNKNOWN REQUEST} {e o} {
	err "Admin buildpacks not supported by target"
    }

    if {[$config @json]} {
	set tmp {}
	foreach r $buildpacks {
	    lappend tmp [$r as-json]
	}
	display [json::write array {*}$tmp]
	return
    }

    [table::do t {# Name Filename Enabled Locked} {
	foreach buildpack [v2 sort @position $buildpacks -dict] {
	    set enabled [expr { [$buildpack @enabled] ? "yes" : "no" }]
	    if {[$buildpack @locked defined?]} {
		set locked [expr { [$buildpack @locked]  ? "yes" : "no" }]
	    } else {
		set locked "n/a"
	    }
	    if {[$buildpack @filename defined?]} {
		set fn [$buildpack @filename]
	    } else {
		set fn "n/a"
	    }
	    $t add \
		[$buildpack @position] \
		[$buildpack @name] \
		$fn \
		$enabled $locked
	}
    }] show display
    return
}

# # ## ### ##### ######## ############# #####################
## Support. Generator callback.

proc ::stackato::cmd::buildpacks::select-for {what p {mode noauto}} {
    debug.cmd/buildpacks {}
    # generate callback - (p)arameter argument.

    # Modes
    # - auto   : If there is only a single buildpack, take it without asking the user.
    # - noauto : Always ask the user.

    # generate callback for 'buildpack delete|rename: name'.

    # Implied client.
    debug.cmd/buildpacks {Retrieve list of buildpacks...}

    ::set choices [v2 buildpack list]
    debug.cmd/buildpacks {BPACK [join $choices "\nBPACK "]}

    if {([llength $choices] == 1) && ($mode eq "auto")} {
	::set newpack [lindex $choices 0]
	display "Choosing the one available buildpack: \"[$newpack @name]\""
	return $newpack
    }

    if {![llength $choices]} {
	warn "No buildpacks available to ${what}."
    }

    if {![cmdr interactive?]} {
	debug.cmd/buildpacks {no interaction}
	$p undefined!
	# implied return/failure
    }

    foreach o $choices {
	dict set map [$o @name] $o
    }
    ::set choices [lsort -dict [dict keys $map]]
    ::set name [term ask/menu "" \
		    "Which buildpack to $what ? " \
		    $choices]

    return [dict get $map $name]
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::buildpacks 0

