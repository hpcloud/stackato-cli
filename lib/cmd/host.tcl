# -*- tcl -*-
return
# # ## ### ##### ######## ############# #####################
# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require fileutil
package require stackato::mgr::cfile
package require stackato::log

namespace eval ::stackato::cmd {
    namespace export host
    namespace ensemble create
}
namespace eval ::stackato::cmd::host {
    namespace export add list remove update default-hostfile
    namespace ensemble create

    namespace import ::stackato::log::err
    namespace import ::stackato::mgr::cfile
}

debug level  cmd/host
debug prefix cmd/host {[debug caller] | }

# # ## ### ##### ######## ############# #####################

## TODO cmd/host - consider factoring the low-level code into mgr/host package

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::host::add {config} {
    # (cmdr::)config -- dry-run, ipaddress, hosts

    debug.cmd/host {add}
    lassign [Get $config] hostfile hosts

    set newhosts [$config @hosts]
    set ip       [$config @ipaddress]

    if {[Contains hosts $newhosts]} {
	err "Unable to add, at least one of\n\t[join $newhosts \n\t]\nalready has a mapping"
    }

    # Add entries for the new mappings.
    lappend hosts {}
    foreach host $newhosts {
	lappend hosts "$ip $host"
    }

    Compress hosts
    Write $config $hostfile $hosts
    return
}

proc ::stackato::cmd::host::update {config} {
    # (cmdr::)config -- dry-run, ipaddress, hosts

    debug.cmd/host {}
    lassign [Get $config] hostfile hosts

    set newhosts [$config @hosts]
    set ip       [$config @ipaddress]

    if {[Contains hosts $newhosts]} {
	err "Unable to add, at least one of\n\t[join $newhosts \n\t]\nalready has a mapping"
    }

    # Remove the old mappings involving the ip-address.
    RemoveAddress hosts $ip

    # Add entries for the new mappings, completing the replacement.
    lappend hosts {}
    foreach host $newhosts {
	lappend hosts "$ip $host"
    }

    Compress hosts
    Write $config $hostfile $hosts
    return
}


proc ::stackato::cmd::host::remove {config} {
    # (cmdr::)config -- dry-run, hostsOrIPs
    debug.cmd/host {}

    lassign [Get $config] hostfile hosts

    set args [$config @hostsOrIPs]

    # Remove all references to the specified ip-addresses and hostnames.
    Remove   hosts $args
    Compress hosts
    Write $config $hostfile $hosts
    return
}

proc ::stackato::cmd::host::list {config} {
    # (cmdr::)config ignored, empty

    debug.cmd/host {}
    lassign [Get $config] hostfile hosts
    puts [join $hosts \n]
    return
}

# # ## ### ##### ######## ############# #####################
proc ::stackato::cmd::host::RemoveAddress {hvar ipaddress} {
    debug.cmd/host {}
    upvar 1 $hvar hosts
    Apply hosts [::list __RemoveAddress $ipaddress]
    return
}
proc ::stackato::cmd::host::__RemoveAddress {ipaddress entry} {
    debug.cmd/host {}
    set pos [lsearch -exact $entry $ipaddress]
    # Ignore not-match, and match as host.
    if {$pos != 0} {
	if {[string equal {} [string trim $entry]]} { return { } }
	return $entry
    }
    # Match a ip-adress, squash whole line.
    return { }
}

# # ## ### ##### ######## ############# #####################
proc ::stackato::cmd::host::Remove {hvar hostoriplist} {
    debug.cmd/host {}
    upvar 1 $hvar hosts
    Apply hosts [::list __Remove $hostoriplist]
    return
}
proc ::stackato::cmd::host::__Remove {hostoriplist entry} {
    debug.cmd/host {}
    foreach h $hostoriplist {
	set pos [lsearch -exact $entry $h]
	# Ignore not-match
	if {$pos < 0} continue
	# Match a ip-adress, squash whole line.
	if {$pos == 0} { return { } }
	# Match as host, remove
	set entry [lreplace $entry $pos $pos]
    }
    # Only hosts matched, if any. If only ip-address left squash
    # the line, else return the modified state.
    if {[llength $entry] <= 1} {
	return { }
    } else {
	return $entry
    }
}

