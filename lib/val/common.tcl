## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Common code to various validation types.
## Currently: @client dependency and refresh.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require stackato::mgr::client

debug level  validate/common
debug prefix validate/common {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export common
    namespace ensemble create
}

namespace eval ::stackato::validate::common {
    namespace export refresh-client nospace not expected
    namespace ensemble create

    namespace import ::stackato::mgr::client
}

# # ## ### ##### ######## ############# #####################
## Nicer error message for the regular validation types.

proc ::stackato::validate::common::expected {p code type x {context {}}} {
    set ptype [$p type]

    if {$ptype eq "option"} {
	set name [$p flag]
    } else {
	set name [$p label]
    }

    if {[string match {A *} $type] ||
	[string match {An *} $type]} {
	set lead {}
    } elseif {[string match {[aeiouAEIOU]*} $type]} {
	set lead {An }
    } else {
	set lead {A }
    }

    return -code error -errorcode [list CMDR VALIDATE {*}$code] \
	"Found a problem with $ptype \"$name\": $lead$type \"$x\" does not exist$context. Please use a different value."
}

# # ## ### ##### ######## ############# #####################
## Nicer error message for the not* validation types.

proc ::stackato::validate::common::not {p code type x {context {}}} {
    set ptype [$p type]

    if {$ptype eq "option"} {
	set name [$p flag]
    } else {
	set name [$p label]
    }

    if {[string match {A *} $type] ||
	[string match {An *} $type]} {
	set lead {}
    } elseif {[string match {[aeiouAEIOU]*} $type]} {
	set lead {An }
    } else {
	set lead {A }
    }

    return -code error -errorcode [list CMDR VALIDATE {*}$code] \
	"Found a problem with $ptype \"$name\": $lead$type named \"$x\" already exists$context. Please use a different name."
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::validate::common::nospace {p code type x} {
    # Custom validation failure when a current space is required, but
    # not present. This is a variation of
    #   ::cmdr::validate::common::fail

    # Determine type of p: state, option, or input.  Use this to
    # choose a proper identifying string in the generated message.

    set ptype [$p type]

    if {$ptype eq "option"} {
	set name [$p flag]
    } else {
	set name [$p label]
    }
    return -code error -errorcode [list CMDR VALIDATE {*}$code] \
	"No space defined. Unable to convert $type candidate \"$x\" for $ptype \"$name\""
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::validate::common::refresh-client {p} {
    # We force all full recomputation of the client value. And of the
    # requirements. They may have changed since the last time
    # => REPL, completions.

    # TODO: find a way of reducing the number of client regenenerations.
    # TODO: idea: Force forget at the beginning of a command line parsing.
    # TODO: but do nothing after, until a change can affect it ... put
    # TODO: this into the 'client' parameter!? everything affecting is
    # TODO: logically before that. issue is command completion inside of
    # TODO: cli shell. ... That is like parsing ?! ...

    # TODO: Need a release hook pushing the changes down into managers.
    # TODO: Especially mgr/client (due to its caching).
    # TODO: Alt: Disable caching in that level.

    debug.validate/common {}

    # NOTE: This call can happen from inside a 'config force', and CMDR
    # has code to prevent the infinite recursion this would cause,
    # disabling both forget and force below.

    # NOTE 2: See if we can transfer /info data between the incarnations.
    # No, we do not really want that. Different targets, and such, possibly.

    debug.validate/common {/reset}
    client authenticated-reset

    debug.validate/common {/refresh}
    $p config @motd
    set c [client authenticated]
    $p config @client set $c

    debug.validate/common {/ok}
    debug.validate/common {==> $c ([$c target])}
    return $c
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::common 0
