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

oo::class create ::stackato::v2::user {
    superclass ::stackato::v2::base
    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	debug.v2/user {}

	#my Attribute guid          string
	my Attribute admin         boolean
	my Attribute default_space &space

	my Many spaces
	my Many organizations
	my Many managed_organizations         organization
	my Many billing_managed_organizations organization
	my Many audited_organizations         organization
	my Many managed_spaces                space
	my Many audited_spaces                space

	my SearchableOn space
	my SearchableOn organization
	my SearchableOn managed_organization
	my SearchableOn billing_managed_organization
	my SearchableOn audited_organization
	my SearchableOn managed_space
	my SearchableOn audited_space

	next $url
    }

    # Pseudo attribute for uuid (pseudo user name).
    forward @guid my id
    export  @guid

    method emails {} {
	return [dict get' [my UAA] emails {}]
    }

    method email {} {
	return [dict get' [lindex [my emails] 0] value ([my id])]
    }

    method given_name {} {
	return [dict get' [my UAA] name givenName {}]
    }

    method family_name {} {
	return [dict get' [my UAA] name familyName {}]
    }

    method full_name {} {
	return "[my given_name] [my family_name]"
    }

    # # ## ### ##### ######## #############
    ## User creation is special, done across UAA and CC.
    # This is the only v2 entity which allows a 'new' object to force
    # the target CC to use a particular UUID. For all other classes
    # the UUID of new entities is determined and set by the CC.

    method create! {email password} {
	debug.v2/user {}
	# UAA first, then in the CC.
	# TODO: Catch CC errors and perform rollback in the UAA.

	debug.v2/user {UAA add-user}
	set uuid [[my client] uaa_add_user $email $password]

	try {
	    # For CC we force an uuid on the target
	    debug.v2/user {CC  commit new}
	    my commit-with $uuid
	} on error {e o} {
	    # TODO: See if there are errors we should trap
	    # specifically to reort as non-internal.
    puts |$e|
    puts |$o|
	    # Roll back in the UAA.
	    [my client] uaa_delete_user $uuid
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
	foreach item [$client uaa_list_users] {
	    set guid [dict get $item id]
	    set uname [dict get [lindex [dict get $item emails] 0] value]
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
