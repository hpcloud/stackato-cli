# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Entity base class.
## - Keeps entity meta data (id, url, timestamps)
## - Keeps entity attributes and data
## - Auto-generates attribute accessor methods.
## - Load on demand for phantom instances (no data, only url)
## - Tracking changes, writing changes (partial updates).
## - Reusing cmdr and local api-compatible validation types 
##   for the attribute types.

### TODO v2base - A1get, ANget - Alternates with url results, instead
### TODO v2base - A1get, ANget - of objs. Reduce amount of conversions,
### TODO v2base - A1get, ANget - depending on context.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require lambda
package require TclOO
package require struct::list
package require oo::util 1.2
package require stackato::jmap
package require stackato::v2
package require stackato::log
package require cmdr::color
# We assume to have mgr::client loaded.
# Cannot load it here, would be a cycle
# v2::base --> v2::xxx --> v2::client --> mgr::client --> v2::base

# Force nice formatting for human-readable data.
#json::write::indented 1
#json::write::aligned  1

# # ## ### ##### ######## ############# #####################
## Debugging

debug level  v2/base
debug prefix v2/base {[::string map [::list [self] [[self] show]] [debug caller]] | }

debug level  v2/base/summary
debug prefix v2/base/summary {}
# {[::string map [::list [self] [[self] show]] [debug caller]] | }

debug level  v2/memory
debug prefix v2/memory {}

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::v2::base::pp {
    # pseudo parameter - for cmdr validation types.
    # Assumes that the VT requires only the parameter name/label, and
    # a type, and no other information.

    variable myname

    method name= {n} {
	set myname $n
    }

    method name {} {
	return $myname
    }

    method the-name {} {
	return $myname
    }

    method label {} {
	return $myname
    }

    method type {} {
	return attribute
    }
}

