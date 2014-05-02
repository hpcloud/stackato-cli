# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## User entity definition

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require dictutil
package require stackato::v2::base

# # ## ### ##### ######## ############# #####################

debug level  v2/user
debug prefix v2/user {[debug caller] | }

# # ## ### ##### ######## ############# #####################

stackato v2 register user
oo::class create ::stackato::v2::user {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	debug.v2/user {}

	#my Attribute guid          string
	my Attribute admin         boolean
	my Attribute active        boolean
	my Attribute default_space &space
	my Attribute username      string

	my Many spaces
	my Many managed_spaces                space
	my Many audited_spaces                space

	my Many organizations
	my Many managed_organizations         organization
	my Many billing_managed_organizations organization
	my Many audited_organizations         organization

	my SearchableOn organization
	my SearchableOn managed_organization
	my SearchableOn billing_managed_organization
	my SearchableOn audited_organization

	my SearchableOn space
	my SearchableOn managed_space
	my SearchableOn audited_space

	next $url
    }

    # Pseudo attribute for uuid (pseudo user name).
    forward @guid my id
    export  @guid

    # Pseudo attribute for name.
    forward @name my the_name
    export  @name

    method emails {} {
	if {[my id] eq "legacy-api"} {
	    return {}
	}
	return [dict get' [my UAA] emails {}]
    }

    method email {} {
	if {[my id] eq "legacy-api"} {
	    return "([my id])"
	}
	return [dict get' [lindex [my emails] 0] value ([my id])]
    }

    method the_name {} {
	if {[my id] eq "legacy-api"} {
	    return "legacy-api"
	}
	# A stackato target provides user name information in the CC
	# entity. We can avoid usage of UAA.
	if {[my @username defined?]} {
	    return [my @username]
	}
	return [dict get' [my UAA] userName {}]
    }

    method given_name {} {
	if {[my id] eq "legacy-api"} {
	    return {}
	}
	return [dict get' [my UAA] name givenName {}]
    }

    method family_name {} {
	if {[my id] eq "legacy-api"} {
	    return {}
	}
	return [dict get' [my UAA] name familyName {}]
    }

    method full_name {} {
	if {[my id] eq "legacy-api"} {
	    return {}
	}
	return "[my given_name] [my family_name]"
    }

    # # ## ### ##### ######## #############
    ## Changing the @admin flag is special, done across UAA and CC.
    ## Goes through the special CC /stackato REST endpoint first, then
    ## tries the regular CFv2 song-and-dance talking to both CC and
    ## UAA.

    method admin! {newvalue} {
	debug.v2/user {}
	if {( [my @admin] &&  $newvalue) ||
	    (![my @admin] && !$newvalue)} {
	    # no change, do nothing
	    return
	}

	set client [authenticated]

	try {
	    # uncomment line below to force execution of the fallback code
	    # my ForceDance

	    my = [$client stackato-change-admin [my id] $newvalue]
	    display [color green OK]

	} trap {STACKATO CLIENT V2 INVALID REQUEST} {e o} {
	    debug.v2/user {}
	    # Show error as is, not internal error. Server side validation failure.
	    err $e

	} trap {STACKATO CLIENT V2 UNKNOWN REQUEST} {e o} {
	    debug.v2/user {No shortcut, sing and dance the full tune}

	    if {$newvalue} {
		my GrantDance $client
	    } else {
		my RevokeDance $client
	    }

	    display [color green OK]
	}

	debug.v2/user {/done}
	return
    }

    method ForceDance {} {
	# Fake missing stackato api to force song and dance
	return -code error -errorcode {STACKATO CLIENT V2 UNKNOWN REQUEST} "XXX"
    }

    method GrantDance {client} {
	debug.v2/user {}

	# Talk to UAA first.
	debug.v2/user {[my id] += scim.write}
	$client uua_scope_modify scim.write members {
	    # Add user
	    lappend members [dict create value [my id] type USER]
	}
	debug.v2/user {[my id] += cloud_controller.admin}
	$client uua_scope_modify cloud_controller.admin members {
	    # Add user
	    lappend members [dict create value [my id] type USER]
	}

	# Now we can go and flip the CC side admin flag as well.
	my @admin set yes
	my commit
	return
    }

    method RevokeDance {client} {
	debug.v2/user {}

	# Talk to UAA first.
	debug.v2/user {[my id] -= scim.write}
	$client uua_scope_modify scim.write members {
	    # Remove user
	    # no struct::list delete available :(
	    set members [struct::list filterfor m $members {
		[dict get $m value] ne [my id]
	    }]
	}
	debug.v2/user {[my id] -= cloud_controller.admin}
	$client uua_scope_modify cloud_controller.admin members {
	    # Remove user
	    # no struct::list delete available :(
	    set members [struct::list filterfor m $members {
		[dict get $m value] ne [my id]
	    }]
	}

	my @admin set no
	my commit
	return
    }

    # # ## ### ##### ######## #############
    ## User creation is special, done across UAA and CC.
    ## Goes through the special CC /stackato REST endpoint first, then
    ## tries the regular CFv2 song-and-dance talking to both CC and
    ## UAA.

    method create! {username email given family password admin} {
	debug.v2/user {}

	# Assume a stackato CC with extended functionality under
	# /v2/stackato/users.

	display {Commit ... } false
	try {
	    my = [[authenticated] stackato-create-user $username $email \
		      $given $family $password $admin]
	    set callerdoesadmin 0

	    if {$admin} {
		display [color green OK]
		display "Granted administrator privileges to \[$email\] ... " false
	    }

	} trap {STACKATO CLIENT V2 INVALID REQUEST} {e o} {
	    debug.v2/user {}
	    # Show error as is, not internal error. Server side validation failure.
	    err $e

	} trap {STACKATO CLIENT V2 UNKNOWN REQUEST} {e o} {
	    debug.v2/user {No shortcut, sing and dance the full tune}

	    my invalidate
	    my SongAndDance $username $email $password

	    set callerdoesadmin $admin
	}

	debug.v2/user {/done}

	debug.v2/user {cda ==> $callerdoesadmin}
	return $callerdoesadmin
    }

    method SongAndDance {username email password} {
	debug.v2/user {}
	# UAA first, then in the CC.
	# TODO: Catch CC errors and perform rollback in the UAA.

	debug.v2/user {UAA add-user}
	set client [my client]
	set uuid [$client uaa_add_user $username $email $password]

	try {
	    # For CC we force an uuid on the target
	    debug.v2/user {CC  commit new}
	    my commit-with $uuid

	    # Back to the UAA, give scim.read rights to all users.
	    $client uua_scope_modify scim.read members {
		# Add user
		lappend members [$theuser id]
	    }

	} on error {e o} {
	    # TODO: See if there are errors we should trap
	    # specifically to report as non-internal.
    puts |$e|
    puts |$o|
	    # Roll back in the UAA.
	    $client uaa_delete_user $uuid
	    # Rethrow
	    return {*}$o $e
	}

	debug.v2/user {/done}
	return
    }

    method delete! {} {
	debug.v2/user {}
	# First in the CC, then UAA.
	# Reverse order of create! (see above).

	set uuid [my id]

	my delete
	my commit
	[my client] uaa_delete_user $uuid

	debug.v2/user {}
	return
    }

    # # ## ### ##### ######## #############

    method UAA {} {
	debug.v2/user {}
	if {![info exists myuaa]} {
	    debug.v2/user {Fill cache}
	    try {
		set myuaa [[my client] uaa_get_user [my id]]
	    } trap {REST HTTP 404} {e o} {
		#puts |$o|
		set myuaa {}
	    }
	}

	debug.v2/user {==> }
	return $myuaa
    }

    method uaa= {data} {
	debug.v2/user {}
	set myuaa $data
	return
    }

    # # ## ### ##### ######## #############

    variable myuaa

    # # ## ### ##### ######## #############
    ## SearchableOn name
    #
    ## The core code is not implemented using the standard methods of
    ## the superclass, but bespoke. Because the information needed is
    ## on the UAA, not CC. The higher levels are again standard.

    classmethod list-by-name {name {depth 0}} {
	# depth is ignored.
	set client [stackato::mgr client authenticated]

	set result {}
	foreach item [$client uaa_list_users \
			  filter "userName eq \"$name\""] {
	    set guid [dict get $item id]
	    set uname [dict get $item userName]
	    if {$uname ne $name} continue
	    lappend result [stackato::v2 deref-type user $guid]
	}
	return $result
    }

    classmethod first-by-name {name {depth 0}} {
	lindex [my list-by-name $name $depth] 0
    }

    classmethod find-by-name {name {depth 0}} {
	set matches [my list-by-name $name $depth]
	switch -exact -- [llength $matches] {
	    0       { my NotFound name $name }
	    1       { return [lindex $matches 0] }
	    default { my Ambiguous name $name }
	}
    }

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::user 0
return
