# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require fileutil
package require json
package require stackato::jmap
package require stackato::yaml

namespace eval ::stackato::client::cli::config {}

debug level  config
debug prefix config {[::debug::snit::call] | }

# # ## ### ##### ######## ############# #####################

proc ::stackato::client::cli::config::fulltrap {} {
    global tcl_platform

    if {$tcl_platform(platform) eq "windows"} {
	signal trap {TERM INT} {
	    if {[catch {
		::stackato::log::say! "\nInterrupted\n"
		::exec::clear
		exit 1
	    }]} {
		# A problem here indicates that the user managed to
		# trigger ^C while we in a child interp. Throw it as
		# regular error to be caught and processed in cli.tcl
		error Interrupted error SIGTERM
	    }
	}
    } else {
	signal -restart trap {TERM INT} {
	    if {[catch {
		::stackato::log::say! "\nInterrupted\n"
		::exec::clear
		exit 1
	    }]} {
		# A problem here indicates that the user managed to
		# trigger ^C while we in a child interp. Throw it as
		# regular error to be caught and processed in cli.tcl
		error Interrupted error SIGTERM
	    }
	}
    }
}

proc ::stackato::client::cli::config::smalltrap {} {
    # Only for logging (fastlogsit) --follow.
    # At that point we have no child interps, so we can call on
    # various things without fear of them undefined (which can happen
    # for the fulltrap, if interupted during cmdclass load and setup).

    global tcl_platform

    if {$tcl_platform(platform) eq "windows"} {
	signal trap {TERM INT} {
	    ::exec::clear
	    exit 1
	}
    } else {
	signal -restart trap {TERM INT} {
	    ::exec::clear
	    exit 1
	}
    }
}

proc ::stackato::client::cli::config::minmem {} {
    Debug.config {}
    variable minmem
    return $minmem
}

proc ::stackato::client::cli::config::nozip {{flag {}}} {
    Debug.config {}
    variable nozip
    if {[llength [info level 0]] == 2} {
	set nozip $flag
    }
    return $nozip
}

proc ::stackato::client::cli::config::trace {{flag {}}} {
    Debug.config {}
    variable trace
    if {[llength [info level 0]] == 2} {
	set trace $flag
    }
    return $trace
}

proc ::stackato::client::cli::config::allow-http {{flag {}}} {
    Debug.config {}
    variable allowhttp
    if {[llength [info level 0]] == 2} {
	set allowhttp $flag
    }
    return $allowhttp
}

proc ::stackato::client::cli::config::base_of {url} {
    return [join [lrange [split $url .] 1 end] .]
}

proc ::stackato::client::cli::config::suggest_url {} {
    Debug.config {}
    variable suggest_url
    if {$suggest_url ne {}} { return $suggest_url }
    set suggest_url [base_of [target_url]]
    return $suggest_url
}

proc ::stackato::client::cli::config::target_url {} {
    Debug.config {}
    variable target_url
    if {$target_url ne {}} { return $target_url }

    set target_file [configfile target]

    if {[fileutil::test $target_file efr]} {
	set target_url [string trim [fileutil::cat $target_file]]
    } else {
	variable default_target
	set target_url $default_target
    }

    return [urlcanon $target_url]
}

proc ::stackato::client::cli::config::target! {url} {
    Debug.config {}
    variable target_url $url
    return
}

proc ::stackato::client::cli::config::urlcanon {url} {
    Debug.config {}
    #checker -scope local exclude warnArgWrite
    if {![regexp {^https?} $url]} {
	set url https://$url
    }
    return [string trimright $url /]
}

proc ::stackato::client::cli::config::targets {} {
    return [all_tokens]
}

proc ::stackato::client::cli::config::store_target {target_host} {
    Debug.config {}

    set target_file [configfile target]

    fileutil::writeFile $target_file $target_host\n
    FixPermissions $target_file
    return
}

proc ::stackato::client::cli::config::all_tokens {{token_file {}}} {
    Debug.config {}

    if {$token_file eq {}} {
	set token_file [configfile token]
    }

    if {![fileutil::test $token_file efr]} {
	return {}
    }

    # @todo@ all_token - cache json parse result ?
    return [json::json2dict \
		[string trim \
		     [fileutil::cat $token_file]]]
}

