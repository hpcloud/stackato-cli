# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require try            ;# I want try/catch/finally
package require TclOO
package require dictutil
package require table
package require stackato::log
package require stackato::jmap
package require stackato::term ; # ask and companions
package require stackato::client::cli::config
package require stackato::client::cli::command::Base
package require stackato::client::cli::command::Misc

namespace eval ::stackato::client::cli::command::User {}

debug level  cli/user
debug prefix cli/user {[::debug::snit::call] | }

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::client::cli::command::User {
    superclass ::stackato::client::cli::command::Base

    # # ## ### ##### ######## #############

    constructor {args} {
	Debug.cli/user {}
	# Namespace import, sort of.
	namespace path [linsert [namespace path] end \
			    ::stackato ::stackato::log ::stackato::client::cli]
	next {*}$args
    }

    # # ## ### ##### ######## #############
    ## API

    method info {} {
	Debug.cli/user {}
	set info [my client_info]

	set username [dict get' $info user N/A]

	if {[my GenerateJson]} {
	    display [jmap map array [list $username]]
	    return
	}

	display "\n\[$username\]"
	return
    }

    method allinfo {} {
	Debug.cli/user {}
	set info [my client_info]
	if {![dict exists $info user]} {
	    set info {}
	} else {
	    set info [[my client] user_info [dict get $info user]]
	}

	if {[my GenerateJson]} {
	    display [jmap map {dict {apps array}} $info]
	    return
	}

	table::do t {Key Value} {
	    foreach {key value} $info {
		$t add $key $value
	    }
	}
	display ""
	$t show display
	return
    }

    method login {{email {}}} {
	Debug.cli/user {}
	set tries 0
	while {1} {
	    try {
		if {$email eq {}} { set email [dict get [my options] email] }

		if {[my promptok]} {
		    if {[my target_url] ne {}} {
			display "Attempting login to \[[my target_url]\]"
		    }
		    if {$email eq {}} {
			set email [term ask/string "Email: "] 
		    }
		}
		if {$email eq {}} {
		    err "Need a valid email"
		}

		set isadmin [[my client] admin?]
		Debug.cli/user {Admin = $isadmin}
		# [bug 93843]
		set password {}
		if {!$isadmin} {
		    set password [string trim [dict get [my options] password]]
		    if {[my promptok]} {
			if {$password eq {}} {
			    set password [string trim [term ask/string* "Password: "]]
			}
		    }
		    if {$password eq {}} {
			err "Need a password"
		    }
		} else {
		    if {[dict exist [my options] password] &&
			([dict get [my options] password] ne {})} {
			display "Ignoring password, logged in as administrator [[my client] user]"
		    } else {
			display "No password asked for, logged in as administrator [[my client] user]"
		    }
		}

		my login_and_save_token $email $password
		say [color green "Successfully logged into \[[my target_url]\]"]

		my client-reset
		if {[dict exists [my options] group]} {
		    # --group provided, make persistent (implied 's group').
		    # Run the misc command, to have all the necessary checks.

		    set misc [command::Misc new {*}[my options]]
		    $misc client [my client]
		    $misc group_set [dict get [my options] group]
		} else {
		    # On sucessful (re)login reset the current group,
		    # it may not be valid for this user. We mention
		    # this however only if the target supported
		    # groups.
		    config reset_group
		    if {[dict exists [my client_info] groups]} {
			say "Reset current group: [color green OK]"
		    }
		}
		return

	    } trap {REST HTTP} {e o} {
		return {*}$o $e

	    } trap {STACKATO CLIENT TARGETERROR} e {
		display [color red "Problem with login, invalid account or password while attempting to login to '[my target_url]'. $e"]

		incr tries
		if {($tries < 3) &&
		    [my promptok] &&
		    ![my HAS [my options] password]} continue
		exit 1

	    } trap {TERM INTERUPT} {e o} {
		return {*}$o $e
		# not retrying, rethrow
		incr tries
		if {($tries < 3) &&
		    [my promptok] &&
		    ![my HAS [my options] password]} continue
		exit 1

	    } trap {STACKATO SERVER DATA ERROR} {e o} {
		return {*}$o $e

	    } trap {STACKATO CLIENT} {e o} {
		return {*}$o $e

	    } on error e {
		# Rethrow as internal error, with a full stack trace.
		return -code error -errorcode {STACKATO CLIENT INTERNAL} \
		    [list $e $::errorInfo $::errorCode]
	    }
	}
	return
    }

    method logout {{thetarget {}}} {
	Debug.cli/user {}

	if {[dict get [my options] all]} {
	    config remove_token_file
	    say [color green "Successfully logged out of all known targets"]
	    return
	}

	if {$thetarget eq {}} {
	    set thetarget [my target_url]
	}

	config remove_token_for $thetarget
	say [color green "Successfully logged out of \[$thetarget]\]"]
	return
    }

    method change_password {{password {}}} {
	Debug.cli/user {}

	if {$password eq {}} {
	    set password [dict get [my options] password]
	}

	Debug.cli/user {password = "$password"}

	set info  [my client_info]
	#checker -scope line exclude badOption
	set email [dict get' $info user {}]

	if {$email eq {}} {
	    set email [term ask/string "Email: "] 
	    #err "Need to be logged in to change password."
	}

	say "Changing password for '$email'\n"

	set verifier [stackato::client new [my target_url] {}]
	if {[config trace] ne {}} {
	    $verifier trace [config trace]
	}

	set tries 0
	while {1} {
	    set oldpassword [string trim [term ask/string* "Old Password: "]]

	    # Verify that the old password is valid.
	    try {
		lassign [$verifier login $email $oldpassword] vtoken vsshkey
		set tokenfile [dict get' [my options] token_file {}]
		config store_token $vtoken $tokenfile $vsshkey
		my client-reset
		my client
	    } trap {STACKATO CLIENT TARGETERROR} e {
		display [color red "Bad password"]
		incr tries
		if {$tries < 3} continue
		exit 1
	    } trap {REST HTTP} {e o} {
		return {*}$o $e
	    } trap {TERM INTERUPT} {e o} {
		return {*}$o $e
	    } trap {STACKATO SERVER DATA ERROR} {e o} {
		return {*}$o $e
	    } trap {STACKATO CLIENT} {e o} {
		return {*}$o $e
	    } on error e {
		# Rethrow as internal error, with a full stack trace.
		return -code error -errorcode {STACKATO CLIENT INTERNAL} \
		    [list $e $::errorInfo $::errorCode]
	    }
	    break
	}
	$verifier destroy

	if {($password eq {}) && [my promptok]} {
	    set password  [string trim [term ask/string* "New Password: "]]
	    set password2 [string trim [term ask/string* "Verify Password: "]]
	    if {$password ne $password2} {
		err "Passwords did not match, try again"
	    }
	}
	if {$password eq {}} {
	    err "Password required"
	}
	[my client] change_password [string trim $password]
	say [color green "\nSuccessfully changed password"]
	return
    }

    # # ## ### ##### ######## #############
    ## Internal commands.

    method login_and_save_token {email password} {
	# Password empty => Admin user. Password will not be transmitted.
	# See [bug 93843] for the code causing the implication.
	Debug.cli/user {}

	lassign [[my client] login $email $password] token sshkey
	set tokenfile [dict get' [my options] token_file {}]

	Debug.cli/user {tokenfile = '$tokenfile'}
	Debug.cli/user {token     = '$token'}
	Debug.cli/user {sshkey    = '$sshkey'}

	config store_token $token $tokenfile $sshkey
	return
    }

    method HAS {dict key} {
	expr {[dict exists $dict $key] &&
	      ([dict get $dict $key] ne {})}
    }

    # # ## ### ##### ######## #############
    ## State

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::client::cli::command::User 0
