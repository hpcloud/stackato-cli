# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

#checker -scope global exclude warnUndefinedVar
# var in question is 'dir'.
if {![package vsatisfies [package provide Tcl] 8.5]} {
    # PRAGMA: returnok
    return
}

# Management of various in-memory structures.
package ifneeded stackato::mgr::alias                 0 [list source [file join $dir alias.tcl]]
package ifneeded stackato::mgr::app                   0 [list source [file join $dir app.tcl]]
package ifneeded stackato::mgr::auth                  0 [list source [file join $dir auth.tcl]]
package ifneeded stackato::mgr::cfile                 0 [list source [file join $dir cfile.tcl]]
package ifneeded stackato::mgr::cgroup                0 [list source [file join $dir cgroup.tcl]]
package ifneeded stackato::mgr::client                0 [list source [file join $dir client.tcl]]
package ifneeded stackato::mgr::context               0 [list source [file join $dir context.tcl]]
package ifneeded stackato::mgr::corg                  0 [list source [file join $dir corg.tcl]]
package ifneeded stackato::mgr::cspace                0 [list source [file join $dir cspace.tcl]]
package ifneeded stackato::mgr::ctarget               0 [list source [file join $dir ctarget.tcl]]
package ifneeded stackato::mgr::exit                  0 [list source [file join $dir exit.tcl]]
package ifneeded stackato::mgr::framework             0 [list source [file join $dir framework.tcl]]
package ifneeded stackato::mgr::framework::base       0 [list source [file join $dir framework_base.tcl]]
package ifneeded stackato::mgr::framework::sabase     0 [list source [file join $dir framework_sabase.tcl]]
package ifneeded stackato::mgr::framework::standalone 0 [list source [file join $dir framework_standalone.tcl]]
package ifneeded stackato::mgr::instmap               0 [list source [file join $dir instmap.tcl]]
package ifneeded stackato::mgr::logstream             0 [list source [file join $dir logstream.tcl]]
package ifneeded stackato::mgr::manifest              0 [list source [file join $dir manifest.tcl]]
package ifneeded stackato::mgr::self                  0 [list source [file join $dir self.tcl]]
package ifneeded stackato::mgr::service               0 [list source [file join $dir service.tcl]]
package ifneeded stackato::mgr::ssh                   0 [list source [file join $dir ssh.tcl]]
package ifneeded stackato::mgr::tadjunct              0 [list source [file join $dir tadjuncts.tcl]]
package ifneeded stackato::mgr::targets               0 [list source [file join $dir targets.tcl]]
package ifneeded stackato::mgr::tclients              0 [list source [file join $dir tclients.tcl]]
package ifneeded stackato::mgr::tunnel                0 [list source [file join $dir tunnel.tcl]]
package ifneeded stackato::mgr::ws                    0 [list source [file join $dir ws.tcl]]
