# -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Database of live (in-memory) entities.
## Database of changes entities.
#
## Global operations:
## - Construct/retrieve from url
## - Validate existence
## - Commit changes.

## Entities come in three distinct states
##
## (1) knows url (= identity), no  data
## (2) knows url (= identity), has data
## (3) no url (identity),      has data

## (Ad 1) Such instances are "phantoms" of server entities. They
## transition to state (2) on the first attribute access, loading the
## server's data on demand.
#
## (Ad 2) Such instances are client-side "replicas" of server
## entities, containing the server's data at the time of their
## retrieval by the client.
#
## (Ad 3) Such instances are uncommitted "new" entities. They
## transition to state (2) on commit, i.e. first data transfer to the
## server. At that point conflicts may occur. It is unclear if the new
## entity will be rejected by the serever, or if the server will return
## the existing id and entity, just/possibly updated. In the latter
## case we may have a phantom or replica in memory already, and
## should/must rewrite the internal references to it, dropping the then
## superfluous state (3) instance. Until it is proven to be a
## possibility we will however optimistically go forward and not create
## the necessary databases tracking the inter-object references to
## allow for such rewriting.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require cmdr::validate ;# Fail utility command.

namespace eval ::stackato {
    namespace export v2
    namespace ensemble create
}
namespace eval ::stackato::v2 {
    namespace export {[a-z]*}
    namespace ensemble create
}

# # ## ### ##### ######## ############# #####################
## Debugging

