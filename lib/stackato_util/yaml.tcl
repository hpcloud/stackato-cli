# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################
## Utility commands for prcessing yaml files.
## Tagged structures etc. Non-stackato specific parts should
## possibly be moved into the tclyaml package.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require tclyaml
package require dictutil ; # dict sort
package require stackato::color

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato {
    namespace export yaml
}

namespace eval ::stackato::yaml {
    namespace export dump-tagged dump-retag \
	tag!warn tag! tags! tags!do tag-of value-of deep-merge \
	strip-mapping-key-tags strip-tags retag-mapping-keys \
	cmap cseq cval dict validate-exact validate-glob

    namespace ensemble create

    namespace import ::stackato::color
}

# Danger! Ensure that regular dict commands used here are
# ::-qualified, i.e. ::dict
namespace eval ::stackato::yaml::dict {
    namespace export set get get' exists find find-tagged
    namespace ensemble create
}

# # ## ### ##### ######## ############# #####################

debug level  yaml
debug prefix yaml {[debug caller] | }

debug level  yaml/resolve
debug prefix yaml/resolve {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Constructor for tagged yaml structures.

proc ::stackato::yaml::cmap {args}   { list mapping [::dict sort $args] }
proc ::stackato::yaml::cseq {args}   { list sequence $args   }
proc ::stackato::yaml::cval {string} { list scalar   $string }

# ## ### ##### ######## ############# #####################
## Yaml processing helper.
## Go from a fully tagged format to one where mapping keys
## are not tagged. We expect them to be scalars anyway.

proc ::stackato::yaml::strip-mapping-key-tags {yml} {
    lassign $yml tag value
    switch -exact -- $tag {
	scalar {
	    # Unchanged.
	    return $yml
	}
	mapping {
	    set new {}
	    foreach {k v} $value {
		set kvalue [tag! scalar $k {mapping key}]
		lappend new $kvalue [strip-mapping-key-tags $v]
	    }
	    return [list $tag $new]
	}
	sequence {
	    set new {}
	    foreach v $value {
		lappend new [strip-mapping-key-tags $v]
	    }
	    return [list $tag $new]
	}
	default {
	    return -code error "Illegal tag '$tag'"
	}
    }
    error "Reached unreachable."
}

# ## ### ##### ######## ############# #####################
## Yaml processing helper. Go to full untagged format.
## Assumes that "strip-mapping-key-tags" was applied already.

proc ::stackato::yaml::strip-tags {yml} {
    lassign $yml tag value
    switch -exact -- $tag {
	scalar {
	    return $value
	}
	mapping {
	    set new {}
	    foreach {k v} $value {
		lappend new $k [strip-tags $v]
	    }
	    return $new
	}
	sequence {
	    set new {}
	    foreach v $value {
		lappend new [strip-tags $v]
	    }
	    return $new
	}
	default {
	    error "Illegal tag '$tag'"
	}
    }
    error "Reached unreachable."
}

# ## ### ##### ######## ############# #####################
## Yaml processing helper. Complement of StripMappingKeyTags.

proc ::stackato::yaml::retag-mapping-keys {yml} {
    debug.yaml {ReTag ($yml)}

    lassign $yml tag value
    switch -exact -- $tag {
	scalar {
	    # Unchanged.
	    return $yml
	}
	mapping {
	    set new {}
	    foreach {k v} $value {
		lappend new \
		    [list scalar $k] \
		    [retag-mapping-keys $v]
	    }
	    return [list $tag $new]
	}
	sequence {
	    set new {}
	    foreach v $value {
		lappend new [retag-mapping-keys $v]
	    }
	    return [list $tag $new]
	}
	default {
	    error "Illegal tag '$tag'"
	}
    }
    error "Reached unreachable."
}


# # ## ### ##### ######## ############# #####################
## Deep merging of two yaml trees.

proc ::stackato::yaml::deep-merge {child parent} {
    debug.yaml {}

    # Assumes that the incoming yml values underwent
    # 'StripMappingKeyTags' before handed here.

    # Child key values have precedence over parent values.

    lassign $child  ctag cvalue
    lassign $parent ptag pvalue

    # If either child or parent is not having a mapping the values
    # cannot be merged. The child then has precedence.
    if {($ctag ne "mapping") ||
	($ptag ne "mapping")} {
	return $child
    }

    # When both values are mappings we recurse and merge their values.

    set result {}
    ::dict for {k v} $cvalue {
	# k = scalar, untagged
	# v = tagged value.
	if {[::dict exists $pvalue $k]} {
	    # Unify child and parent values.
	    lappend result $k [deep-merge $v [::dict get $pvalue $k]]
	} else {
	    # Keep the child, no parent.
	    lappend result $k $v
	}
    }

    ::dict for {k v} $pvalue {
	# k = scalar, untagged
	# v = tagged value.

	# Ignore values known to the child. Have been merged
	# already, above, where necessary.
	if {[::dict exists $cvalue $k]} continue

	# Add parent key, nothing from the child
	lappend result $k $v
    }

    # Done.
    return [list $ctag $result]
}

# # ## ### ##### ######## ############# #####################
## Structure access with tag checking.

proc ::stackato::yaml::tag!warn {tag yml {label structure}} {
    lassign $yml thetag thevalue
    if {$thetag eq $tag} return
    say! [color yellow "Manifest warning: Expected a yaml $tag for $label, got a $thetag"]
    return
}

proc ::stackato::yaml::tag! {tag yml {label structure}} {
    lassign $yml thetag thevalue
    if {$thetag eq $tag} { return $thevalue }
    return -code error -errorcode {STACKATO CLIENT CLI MANIFEST TAG} \
	"Manifest validation error: Expected a yaml $tag for $label, got a $thetag"
}

proc ::stackato::yaml::tags! {tags yml {label structure}} {
    lassign $yml thetag _
    if {$thetag in $tags} { return $yml }
    return -code error -errorcode {STACKATO CLIENT CLI MANIFEST TAG} \
	"Manifest validation error: Expected a yaml [linsert [join $tags {, }] end-1 or] for $label, got a $thetag"
}

proc ::stackato::yaml::tags!do {yml label tagvar datavar body} {
    lassign $yml thetag thedata
    set tags [::dict keys $body]
    if {$thetag ni $tags} {
	return -code error -errorcode {STACKATO CLIENT CLI MANIFEST TAG} \
	    "Manifest validation error: Expected a yaml [linsert [join $tags {, }] end-1 or] for $label, got a $thetag"
    }

    upvar 1 $tagvar tag $datavar data
    set tag $thetag
    set data $thedata
    uplevel 1 [::dict get $body $thetag]
}

# # ## ### ##### ######## ############# #####################
## Basic accessors, no checks

proc ::stackato::yaml::tag-of {yml} {
    return [lindex $yml 0]
}

proc ::stackato::yaml::value-of {yml} {
    return [lindex $yml 1]
}

# # ## ### ##### ######## ############# #####################
## Accessors for large structure validation.

proc ::stackato::yaml::validate-glob {map label -- kv vv switch} {
    debug.yaml {}
    upvar 1 $kv key $vv value

    lappend switch * {}
    foreach {key value} [tag! mapping $map "key \"$label\""] {
	debug.yaml {-- $label :: $key}
	uplevel 1 [list switch -glob -- $key $switch]
    }
    return
}

# # ## ### ##### ######## ############# #####################
## Debugging. Show (intermediate) structure(s).

proc ::stackato::yaml::dump-tagged {yml} {
    # Assumes fully tagged structure.

    tclyaml writeTags channel stdout $yml
    return
}

proc ::stackato::yaml::dump-retag {yml} {
    # Assumes partially tagged structure (no tags on mapping keys).

    tclyaml writeTags channel stdout [retag-mapping-keys $yml]
    return
}

# # ## ### ##### ######## ############# #####################
## Treating nested tagged yaml mappings as dictionaries.

# Danger! Ensure that regular dict commands used here are
# ::-qualified, i.e. ::dict
namespace eval ::stackato::yaml::dict {
    # import late, commands must be defined.
    namespace import ::stackato::yaml::tag!
    namespace import ::stackato::yaml::cmap
    namespace import ::stackato::yaml::dump-retag
    namespace import ::stackato::yaml::strip-tags
}

proc ::stackato::yaml::dict::set {dictvar args} {
    debug.yaml {}

    upvar 1 $dictvar dict

    ::set value [lindex $args end]
    ::set keys  [lrange $args 0 end-1]

    if {![llength $keys]} {
	error "No keys"
    }

    # Read
    ::set dictvalue [tag! mapping $dict]
    ::set head [lindex $keys 0]
    ::set tail [lrange $keys 1 end]

    if {[::dict exists $dictvalue $head]} {
	::set child [::dict get $dictvalue $head]
    } else {
	::set child {mapping {}}
    }

    # Modify
    if {[llength $tail]} {
	set child {*}$tail $value
    } else {
	::set child $value
    }

    # Write back
    ::dict set dictvalue $head $child
    ::set dict [cmap {*}$dictvalue]
    return
}

proc ::stackato::yaml::dict::get {dict args} {
    debug.yaml {}

    if {![find $dict result {*}$args]} {
	return -code error "key path '$args' not known in dictionary"
    }

    debug.yaml {==> $result}
    return $result
}

proc ::stackato::yaml::dict::get' {dict args} {
    debug.yaml {}

    ::set default [lindex $args end]
    ::set args    [lrange $args 0 end-1]

    if {![find $dict result {*}$args]} {
	debug.yaml {==> (default) $default}
	return $default
    }

    debug.yaml {==> (found) $result}
    return $result
}

