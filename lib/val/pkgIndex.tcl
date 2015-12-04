# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

#checker -scope global exclude warnUndefinedVar
# var in question is 'dir'.
if {![package vsatisfies [package provide Tcl] 8.5]} {
    # PRAGMA: returnok
    return
}

# Custom validation types
package ifneeded stackato::validate::alias               0 [list source [file join $dir alias.tcl]]
package ifneeded stackato::validate::appname             0 [list source [file join $dir appname.tcl]]
package ifneeded stackato::validate::appname-api         0 [list source [file join $dir appname-api.tcl]]
package ifneeded stackato::validate::appname-dot         0 [list source [file join $dir appname-dot.tcl]]
package ifneeded stackato::validate::appname-lex         0 [list source [file join $dir appname-lex.tcl]]
package ifneeded stackato::validate::approute            0 [list source [file join $dir approute.tcl]]
package ifneeded stackato::validate::appversion          0 [list source [file join $dir appversion.tcl]]
package ifneeded stackato::validate::buildpack           0 [list source [file join $dir buildpack.tcl]]
package ifneeded stackato::validate::colormode           0 [list source [file join $dir colormode.tcl]]
package ifneeded stackato::validate::debug               0 [list source [file join $dir debug.tcl]]
package ifneeded stackato::validate::entity              0 [list source [file join $dir entities.tcl]]
package ifneeded stackato::validate::envassign           0 [list source [file join $dir envassign.tcl]]
package ifneeded stackato::validate::envmode             0 [list source [file join $dir envmode.tcl]]
package ifneeded stackato::validate::featureflag         0 [list source [file join $dir featureflag.tcl]]
package ifneeded stackato::validate::hostport            0 [list source [file join $dir hostport.tcl]]
package ifneeded stackato::validate::http-header         0 [list source [file join $dir httpheader.tcl]]
package ifneeded stackato::validate::http-operation      0 [list source [file join $dir httpop.tcl]]
package ifneeded stackato::validate::instance            0 [list source [file join $dir instance.tcl]]
package ifneeded stackato::validate::integer0            0 [list source [file join $dir integer0.tcl]]
package ifneeded stackato::validate::integer1            0 [list source [file join $dir integer1.tcl]]
package ifneeded stackato::validate::interval            0 [list source [file join $dir interval.tcl]]
package ifneeded stackato::validate::intervalornone      0 [list source [file join $dir intervalornone.tcl]]
package ifneeded stackato::validate::memspec             0 [list source [file join $dir memspec.tcl]]
package ifneeded stackato::validate::memspecplus         0 [list source [file join $dir memspecplus.tcl]]
package ifneeded stackato::validate::notappname          0 [list source [file join $dir notappname.tcl]]
package ifneeded stackato::validate::notbuildpack        0 [list source [file join $dir notbuildpack.tcl]]
package ifneeded stackato::validate::notclicmd           0 [list source [file join $dir notclicmd.tcl]]
package ifneeded stackato::validate::notorgname          0 [list source [file join $dir notorgname.tcl]]
package ifneeded stackato::validate::notquotaname        0 [list source [file join $dir notquotaname.tcl]]
package ifneeded stackato::validate::notsecuritygroup    0 [list source [file join $dir notsecgroup.tcl]]
package ifneeded stackato::validate::notserviceauthtoken 0 [list source [file join $dir notserviceauthtoken.tcl]]
package ifneeded stackato::validate::notservicebroker    0 [list source [file join $dir notservicebroker.tcl]]
package ifneeded stackato::validate::notserviceinstance  0 [list source [file join $dir notserviceinstance.tcl]]
package ifneeded stackato::validate::notserviceplan      0 [list source [file join $dir notserviceplan.tcl]]
package ifneeded stackato::validate::notspacename        0 [list source [file join $dir notspacename.tcl]]
package ifneeded stackato::validate::notspacequota       0 [list source [file join $dir notspacequota.tcl]]
package ifneeded stackato::validate::notusername         0 [list source [file join $dir notusername.tcl]]
package ifneeded stackato::validate::orgname             0 [list source [file join $dir orgname.tcl]]
package ifneeded stackato::validate::orgname-user        0 [list source [file join $dir orgname-user.tcl]]
package ifneeded stackato::validate::otherspacename      0 [list source [file join $dir otherspacename.tcl]]
package ifneeded stackato::validate::path                0 [list source [file join $dir path.tcl]]
package ifneeded stackato::validate::percent             0 [list source [file join $dir percent.tcl]]
package ifneeded stackato::validate::percent-int         0 [list source [file join $dir percent-int.tcl]]
package ifneeded stackato::validate::quotaname           0 [list source [file join $dir quotaname.tcl]]
package ifneeded stackato::validate::routename           0 [list source [file join $dir routename.tcl]]
package ifneeded stackato::validate::securitygroup       0 [list source [file join $dir secgroup.tcl]]
package ifneeded stackato::validate::serviceauthtoken    0 [list source [file join $dir serviceauthtoken.tcl]]
package ifneeded stackato::validate::servicebroker       0 [list source [file join $dir servicebroker.tcl]]
package ifneeded stackato::validate::serviceinstance     0 [list source [file join $dir serviceinstance.tcl]]
package ifneeded stackato::validate::serviceplan         0 [list source [file join $dir serviceplan.tcl]]
package ifneeded stackato::validate::servicetype         0 [list source [file join $dir servicetype.tcl]]
package ifneeded stackato::validate::spacename           0 [list source [file join $dir spacename.tcl]]
package ifneeded stackato::validate::spacequota          0 [list source [file join $dir spacequota.tcl]]
package ifneeded stackato::validate::spaceuuid           0 [list source [file join $dir spaceuuid.tcl]]
package ifneeded stackato::validate::stackname           0 [list source [file join $dir stackname.tcl]]
package ifneeded stackato::validate::target              0 [list source [file join $dir target.tcl]]
package ifneeded stackato::validate::ulmode              0 [list source [file join $dir ulmode.tcl]]
package ifneeded stackato::validate::username            0 [list source [file join $dir username.tcl]]
package ifneeded stackato::validate::username-org        0 [list source [file join $dir username-org.tcl]]
package ifneeded stackato::validate::username-space      0 [list source [file join $dir username-space.tcl]]
package ifneeded stackato::validate::vappname            0 [list source [file join $dir vappname.tcl]]
package ifneeded stackato::validate::zonename            0 [list source [file join $dir zonename.tcl]]

# Code common to various validation types. Not a VT in itself.
package ifneeded stackato::validate::common       0 [list source [file join $dir common.tcl]]
