# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations. Management of buildpacks.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::ask
package require cmdr::color
package require stackato::log
package require stackato::mgr::client
package require stackato::mgr::context
package require stackato::v2
package require zipfile::encode
package require fileutil
package require fileutil::traverse
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

    namespace import ::cmdr::ask
    namespace import ::cmdr::color
    namespace import ::stackato::log::again+
    namespace import ::stackato::log::clearlast
    namespace import ::stackato::log::display
    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::client
    namespace import ::stackato::mgr::context
    namespace import ::stackato::v2
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::buildpacks::create {config} {
    debug.cmd/buildpacks {}

    set zip       [$config @zip]
    set transient 0
    set fname     [Name $zip]

    try {
	Ingest $config zip transient

	set buildpack [v2 buildpack new]
	$buildpack @name set [$config @name]

	if {[$config @position set?]} {
	    $buildpack @position set [$config @position]
	}
	if {[$config @enabled set?]} {
	    $buildpack @enabled set [$config @enabled]
	}

	display "Creating new buildpack [color name [$buildpack @name]] ... " false
	$buildpack commit
	display [color good OK]

	display "Uploading buildpack bits ([color name $fname]) ... " false
	Keeping $config $zip $buildpack
	$buildpack upload! $zip $fname
	display [color good OK]

	# A lock request is done last, in case setting the flag as part of
	# buildpack creation will prevent the upload of the bits.
	if {[$config @locked set?] && [$config @locked]} {
	    display "Locking buildpack ... " false
	    $buildpack @locked set [$config @locked]
	    $buildpack commit
	    display [color good OK]
	}
    } finally {
	if {$transient} {
	    debug.cmd/buildpacks {deleting $zip}
	    file delete $zip
	}
    }
    debug.cmd/buildpacks {buildpack = $buildpack ([$buildpack @name])}
    return
}

proc ::stackato::cmd::buildpacks::Keeping {config zip buildpack} {
    debug.cmd/buildpacks {}
    if {[$config @keep-form set?]} {
	debug.cmd/buildpacks {form = [$config @keep-form]}
	$buildpack keep-form [$config @keep-form]
    }
    if {[$config @keep-zip set?]} {
	debug.cmd/buildpacks {zip  = [$config @keep-zip]}
	file copy -force $zip [$config @keep-zip]
    }
    return
}

proc ::stackato::cmd::buildpacks::Ingest {config zv tv} {
    debug.cmd/buildpacks {}
    upvar 1 $zv zip $tv transient

    if {[file isfile $zip]} {
	debug.cmd/buildpacks {file = $zip}

	if {![zipfile::decode::iszip $zip]} {
	    err "Input \"zip\" expected a zip archive, got \"$zip\""
	}

	Rewrite zip transient {*}[ValidateZip $zip]
	return
    }

    if {[file isdirectory $zip]} {
	debug.cmd/buildpacks {dir = $zip}
	# A directory is converted into the zip file to upload.

	# Validate - Look for bin/compile - strip as part of pack.
	set zip [ValidateDir $zip]

	try {
	    set zip [Pack $zip]
	    set transient 1
	} on error {e o} {
	    err $e
	}

	return
    }

    set client [$config @client]
    lassign    [GetArchive $client $transient $zip] transient zip

    if {![zipfile::decode::iszip $zip]} {
	err "Input \"zip\" expected a zip archive, got \"$zip\""
    }

    Rewrite zip transient {*}[ValidateZip $zip]
    return
}

proc ::stackato::cmd::buildpacks::Name {zip} {
    set fname [lindex [split $zip /] end]
    if {$fname eq "."} { set fname [file tail [pwd]] }

    if {[file extension $fname] ne ".zip"} { append fname .zip }
    return $fname
}

