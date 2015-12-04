# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Organization names
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate
package require stackato::mgr::client;# pulls v2 also
package require stackato::mgr::self
package require stackato::validate::common

debug level  validate/orgname-user
debug prefix validate/orgname-user {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export orgname-user
    namespace ensemble create
}

namespace eval ::stackato::validate::orgname-user {
    namespace export default validate complete release acceptable
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail-unknown-simple-msg
    namespace import ::stackato::v2
    namespace import ::stackato::mgr::self
    namespace import ::stackato::validate::common::refresh-client
}

proc ::stackato::validate::orgname-user::default  {p}   { return {} }
proc ::stackato::validate::orgname-user::release  {p x} { return }
proc ::stackato::validate::orgname-user::complete {p x} {
    complete-enum [struct::list map [Get $p] [lambda o {
	$o @name
    }]] 0 $x
}

proc ::stackato::validate::orgname-user::validate {p x} {
    debug.validate/orgname-user {}

    # See also corg::get.
    set orgsofuser [lsort -dict [Get $p]]
    set matches [struct::list filter $orgsofuser [lambda {x o} {
	string equal $x [$o @name]
    } $x]]

    set n [llength $matches]

    debug.validate/orgname-user {matches = $n ($matches)}

    if {$n == 1} {
	# Found it. Return.
	debug.validate/orgname-user {OK/canon = $x}
	return [lindex $matches 0]
    } elseif {$n > 1} {
	# Found many. Report the ambiguity.
	debug.validate/orgname-user {FAIL/many = $matches}
	append msg "The organization name \"$x\" is ambiguous."
	return -code error -errorcode {CMDR VALIDATE ORGNAME-USER} $msg
    }

    # Not found. Ok, the org is not available to the user. Check the
    # total list of orgs now too, to distinguish between specification
    # of an unknown org vs a known org the user has no permissions
    # for.

    set orgsall [lsort -dict [v2 organization list]]
    if {$orgsall ne $orgsofuser} {
	# The user sees a different set of orgs via the global API
	# then with the per-user API. This implies that the user is an
	# admin (which sees more), and that it does not belong to the
	# specified org.

	append msg "Administrator \"$username\" does not belong to organization \"$x\"."
	return -code error -errorcode {CMDR VALIDATE ORGNAME-USER} $msg
    }

    debug.validate/orgname-user {FAIL = ($msg)}
    fail-unknown-simple-msg \
	"[self please orgs Run] to see list of organizations" \
	$p ORGNAME-USER "organization" $x
}

proc ::stackato::validate::orgname-user::Get {p} {
    upvar 1 username username
    refresh-client $p

    # The choice of org is restricted to the orgs associated with the
    # user we are logged in as. Bug 104693.
    ::set client [$p config @client]
    ::set user [$client current_user_id]

    if {$user eq {}} {
	# Not logged in, but we have to be
	stackato::client::AuthError
    } else {
	::set username [$client current_user]
	::set user     [v2 deref-type user $user]
	return [$user @organizations]
    }
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::orgname-user 0
