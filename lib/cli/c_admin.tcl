# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require try            ;# I want try/catch/finally
package require lambda
package require struct::list
package require textutil::adjust
package require TclOO
package require stackato::client::cli::command::Base
package require stackato::client::cli::command::User
package require stackato::client::cli::command::Services
package require stackato::client::cli::command::Apps
package require stackato::client::cli::command::Misc
package require stackato::term

namespace eval ::stackato::client::cli::command::Admin {}

debug level  cli/admin
debug prefix cli/admin {[::debug::snit::call] | }

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::client::cli::command::Admin {
    superclass ::stackato::client::cli::command::Base

    # # ## ### ##### ######## #############

    constructor {args} {
	Debug.cli/admin {}

	# Namespace import, sort of.
	namespace path [linsert [namespace path] end \
			    ::stackato ::stackato::log ::stackato::client::cli]
	next {*}$args
    }

    destructor {
	Debug.cli/admin {}
    }

    # # ## ### ##### ######## #############
    ## API

    method list_users {} {
	Debug.cli/admin {}

	set users [[my client] users]
	set users [lsort -command [lambda {a b} {
	    string compare [dict getit $a email] [dict getit $b email]
	}] $users]

	if {[my GenerateJson]} {
	    display [jmap users $users]
	    return
	}

	display ""
	if {![llength $users]} {
	    display "No Users"
	    return
	}

	table::do t {Email Admin Apps} {
	    foreach u $users {
		set apps [struct::list map [dict getit $u apps] [lambda x {
		    dict getit $x name
		}]]
		set apps [lsort -dict $apps]
		set apps [join $apps {, }]
		set apps [textutil::adjust::adjust $apps -length 60 -strictlength 1]
		$t add \
		    [dict getit $u email] \
		    [dict getit $u admin] \
		    $apps
	    }
	}
	#display ""
	$t show display
	return
    }

    method add_user {{email {}}} {
	Debug.cli/admin {}

	if {$email eq {}} { set email [dict get [my options] email] }
	set password [dict get [my options] password]

	if {[my promptok]} {
	    if {$email eq {}} {
		set email [term ask/string "Email: "] 
	    }
	    if {$password eq {}} {
		set password  [term ask/string* "Password: "]
		set password2 [term ask/string* "Verify Password: "]
		if {$password ne $password2} {
		    err "Passwords did not match, try again"
		}
	    }
	}

	if {$email eq {}} {
	    err "Need a valid email"
	}
	if {$password eq {}} {
	    err "Need a password"
	}

	display {Creating New User: } false

	[my client] add_user $email $password
	display [color green OK]

	# # ## ### Check and process group-specific information.

	set hasgroup  [dict exists [my options] group]
	set haslimits [my HasLimits]

	if {$hasgroup || $haslimits} {
	    set cmd [command::Misc new {*}[my options]]
	    $cmd client [my client]

	    if {$hasgroup} {
		$cmd group_add_user __ [dict get [my options] group] $email
	    }

	    if {$haslimits} {
		$cmd group_limits __ $email
	    }

	    $cmd destroy
	}

	# # ## ### Done with group-specific information

	if {[my auth_token] ne {}} return
	# if we are not logged in for the current target, log in as the new user

	set cmd [command::User new {*}[my options] password $password]
	$cmd login $email
	$cmd destroy
	return
    }

    method HasLimits {} {
	foreach k {mem limit-apps limit-appuris limit-services limit-sudo} {
	    if {![dict exists [my options] $k]} continue
	    return 1
	}
	return 0
    }

    method delete_user {user_email} {
	Debug.cli/admin {}

	# Check to make sure all apps and services are deleted before deleting the user
	# implicit proxying

	[my client] proxy_for $user_email

	set apps [[my client] apps]
	if {[llength $apps]} {
	    # Why is this not outside? This way if there are services,
	    # but no apps, no question is asked.
	    if {[my promptok]} {
		set proceed \
		    [term ask/yn \
			 "\nDeployed applications and associated services will be DELETED, continue ? " \
			 no]
		if {!$proceed} {
		    err "Aborted" 
		}
	    }

	    set cmd [command::Apps new {*}[my options] proxy $user_email]
	    foreach a $apps {
		$cmd delete_app [dict getit $a name] 1
	    }
	    $cmd destroy
	}

	set services [[my client] services]
	if {[llength $services]} {
	    set cmd [command::Services new {*}[my options] proxy $user_email]
	    foreach s $services {
		$cmd delete_service [dict getit $s name]
	    }
	    $cmd destroy
	}

	display {Deleting User: } false
	[my client] proxy= {}
	[my client] delete_user $user_email
	display [color green OK]
	return
    }

    method admin_report {__ {destination {}}} {
	Debug.cli/admin {}

	if {$destination eq {}} {
	    regsub {^[^/]*//} [[my client] target] {} destination
	    append destination -report.tgz
	}

	display "Generating report $destination:"

	fileutil::writeFile -translation binary $destination \
	    [[my client] report]

	display [color green OK]
	return
    }

    method admin_patch {__ patch} {
	Debug.cli/admin {}

	set ssh [auto_execok ssh]
	if {![llength $ssh]} {
	    err "Local helper application ssh not found in PATH.$helpsuffix"
	}

	set target [my target_url]
	regsub ^https?:// $target {} target

	lassign [my GetPatchFile $patch] transient patch

	Debug.cli/admin {Target    = $target}
	Debug.cli/admin {File      = $patch}
	Debug.cli/admin {Transient = $transient}

	try {
	    # Note how we are performing the upload without using a
	    # separate scp command.  The patch file is made the stdin
	    # of the ssh, and written to the destination by the 'cat'
	    # with output redirection.

	    # Note further that this method of uploading disables all
	    # interaction with the user when the patch application is
	    # run. The application must be fully automatic.

	    set patchdir "\$HOME/patches"
	    set dst $patchdir/[file tail $patch]

	    lappend cmd	"echo Uploading..."
	    lappend cmd	"mkdir -p \"$patchdir\""
	    lappend cmd "cat > \"$dst\""
	    lappend cmd "chmod u+x \"$dst\""
	    lappend cmd "echo Applying..."
	    lappend cmd "\"$dst\""

	    Debug.cli/admin {Command = [join $cmd "\n Command = "]}
	    #return

	    exec 2>@ stderr >@ stdout < $patch \
		{*}$ssh stackato@${target} \
		[join $cmd { ; }]
	} trap {CHILDSTATUS} {e o} {

	    if {$transient} { file delete $patch }

	    set status [lindex [dict get $o -errorcode] end]
	    if {$status == 255} {
		err "Server closed connection."
	    } else {
		exit $status
	    }
	}

	if {$transient} { file delete $patch }
	return
    }

    method GetPatchFile {path} {
	Debug.cli/admin {}

	if {[regexp {^https?://} $path]} {
	    # Argument is url. Retrieve directly.

	    return [my GetPatchUrl $path "Invalid url \"$path\"."]
	}

	if {![file exists $path]} {
	    Debug.cli/admin {HTTP}
	    # Do http retrieval from constructed url.

	    set version [my ServerVersion]
	    Debug.cli/admin {Server = $version}

	    lassign [split $version .] major minor
	    set version $major.$minor

	    set url http://get.stackato.com/patch/$version/$path
	    Debug.cli/admin {Url = $url}

	    return [my GetPatchUrl $url "Unknown $version patch \"$path\"."]
	}

	if {![file readable $path]} {
	    err "Path $path is not readable."
	}
	if {![file isfile $path]} {
	    err "Path $path is not a file."
	}

	return [list 0 $path]
    }

    method GetPatchUrl {url err} {
	set tmp [fileutil::tempfile stackato-patch-]
	Debug.cli/admin {Tmp = $tmp}

	try {
	    fileutil::writeFile -translation binary $tmp \
		[lindex [[my client] http_get_raw $url application/octet-stream] 1]
	} on error {e o} {
	    # Ensure removal of the now unused tempfile
	    file delete $tmp
	    # Note: Exposes constructed url
	    #err "Unable to retrieve $url: $e"
	    err $err
	}

	return [list 1 $tmp]
    }

    method Expect {log password args} {
	global expect_out
	exp_log_user 0
	#exp_internal 1
	exp_spawn {*}$args
	expect {
	    "password: " {
		exp_send $password\r
	    }
	    timeout {}
	    eof {
		return
	    }
	}
	if {$log} {
	    exp_log_user 1
	    interact
	    return
	}
	expect {
	    "password: " {
		err "Bad password"
	    }
	    timeout {
	    }
	    eof {
		return
	    }
	}
    }

    # # ## ### ##### ######## #############
    ## Internal commands.

    # # ## ### ##### ######## #############
    ## State

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::client::cli::command::Admin 0