# # ## ### ##### ######## ############# #####################
proc ::stackato::cmd::host::Compress {hvar} {
    debug.cmd/host {}
    upvar 1 $hvar hosts
    set lastempty 0
    Apply hosts __Compress
    return
}
proc ::stackato::cmd::host::__Compress {entry} {
    debug.cmd/host {}
    upvar 1 lastempty lastempty
    set empty [string equal {} [string trim $entry]]
    if {$empty && $lastempty} {
	return {}
    }
    set lastempty $empty
    if {$empty} { return { } }
    return $entry
}

# # ## ### ##### ######## ############# #####################
proc ::stackato::cmd::host::Contains {hvar hostnames} {
    debug.cmd/host {}
    upvar 1 $hvar hosts
    return [Match hosts [::list __Contains $hostnames]]
}
proc ::stackato::cmd::host::__Contains {hostnames entry} {
    debug.cmd/host {}
    foreach h $hostnames {
	set pos [lsearch -exact $entry $h]
	# Not found, or ip-address column -> ignore
	if {$pos <= 0} continue
	# Found, stop.
	return 1
    }
    return 0
}

# # ## ### ##### ######## ############# #####################
proc ::stackato::cmd::host::Apply {hvar cmd} {
    debug.cmd/host {}
    upvar 1 $hvar hosts
    set new {}
    foreach entry $hosts {
	if {[string match "\#*" [string trim $entry]]} {
	    lappend new $entry
	} else {
	    set centry [uplevel 1 [::list {*}$cmd $entry]]
	    if {$centry ne {}} {
		lappend new $centry
	    }
	}
    }
    set hosts $new
    return
}

proc ::stackato::cmd::host::Match {hvar cmd} {
    debug.cmd/host {}
    upvar 1 $hvar hosts
    foreach entry $hosts {
	if {[string match "\#*" [string trim $entry]]} {
	    continue
	}
	if {[uplevel 1 [::list {*}$cmd $entry]]} {
	    return 1
	}
    }
    return 0
}

# # ## ### ##### ######## ############# #####################
proc ::stackato::cmd::host::Write {config hostfile lines} {
    debug.cmd/host {}
    # Save to a temp file first.

    if {[$config @dry-run]} {
	puts "CHANGED [join $lines "\nCHANGED "]"
	return
    }

    set tmp [fileutil::tempfile stackato_winhost_]
    fileutil::writeFile $tmp [string trim [join $lines \n]]\n
    cfile fix-permissions $tmp 0644

    # Now for the tricky part, copying the modified file content
    # into the system file.
    #
    # - Generate a .bat file which runs a powershell script which
    #   launches a copy command in elevated mode.
    #
    # - Execute powershell to launch a copy command in elevated
    #   privileges
    #
    # What system restrictions doe use of powershell pose ?
    # XP+, Vista+, Win7+ ?

    # Atomic overwrite of the true destination.
    if {[catch {
	file rename -force -- $tmp $hostfile
    } msg]} {
	global tcl_platform

	#file delete $tmp
	if {$tcl_platform(platform) eq "windows"} {
	    err "Unable write changes back into $hostfile: $msg"
	} else {
	    err "Unable write changes back into $hostfile: $msg.\nPlease consider running the command via 'sudo'."
	}
    }
    return
}

# Return content of the system's hosts file, as a list of lines.
proc ::stackato::cmd::host::Get {config} {
    debug.cmd/host {}

    set base [$config @hostfile]
    foreach f [::list $base $base.txt] {
	if {![file exists $f]} continue
	if {[catch {
	    fileutil::cat $f
	} res]} {
	    err $res
	}
	return [::list $f [split $res \n]]
    }
    return -code error "Windows Hosts file not found"
}

proc ::stackato::cmd::host::default-hostfile {p} {
    debug.cmd/host {}

    global tcl_platform
    if {$tcl_platform(platform) eq "windows"} {
	# Return path to the Win32 hosts file.
	return $::env(SystemRoot)/system32/drivers/etc/hosts
    } else {
	# Return path to the unix hosts file.
	return /etc/hosts
    }
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::host 0