proc ::stackato::cmd::buildpacks::ValidateDir {path} {
    debug.cmd/buildpacks {}
    #set path [file normalize $path]
    fileutil::traverse T $path
    T foreach sub {
	if {![file isdirectory $sub]} continue
	if {![file exists $sub/bin/compile]} continue
	T destroy

	if {$sub ne $path} {
	    #set sub [fileutil::stripPath $path $sub]
	    display [color note "Found actual buildpack in $sub"]
	}

	debug.cmd/buildpacks {==> $sub}
	return $sub
    }
    T destroy
    err "Expected a buildpack, did not find bin/compile under $path"
}

proc ::stackato::cmd::buildpacks::Rewrite {zv tv zpath prefix} {
    debug.cmd/buildpacks {}
    upvar 1 $zv zip $tv transient

    if {$prefix eq {}} return
    # Rewrite the incoming zip file to strip the prefix from all paths.

    display "Strip path prefix \"$prefix\" ... " false

    set tmpdir [fileutil::tempfile stackato-buildpack-rewrite-]
    file delete $tmpdir
    file mkdir  $tmpdir

    zipfile::decode::unzipfile $zpath $tmpdir

    set zip [Pack $tmpdir/$prefix 0]
    if {$transient} {
	debug.cmd/buildpacks {Drop old tempfile $zpath}
	file delete $zpath
    }

    file delete -force $tmpdir
    set transient 1

    display [color good OK]
    debug.cmd/buildpacks {/done}
    return
}

proc ::stackato::cmd::buildpacks::ValidateZip {path} {
    debug.cmd/buildpacks {}

    zipfile::decode::open $path
    set zd [zipfile::decode::archive]
    set f  [dict get $zd files]
    zipfile::decode::close

    dict for {fname data} $f {
	if {$fname eq "bin/compile"} {
	    return [::list $path {}]
	}
	if {[regexp {^(.*)/bin/compile$} $fname -> prefix]} {
	    return [::list $path $prefix]
	}
    }

    err "Expected a buildpack, did not find bin/compile inside $path"
}

proc ::stackato::cmd::buildpacks::Pack {path {log 1}} {
    debug.cmd/buildpacks {}

    if {$log} { display "Packing directory \"[color name $path]\" ... " false }

    set z [zipfile::encode Z]
    foreach f [GetFilesToPack $path] {
	if {$log} { again+ $f }

	debug.cmd/buildpacks {++ $f}
	$z file: $f 0 $path/$f
    }

    set zipfile [BPTmp]

    debug.cmd/buildpacks {Tmp = $zipfile}
    debug.cmd/buildpacks {write zip...}

    $z write $zipfile
    $z destroy

    if {$log} {
	again+ {}
	display [color good OK]
	clearlast
    }

    debug.cmd/buildpacks {...done}
    return $zipfile
}

proc ::stackato::cmd::buildpacks::GetFilesToPack {path} {
    debug.cmd/buildpacks {}
    return [struct::list map [fileutil::find $path {file exists}] [lambda {p x} {
	fileutil::stripPath $p $x
    } $path]]
}

proc ::stackato::cmd::buildpacks::GetArchive {client transient path} {
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

    return [::list $transient $path]
}

proc ::stackato::cmd::buildpacks::BPTmp {} {
    # Note: We add the .zip extension to the file because the
    # receiving code of the CF target validates a archive by its
    # extension, not by its magic. No .zip => fail.

    set tmp [fileutil::tempfile stackato-buildpack-]
    file delete $tmp
    append tmp .zip

    return $tmp
}

proc ::stackato::cmd::buildpacks::GetUrl {client url err} {
    set tmp [BPTmp]
    debug.cmd/buildpacks {Tmp = $tmp}

    display "Downloading [color name $url]"

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
	debug.cmd/buildpacks {Closing $chan /err}
	close $chan

	# On windows delay between close and deletion to allow the OS
	# to settle and update the file's permissions.
	if {$::tcl_platform(platform) eq "windows"} {
	    after 1000
	}

	debug.cmd/buildpacks {Remove $tmp}
	# Ensure removal of the now unused tempfile
	file delete $tmp
	debug.cmd/buildpacks {Tmp exists = [file exists $tmp]}

	# Note: Exposes constructed url
	#err "Unable to retrieve $url: $e"
	err $err
    } finally {
	# Restore original state (cf auth, no redirections).
	$client configure -follow-redirections $saved -headers $hdrs \
	    -rblocksize {} -rprogress {} -channel {}
    }

    display " [color green OK]"
    clearlast

    debug.cmd/buildpacks {Closing $chan /ok}
    close $chan

    debug.cmd/buildpacks {/done}
    return [::list 1 $tmp]
}

