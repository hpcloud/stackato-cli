# -*- tcl -*-
# # ## ### ##### ######## ############# #####################
# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require dictutil
package require stackato::mgr::ctarget

debug level  misc
debug prefix misc {[debug caller] | }

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato {
    namespace export misc
    namespace ensemble create
}

namespace eval ::stackato::misc {
    namespace export fix-credentials health full-normalize
    namespace ensemble create

    namespace import ::stackato::mgr::ctarget
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::misc::full-normalize {path} {
    return [file dirname [file normalize $path/___]]
}

proc ::stackato::misc::fix-credentials {s} {
    debug.misc {}
    # HACK. If the hostname in the credentials is 127.0.0.1, and
    # the target url in use is of the form api.<hostname>, then we
    # fix the hostname.

    foreach key {hostname host} {
	if {![dict exists $s credentials $key]} continue
	if {[dict getit $s credentials $key] eq "127.0.0.1"} {
	    set target [ctarget get]
	    regsub -nocase {^http(s*)://} $target {} target
	    if {[string match {api.*} $target]} {
		set target [join [lrange [split $target .] 1 end] .]
		dict set s credentials $key $target
	    }
	}
    }

    return $s
}

proc ::stackato::misc::health {d} {
    #checker -scope line exclude badOption
    if {($d eq {}) || ([dict get' $d state {}] eq {})} { return N/A }
    if {[dict get $d state] eq "STOPPED"}              { return STOPPED }

    set healthy_instances [dict getit $d runningInstances]
    set expected_instance [dict getit $d instances]
    set health 0

    # Hack around wierd server response.
    if {$healthy_instances eq "null"} {
	set healthy_instances 0
    }

    if {([dict get $d state] eq "STARTED") &&
	($expected_instance > 0) &&
	$healthy_instances
    } {
	set health [expr {(1000 * $healthy_instances) /
			  $expected_instance}]
    }

    if {$health == 1000} { return RUNNING }

    return [expr {round($health / 10.)}]
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::misc 0
