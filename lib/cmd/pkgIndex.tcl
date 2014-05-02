#checker -scope global exclude warnUndefinedVar
# var in question is 'dir'.
if {![package vsatisfies [package provide Tcl] 8.5]} {
    # PRAGMA: returnok
    return
}

# The version number of "stackato::client::cli" below is the release
# version number reported for stackato, the client app.  The internal
# STACKATO version number is coded as the version of package
# "stackato::cmdr"

package ifneeded stackato::cmd::admin         0        [list source [file join $dir admin.tcl]]
package ifneeded stackato::cmd::alias         0        [list source [file join $dir alias.tcl]]
package ifneeded stackato::cmd::app           0        [list source [file join $dir app.tcl]]
package ifneeded stackato::cmd::buildpacks    0        [list source [file join $dir buildpacks.tcl]]
package ifneeded stackato::cmd::cgroup        0        [list source [file join $dir cgroup.tcl]]
package ifneeded stackato::cmd::do            0        [list source [file join $dir do.tcl]]
package ifneeded stackato::cmd::domains       0        [list source [file join $dir domains.tcl]]
package ifneeded stackato::cmd::groups        0        [list source [file join $dir groups.tcl]]
#package ifneeded stackato::cmd::host          0        [list source [file join $dir host.tcl]]
package ifneeded stackato::cmd::misc          0        [list source [file join $dir misc.tcl]]
package ifneeded stackato::cmd::orgs          0        [list source [file join $dir orgs.tcl]]
package ifneeded stackato::cmd::query         0        [list source [file join $dir query.tcl]]
package ifneeded stackato::cmd::quotas        0        [list source [file join $dir quotas.tcl]]
package ifneeded stackato::cmd::routes        0        [list source [file join $dir routes.tcl]]
package ifneeded stackato::cmd::scp           0        [list source [file join $dir scp.tcl]]
package ifneeded stackato::cmd::serviceauth   0        [list source [file join $dir serviceauth.tcl]]
package ifneeded stackato::cmd::servicebroker 0        [list source [file join $dir servicebroker.tcl]]
package ifneeded stackato::cmd::servicemgr    0        [list source [file join $dir servicemgr.tcl]]
package ifneeded stackato::cmd::spaces        0        [list source [file join $dir spaces.tcl]]
package ifneeded stackato::cmd::target        0        [list source [file join $dir target.tcl]]
package ifneeded stackato::cmd::usermgr       0        [list source [file join $dir usermgr.tcl]]
package ifneeded stackato::cmd::zones         0        [list source [file join $dir zones.tcl]]
package ifneeded stackato::cmdr               3.0.8    [list source [file join $dir cmdr.tcl]]