proc ::stackato::cmd::buildpacks::Progress {token total n} {
    # This code assumes that the last say* was the prefix
    # of the upload progress display.

    # This may happen for a bad url.
    if {$total eq {}} {
	set p {}
	set total ??
    } else {
	set p "[expr {$n*100/$total}]% "
    }
    again+ "${p}($n/$total)"
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

    display "Renaming buildpack \[[color name $old]\] to '[color name $new]' ... " false
    $buildpack commit
    display [color good OK]
    return
}

proc ::stackato::cmd::buildpacks::lock {config} {
    debug.cmd/buildpacks {}

    set buildpack [$config @name]

    $buildpack @locked set 1

    display "Locking buildpack \[[color name [$buildpack @name]]\] ... " false
    $buildpack commit
    display [color good OK]
    return
}

proc ::stackato::cmd::buildpacks::unlock {config} {
    debug.cmd/buildpacks {}

    set buildpack [$config @name]

    $buildpack @locked set 0

    display "Unlocking buildpack \[[color name [$buildpack @name]]\] ... " false
    $buildpack commit
    display [color good OK]
    return
}

proc ::stackato::cmd::buildpacks::update {config} {
    debug.cmd/buildpacks {}

    set buildpack [$config @name]
    debug.cmd/buildpacks {buildpack = $buildpack ([$buildpack @name])}

    display "Updating buildpack \[[color name [$buildpack @name]]\] ..."

    set changes 0
    foreach {attr label} {
	@position {Position}
	@enabled  {Enabled }
	@locked   {Locked  }
    } {
	display "  $label ... " false
	if {![$config $attr set?]} {
	    display [color note Unchanged]
	    continue
	}
	display "Changed to [$config $attr]"
	$buildpack $attr set [$config $attr]
	incr changes
    }

    if {$changes} {
	$buildpack commit
	display [color good OK]
    }

    if {[$config @zip set?]} {
	set zip       [$config @zip]
	set transient 0
	set fname [Name $zip]

	try {
	    Ingest $config zip transient

	    display "Uploading new buildpack bits ([color name $fname]) ... " false
	    Keeping $config $zip $buildpack
	    $buildpack upload! $zip $fname
	    display [color good OK]

	} finally {
	    if {$transient} {
		debug.cmd/buildpacks {deleting $zip}
		file delete $zip
	    }
	}
    }
    return
}

proc ::stackato::cmd::buildpacks::delete {config} {
    debug.cmd/buildpacks {}
    # @name - buildpack name

    set buildpack [$config @name]
    debug.cmd/buildpacks {buildpack = $buildpack ([$buildpack @name])}

    if {[cmdr interactive?] &&
	![ask yn \
	      "\nReally delete \"[$buildpack @name]\" ? " \
	      no]} return

    $buildpack delete

    display "Deleting buildpack [color name [$buildpack @name]] ... " false
    $buildpack commit
    display [color good OK]
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::buildpacks::list {config} {
    debug.cmd/buildpacks {}
    # No arguments.

    if {![$config @json]} {
	display "\nBuildpacks: [context format-target]"
    }

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

    if {![llength $buildpacks]} {
	display [color note "No buildpacks"]
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
		[color name [$buildpack @name]] \
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
	display "Choosing the one available buildpack: \"[color name [$newpack @name]]\""
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
    ::set name [ask menu "" \
		    "Which buildpack to $what ? " \
		    $choices]

    return [dict get $map $name]
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::buildpacks 0