proc ::stackato::yaml::dict::exists {dict args} {
    debug.yaml {}
    return [find-tagged $dict __dummy__ {*}$args]
}

proc ::stackato::yaml::dict::find {context resultvar args} {
    debug.yaml {}

    # Follow the specified path of keys down into the context
    # structure (tagged).  Stop and fail when intermediate structures
    # are not mappings or do not contain the key. The result is
    # stripped of any tags.

    upvar 1 $resultvar result
    if {[find-tagged $context result {*}$args]} {

	# NOTE: At this point the result is still a tagged structure!
	# Could be scalar, or more complex. Regardless, for the
	# resolution (see callers) we need a proper string to replace
	# the symbol with. Hence the yaml strip-tags we created early
	# on.

	::set result [strip-tags $result]

	debug.yaml {==> $result}
	return 1
    } else {
	debug.yaml {not found}
	return 0
    }
}

proc ::stackato::yaml::dict::find-tagged {context resultvar args} {
    debug.yaml {}

    # Follow the specified path of keys down into the context
    # structure (tagged).  Stop and fail when intermediate structures
    # are not mappings or do not contain the key.

    debug.yaml/resolve {FID -> $resultvar}
    debug.yaml/resolve {FID <- $args}
    debug.yaml/resolve {FID % ($context)}
    debug.yaml/resolve {[dump-retag $context]}

    upvar 1 $resultvar result
    foreach symbol $args {
	if {[catch {
	    ::set cv [tag! mapping $context context]
	}]} {
	    debug.yaml {==> fail, nested, not a mapping}
	    return 0
	}
	if {![::dict exists $cv $symbol]} {
	    debug.yaml {==> fail, not found}
	    return 0
	}
	::set context [::dict get $cv $symbol]
    }

    debug.yaml/resolve {FID = ($context)}
    debug.yaml/resolve {[dump-retag $context]}

    ::set result $context

    debug.yaml {==> ok ($result)}
    return 1
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::yaml 0