proc ::stackato::client::cli::config::auth_token {args} {
    Debug.config {}
    variable token
    if {$token eq {}} {
	set tokens [all_tokens {*}$args]
	if {[llength $tokens]} {
	    #checker -scope line exclude badOption
	    set token [dict get' $tokens [target_url] {}]
	}
    }
    return $token
}

proc ::stackato::client::cli::config::remove_token_file {} {
    Debug.config {}

    set todelete [configfiles token]
    foreach stem [configfiles key] {
	lappend todelete {*}[glob -nocomplain ${stem}*]

    }
    file delete -- {*}$todelete
    return
}

proc ::stackato::client::cli::config::remove_token_for {target} {
    Debug.config {}

    set token_file [configfile token]
    set tokens [all_tokens $token_file]

    if {![dict exists $tokens $target]} {
	Debug.config {unknown target}
	stackato::log::err "Unable to log out of unknown target \[$target\]"
    }

    Debug.config {cleaning up}

    set thetoken [dict get $tokens $target]

    Debug.config {token = $thetoken}

    dict unset tokens $target

    Debug.config {dict = ($tokens)}

    fileutil::writeFile $token_file [stackato::jmap targets $tokens]\n
    FixPermissions $token_file

    set todelete {}
    foreach stem [configfiles key] {
	foreach kf [glob -nocomplain ${stem}*] {
	    Debug.config {candidate: $kf}
	    if {![string match key_${thetoken}* [file tail $kf]]} continue
	    Debug.config {schedule for delete: $kf}
	    lappend todelete $kf
	}
    }
    if {![llength $todelete]} return

    Debug.config {delete [join $todelete "\ndelete "]}

    file delete -- {*}$todelete
    return
}

proc ::stackato::client::cli::config::store_token {token {token_file {}} {sshkey {}}} {
    Debug.config {}
    variable target_url

    if {$token_file eq {}} {
	set token_file [configfile token]
    }

    set tokens [all_tokens $token_file]
    dict set tokens $target_url $token

    Debug.config {dict = ($tokens)}

    fileutil::writeFile $token_file [stackato::jmap targets $tokens]\n
    FixPermissions $token_file

    if {[llength [info level 0]] <= 3} return
    if {$sshkey eq {}} return
    # We have an ssh key. Save it as well.

    set keyfile [keyfile $token]
    fileutil::writeFile $keyfile $sshkey
    FixPermissions $keyfile
    return
}

proc ::stackato::client::cli::config::keyfile {token} {
    Debug.config {}
    return [configfile key _$token]
}

proc ::stackato::client::cli::config::instances {} {
    Debug.config {}

    set instances_file [configfile instances]

    if {![fileutil::test $instances_file efr]} {
	return {}
    }

    # @todo@ instances - cache json parse result ?
    return [json::json2dict \
		[string trim \
		     [fileutil::cat $instances_file]]]
}

proc ::stackato::client::cli::config::store_instances {instances} {
    Debug.config {}

    set instances_file [configfile instances]

    fileutil::writeFile $instances_file \
	[stackato::jmap instancemap $instances]
    return
}

proc ::stackato::client::cli::config::aliases {} {
    Debug.config {}

    set aliases_file [configfile aliases]

    # @todo@ aliases - cache yaml parse result ?

    try {
	return [lindex [tclyaml read file $aliases_file] 0 0]
    } on error {e o} {
	Debug.config {@E = '$e'}
	Debug.config {@O = ($o)}
	return {}
    }
}

proc ::stackato::client::cli::config::store_aliases {aliases} {
    Debug.config {}
    # aliases = dict, cmd -> true command.

    set aliases_file [configfile aliases]

    tclyaml write file {
	dict
    } $aliases_file $aliases
    return
}

proc ::stackato::client::cli::config::all_groups {} {
    Debug.config {}

    set group_file [configfile group]

    if {![fileutil::test $group_file efr]} {
	return {}
    }

    return [json::json2dict \
		[string trim \
		     [string trim [fileutil::cat $group_file]]]]
}

proc ::stackato::client::cli::config::group {} {
    Debug.config {}
    #checker -scope line exclude badOption
    return [dict get' [all_groups] [target_url] {}]
}

proc ::stackato::client::cli::config::store_group {group} {
    Debug.config {}

    set group_file [configfile group]

    set groups [all_groups]
    dict set groups [target_url] $group

    fileutil::writeFile $group_file [stackato::jmap tgroups $groups]\n
    FixPermissions      $group_file
    return
}

proc ::stackato::client::cli::config::reset_group {} {
    Debug.config {}

    set group_file [configfile group]

    set groups [all_groups]
    dict unset groups [target_url]

    fileutil::writeFile $group_file [stackato::jmap tgroups $groups]\n
    FixPermissions      $group_file
    return
}

proc ::stackato::client::cli::config::remove_group_file {} {
    Debug.config {}
    file delete -- [configfile group]
    return
}

proc ::stackato::client::cli::config::clients {} {
    Debug.config {}
    variable clients

    if {[llength $clients]} { return $clients }
    variable stockclients

    set clients_file [configfile clients]

    if {[lindex [file system $stockclients] 0] ne "native"} {
	# Work around tclyaml issue with virtual files by
	# copying it to the disk and reading from there.

	set tmp [fileutil::tempfile stackato_stockclients_]
	file copy -force $stockclients $tmp

	set stock [lindex [tclyaml readTags file $tmp] 0 0]

	file delete -force $tmp

    } else {
	set stock [lindex [tclyaml readTags file $stockclients] 0 0]
    }

    set stock [stackato::yaml stripMappingKeyTags $stock]

    Debug.config {= STOCK ============================================}
    Debug.config {[stackato::yaml dumpX $stock]}
    Debug.config {====================================================}

    if {[file exists $clients_file]} {
	set user [lindex [tclyaml readTags file $clients_file] 0 0]
	set user [stackato::yaml stripMappingKeyTags $user]

	Debug.config {= USER =============================================}
	Debug.config {[stackato::yaml dumpX $user]}
	Debug.config {====================================================}

	# Merge user and stock. Data has 2 levels. service type, under
	# which we have named clients mapping to their command line,
	# or dict of command line and environment.

	set clients [stackato::yaml deepMerge $user $stock]
    } else {
	set clients $stock
    }

    Debug.config {= MERGED ===========================================}
    Debug.config {[stackato::yaml dumpX $clients]}
    Debug.config {====================================================}

    # Normalize the information in two steps.
    # 1. Ensure that everything has a nested definition with 'command' key.
    # 2. If the first workd of the command is the name of the key, remove
    #    it. This allows us to use old and new clients.yaml files.

    set clients [NormStructure $clients]
    set clients [NormCommands  $clients]

    Debug.config {= NORMALIZED =======================================}
    Debug.config {[stackato::yaml dumpX $clients]}
    Debug.config {====================================================}

    # Convert to a full Tcl nested dictionary, for more convenient
    # access by our users.
    return [stackato::yaml stripTags $clients]
}

proc ::stackato::client::cli::config::NormStructure {clients} {
    set dict [stackato::yaml tag! mapping $clients {}]

    # normalize the structure of the yaml. Each tunnel command whose
    # definition is a plain scaler must be wrapped into a proper
    # sub-mapping with the command: key.

    dict for {vendor vdef} $dict {
	# vdef = mapping (cmd -> cmddef)
	set vdict [stackato::yaml tag! mapping $vdef {}]
	set changed 0
	dict for {cmd cdef} $vdict {
	    lassign [stackato::yaml tags! {scalar mapping} $cdef {}] tag value
	    if {$tag eq "scalar"} {
		# Put the command into a proper nested structure.
		dict set vdict $cmd [list mapping [list command [list scalar $value]]]
		set changed 1
	    }
	}
	if {$changed} {
	    dict set dict $vendor [list mapping $vdict]
	}
    }

    return [list mapping $dict]
}

proc ::stackato::client::cli::config::NormCommands {clients} {
    set dict [stackato::yaml tag! mapping $clients {}]

    # Normalize the command: value. If the first word matches the key
    # then this word has to be removed, and the data came from an
    # old-style clients file.

    dict for {vendor vdef} $dict {
	# vdef = mapping (cmd -> cmddef)
	set vdict [stackato::yaml tag! mapping $vdef {vendor def}]
	set changed 0
	dict for {cmd cdef} $vdict {
	    set cdict [stackato::yaml tag! mapping $cdef {command def}]

	    set tcmdline [dict get $cdict command]
	    set cmdline [stackato::yaml tag! scalar $tcmdline command]

	    if {$cmd eq [lindex $cmdline 0]} {
		set cmdline [lrange $cmdline 1 end]

		dict set cdict command [list scalar $cmdline]
		dict set vdict $cmd    [list mapping $cdict]
		set changed 1
	    }
	}
	if {$changed} {
	    dict set dict $vendor [list mapping $vdict]
	}
    }

    return [list mapping $dict]
}

proc ::stackato::client::cli::config::topdir {} {
    Debug.config {}
    variable topdir
    return $topdir
}

# # ## ### ##### ######## ############# #####################

if {$::tcl_platform(platform) eq "windows"} {
    #checker exclude warnRedefine
    proc ::stackato::client::cli::config::FixPermissions {path {mask_ignored {}}} {
	Debug.config {/windows}
	#checker exclude nonPortCmd
	file attribute $path -readonly 0
    }
} else {
    #checker exclude warnRedefine
    proc ::stackato::client::cli::config::FixPermissions {path {mask 0600}} {
	Debug.config {/unix}
	#checker exclude nonPortCmd
	file attribute $path -permissions $mask
    }
}

proc ::stackato::client::cli::config::configfiles {key} {
    Debug.config {}
    variable config
    return [dict get $config $key]
}

proc ::stackato::client::cli::config::configfile {key {suffix {}}} {
    Debug.config {}
    variable config

    # Search for the possible configuration files we maintain.
    set files [dict get $config $key]
    set first 1
    set found 0

    foreach f $files {
	set f $f$suffix
	if {![file exists $f]} { set first 0 ; continue }
	set found 1
	break
    }

    set ff [lindex $files 0]$suffix

    if {!$found} {
	# First in the list is the default we should write to.
	return $ff
    }

    # We found an older file. To shorten future searches we now copy
    # it over to the first, primary file to use. We do not delete the
    # older file tough, so that older clients may still have, although
    # the information may be outdated.

    if {!$first} {
	file mkdir [file dirname $ff]
	file copy -- $f $ff
    }

    # With the copy of the old file in place of the primary we can
    # always return the path to the primary file for reading (or
    # writing).

    return [file normalize $ff]
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::client::cli::config {
    variable minmem 20

    variable default_target api.stackato.local

    variable config {
	target    {~/.stackato/client/target    ~/.stackato/target    ~/.stackato_target   }
	token     {~/.stackato/client/token     ~/.stackato/token     ~/.stackato_token    }
	key       {~/.stackato/client/key       ~/.stackato/key       ~/.stackato_key      }
	instances {~/.stackato/client/instances ~/.stackato/instances ~/.stackato_instances}
	aliases   {~/.stackato/client/aliases   ~/.stackato/aliases   ~/.stackato_aliases ~/.stackato-aliases}
	clients   {~/.stackato/client/clients   ~/.stackato/clients   ~/.stackato_clients}
	group     {~/.stackato/client/group}
    }

    variable allowhttp   0
    variable trace       0
    variable nozip       0
    variable target_url  {}
    variable suggest_url {} ;# read-only
    variable clients     {}
    variable group       {}

    variable self   [file normalize [info script]]
    variable topdir [file dirname [file dirname [file dirname $self]]]

    variable stockclients [file join $topdir config clients.yml]

    variable work_dir [pwd]
    variable token    {}

    namespace export \
	minmem nozip trace allow-http clients group store_group \
	suggest_url target_url store_target keyfile target! \
	all_tokens auth_token remove_token_file store_token \
	instances store_instances targets base_of reset_group \
	aliases store_aliases urlcanon topdir remove_group_file \
	remove_token_for fulltrap smalltrap

    namespace ensemble create
}

# Normalize the ~ in the paths, to show full paths in debug output.
apply {{} {
    variable config
    set newc {}
    foreach {k v} $config {
	set new {}
	foreach path $v {
	    lappend new [file normalize $path]
	}
	lappend newc $k $new
    }
    set config $newc

} ::stackato::client::cli::config}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::client::cli::config 0