oo::class create ::stackato::v2::base {
    # # ## ### ##### ######## #############
    ## Instance state

    # Introspection: attributes, references, many-relations
    # Each returns a dictionary mapping name to type.

    method attrs {} { return $myattr }
    method refs {}  { return $myone  }
    method many {}  { return $mymany }

    # Map from attribute name to json name.
    method json-names   {}     { return $myjname }
    method json-name-of {name} { dict get $myjname $name  }

    # Attribute data management
    # - - -- --- ----- --------
    # myjson - parsed json coming from the server.
    #          dict ( metadata --> dict (url,
    #                                    guid,
    #                                    created_at,
    #                                    modified_at)
    #                 entity   --> dict (name --> value))
    #
    # mydata - Current attribute values, indexed by attribute name.
    #          A cache filled from "myjson".
    #          dict (name --> value)
    #	Notes on attribute values:
    #	~~~~~~~~~~~~~~~~~~~~~~~~~~
    #	Regular   :	as-is	  API: as-is
    #	Reference :	url	  API: instance command
    #	Relation  :	list(url) API: list (inst.cmd)
    #
    # mydiff - Attribute values changed relative to last commit.
    #          Use for partial updates. Indexed by _json_ name of the
    #          attribute.
    #          dict (name --> value)
    # mymap  - Attribute json conversion hints for jmap.
    #
    # mylog  - Attribute changelog, indexed by attribute name,
    #          for rollback, i.e. cancellation of changes.
    #          dict (name --> list (old-defined, old-value))
    #
    # mydelete  - Boolean flag. True when the object is to be deleted.
    # mydelargs - Form arguments for delete.
    #
    # myheaders - REST headers from the last commit (change-by-url)
    #
    # Note: References to other entities (&-attributes, and relations)
    #       are stored as guid in 'mydata' (and url in myjson).
    #       Because of the indirection through the global entity map
    #       it is not necessary to manage reference counts. The referenced
    #       entity is brought into memory as necessary.

    # Attribute configuration
    # - - -- --- ----- --------
    # mydefault - Map from attribute names to default values.
    #             dict (name --> value).
    #
    # myattr, myone, mymany - Maps of attribute names and
    #                         relationships, to their respective
    #                         types.
    #
    #     Required by the decoder of summaries.
    #
    # myexcluded - List of forbidden attribute names.

    # Most other configuration data is encoded in the method forwards
    # created per attribute or relation, i.e. the fixed arguments of
    # said forwards.

    variable \
	myjson mydata mydiff mylog mydefault mydelete mymap myfullmap \
	myattr myone mymany myexcluded mysumaction mynote mydelargs \
	mylabel mypp myheaders myjname \
	myfake

    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	debug.v2/base {}

	set mypp [::stackato::v2::base::pp new]

	# Direct access ALL ::stackato::v2 commands.
	namespace path [linsert	[namespace path] end \
			    ::stackato::v2 \
			    ::stackato::mgr::client]
	namespace import ::stackato::jmap
	namespace import ::stackato::log::display
	namespace import ::cmdr::color

	# Note: Use of 'Enter' is controlled by the caller. Perform
	# construction only through the public ::stackato::v2
	# commands.

	# Note 2: Derived classes are expected to run the base class
	# construction first.
	# --> mymap is filled

	# Fill various missing variables with defaults
	if {![info exists myattr]}      { set myattr {} }
	if {![info exists myone ]}      { set myone  {} }
	if {![info exists mymany]}      { set mymany {} }
	if {![info exists myfake]}      { set myfake {} }
	if {![info exists myjname]}     { set myjname {} }
	if {![info exists mysumaction]} { set mysumaction {} }

	# Convert to full hint structure for json map.
	set mymap [list dict $mymap]
	set myfullmap [list dict [list entity $mymap metadata dict]]

	debug.v2/base {json map = ($mymap)}
	debug.v2/base {json map = ($myfullmap)}

	set mydelete   0
	set mydelargs  {}
	set mydefault  {} ; # Defaults for missing server information.
	set myjson     {} ; # Server side json, if any.
	set mydata     {} ; # Client side attribute cache
	set mydiff     {} ; # Data of changed attributes
	set mylog      {} ; # Saved old values of changes attributes.

	# Skip object map entry for "new" entities.
	if {$url eq {}} return

	debug.v2/base {phantom $url}

	# Fake the url.
	dict set myjson metadata url  $url
	dict set myjson metadata guid [id-of $url]

	# ATTENTION :: The fake url may get a correction on
	# server-side creation, when the actual API endpoint/type
	# becomes known. Example: MSI => SI.

	Enter [self]
	return
    }

    destructor {
	if {[my is new]} return
	# Remove only phantoms and replicas from the object map.
	Drop [self]
	return
    }

    # # ## ### ##### ######## #############
    ## Debug helpers.

    method as-json {} {
	# Main entry point. Clear dict of seen entities.
	my ResolvePhantom as-json
	jmap seen-clear

	debug.v2/base {$myfullmap}
	jmap map $myfullmap $myjson
    }

    method as-json-map {} {
	# Secondary entry point from within 'jmap map' (1ref handling).
	# Keep knowledge of seen entities to block run-away recursion.
	my ResolvePhantom as-json
	jmap map $myfullmap $myjson
    }

    method delta {} {
	jmap map $mymap $mydiff
    }

    classmethod show {} { self }
    method show {} {
	# Inlined 'typeof' and 'id' methods.
	# Do not use debug narrative, prevent infinite recursion.
	# See debugging section at top for use.

	set type [namespace tail [info object class [self]]]
	if {[info exists myjson]} {
	    set id [dict get' $myjson metadata guid ????]
	} else {
	    set id ????
	}
	return "${type}::$id ([self])"
    }

    # # ## ### ##### ######## #############
    ## Identity

    method == {other} {
	if {$other eq {}} { return 0 }
	string equal [my url] [$other url]
    }
    export ==

    # # ## ### ##### ######## #############
    ## General listing of entities
    ## ATTENTION! Replicated in derived class service_instances.
    ## For use by subsequent derived classes. Possible bug in the
    ## setup of class methods.

    # Dependencies
    # find-by --> list-filter --> C/filtered-of <canned list-of>
    # list    --> C/list-of

    classmethod list {{depth 0} args} {
	# args = config
	debug.v2/base {}
	set type [namespace tail [self]]
	if {[string match *y $type]} {
	    # y => ies pluralization
	    set type [string range $type 0 end-1]ies
	} else {
	    # s pluralization.
	    append type s
	}
	set client [stackato::mgr client authenticated]
	if {$depth > 0} {
	    lappend args depth $depth
	}
	stackato::v2 deref* [$client list-of $type $args]
    }

    classmethod list-filter {key value {depth 0} {config {}}} {
	debug.v2/base {}
	set type [namespace tail [self]]
	if {[string match *y $type]} {
	    # y => ies pluralization
	    set type [string range $type 0 end-1]ies
	} else {
	    # s pluralization.
	    append type s
	}
	set client [stackato::mgr client authenticated]
	stackato::v2 deref* [$client filtered-of $type $key $value $depth $config]
    }

    classmethod find-by {key value {depth 0} {config {}}} {
	debug.v2/base {}
	set matches [my list-filter $key $value $depth $config]
	switch -exact -- [llength $matches] {
	    0       { my NotFound  $key $value }
	    1       { return [lindex $matches 0] }
	    default { my Ambiguous $key $value }
	}
    }

    classmethod NotFound {key value} {
	set type [namespace tail [self]]
	return -code error \
	    -errorcode [list STACKATO CLIENT V2 [string toupper $type] [string toupper $key] NOTFOUND $value] \
	    "[string totitle $type] $key \"$value\" not found"
    }

    classmethod Ambiguous {key value} {
	set type [namespace tail [self]]
	return -code error \
	    -errorcode [list STACKATO CLIENT V2 [string toupper $type] [string toupper $key] AMIGUOUS $value] \
	    "Ambiguous $type $key \"$value\""
    }

    # # ## ### ##### ######## #############

    method header {k} {
	dict get $myheaders $k
    }

    method have-header {k} {
	dict exists $myheaders $k
    }

    method delete {args} {
	debug.v2/base {}
	# Flag for destruction. Requires a commit to update the server.
	set mydelete 1
	set mydelargs $args
	return
    }

    method delete! {} {
	my delete
	my commit
	return
    }

    method journal {} {
	debug.v2/base {}
	return $mylog
    }

    forward save   my commit
    forward revert my rollback

    method rollback {} {
	debug.v2/base {}
	# Move saved data back into current state.
	dict for {attr spec} $mylog {
	    debug.v2/base {revert $attr ==> $spec}

	    lassign $spec defined old
	    if {$defined} {
		debug.v2/base {revert $attr ==> old value ($old)}
		dict set   mydata $attr $old
	    } else {
		debug.v2/base {revert $attr ==> unset}
		dict unset mydata $attr
	    }
	}

	# Clear state backup and delta collection.
	# Current state fully restored to before any changes.
	set mylog  {}
	set mydiff {}

	# Also undo 'flagged for destruction'.
	set mydelete  0
	set mydelargs {}

	# Drop from the in-memory set of committable instances
	Unchanged [self]

	debug.v2/base {/done}
	return
    }

    method commit-with {uuid} {
	debug.v2/base {}
	# Hack the delta to force a specific uuid on the CC for this entity.
	# Only user, so far is 'user', as its creation is spread over CC and UAA.
	# self must be 'new'

	if {![my is new]} {
	    my InternalError "Bad object [self] for commit-with, is not 'new'" \
		COMMIT-WITH
	}

	my change guid $uuid
	my commit
	return
    }

    method commit {args} {
	debug.v2/base {}

	# args = form parameters (url encoded).
	if {[llength $args]} {
	    set form ?[http::formatQuery {*}$args]
	} else {
	    set form {}
	}

	set state [my state]
	debug.v2/base {$state $form}

	switch -exact -- $state {
	    delete {
		set url [my url]
		if {$url ne {}} {
		    if {[llength $mydelargs]} {
			set form ?[http::formatQuery {*}$mydelargs]
		    } else {
			set form {}
		    }
		    [authenticated] delete-by-url $url$form
		}

		# Always squash the client-side in-memory
		# representation.
		my destroy
		return
	    }
	    new {
		# New object. Not known server side. Create, then load back
		# the full state from the response. In case of attributes
		# not usable in create follow with an update cycle to push
		# them as well.

		# The mydiff contains all the new values to transfer.
		# NOTE: 'unset' attributes are represented by a 'null' value.
		# NOTE: Take this into account during transformation.
		#TODO proper null handling

		set json [my delta]

		debug.v2/base {Convert ($mydiff)}
		debug.v2/base {Via     $mymap}
		debug.v2/base {Result  $json}

		my = [[authenticated] create-for-type [my create-url] $json]
	    }
	    replica {
		# Check for changes, and ignore if there are none.
		if {![dict size $mydiff]} {
		    debug.v2/base {no changes, no upload}
		    return
		}

		set json [my delta]

		debug.v2/base {Convert ($mydiff)}
		debug.v2/base {Via     $mymap}
		debug.v2/base {Result  $json}

		lassign [[authenticated] change-by-url [my url]$form $json] new myheaders

		# Canonicalize to lower-case keys. (Original keys are kept).
		dict for {k v} $myheaders {
		    dict set myheaders [string tolower $k] $v
		}

		my = $new

	    }
	    phantom {
		# Phantoms are not changed, by dint of not being
		# loaded. Ignore.
		return
	    }
	    default {
		my InternalError "unknown entity state $state" UNKNOWN STATE
	    }
	}

	debug.v2/base {/done}
	return
    }

    method = {json} {
	debug.v2/base {}
	# This is trivial, compared to the older code.
	# - Save the json, and clear everything else.

	# Temporarily revoke the object.
	if {![my is new]} { Drop [self] }

	# On attribute access the json data is pulled lazily into the
	# in-memory cache. The older code did this immediately,
	# possibly converting lots of things not needed by the actual
	# operation.
	#
	# This deferal is especially important for references,
	# i.e. &type and to-many relations. Create phantoms and
	# replicas only when/if needed.
	#
	# Having just pulled from the server we start with no changes
	# and differences also.

	set actualtype   [TypeOf [dict get $json metadata url]]
	set expectedtype [my typeof]

	debug.v2/base {have $expectedtype}
	debug.v2/base {got  $actualtype}

	if {0 && ($expectedtype ne $actualtype)} {
	    my DataTypeMismatch \
		"attempting to assign $actualtype data to $expectedtype instance" \
		 ENTITY $expectedtype JSON $actualtype
	}

	set myjson     $json
	set mydelete   0
	set mydata     {} ; # Client side attribute cache
	set mydiff     {} ; # Data of changed attributes
	set mylog      {} ; # Saved old values of changes attributes.


	# (Re)enter the object with its final identity.
	Enter [self]

	debug.v2/base {assigned [my as-json]}
	debug.v2/base {/done}
	return
    }
    export =

    method invalidate {} {
	# Clear all data, forces a reload on next access to any attribute.
	set myjson     {}
	set mydelete   0
	set mydata     {} ; # Client side attribute cache
	set mydiff     {} ; # Data of changed attributes
	set mylog      {} ; # Saved old values of changes attributes.
    }

    method change {k v} {
	dict set mydiff $k $v
	return
    }

    method force-inlined {} {
	debug.v2/memory { EXPAND [my url] BEGIN}

	dict for {k v} $myone {
	    if {![my @$k inlined?]} continue
	    [my @$k] force-inlined
	}
	dict for {k v} $mymany {
	    if {![my @$k inlined?]} continue
	    foreach ref [my @$k] {
		$ref force-inlined
	    }
	}

	debug.v2/memory { EXPAND [my url] END}
	return
    }

    # # ## ### ##### ######## #############
    ## General information

    method client {} {
	debug.v2/base {}
	set c [authenticated]
	debug.v2/base {==> $c}
	return $c
    }

    method typeof {} {
	debug.v2/base {}
	set type [namespace tail [info object class [self]]]
	debug.v2/base {==> $type}
	return $type
    }

    method create-url {} {
	set type [my typeof]
	if {[string match *y $type]} {
	    # y => ies pluralization
	    set type [string range $type 0 end-1]ies
	} else {
	    # s pluralization.
	    append type s
	}
	return $type
    }

    method delete-url {} {
	set type [my typeof]
	if {[string match *y $type]} {
	    # y => ies pluralization
	    set type [string range $type 0 end-1]ies
	} else {
	    # s pluralization.
	    append type s
	}

	return $type
    }

    method url {} {
	debug.v2/base {}
	set url [dict get' $myjson metadata url {}]
	debug.v2/base {==> $url}
	return $url
    }

    method id {} {
	debug.v2/base {}
	if {[info exists myjson]} {
	    set id [dict get' $myjson metadata guid ????]
	} else {
	    set id ????
	}
	debug.v2/base {==> $id}
	return $id
    }

    method meta {field} {
	debug.v2/base {}
	set r [dict get $myjson metadata $field]
	debug.v2/base {==> $r}
	return $r
    }

    method created {} {
	debug.v2/base {}
	set r [dict get $myjson metadata created_at]
	debug.v2/base {==> $r}
	return $r
    }

    method modified {} {
	debug.v2/base {}
	set r [dict get $myjson metadata modified_at]
	debug.v2/base {==> $r}
	return $r
    }

    method state {} {
	debug.v2/base {}
	if {$mydelete} {
	    set state delete
	} elseif {![dict exists $myjson metadata url]} {
	    set state new
	} elseif {![dict exists $myjson entity]} {
	    set state phantom
	} else {
	    set state replica
	}

	debug.v2/base {==> $state}
	return $state
    }

    method is {what} {
	debug.v2/base {}
	set flag [expr {[my state] eq $what}]
	debug.v2/base {==> $flag}
	return $flag
    }

    # # ## ### ##### ######## #############

    # Summaries ... The main point of summarization is to get the
    # important data about a set of rleated objects very quickly (one
    # REST round trip) from the server without having to explicitly
    # walk the relations, and pull all pieces. The difference to
    # listings with inline-relations-depth > 0 is that irrelevant
    # information is not collected by the summary, nor transfered.

    method summary {} {
	debug.v2/base {}
	set json [[authenticated] json_get [my url]/summary]

	debug.v2/base {==> $json}
	return $json
    }

    method summarize {{data {}}} {
	debug.v2/base/summary {}

	# Set flag to prevent assignments from resolving the
	# phantom. That would defeat the purpose using a summary in
	# the first place. Fake as 'replica' with lots of
	# undefined attributes.
	dict set myjson entity {}

	if {[llength [info level 0]] == 2} {
	    debug.v2/base/summary {retrieve summary}
	    set json  [my summary]
	    set stype [my typeof]
	    debug.v2/base/summary {$stype summary $json}
	} else {
	    debug.v2/base/summary {outer summary}
	    lassign $data json stype
	    debug.v2/base/summary {$stype summary $json}
	}

	dict for {k v} $json {
	    debug.v2/base/summary {process $k ...}

	    if {[dict exists $mysumaction $k]} {
		debug.v2/base/summary {    special action}

		# Run the special action associated with this key
		set action [dict get $mysumaction $k]
		{*}$action $v

	    } elseif {[dict exists $myattr $k]} {
		debug.v2/base/summary {    attribute}

		# Simply assign value to self.
		my @$k set $v

	    } elseif {[dict exists $myone $k]} {
		set type [dict get $myone $k]
		debug.v2/base/summary {    reference --> $type}

		# Recurse!
		# Create phantom for the referenced object, and have
		# it summarize itself from the value.  Then
		# assign. Value is a dict. The guid element tells us
		# the id. The relation type provides the rest.

		set uuid [dict get $v guid]
		set obj  [deref-type $type $uuid]
		$obj summarize [list $v $stype]
		my @$k set $obj

	    } elseif {[dict exists $mymany $k]} {
		set type [dict get $mymany $k]
		debug.v2/base/summary {    many relation --> $type}

		# Recurse!
		# Create phantoms for the referenced objects, and have
		# them summarize themselves from the value.  Then
		# assign. Value is a dict. The guid element tells us
		# the id. The relation type provides the rest.

		set objlist {}
		foreach item $v {
		    set uuid [dict get $item guid]
		    set obj [deref-type $type $uuid]
		    $obj summarize [list $item $stype]
		    lappend objlist $obj
		}

		my @$k set $objlist
	    } else {
		debug.v2/base/summary {    ignored}
	    }
	}

	# Change state back into a phantom, so that access through the
	# attributes not provided by the summary generate a regular
	# download. This of course points to data which should be in
	# the summary, but is not.
	dict unset myjson entity
	#set mynote "Incomplete $stype summary, retrieving full entity..."

	debug.v2/base/summary {/done ==> [self]}
	return [self]
    }

    # # ## ### ##### ######## #############
    ## Attribute access

    method Access {name jname type nullable args} {
	debug.v2/base {}

	# - Get      : |args|=0
	# - Set      : set <value>
	# - Unset    : unset
	# - Defined? : defined?
	# - Label    : label
	#
	# type is command prefix, cmdr validation type, or API
	# compatible.

	if {![llength $args]} {
	    return [my Aget $name $jname $type $nullable]
	}

	set args [lassign $args method]
	return [my A$method $name $jname $type $nullable {*}$args]
    }

    method Access1 {name jname type args} {
	debug.v2/base {}

	# - Get      : |args|=0
	# - Set      : set <value>
	# - Unset    : unset
	# - Defined? : defined?
	# -          : <m> args...
	#
	# type is name of other entity, without namespace prefix.

	if {![llength $args]} {
	    return [my A1get $name $jname $type]
	}

	set args [lassign $args method]
	if {$method in {set unset defined? inlined?}} {
	    return [my A1$method $name $jname $type {*}$args]
	}

	set obj [my A1get $name $jname $type]
	return [$obj $method {*}$args]
    }

    method AccessN {name xname jname type args} {
	# name = attribute
	# xname = relationship, singular
	# type singular
	debug.v2/base {}

	# - Get      : |args|=0
	# - Get      : get ?depth?
	# - Set      : set <value>
	# - Get      : get* config-dict ?cmd ...?
	# - Unset    : unset
	# - Defined? : defined?
	# - Add      : add    <x>...
	# - Remove   : remove <x>...
	# - Map      : map    <cmd-prefix>
	# - Filter   : filter <cmd-prefix>
	#            : filter-by <attr> <value>
	# -          : <m> args... (deref+invoke mapped over all elements).

	if {![llength $args]} {
	    return [my ANget $name $jname $type]
	}

	set args [lassign $args method]
	if {$method in {decache set get get* unset defined? inlined?}} {
	    return [my AN$method $name $jname $type {*}$args]
	}

	if {$method eq "add"} {
	    return [my Add $name $xname $jname $type $args]
	} elseif {$method eq "remove"} {
	    return [my Remove $name $xname $jname $type $args]
	} elseif {$method eq "map"} {
	    return [my Map $name $jname $type {*}$args]
	} elseif {$method eq "filter"} {
	    return [my Filter $name $jname $type {*}$args]
	} elseif {$method eq "filter-by"} {
	    return [my Filter $name $jname $type \
			[lambda {attr val obj} {
			    string equal $val [$obj $attr]
			} {*}$args]]
	}

	return [my Map $name $jname $type [lambda {cmd o} {
	    $o {*}$cmd
	} [list $method {*}$args]]]
    }

    # # ## ### ##### ######## #############
    ## Attribute access, internals - Regular
    ## Aget, Aset, Aunset

    method Alabel {name jname type nullable} {
	debug.v2/base {}
	return [dict get $mylabel $name]
    }

    method Adefined? {name jname type nullable} {
	# Cached, yes.
	if {[dict exists $mydata $name]} { return 1 }

	# Not cached, new => No.
	if {[my is new]} { return 0 }

	my ResolvePhantom @$name

	# A replica, and defined => Yes.
	if {[dict exists $myjson entity $jname]} { return 1 }

	# Overall no.
	return 0
    }

    method Aget {name jname type nullable} {
	debug.v2/base {}

	# Take from cache.
	if {[dict exists $mydata $name]} {
	    debug.v2/base {cached  ==> [dict get $mydata $name]}
	    return [dict get $mydata $name]
	}

	if {[my is new]} {
	    my Undefined "attribute $name" ATTRIBUTE $name
	}

	my ResolvePhantom @$name

	if {[dict exists $myjson entity $jname]} {
	    set value [dict get $myjson entity $jname]
	    debug.v2/base {served  ==> $value}

	} elseif {[dict exists $mydefault $name]} {
	    set value [dict get $mydefault $name]
	    debug.v2/base {default ==> $value}

	} else {
	    debug.v2/base {'$jname' not found in: {[lsort -dict [dict keys [dict get $myjson entity]]]}}

	    my Undefined "attribute $name" ATTRIBUTE $name
	}

	if {!$nullable || ($value ne "null")} {
	    # Reverse validation of the data coming from the server.
	    # Also normalization.
	    $mypp name= $name
	    set value [{*}$type validate $mypp $value]
	} else {
	    # Translate json null into Tcl empty string.
	    set value {}
	}

	dict set mydata $name $value
	return $value
    }

    method Aset {name jname type nullable newvalue} {
	debug.v2/base {}

	# Validate and canonicalize before even trying to record the
	# proposed change. Use the pseudo-parameter to supply the
	# attribute name in case of validation failure. Skip this if
	# the attribute is nullable and set to null.
	if {!$nullable || ($newvalue ne "null")} {
	    $mypp name= $name
	    set newvalue [{*}$type validate $mypp $newvalue]
	}

	# Get current value.
	try {
	    set olddefined 1
	    set oldvalue   [my Aget $name $jname $type $nullable]
	} trap {STACKATO CLIENT V2 UNDEFINED ATTRIBUTE} {e o} {
	    set olddefined 0
	    set oldvalue   {}
	}

	debug.v2/base {olddefined = $olddefined}
	debug.v2/base {oldvalue   = ($oldvalue)}
	debug.v2/base {newvalue   = ($newvalue)}

	if {$olddefined && ($oldvalue == $newvalue)} {
	    # No change, nothing to do.
	    debug.v2/base {no change, ignore}
	    return
	}

	# Save new value as current.
	dict set mydata $name $newvalue

	# Update delta information.

	# Note: We are not checking if the new value is the same as
	# stored in the log. IOW implicit, user-performed rollbacks
	# are neither registered, nor reacted upon.
	my change $jname $newvalue

	if {[dict exists $mylog $name]} return
	dict set mylog $name [list $olddefined $oldvalue]

	# Add to the in-memory set of committable instances
	Change [self]
	return
    }

    method Aunset {name jname type nullable} {
	debug.v2/base {}

	# Get current value for saving to log.
	try {
	    set olddefined 1
	    set oldvalue   [my Aget $name $jname $type $nullable]
	} trap {STACKATO CLIENT V2 UNDEFINED ATTRIBUTE} {e o} {
	    set olddefined 0
	    set oldvalue   {}
	}

	if {!$olddefined} {
	    # No change, nothing to do.
	    return
	}

	# Save new value as current.
	dict unset mydata $name

	# Update delta information.

	# Note: We are not checking if the new value is the same as
	# stored in the log. IOW implicit, user-performed rollbacks
	# are neither registered, nor reacted upon.

	my change $jname null

	if {[dict exists $mylog $name]} return
	dict set mylog $name [list $olddefined $oldvalue]

	# Add to the in-memory set of committable instances
	Change [self]
	return
    }

    # # ## ### ##### ######## #############
    ## Attribute access, internals - To1
    ## A1get, A1set, A1unset

    method A1defined? {name jname type} {
	# Cached, yes.
	if {[dict exists $mydata $name]} { return 1 }

	# Not cached, new => No.
	if {[my is new]} { return 0 }

	my ResolvePhantom ^$name

	# A replica, and defined => Yes.
	if {[dict exists $myjson entity $jname]}       { return 1 }
	if {[dict exists $myjson entity ${jname}_url]} { return 1 }

	# Overall no.
	return 0
    }

    method A1inlined? {name jname type} {
	# Cached, no.
	if {[dict exists $mydata $name]} { return 0 }

	# Not cached, new => No.
	if {[my is new]} { return 0 }

	my ResolvePhantom ^$name

	# A replica, and inline defined => Yes.
	if {[dict exists $myjson entity $jname] &&
	    [dict exists $myjson entity ${jname}_url]} {
	    return 1
	}

	# Overall no.
	return 0
    }

    method A1get {name jname type} {
	debug.v2/base {}

	# jname is a stem. The underlying json may contain one of two
	# possible keys:
	#
	# - jname       => The referenced object is inlined.
	# - (jname)_url => Plain reference by url

	# Note: The cache stores the url, not the entity instance
	# command. Indirection through object map.

	# Take from cache
	if {[dict exists $mydata $name]} {
	    set url [dict get $mydata $name]
	    debug.v2/base {cached  ==> $url}
	    return [deref $url]
	}

	if {[my is new]} {
	    my Undefined "attribute $name" ATTRIBUTE $name
	}

	my ResolvePhantom ^$name

	if {[dict exists $myjson entity $jname]} {
	    # Inlined entity found. Create object and save url for
	    # access.

	    set json [dict get $myjson entity $jname]
	    set obj [get-for $json]
	    set url [$obj url]
	    debug.v2/base {inlined ==> $url}

	} elseif { [dict exists $myjson entity ${jname}_guid] &&
		   [[authenticated] has-orphan [dict get $myjson entity ${jname}_guid]] } {

	    # Semi-inlined entity through orphan-relations. We can
	    # expect its data to be found in the orphan-cache of the
	    # client. Well, no. The _guid key can exist and be set
	    # even for a plain entity without orphan-relations
	    # information. So, testing for existence before going into
	    # this branch, and pass to the _url branch if the data is
	    # missing.

	    set guid [dict get $myjson entity ${jname}_guid]
	    set json [[authenticated] get-orphan $guid]

	    set obj [get-for $json]
	    set url [$obj url]
	    debug.v2/base {inlined ==> $url}

	    # Make it a full inline.
	    # Ok with Tcl, only a reference with a shared Tcl_Obj.
	    dict set $myjson entity $jname $json

	} elseif {[dict exists $myjson entity ${jname}_url]} {
	    # Entity reference. Save the url for access.

	    set url [dict get $myjson entity ${jname}_url]
	    debug.v2/base {served  ==> $url}

	    if {$type eq "service_instance"} {

		# HACK to support MSI|UPSI. Preload. We have to
		# inspect the json information to know the proper type
		# (MSI vs UPSI) for the in-memory object to
		# create. Without doing this the deref at the bottom
		# will use the SI base-class, wrong on all accounts.

		set json [[authenticated] get-by-url $url]
		set url [[get-for $json] url]
	    }
	} elseif {[dict exists $mydefault $name]} {
	    set url [dict get $mydefault $name]
	    debug.v2/base {default ==> $url}

	} else {
	    my Undefined "attribute $name" ATTRIBUTE $name
	}

	dict set mydata $name $url
	return [deref $url]
    }

    method A1set {name jname type newvalue} {
	# Like Aset, except it expects newvalue to be a 'type'
	# instance, and pulls the url for actual storage.
	# (de-transform, like A1get transforms (generates obj on access).

	debug.v2/base {}

	# newvalue must be an entity instance of <type>
	set newvalue [validate $type $newvalue]
	# newvalue now is url to the specified entity

	# ------ From here nearly identical to Aset -------------
	# Differences:
	# - Nature and retrieval of old value.
	# - json key and data for mydiff.

	# Get current value. (url of object!)
	try {
	    set olddefined 1
	    set oldvalue   [[my A1get $name $jname $type] url]
	} trap {STACKATO CLIENT V2 UNDEFINED ATTRIBUTE} {e o} {
	    set olddefined 0
	    set oldvalue   {}
	}

	if {$olddefined && ($oldvalue == $newvalue)} {
	    # No change, nothing to do.
	    return
	}

	# Save new value as current.
	dict set mydata $name $newvalue

	# Update delta information.

	# Note: We are not checking if the new value is the same as
	# stored in the log. IOW implicit, user-performed rollbacks
	# are neither registered, nor reacted upon.

	my change ${jname}_guid [id-of $newvalue]

	if {[dict exists $mylog $name]} return
	dict set mylog $name [list $olddefined $oldvalue]

	# Add to the in-memory set of committable instances
	Change [self]
	return
    }

    method A1unset {name jname type} {
	debug.v2/base {}

	# Get current value for saving to log.
	try {
	    set olddefined 1
	    set oldvalue   [[my A1get $name $jname $type] url]
	} trap {STACKATO CLIENT V2 UNDEFINED ATTRIBUTE} {e o} {
	    set olddefined 0
	    set oldvalue   {}
	}

	if {!$olddefined} {
	    # No change, nothing to do.
	    return
	}

	# Save new value as current.
	dict unset mydata $name

	# Update delta information.

	# Note: We are not checking if the new value is the same as
	# stored in the log. IOW implicit, user-performed rollbacks
	# are neither registered, nor reacted upon.

	my change ${jname}_guid null

	if {[dict exists $mylog $name]} return
	dict set mylog $name [list $olddefined $oldvalue]

	# Add to the in-memory set of committable instances
	Change [self]
	return
    }

    # # ## ### ##### ######## #############
    ## Attribute access, internals - ToN
    ## ANget, ANset, ANunset, Add, Remove, Map

    method ANdefined? {name jname type} {
	# Cached, yes.
	if {[dict exists $mydata $name]} { return 1 }

	# Not cached, new => No.
	if {[my is new]} { return 0 }

	my ResolvePhantom ^^$name

	# A replica, and defined => Yes.
	if {[dict exists $myjson entity $jname]}       { return 1 }
	if {[dict exists $myjson entity ${jname}_url]} { return 1 }

	# Overall no.
	return 0
    }

    method ANinlined? {name jname type} {
	# Cached, no. (any inline is resolved)
	if {[dict exists $mydata $name]} { return 0 }

	# Not cached, new => No.
	if {[my is new]} { return 0 }

	my ResolvePhantom ^^$name

	# A replica, and defined => Yes.
	if {[dict exists $myjson entity $jname] &&
	    [dict exists $myjson entity ${jname}_url]} {
	    return 1
	}

	# Overall no.
	return 0
    }

    method ANget {name jname type {depth 0}} {
	debug.v2/base {}

	# Take from cache.
	if {[dict exists $mydata $name]} {
	    set urllist [dict get $mydata $name]
	    debug.v2/base {cached  ==> $urllist}
	    return [deref* $urllist]
	}

	if {[my is new]} {
	    my Undefined "relation $name" RELATION $name
	}

	my ResolvePhantom ^^$name

	if {[dict exists $myjson entity $jname]} {
	    # Inlined list of related entities found. Create the
	    # objects and save their urls for access.

	    # NOTE: Under orphan-relations the elements of the list
	    # are guids, not json. We are testing this dynamically.

	    set urllist {}
	    set objlist {}

	    set jl {}
	    foreach json [dict get $myjson entity $jname] {
		if {[[authenticated] has-orphan $json]} {
		    # json is actually a guid. The json is in the
		    # client's orphan cache.
		    set json [[authenticated] get-orphan $json]
		    lappend jl $json
		    # Replace the list of uuids with the list of jsons
		    # We assume that this branch is executed either none, or all the time.
		    dict set myjson entity $jname $jl
		}

		set obj [get-for $json]
		set url [$obj url]
		debug.v2/base {inlined ==> $url}

		lappend objlist $obj
		lappend urllist $url
	    }

	} elseif {[dict exists $myjson entity ${jname}_url]} {
	    # Implied list of entity references, as single
	    # url returning paginated array of the resources.

	    set url [dict get $myjson entity ${jname}_url]

	    debug.v2/base {origin = $url}

	    set config {}
	    if {$depth > 0} {
		dict set config depth $depth
	    }
	    set urllist [[authenticated] list-by-url $url $config]

	    if {$type eq "service_instance"} {
		# HACK to support MSI|UPSI. Preload the objects. We
		# have to inspect the json information to know the
		# proper type (MSI vs UPSI) for the in-memory object
		# to create. Without doing this the deref* below will
		# use the SI base-class, wrong on all accounts.

		set tmp {}
		foreach u $urllist {
		    set json [[authenticated] get-by-url $u]
		    lappend tmp [[get-for $json] url]
		}
		set urllist $tmp
	    }

	    set objlist [deref* $urllist]
	} else {
	    # else: defaults - none
	    my Undefined "attribute $name" ATTRIBUTE $name
	}

	# Remember for future access.
	dict set mydata $name $urllist
	return $objlist
    }

    method ANdecache {name jname type} {
	debug.v2/base {}
	set cachekey ${name}|*
	foreach k [dict keys $mydata $cachekey] {
	    dict unset mydata $k
	}
	return
    }

    method ANget* {name jname type config args} {
	debug.v2/base {}

	set cachekey ${name}|[dict sort $config]
	debug.v2/base {cached? ($cachekey)}

	# Take from cache.
	if {[dict exists $mydata $cachekey]} {

	    set urllist [dict get $mydata $cachekey]
	    debug.v2/base {cached  ==> $urllist}
	    set objlist [deref* $urllist]
	    #return [deref* $urllist]
	} else {
	    # Nothing cached, compute.

	    if {[my is new]} {
		my Undefined "relation $name" RELATION $name
	    }

	    my ResolvePhantom ^^$name

	    # Note: With a custom search configuration the information
	    # cannot be cached in the json, we have to retrieve it
	    # always from the target. The first clause below ensures
	    # that the json cache is skipped.

	    if {![dict size $config] && [dict exists $myjson entity $jname]} {
		# Inlined list of related entities found. Create the
		# objects and save their urls for access.

		debug.v2/base {inlined}

		# NOTE: Under orphan-relations the elements of the
		# list are guids, not json. We are testing this dynamically.

		set urllist {}
		set objlist {}

		set jl {}
		foreach json [dict get $myjson entity $jname] {
		    if {[[authenticated] has-orphan $json]} {
			# json is actually a guid. The json is in the
			# client's orphan cache.
			set json [[authenticated] get-orphan $json]
			lappend jl $json
			# Replace the list of uuids with the list of jsons
			# We assume that this branch is executed either none, or all the time.
			dict set myjson entity $jname $jl
		    }

		    set obj [get-for $json]
		    set url [$obj url]
		    debug.v2/base {inlined ==> $url}

		    lappend objlist $obj
		    lappend urllist $url
		}
	    } elseif {[dict exists $myjson entity ${jname}_url]} {
		# Implied list of entity references, as single
		# url returning paginated array of the resources.

		set url [dict get $myjson entity ${jname}_url]
		debug.v2/base {origin = $url}

		set urllist [[authenticated] list-by-url $url $config]
		set objlist [deref* $urllist]
	    } elseif {[dict exists $myfake $name]} {

		set url [my url]/$name
		dict set myjson entity ${jname}_url $url

		set urllist [[authenticated] list-by-url $url $config]
		set objlist [deref* $urllist]

	    } else {
		# else: defaults - none
		my Undefined "attribute $name" ATTRIBUTE $name
	    }

	    # Remember for future access.
	    dict set mydata $cachekey $urllist
	}

	# Return as is without a processing command.
	if {![llength $args]} {
	    return $objlist
	}

	# Analogous to AccessN, modified for direct access to the list
	# of objects.
	set args [lassign $args method]
	if {$method eq "map"} {
	    return [my MapCore $objlist {*}$args]
	} elseif {$method eq "filter"} {
	    return [my FilterCore $objlist {*}$args]

	} elseif {$method eq "filter-by"} {
	    return [my FilterCore $objlist \
			[lambda {attr val obj} {
			    string equal $val [$obj $attr]
			} {*}$args]]
	}

	return [my MapCore $objlist [lambda {cmd o} {
	    $o {*}$cmd
	} [list $method {*}$args]]]
    }

    method ANset {name jname type newvalue} {
	debug.v2/base {}
	# newvalue = list of type entity instances

	# Like A1set, except it expects newvalue to be a list of 'type'
	# instances, and pulls their urls for actual storage.
	# (de-transform, like ANget transforms (generates obj on access).

	debug.v2/base {}

	# newvalue must be a list of entity instances of <type>
	set urllist {}
	foreach obj $newvalue {
	   lappend urllist [validate $type $obj]
	}
	set newvalue $urllist
	# newvalue now is url to the specified entity

	# ------ From here nearly identical to Aset -------------
	# Differences:
	# - Nature and retrieval of old value.
	# - json key and data for mydiff.

	# Get current value. (url of object!)
	try {
	    set olddefined 1
	    set oldvalue   [ref* [my ANget $name $jname $type]]
	} trap {STACKATO CLIENT V2 UNDEFINED ATTRIBUTE} {e o} {
	    set olddefined 0
	    set oldvalue   {}
	}

	if {$olddefined && ([lsort $oldvalue] == [lsort $newvalue])} {
	    # No change, nothing to do.
	    return
	}

	# Save new value as current.
	dict set mydata $name $newvalue

	# Update delta information.

	# Note: We are not checking if the new value is the same as
	# stored in the log. IOW implicit, user-performed rollbacks
	# are neither registered, nor reacted upon.

	my change ${jname}_guid [id-of* $newvalue]

	if {[dict exists $mylog $name]} return
	dict set mylog $name [list $olddefined $oldvalue]

	# Add to the in-memory set of committable instances
	Change [self]
	return
    }

    method ANunset {name jname type} {
	debug.v2/base {}

	# Get current value for saving to log.
	try {
	    set olddefined 1
	    set oldvalue   [ref* [my ANget $name $jname $type]]
	} trap {STACKATO CLIENT V2 UNDEFINED ATTRIBUTE} {e o} {
	    set olddefined 0
	    set oldvalue   {}
	}

	if {!$olddefined} {
	    # No change, nothing to do.
	    return
	}

	# Save new value as current.
	dict unset mydata $name

	# Update delta information.

	# Note: We are not checking if the new value is the same as
	# stored in the log. IOW implicit, user-performed rollbacks
	# are neither registered, nor reacted upon.

	my change ${jname}_guid null

	if {[dict exists $mylog $name]} return
	dict set mylog $name [list $olddefined $oldvalue]

	# Add to the in-memory set of committable instances
	Change [self]
	return

    }

    method Add {name xname jname type listtoadd} {
	debug.v2/base {}
	# listtoadd = list of type entity instances

	if {![llength $listtoadd]} {
	    debug.v2/base {Nothing added, ignored}
	    return
	}

	# values must be entity instances of <type>
	foreach obj $listtoadd {
	    lappend urllist [validate $type $obj]
	}
	debug.v2/base {++ $urllist}

	# Reduce to unique adds...
	set urllist [lsort -unique $urllist]

	# Get current value.
	try {
	    set olddefined 1
	    set oldvalue   [my ANget $name $jname $type]
	    set oldurls    [dict get $mydata $name]

	} trap {STACKATO CLIENT V2 UNDEFINED RELATION} {e o} {
	    set olddefined 0
	    set oldvalue   {}
	    set oldurls {}
	}

	debug.v2/base {Current = [join $oldurls "\nCurrent ="]}

	# Weed out values already in the list.
	set added {}
	foreach url $urllist {
	    if {$url in $oldurls} continue
	    lappend added $url
	}

	debug.v2/base {Added = [join $added "\nAdded ="]}

	if {![llength $added]} {
	    debug.v2/base {Nothing added, ignored}
	    return
	}

	if {[my is new]} {
	    # Operate directly on the delta to send on commit.
	    # There the relationship is represented as an array of uuid's.
	    # For a new object there is no server state to manipulate, yet.

	    foreach url $added {
		dict append  mydiff ${xname}_guids [id-of $url]
		dict lappend mydata $name $url
	    }
	    return
	}

	# Update the server state.
	# This returns the new json also.
	foreach url $added {
	    debug.v2/base {link [my url] $xname [id-of $url]}
	    my = [[authenticated] link [my url] $xname [id-of $url]]

	    # Update local cache on each success
	    dict lappend mydata $name $url
	}
	return
    }

    method Remove {name xname jname type listtoremove} {
	debug.v2/base {}
	# listtoremove = list of type entity instances

	if {![llength $listtoremove]} {
	    debug.v2/base {Nothing removed, ignored}
	    return
	}

	# values must be entity instances of <type>
	foreach obj $listtoremove {
	    lappend urllist [validate $type $obj]
	}
	debug.v2/base {-- $urllist}

	# Reduce to unique removals...
	set urllist [lsort -unique $urllist]

	# Get current value.
	try {
	    set olddefined 1
	    set oldvalue   [my ANget $name $jname $type]
	    set oldurls    [dict get $mydata $name]
	} trap {STACKATO CLIENT V2 UNDEFINED RELATION} {e o} {
	    set olddefined 0
	    set oldvalue   {}
	    set oldurls    {}
	}

	debug.v2/base {Current = [join $oldurls "\nCurrent ="]}

	# Update local cache (list of urls).
	# Weed out values not in the list already
	set removed {}
	foreach url $urllist {
	    if {$url ni $oldurls} continue
	    lappend removed $url
	}

	debug.v2/base {Removed = [join $removed "\nRemoved ="]}

	if {![llength $removed]} {
	    debug.v2/base {Nothing removed, ignored}
	    return
	}

	if {[my is new]} {
	    # Operate directly on the delta to send on commit.
	    # There the relationship is represented as an array of uuid's.
	    # For a new object there is no server state to manipulate, yet.

	    set current [dict get' $mydiff ${xname}_guids {}]
	    foreach url $removed {
		set pos     [lsearch -exact $current [id-of $url]]
		set current [lreplace $current $pos $pos]

		set pos     [lsearch -exact $oldurls $url]
		set oldurls [lreplace $oldurls $pos $pos]
	    }
	    my change ${xname}_guids $current
	    dict set mydata $name $oldurls
	    return
	}

	# Update the server state.
	# This returns the new json also.
	foreach url $removed {
	    debug.v2/base {unlink [my url] $xname [id-of $url]}
	    my = [[authenticated] unlink [my url] $xname [id-of $url]]

	    # Update local cache on each success.
	    set pos     [lsearch -exact $oldurls $url]
	    set oldurls [lreplace $oldurls $pos $pos]
	    dict set mydata $name $oldurls
	}
	return
    }

    method MapCore {objlist cmdprefix} {
	debug.v2/base {}
	set result {}
	# ?struct::list map
	foreach obj $objlist {
	    lappend result [{*}$cmdprefix $obj]
	}
	return $result
    }

    method FilterCore {objlist cmdprefix} {
	debug.v2/base {}
	set result {}
	# ?struct::list filter
	foreach obj $objlist {
	    if {![{*}$cmdprefix $obj]} continue
	    lappend result $obj
	}
	return $result
    }

    method Map {name jname type cmdprefix} {
	debug.v2/base {}
	# ?struct::list map
	my MapCore [my ANget $name $jname $type] $cmdprefix
    }

    method Filter {name jname type cmdprefix} {
	debug.v2/base {}
	# ?struct::list filter
	my FilterCore [my ANget $name $jname $type 1] $cmdprefix
    }

    # # ## ### ##### ######## #############
    ## Attribute access, core data structure manipulation

    # # ## ### ##### ######## #############
    ## Attribute definition

    method Forbidden {args} {
	# Set a list of attribute names we are not allowed to use,
	# because these keys into the data cache are used for other
	# purposes by the entity in question.

	set myexcluded $args
	return
    }

    method CheckForbidden? {name} {
	if {![info exists myexcluded] || ($name ni $myexcluded)} return
	my InternalError "Bad attribute \"$name\", forbidden from using this name" \
	    ATTRIBUTE FORBIDDEN $name
    }

    method Attribute {name type args} {
	debug.v2/base {}
	my CheckForbidden? $name

	set jsonname [dict get' $args as $name]

	debug.v2/base {json key = ($jsonname)}

	if {[dict exists $args default]} {
	    dict set mydefault $name [dict get $args default]
	    debug.v2/base {default  = ([dict get $mydefault $name])}
	}

	dict set mylabel $name $name
	if {[dict exists $args label]} {
	    dict set mylabel $name [dict get $args label]
	    debug.v2/base {label    = ([dict get $mylabel $name])}
	}

	if {[string match &* $type]} {
	    set type [string range $type 1 end]

	    # Object reference attribute.
	    # In cf v2 known as a ToOne relationship.
	    # Create the accessor methods.
	    #
	    # @x            : get value of attribute (obj)
	    # @x set v      : set value of attribute (obj)
	    # @x unset      : unset attribute
	    # @x <m> ...    : invoke (<x> <m>...) for the referenced object <x>.
	    #                 (get shortcut)

	    dict set myone   $name $type
	    dict set myjname $name $jsonname

	    debug.v2/base {to-one   = ($type)}
	    oo::objdefine [self] forward @$name my Access1 $name $jsonname $type
	    oo::objdefine [self] export  @$name

	    debug.v2/base {json hint = (nstring)}
	    dict set mymap ${jsonname}_guid nstring
	    dict set mymap $jsonname        1ref

	} else {
	    # Regular attribute. Create the accessor methods
	    #
	    # @x            : get value of attribute
	    # @x set v      : set value of attribute
	    # @x unset      : unset attribute
	    # @x label      : get human readable name

	    set nullable 0
	    if {[string match null|* $type]} {
		set type [string range $type 5 end]
		set nullable 1
	    }

	    # types = dict integer url string boolean
	    switch -exact -- $type {
		boolean     { set hint nbool   }
		double      { set hint nnumber }
		integer     { set hint nnumber }
		dict        { set hint dict    }
		ndict       {
		    set hint ndict
		    set type dict
		}
		list-string { set hint {array string} }
		!string {
		    set hint string
		    set type string
		}
		default { set hint nstring }
	    }

	    debug.v2/base {nullable  = ($nullable)}
	    debug.v2/base {json hint = ($hint)}
	    dict set mymap $jsonname $hint

	    dict set myattr  $name $type
	    dict set myjname $name $jsonname

	    set type [my ValidatorOf $type]

	    debug.v2/base {validate = ($type)}
	    oo::objdefine [self] forward @$name my Access $name $jsonname $type $nullable
	    oo::objdefine [self] export  @$name
	}
	return
    }

    method Many {name {type {}}} {
	debug.v2/base {}
	my CheckForbidden? $name

	if {$type eq {}} {
	    set type $name
	}
	if {[string match *s $type]} {
	    set type [string range $type 0 end-1]
	}
	if {[string match *s $name]} {
	    set xname [string range $name 0 end-1]
	} else {
	    set xname $name
	}
	debug.v2/base {to-many  = ($type)}
	dict set mymany  $name $type
	dict set myjname $name $name

	debug.v2/base {json hint = (narray)}
	dict set mymap ${xname}_guids narray

	# Should get hints of the referenced entity.
	# Problematic, cycles, infinite recursion.
	#dict set mymap $name [list array [list ref $type]]
	dict set mymap $name {array 1ref}

	# list reference attribute.
	# In cf v2 known as a ToMany relationship.
	# Create the accessor methods.
	#
	# @x            : get value of attribute (list of objs)
	# @x get ?dep?  : ditto, with inline-relations-depth=<dep>
	# @x set v      : set value of attribute (list of objs)
	# @x unset      : unset attribute
	# @x add ...    : add objs to the attribute value (append)
	# @x remove ... : remove objs from attribute value
	# @x map cmd... : invoke (<x> cmd...) for each obj <x>
	# @x filter cmd...
	# @x <m> ...    : invoke (<x> <m>...) for each obj <x>
	#                 (map shortcut)

	# NOTE: jname == name here, currently, always.

	oo::objdefine [self] forward @$name my AccessN $name $xname $name $type
	oo::objdefine [self] export  @$name
	return
    }

    method Fake {name} {
	dict set myfake $name .
	return
    }

    method SearchableOn {key} {
	debug.v2/base {}
	#TODO searchable-on $key
	return
    }

    method Summary {args} {
	set mysumaction $args
	return
    }

    # TODO scoped_to_space, scoped_to_organization

    # # ## ### ##### ######## #############
    ## Internals

    method ResolvePhantom {context} {
	debug.v2/base {}
	if {![my is phantom]} {
	    debug.v2/base {/done, already loaded}
	    return
	}

	if {[info exists mynote]} {
	    display [color bad "[my show] $context = $mynote"]
	}

	debug.v2/base {retrieve from [[authenticated] target] :: [my url]}
	# Note that we are not invalidating any changes we may have
	# already done to the entity (in the cache, and logs).
	set myjson [[authenticated] get-by-url [my url]]

	debug.v2/base {loaded [my as-json]}
	debug.v2/base {/done}
	return
    }

    method ValidatorOf {type} {
	debug.v2/base {}
	# Special mappings.

	switch -exact -- $type {
	    string -
	    dict   -
	    list-string {
		debug.v2/base { special: $type /rewrite}
		# TODO: Proper type for dict attr in the future
		# TODO: Proper type for list-of-string attr in the future
		return ::cmdr::validate::identity
	    }
	    double {
		return ::cmdr::validate::double
	    }
	}

	# Type is validation command as is. No change.
	if {[llength [info commands $type]]} {
	    debug.v2/base { known command /as-is}
	    return $type
	}

	# Type is name of a cmdr validation type.
	if {[llength [info commands ::cmdr::validate::$type]]} {
	    debug.v2/base { cmdr validation /rewrite}
	    return ::cmdr::validate::$type
	}

	# Unmappable. Assume that it is a valid command prefix (like a
	# lambda).
	debug.v2/base { unknown /as-is}
	return $type
    }

    method Undefined {message args} {
	my Error "undefined $message" UNDEFINED {*}$args
    }

    method DataTypeMismatch {message args} {
	my Error "type mismatch: $message" DATA TYPE MISMATCH {*}$args
    }

    method InternalError {message args} {
	my Error "internal: $message" INTERNAL {*}$args
    }

    method Error {message args} {
	debug.v2/base {[list STACKATO CLIENT V2 {*}$args]}
	return -code error \
	    -errorcode [list STACKATO CLIENT V2 {*}$args] \
	    "client v2: $message"
    }

    # # ## ### ##### ######## #############
    method dump_inlined {} {
	# Show the entities inlined in the json, if any.
	my DUMP1 $myjson "  "
	return
    }
    method DUMP1 {json prefix} {
	set who  [dict get $json metadata url]
	set json [dict get $json entity]

	foreach k [lsort -dict [dict keys $json]] {
	    # x_url => x is inlined value (single, or list)
	    if {![string match *_url $k]} continue

	    regsub {_url$} $k {} stem
	    if {![dict exists $json $stem]} continue

	    set sub [dict get $json $stem]

	    # determine 1 vs N, i.e single vs list.
	    # Do it as local, we have myone|many only for the top json, and not for the nested.

	    if {$sub eq {}} continue

	    # Treat as dict if possible and check for special keys indicating single object.
	    if {(([llength $sub] %2) == 0) &&
		[dict exists $sub metadata]} {
		# 1 - single ref
		my SHOW1 $sub $prefix
	    } else {
		# Not a dict, or missing the marker. Must be list.
		puts "${prefix}LIST__ $who                         "
		foreach el $sub {
		    my SHOW1 $el "- $prefix"
		}
	    }
	}
    }
    method SHOW1 {json prefix} {
	puts "${prefix}INLINE [dict get $json metadata url]"
	# Recurse, look for more.
	my DUMP1 $json "  $prefix"
    }

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::base 0
return
