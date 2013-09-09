# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

## This module manages the set of command aliases/shortcuts defined by
## the cli user.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require fileutil
package require stackato::yaml
package require stackato::mgr::cfile

namespace eval ::stackato::mgr {
    namespace export alias
    namespace ensemble create
}
namespace eval ::stackato::mgr::alias {
    namespace export \
	has add remove known store
    namespace ensemble create

    namespace import ::stackato::mgr::cfile
}

debug level  mgr/alias
debug prefix mgr/alias {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## API for the user visible commands.

proc ::stackato::mgr::alias::has {key} {
    debug.mgr/alias {}
    return [dict exists [known] $key]
}

proc ::stackato::mgr::alias::add {key cmdprefix} {
    debug.mgr/alias {}

    set aliases [known] ;#dict
    dict set aliases $key $cmdprefix
    Store $aliases
    return
}

proc ::stackato::mgr::alias::remove {key} {
    debug.mgr/alias {}

    set aliases [known] ;#dict
    dict unset aliases $key
    Store $aliases
    return
}

# # ## ### ##### ######## ############# #####################
## Low level access to the client's persistent state for aliases.

proc ::stackato::mgr::alias::known {} {
    debug.mgr/alias {}

    set aliases_file [cfile get aliases]

    # @todo@ aliases - cache yaml parse result ?

    try {
	return [lindex [tclyaml read file $aliases_file] 0 0]
    } on error {e o} {
	debug.mgr/alias {@E = '$e'}
	debug.mgr/alias {@O = ($o)}
	return {}
    }
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::alias::Store {aliases} {
    debug.mgr/alias {}
    # aliases = dict, cmd -> true command.

    set aliases_file [cfile get aliases]

    file mkdir [file dirname $aliases_file]
    tclyaml write file {
	dict
    } $aliases_file $aliases
    return
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::mgr::alias {}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::alias 0
