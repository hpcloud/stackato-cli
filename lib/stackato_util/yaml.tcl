# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################
## Utility commands for prcessing yaml files.
## Tagged structures etc. Non-stackato specific parts should
## possibly be moved into the tclyaml package.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require tclyaml

namespace eval ::stackato::yaml {}

debug level  yaml
debug prefix yaml {}

# ## ### ##### ######## ############# #####################
## Yaml processing helper.
## Go from a fully tagged format to one where mapping keys
## are not tagged. We expect them to be scalars anyway.

proc ::stackato::yaml::stripMappingKeyTags {yml} {
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
		lappend new $kvalue [stripMappingKeyTags $v]
	    }
	    return [list $tag $new]
	}
	sequence {
	    set new {}
	    foreach v $value {
		lappend new [stripMappingKeyTags $v]
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
## Assumes that "stripMappingKeyTags" was applied already.

proc ::stackato::yaml::stripTags {yml} {
    lassign $yml tag value
    switch -exact -- $tag {
	scalar {
	    return $value
	}
	mapping {
	    set new {}
	    foreach {k v} $value {
		lappend new $k [stripTags $v]
	    }
	    return $new
	}
	sequence {
	    set new {}
	    foreach v $value {
		lappend new [stripTags $v]
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

proc ::stackato::yaml::retagMappingKeys {yml} {
    Debug.yaml {ReTag ($yml)}

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
		    [retagMappingKeys $v]
	    }
	    return [list $tag $new]
	}
	sequence {
	    set new {}
	    foreach v $value {
		lappend new [retagMappingKeys $v]
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
## Deep merging of manifest data structures.

proc ::stackato::yaml::deepMerge {child parent} {
    Debug.yaml {DeepMerge ($child) ($parent)}

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
    dict for {k v} $cvalue {
	# k = scalar, untagged
	# v = tagged value.
	if {[dict exists $pvalue $k]} {
	    # Unify child and parent values.
	    lappend result $k [deepMerge $v [dict get $pvalue $k]]
	} else {
	    # Keep the child, no parent.
	    lappend result $k $v
	}
    }

    dict for {k v} $pvalue {
	# k = scalar, untagged
	# v = tagged value.

	# Ignore values known to the child. Have been merged
	# already, above, where necessary.
	if {[dict exists $cvalue $k]} continue

	# Add parent key, nothing from the child
	lappend result $k $v
    }

    # Done.
    return [list $ctag $result]
}

# # ## ### ##### ######## ############# #####################
## Access with tag checking.

proc ::stackato::yaml::tag! {tag yml {label structure}} {
    lassign $yml thetag thevalue
    if {$thetag eq $tag} { return $thevalue }
    return -code error "Expected $tag for $label, got $thetag"
}

proc ::stackato::yaml::tags! {tags yml {label structure}} {
    lassign $yml thetag _
    if {$thetag in $tags} { return $yml }
    return -code error "Expected [linsert [join $tags {, }] end-1 or] for $label, got $thetag"
}

# # ## ### ##### ######## ############# #####################
## Debugging. Show structure.

proc ::stackato::yaml::dump {yml} {
    # Helper command, use it to show intermediate structures.
    # Assumes fully tagged structure.

    tclyaml writeTags channel stdout $yml
    return
}

proc ::stackato::yaml::dumpX {yml} {
    # Helper command, use it to show intermediate structures.
    # Assumes partially tagged structure (no tags on map keys.

    tclyaml writeTags channel stdout [retagMappingKeys $yml]
    return
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::yaml {
    namespace export map dump dumpX tag! tags! deepMerge \
	stripMappingKeyTags stripTags retagMappingKeys
    namespace ensemble create
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::yaml 0
