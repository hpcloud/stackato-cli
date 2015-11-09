# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## This module manages the mapping from service vendor to standard
## tunnel clients.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require fileutil
package require tclyaml
package require stackato::mgr::cfile
package require stackato::mgr::self

namespace eval ::stackato::mgr {
    namespace export tclients
    namespace ensemble create
}

namespace eval ::stackato::mgr::tclients {
    namespace export get
    namespace ensemble create

    namespace import ::stackato::mgr::cfile
    namespace import ::stackato::mgr::self
}

debug level  mgr/tclients
debug prefix mgr/tclients {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## API

proc ::stackato::mgr::tclients::get {} {
    debug.mgr/tclients {}
    variable clients

    if {[llength $clients]} { return $clients }
    variable stockclients

    set clients_file [cfile get clients]

    if {[lindex [file system $stockclients] 0] ne "native"} {
	# Work around tclyaml issue with virtual files by
	# copying it to the disk and reading from there.

	set tmp [fileutil::tempfile stackato_stockclients_]
	file copy -force -- $stockclients $tmp

	set stock [lindex [tclyaml readTags file $tmp] 0 0]

	file delete -force -- $tmp

    } else {
	set stock [lindex [tclyaml readTags file $stockclients] 0 0]
    }

    set stock [stackato::yaml strip-mapping-key-tags $stock]

    debug.mgr/tclients {= STOCK ============================================}
    debug.mgr/tclients {[stackato::yaml dump-retag $stock]}
    debug.mgr/tclients {====================================================}

    if {[file exists $clients_file]} {
	set user [lindex [tclyaml readTags file $clients_file] 0 0]
	set user [stackato::yaml strip-mapping-key-tags $user]

	debug.mgr/tclients {= USER =============================================}
	debug.mgr/tclients {[stackato::yaml dump-retag $user]}
	debug.mgr/tclients {====================================================}

	# Merge user and stock. Data has 2 levels. service type, under
	# which we have named clients mapping to their command line,
	# or dict of command line and environment.

	set clients [stackato::yaml deep-merge $user $stock]
    } else {
	set clients $stock
    }

    debug.mgr/tclients {= MERGED ===========================================}
    debug.mgr/tclients {[stackato::yaml dump-retag $clients]}
    debug.mgr/tclients {====================================================}

    # Normalize the information in two steps.
    # 1. Ensure that everything has a nested definition with 'command' key.
    # 2. If the first workd of the command is the name of the key, remove
    #    it. This allows us to use old and new clients.yaml files.

    set clients [NormStructure $clients]
    set clients [NormCommands  $clients]

    debug.mgr/tclients {= NORMALIZED =======================================}
    debug.mgr/tclients {[stackato::yaml dump-retag $clients]}
    debug.mgr/tclients {====================================================}

    # Convert to a full Tcl nested dictionary, for more convenient
    # access by our users.
    return [stackato::yaml strip-tags $clients]
}

proc ::stackato::mgr::tclients::NormStructure {clients} {
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

proc ::stackato::mgr::tclients::NormCommands {clients} {
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

# # ## ### ##### ######## ############# #####################
## State

namespace eval ::stackato::mgr::tclients {
    variable clients      {}
    variable stockclients [file join [self topdir] config clients.yml]
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::tclients 0
