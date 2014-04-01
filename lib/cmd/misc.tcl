# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations. Miscellaneous things, mainly for
## debugging.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require fileutil
package require linenoise
package require try
package require stackato::mgr::self

debug level  cmd/misc
debug prefix cmd/misc {[debug caller] | }

namespace eval ::stackato::cmd {
    namespace export misc
    namespace ensemble create
}
namespace eval ::stackato::cmd::misc {
    namespace export columns home revision version chan-config
    namespace ensemble create

    namespace import ::stackato::mgr::self
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::misc::chan-config {chan _config} {
    array set config [fconfigure $chan]
    parray config
    return
}

proc ::stackato::cmd::misc::columns {config} {
    # (cmdr::)config ignored
    debug.cmd/misc {}

    puts [linenoise columns]
    return
}

proc ::stackato::cmd::misc::home {config} {
    # (cmdr::)config ignored
    debug.cmd/misc {}

    catch { puts "STACKATO_APP_ROOT=$::env(STACKATO_APP_ROOT)" }
    puts "HOME=             $::env(HOME)"
    puts "~=                [file normalize ~]"
    return
}

proc ::stackato::cmd::misc::revision {config} {
    # (cmdr::)config ignored
    debug.cmd/misc {}
    puts [self revision]
    return
}

proc ::stackato::cmd::misc::version {config} {
    # (cmdr::)config ignored
    debug.cmd/misc {}
    puts "[self me] [package present stackato::cmdr] ([self plain-revision])"
    return
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::misc 0

