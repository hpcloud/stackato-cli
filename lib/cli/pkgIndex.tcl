# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################
#checker -scope global exclude warnUndefinedVar
# var in question is 'dir'.
if {![package vsatisfies [package provide Tcl] 8.5]} {
    # PRAGMA: returnok
    return
}

# The version number of "stackato::client::cli" below is the release
# version number reported for stackato, the client app.  The internal
# STACKATO version number is coded as the version of package
# "stackato::client", see the sibling directory 'client'.

#                   Vendor (VMC) version tracked: 0.3.14.
package ifneeded stackato::client::cli                        1.7.1 [list source [file join $dir cli.tcl]]
package ifneeded stackato::client::cli::usage                 0     [list source [file join $dir usage.tcl]]
package ifneeded stackato::client::cli::config                0     [list source [file join $dir config.tcl]]
package ifneeded stackato::client::cli::framework             0     [list source [file join $dir framework.tcl]]
package ifneeded stackato::client::cli::framework::base       0     [list source [file join $dir framework_base.tcl]]
package ifneeded stackato::client::cli::framework::standalone 0     [list source [file join $dir framework_standalone.tcl]]
package ifneeded stackato::client::cli::framework::sabase     0     [list source [file join $dir framework_sabase.tcl]]
package ifneeded stackato::client::cli::manifest              0     [list source [file join $dir manifest.tcl]]

# Command implementations.
package ifneeded stackato::client::cli::command::Base         0 [list source [file join $dir c_base.tcl]]
package ifneeded stackato::client::cli::command::Misc         0 [list source [file join $dir c_misc.tcl]]
package ifneeded stackato::client::cli::command::User         0 [list source [file join $dir c_user.tcl]]
package ifneeded stackato::client::cli::command::Admin        0 [list source [file join $dir c_admin.tcl]]
package ifneeded stackato::client::cli::command::Apps         0 [list source [file join $dir c_apps.tcl]]
package ifneeded stackato::client::cli::command::Services     0 [list source [file join $dir c_services.tcl]]
package ifneeded stackato::client::cli::command::ServiceHelp  0 [list source [file join $dir c_svchelp.tcl]]
package ifneeded stackato::client::cli::command::TunnelHelp   0 [list source [file join $dir c_tunhelp.tcl]]
package ifneeded stackato::client::cli::command::MemHelp      0 [list source [file join $dir memhelp.tcl]]
package ifneeded stackato::client::cli::command::ManifestHelp 0 [list source [file join $dir manihelp.tcl]]
package ifneeded stackato::client::cli::command::LogStream    0 [list source [file join $dir tail.tcl]]
