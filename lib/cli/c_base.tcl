# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require stackato::color
package require stackato::client::cli::config
package require stackato::client::cli::manifest
package require stackato::client
package require dictutil

namespace eval ::stackato::client::cli::command::Base {}

debug level  cli/base
debug prefix cli/base {[::debug::snit::call] | }

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::client::cli::command::Base {
    # # ## ### ##### ######## #############

    constructor {args} {
	Debug.cli/base {}

        set myoptions $args

	set mynoprompt   [dict get $myoptions noprompts]
	set mypromptok   [expr {!$mynoprompt}]

	# Caches
	set myclient     {} ;# object command
	set myclientinfo {} ;# dict
	set mytargeturl  {} ;# string
	set myauthtoken  {} ;# string
	set myruntimes   {} ;# dict
	set myframeworks {} ;# list
	set mygroup      {} ;# string
	set mygroupcached 0 ;# boolean

        # Fix for system ruby and Highline (stdin) on MacOSX
        #if RUBY_PLATFORM =~ /darwin/ && RUBY_VERSION == '1.8.7' && RUBY_PATCHLEVEL <= 174
        #  HighLine.track_eof = false
        #end

	# Namespace import, sort of.
	namespace path [linsert [namespace path] end \
			    ::stackato ::stackato::client::cli]

        # Suppress colorize on Windows systems for now.
        #if !!RUBY_PLATFORM['mingw'] || !!RUBY_PLATFORM['mswin32'] || !!RUBY_PLATFORM['cygwin']
        #  VMC::Cli::Config.colorize = false
        #end

	if {$::tcl_platform(platform) eq "windows"} {
	    color colorize 0
	}
	return
    }

    destructor {
	Debug.cli/base {}
	if {$myclient eq {}} return
	$myclient destroy
	return
    }

    # # ## ### ##### ######## #############
    ## API

    method options {} { return $myoptions }

    method promptok {} { return $mypromptok }

    method client-reset {} {
	set myauthtoken {}
	set myclient {}
	set mygroup {}
	return
    }

    method client {{client {}}} {
	Debug.cli/base {}
	if {$client ne {}} {
	    set myclient $client
	}
	if {$myclient ne {}} { return $myclient }

	set myclient [stackato::client new \
			  [my target_url] \
			  [my auth_token]]

	if {[config trace] ne {}} {
	    $myclient trace [config trace]
	}
	#checker -scope line exclude badOption
	if {[llength [dict get' $myoptions proxy {}]]} {
	    $myclient proxy_for [dict get $myoptions proxy]
	}

	return $myclient
    }

    method client_info {} {
	Debug.cli/base {}
	if {$myclientinfo ne {}} { return $myclientinfo }

	Debug.cli/base {Retrieve client information}
	set myclientinfo [[my client] info]
	return $myclientinfo
    }

    method clientinfo_reset {} {
	Debug.cli/base {}
	set myclientinfo {}
	[my client] info_reset
	return
    }

    method target_url {} {
	Debug.cli/base {}
	if {$mytargeturl ne {}} {
	    Debug.cli/base {Cached target = $mytargeturl}
	    return $mytargeturl
	}

	if {[dict exists $myoptions target]} {
	    Debug.cli/base {Read target from options}
	    set mytargeturl [config urlcanon [dict get $myoptions target]]
	    # Bug 94092. Make the config system aware of our choice so
	    # that it will not save data based on the configured
	    # target but the actual one, where it matters (login, for
	    # example).
	    config target! $mytargeturl
	} else {
	    Debug.cli/base {Read target from file}
	    set mytargeturl [config target_url]
	}

	Debug.cli/base {Target = $mytargeturl}
	return $mytargeturl
    }

    method confer-group {{check 1}} {
	Debug.cli/base {}
	if {$check} { my CheckLogin }
	[my client] group [my group]
	# Squash client information we got without a group set.
	my clientinfo_reset
	return
    }

    method no-group {} {
	Debug.cli/base {}
	$myclient group {}
	return
    }

    method group {} {
	Debug.cli/base {}
	if {$mygroupcached} {
	    Debug.cli/base {Cached group = $mygroup}
	    return $mygroup
	}

	if {[dict exists $myoptions group]} {
	    Debug.cli/base {Read group from options}
	    set group [dict get $myoptions group]
	    set persistent 0
	} else {
	    Debug.cli/base {Read group from file}
	    set group [config group]
	    set persistent 1
	}

	Debug.cli/base {Group   = $group}
	Debug.cli/base {Persist = $persistent}

	# Check validity, only if actually set, and if not forced to
	# use anyway.
	if {![dict exists $myoptions debug-group] &&
	    ($group ne {}) &&
	    ($group ni [my TheUsersGroups])} {
	    say [color red "Error: Current group \[$group\] is not known to the target."]
	    if {$persistent} {
		say "Run \"[usage::me] group reset\" or \"[usage::me] group <name>\" to re-enable regular operation."
	    }
	    ::exit 1
	}

	set mygroup $group
	set mygroupcached 1
	return $mygroup
    }

    method TheUsersGroups {} {
	set cinfo [my client_info]
	if {![dict exists $cinfo user]} { return {} }

	Debug.cli/base {[array set ci $cinfo][parray ci][unset ci]}

	if {[dict exists $cinfo admin] &&
	    [dict get    $cinfo admin]} {
	    set groups [dict get $cinfo all_groups]
	} else {
	    set groups [dict get $cinfo groups]
	}
	return $groups
    }

    method auth_token {} {
	Debug.cli/base {}
	if {$myauthtoken ne {}} { return $myauthtoken }

	if {[dict exists $myoptions token_value]} {
	    Debug.cli/base {Read auth token from command line}

	    set myauthtoken [dict get $myoptions token_value]
	} elseif {[dict exists $myoptions token_file]} {
	    Debug.cli/base {Read auth token from custom file}

	    set myauthtoken \
		[config auth_token \
		     [dict get $myoptions token_file]]
	} else {
	    Debug.cli/base {Read auth token from standard file}

	    set myauthtoken [config auth_token]
	}
	return $myauthtoken
    }

    method runtimes_info {} {
	Debug.cli/base {}
	if {$myruntimes ne {}} { return $myruntimes }

	set info [my client_info]

	Debug.cli/base {Compute runtimes}
	set myruntimes {}
	if {[dict exists $info frameworks]} {
	    foreach f [dict values [dict get $info frameworks]] {
		if {![dict exists $f runtimes]} continue
		foreach r [dict get $f runtimes] {
		    dict set myruntimes [dict getit $r name] $r
		}

	    }
	}

	#checker -scope line exclude badOption
	set myruntimes [dict sort $myruntimes]
	return $myruntimes
	#@type = dict (<name> -> dict)
    }

    method frameworks_info {} {
	Debug.cli/base {}
	if {$myframeworks ne {}} { return $myframeworks }
	set info [my client_info]

	Debug.cli/base {ci = [jmap clientinfo $info]}

	Debug.cli/base {Compute frameworks}
	set myframeworks {}

	if {[dict exists $info frameworks]} {
	    set fw [dict get $info frameworks]
	    Debug.cli/base {fw = [jmap fwinfo $fw]}

	    foreach f [dict values $fw] {
		Debug.cli/base {** $f}
		set name [dict getit $f name]
		set subf [dict get'  $f sub_frameworks {}]
		lappend myframeworks $name $subf
	    }
	}

	set myframeworks [dict sort $myframeworks]
	return $myframeworks
	#@type = list(string)
    }

    # # ## ### ##### ######## #############
    ## Internal commands.

    method CheckLogin {} {
	Debug.cli/base {}

	if {[[my client] logged_in?]} return
	::stackato::client::AuthError
	return
    }

    method GenerateJson {} {
	return [dict get [my options] json]
    }

    method ServerVersion {} {
	Debug.cli/services/support {}

	set v [dict get' [[my client] info] vendor_version 0.0]
	regsub -- {-g.*$} $v {} v
	set v [string map {v {} - .} $v]
	return $v
    }

    method ValidateOptions {legal {script {}}} {
	set illegal [my CheckOptions $legal]
	if {[llength $illegal]} {
	    set v "Options not recognized here: [join [lsort -dict $illegal] {, }]"
	    if {$script ne {}} {
		set text [uplevel 1 $script]
		if {$text ne {}} {
		    append v \n$text
		}
	    }
	    return -code error -errorcode {OPTION INVALID} $v
	}
    }

    method CheckOptions {legal} {
	set illegal {}
	foreach specified [dict get' [my options] __options {}] {
	    if {$specified in $legal} continue
	    lappend illegal $specified
	}
	return $illegal
    }

    method appself {} {
	variable ::stackato::client::cli::usage::wrapped
	set noe [info nameofexecutable]
	if {$wrapped} {
	    return [list $noe]
	} else {
	    global argv0
	    return [list $noe $argv0]
	}
    }

    # # ## ### ##### ######## #############
    ## State

    variable myoptions mynoprompt mypromptok \
	     myclient myclientinfo mytargeturl \
	     myauthtoken mygroup mygroupcached \
	     myruntimes myframeworks

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::client::cli::command::Base 0
