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

debug level  v2/memory
debug prefix v2/memory {}

# # ## ### ##### ######## ############# #####################
## Public API.

proc ::stackato::v2::sort {field objects args} {
    debug.v2 {}

    if {[llength $objects] < 2} {
	return $objects
    }

    foreach o $objects {
	#debug.v2 {sort item: ([$o $field]) ==> $o}
	dict lappend per [$o $field] $o
    }

    set result {}
    foreach key [lsort {*}$args [dict keys $per]] {
	lappend result {*}[dict get $per $key]
    }

    return $result
}

proc ::stackato::v2::types {} {
    debug.v2 {}
    variable types
    debug.v2 {==> ($types)}
    return $types
}

proc ::stackato::v2::register {type} {
    debug.v2 {}
    variable types
    lappend  types $type
    debug.v2 {/done}
    return
}

proc ::stackato::v2::validate {type cmd} {
    debug.v2 {}
    if {[IsEntity $cmd]} {
	if {$type eq [$cmd typeof]} {
	    return [$cmd url]
	} else {
	    set atype [$cmd typeof]
	    return -code error -errorcode [list STACKATO V2 ENTITY MIS-MATCH $type $atype] \
		"Expected a $type entity, got the $atype entity \"$cmd\""
	}
    } else {
	return -code error -errorcode [list STACKATO V2 NON-ENTITY $type] \
	    "Expected a $type entity, got the non-entity \"$cmd\""
    }
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

    # ATTENTION :: HACK :: We may have a key "entity:type" overriding
    # the type information normally found in "metadata:url". This
    # means we have to go through 'deref-type' to get the object, so
    # that we can make the necessary corrections before creating the
    # in-memory object.

    set url   [dict get $json metadata url]
    set type  [dict get' $json entity type [TypeOf $url]]
    set id    [id-of $url]

    set obj [deref-type $type $id]

    # ATTENTION :: HACK :: If the type found above is
    # "user_provided_service_instance" it may have come from the
    # server with bad url information, i.e. matching
    # /v2/service_instance/* for itself and its relations (like
    # service-bindings). We have to correct these to the proper type.

    if {$type eq "user_provided_service_instance"} {
	FixUPSI json $id
    }

    $obj = $json ; # TODO: strict check of modification dates?
    debug.v2 {==> $obj}
    debug.v2/memory { KNOWN [$obj url]}
    return $obj
}

proc ::stackato::v2::FixUPSI {jv id} {
    upvar 1 $jv json
    # We are brutal here, treating the nested json as plain string and
    # rewriting all matching the bad url pattern. This should modify
    # only any json values, as the url is not used in keys.
    # DANGER: An id being a prefix of some other id, also used in the json.
    # Should not happen, with ids all the same length.
    regsub -all \
	"/v2/service_instances/$id"              $json \
	"/v2/user_provided_service_instances/$id" json

    # Now treat the data as nested dict again, and drop the
    # 'entity:type' key.
    dict unset json entity type
    return
}

proc ::stackato::v2::commit {} {
    debug.v2 {}
    variable changed

    dict for {obj _} $changed {
	$obj commit
    }

    debug.v2 {/done}
    return
}

proc ::stackato::v2::rollback {} {
    debug.v2 {}
    variable changed

    dict for {obj _} $changed {
	$obj rollback
    }

    debug.v2 {/done}
    return
}

# # ## ### ##### ######## ############# #####################
## Internal support.
## - Database of active/live (in-memory) entity instances.
## - Database of changed entities.

proc ::stackato::v2::reset {} {
    debug.v2 {}
    variable isobject

    dict for {obj _} $isobject {
	$obj destroy
    }

    debug.v2 {/done}
    return
}

proc ::stackato::v2::Enter {cmd} {
    debug.v2 {}
    variable isobject
    variable toobject

    if {[dict exists $isobject $cmd]} {
	return -code error -errorcode {STACKATO CLIENT V2 LIVE DUPLICATE} \
	    "Attempt at duplicate entry of [$cmd typeof] entity $cmd"
    }

    dict set isobject $cmd on
    dict set toobject [$cmd url] $cmd

    debug.v2/memory { ENTER_ [$cmd url]}
    debug.v2 {/done}
    return
}

proc ::stackato::v2::Drop {cmd} {
    debug.v2 {}
    variable isobject
    variable toobject

    if {![dict exists $isobject $cmd]} {
	return -code error -errorcode {STACKATO CLIENT V2 LIVE UNKNOWN} \
	    "Attempt to remove unknown [$cmd typeof] entity $cmd"
    }

    dict unset isobject $cmd
    dict unset toobject [$cmd url]

    debug.v2/memory { DROP__ [$cmd url]}
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

    # ATTENTION :: HACK :: Find all types of service instances, even
    # for a not-quite-correct incoming url.

    set found [dict exists $toobject $url]
    if {!$found && ([TypeOf $url] eq "service_instance")} {
	# Try again, maybe a user-provide service instance.
	regsub /service_instance $url /user_provided_service_instance url
	set found [dict exists $toobject $url]
    }

    debug.v2 {= $found}
    return $found
}

proc ::stackato::v2::GetKnown {url} {
    debug.v2 {}
    variable toobject

    # ATTENTION :: HACK :: Find all types of service instances, even
    # for a not-quite-correct incoming url.

    set found [dict exists $toobject $url]
    if {!$found && ([TypeOf $url] eq "service_instance")} {
	# Try again, maybe a user-provide service instance.
	regsub v2/service_instance $url v2/user_provided_service_instance url
    }

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
    # Special case 'ies' => 'y'
    set type [lindex [split $url /] end-1]
    if {[string match *ies $type]} {
	return [regsub {ies$} $type {y}]
    } else {
	return [regsub {s$} $type {}]
    }
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
    # list of type-names, i.e. client supported entities.

    variable isobject {} ; # object --> '1'
    variable toobject {} ; # url --> object
    variable changed  {} ; # object --> '1'

    variable types    {} ; # list (type-name...)
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2 0
return