debug level  v2
debug prefix v2 {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Public API.

proc ::stackato::v2::validate {type cmd} {
    debug.v2 {}
    if {[IsEntity $cmd] && ($type eq [$cmd typeof])} {
	return [$cmd url]
    }
    ::cmdr::validate::fail [list STACKATO V2 ENTITY $type [$cmd typeof]] \
	"a $type entity" "$cmd ([$cmd typeof], entity=[IsEntity $cmd])"
    return
}

proc ::stackato::v2::deref {url} {
    debug.v2 {}
    # Check if we have an object for the requested entity, and if so,
    # return it.
    if {[IsKnown $url]} {
	set obj [GetKnown $url]
    } else {
	set obj [new $url]
    }

    debug.v2 {==> $obj}
    return $obj
}

proc ::stackato::v2::deref-type {type uuid} {
    debug.v2 {}
    set obj [deref [Url $type $uuid]]

    debug.v2 {==> $obj}
    return $obj
}

proc ::stackato::v2::deref* {urllist} {
    debug.v2 {}

    set objlist [struct::list map $urllist [lambda@ stackato::v2 u { deref $u }]]

    debug.v2 {==> $objlist}
    return $objlist
}

proc ::stackato::v2::id-of {url} {
    return [lindex [split $url /] end]
}

proc ::stackato::v2::id-of* {urllist} {
    debug.v2 {}

    set idlist [struct::list map $urllist [lambda@ stackato::v2 u { id-of $u }]]

    debug.v2 {==> $idlist}
    return $idlist
}

proc ::stackato::v2::ref* {objlist} {
    debug.v2 {}

    set urllist [struct::list map $objlist [lambda o { $o url }]]

    debug.v2 {==> $urllist}
    return $urllist
}

proc ::stackato::v2::new {url} {
    debug.v2 {}

    set type [TypeOf $url]
    debug.v2 {type = ($type)}
    set obj [$type new $url]

    debug.v2 {==> $obj}
    return $obj
}

proc ::stackato::v2::get-for {json} {
    debug.v2 {}
    # json = dict (entity   --> dict (...)
    #              metadata --> dict (guid
    #                                 url
    #                                 created_at
    #                                 updated_at))
    #             

    # Get object, note that it may be a phantom (1). We have the data
    # to push it into state (2). If it was not a phantom we should
    # possibly check modification times to choose which data to use.

    set obj [deref [dict get $json metadata url]]
    $obj = $json ; # TODO: strict check of modification dates?

    debug.v2 {==> $obj}
    return $obj
}

proc ::stackato::v2::commit {} {
    debug.v2 {}
    variable changed
    foreach obj [dict keys $changed] {
	$obj commit
    }

    debug.v2 {/done}
    return
}

proc ::stackato::v2::rollback {} {
    debug.v2 {}
    variable changed
    foreach obj [dict keys $changed] {
	$obj rollback
    }

    debug.v2 {/done}
    return
}

# # ## ### ##### ######## ############# #####################
## Internal support.
## - Database of active/live (in-memory) entity instances.
## - Database of changed entities.

proc ::stackato::v2::Enter {cmd} {
    debug.v2 {}
    variable isobject
    variable toobject

    if {[dict exists $isobject $cmd]} {
	return -code error -code {STACKATO CLIENT V2 LIVE DUPLICATE} \
	    "Attempt at duplicate entry of [$cmd type] entity $cmd"
    }

    dict set isobject $cmd on
    dict set toobject [$cmd url] $cmd

    debug.v2 {/done}
    return
}

proc ::stackato::v2::Drop {cmd} {
    debug.v2 {}
    variable isobject
    variable toobject

    if {![dict exists $isobject $cmd]} {
	return -code error -code {STACKATO CLIENT V2 LIVE UNKNOWN} \
	    "Attempt to remove unknown [$cmd type] entity $cmd"
    }

    dict unset isobject $cmd
    dict unset toobject [$cmd url]

    debug.v2 {/done}
    return
}

proc ::stackato::v2::IsEntity {cmd} {
    debug.v2 {}
    variable isobject
    set result [dict exists $isobject $cmd]
    debug.v2 {= $result}
    return $result
}

proc ::stackato::v2::IsKnown {url} {
    debug.v2 {}
    variable toobject
    set result [dict exists $toobject $url]
    debug.v2 {= $result}
    return $result
}

proc ::stackato::v2::GetKnown {url} {
    debug.v2 {}
    variable toobject
    set result [dict get $toobject $url]
    debug.v2 {= $result}
    return $result
}

proc ::stackato::v2::Url {type id} {
    # Add plural-'s' character for urls from types.
    return /v2/${type}s/$id
}

proc ::stackato::v2::TypeOf {url} {
    # Note: Chop the trailing plural 's' character of the type
    # name. Internally we mostly use singular form. The class names
    # for the types are among that.
    return [regsub {s$} [lindex [split $url /] end-1] {}]
}

proc ::stackato::v2::Decompose {url tv iv} {
    upvar 1 $tv type $iv id
    lassign [lrange [split $url /] end-1 end] type id
    # Note: Chop the trailing plural 's' character of the type
    # name. Internally we mostly use singular form. The class names
    # for the types are among that.
    regsub {s$} $type {} type
    return
}

proc ::stackato::v2::Change {cmd} {
    debug.v2 {}
    variable isobject
    variable changed

    # Do not check for existence in the object database.
    # Change is orthogonal and applies to 'new' instances also, which
    # are not recorded until commit.

    dict set changed $cmd yes

    debug.v2 {/done}
    return
}

proc ::stackato::v2::Unchanged {cmd} {
    debug.v2 {}
    variable isobject
    variable changed

    # Do not check for existence in the object database.
    # Change is orthogonal and applies to 'new' instances also, which
    # are not recorded until commit.

    dict unset changed $cmd

    debug.v2 {/done}
    return
}

# # ## ### ##### ######## ############# #####################
## Package configuration and state.

namespace eval ::stackato::v2 {
    # Configuration
    # instance command: client object

    variable client

    # State
    # dict (url --> object): translate url to existing object, if any.
    # dict (object --> '1'): validate object
    # dict (object --> '1'): set of changed objects.

    variable isobject {} ; # object --> '1'
    variable toobject {} ; # url --> object
    variable changed  {} ; # object --> '1'
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2 0
return
