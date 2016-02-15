# -*- tcl -*- Copyright (c) 2013 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## TEApot meta data support: references.

# # ## ### ##### ######## ############# #####################
## Export (internals - )

namespace eval ::kettle::mdref {
    namespace export {[a-z]*} 2tcl
    namespace ensemble create
}

# # ## ### ##### ######## ############# #####################
## State

# # ## ### ##### ######## ############# #####################
## API.

proc ::kettle::mdref::valid {ref {mv {}}} {
    if {$mv ne ""} {upvar 1 $mv message}

    # Get size to check, implicitly also checks that the reference is
    # a valid list.

    if {[catch {
	set size [llength $ref]
    } msg]} {
	set message $msg
	return 0
    }

    # Basics: Empty is bad. Just the package name is ok.

    if {$size == 0} {set message "Empty" ; return 0}
    if {$size == 1} {return 1}

    set ref [lrange $ref 1 end] ; # Cut name

    while {[llength $ref]} {
	# Scan until first option
	set v [lindex $ref 0]
	if {[string match -* $v]} break
	# Check that the non-option is a valid requirements.
	if {![Vreqvalid $v message]} {
	    return 0
	}
	set ref [lrange $ref 1 end] ; # Cut requirement
    }

    # Uneven length is bad. The last option will have no
    # value. Remember, first element is name, then requirements, then
    # option/value pairs. An even length is expected when looking at
    # the option/value pairse.

    if {[llength $ref] % 2 == 1} {
	set message "Last option is without value"
	return 0
    }

    # Scan the options and validate them.

    foreach {k v} $ref {
	switch -exact -- $k {
	    -require {
		if {![Vreqvalid $v message]} {
		    return 0
		}
	    }
	    -platform -
	    -archglob {}
	    -is {
		if {![Evalid $v message]} {
		    return 0
		}
	    }
	    default {
		set message "Unknown option \"$k\""
		return 0
	    }
	}
    }

    return 1
}

proc ::kettle::mdref::normalize {references} {
    # Take a list of references and remove redundancies in each
    # reference, and across all references.

    # In a first iteration each reference is brought into canonical
    # form. This removes the redundancies in each reference. Then we
    # sort the references by package name, and for each package with
    # more than one reference we put them together and re-construct
    # the canonical form.

    array set package {}

    # Bug 72969. Keep the order of dependencies, it may be important
    # during setup.

    set names {}

    foreach ref $references {
	set name [lindex $ref 0]
	set spec [lrange $ref 1 end]

	set ref [Conslist $name $spec]

	set name [lindex $ref 0]
	set spec [lrange $ref 1 end]

	if {![info exists package($name)]} {
	    lappend names $name
	}
	lappend package($name) $spec
    }

    set references {}
    foreach name $names {
	set specs $package($name)

	if {[llength $specs] == 1} {
	    # Single reference, reconstruct from parts, is canonical
	    # already.

	    lappend references [linsert [lindex $specs 0] 0 $name]
	} else {
	    # Multiple references to one package.
	    # Merge specs into one list and re-canonicalize.

	    set spec [concat {*}$specs]
	    lappend references [Conslist $name $spec]
	}
    }

    return $references
}

proc ::kettle::mdref::2tcl {ref} {
    # Convert internal form (requirements are 1/2-element lists) to
    # Tcl form, requirements are 'a', 'a-b', 'a-'. This form is
    # accepted on input, easier to read by a user, and no difference
    # to regular Tcl. We additionally convert -require options into
    # plain non-option requirements sitting between name and the
    # option/value part.

    set res [lindex $ref 0]

    # Non-option requirements.

    set oidx 1
    foreach v [lrange $ref 1 end] {
	# Scan until first option
	if {[string match -* $v]} break
	incr oidx
	lappend res [Vreqstring $v]
    }
    set options [lrange $ref $oidx end]

    # Option requirements to non-option requirements.

    foreach {k v} $options {
	if {$k ne "-require"} continue
	lappend res [Vreqstring $v]
    }

    # All other options.

    foreach {k v} $options {
	if {$k eq "-require"} continue
	lappend res $k $v
    }
    return $res
}

# # ## ### ##### ######## ############# #####################
## Internals

proc ::kettle::mdref::Conslist {name spec} {

    # The constructor for references recognizes not only the options
    # for the newer syntax, but also for the new syntax (see top of
    # file). The latter are accepted if and only if not mixed with the
    # newer options, and are converted on the fly to the newer syntax.
    # Requirements between name and options are recognized and
    # collected as well.

    # Additional work done by the constructor is
    # - Removal of redundant switches
    #   @ -platform, -archglob, -is = Only last value counts.
    #   @ -require                  = Only unique ranges, non-redundant ranges
    # - Sort of switches.
    # This generates a canonical reference.

    # Quick return if reference is plain name without switches.

    if {![llength $spec]} {
	return [list $name]
    }

    # Phase I. Take spec apart into requirements and regular switches.

    set ver   {} ; set hasver  0 ; # Data for -version,  flag when used.
    set exact 0  ; set hasex   0 ; # Data for -exact,    flag when used.
    set plat  {} ; set hasplat 0 ; # Data for -platform, flag when used.
    set ag    {} ; set hasag   0 ; # Data for -archglob, flag when used.
    set is    {} ; set hasis   0 ; # Data for -is,       flag when used.

    array set reqs {}

    set oidx 0
    foreach v $spec {
	# Scan until first option
	if {[string match -* $v]} break
	incr oidx
	set reqs($v) .
    }

    foreach {o v} [lrange $spec $oidx end] {
	switch -exact -- $o {
	    -exact    {set exact $v ; set hasex   1}
	    -version  {set ver   $v ; set hasver  1}
	    -platform {set plat  $v ; set hasplat 1}
	    -archglob {set ag    $v ; set hasag   1}
	    -is       {set is    $v ; set hasis   1}
	    -require  {set reqs($v) .}
	}
    }

    # Phase II. Validate the input, basics. Check for old vs. new, and
    # various other simple validations.

    if {$hasver || $hasex} {
	if {[array size reqs]} {
	    return -code error "Cannot mix old and new style version requirements"
	}

	# -exact implies -version
	if {$hasex && !$hasver} {
	    return -code error "-exact without -version"
	}

	if {$hasex && ![string is boolean -strict $exact]} {
	    return -code error "Expected boolean for -exact, but got \"$v\""
	}
	if {$hasver && ![Vvalid $ver message]} {
	    return -code error $message
	}

	# Translate to new form.

	lappend item $ver
	if {$exact} {
	    lappend item [Vnext $ver]
	} else {
	    # Cap at next major version.
	    # -version 8   => 8-9
	    # -version 8.4 => 8.4-9

	    lappend item [expr {[lindex [split $ver .] 0]+1}]
	}
	set reqs($item) .
    }

    if {$hasis} {
	set is [string tolower $is]
	if {![Evalid $is message]} {
	    return -code error $message
	}
    }

    # Phase III. Get over the requirements and remove redundant
    # ranges. Validate them first. If there is only one range it
    # cannot be redundant.

    if {[array size reqs]} {
	foreach req [array names reqs] {
	    Vreqcheck $req
	    # Translate X-Y forms into the list form for all internal use
	    if {[string match *-* $req]} {
		set rx [split $req -]
		unset reqs($req)
		set reqs($rx) .
	    }
	}

	if {[array size reqs] > 1} {
	    foreach req [array names reqs] {
		foreach other [array names reqs] {
		    # Ignore self.
		    if {$other eq $req} continue
		    if {[Subset $req $other]} {
			unset reqs($req)
			break
		    }
		}
	    }
	}
    }

    # Phase IV. Put the pieces back together to get the canonical
    # form. Which contains every requirement in option form.

    set ref [list $name]
    if {$hasis}   {lappend ref -is $is}
    if {$hasag}   {lappend ref -archglob $ag}
    if {$hasplat} {lappend ref -platform $plat}

    if {[array size reqs]} {
	foreach req [lsort -dict [array names reqs]] {
	    lappend ref -require $req
	}
    }

    # No validation required, we know that the result is ok. We
    # checked all the inputs in the same manner as the validator.

    return $ref
}

proc ::kettle::mdref::Subset {a b} {
    # Returns true if the requirement A is a true subset of requirement B.

    # 1  A = vA            B = vB
    # 2  A = vA -          B = vB -
    # 3  A = vAmin vAmax   B = vBmin vBmax

    # 3 cases per A and B, for a total of 9 combinations.

    # This can be reduced by recognizing that (1) is actually (3),
    # with the max value implied, i.e. derived from the min value.
    # This reduces the situation to four combinations.

    set a [Rtype $a mina maxa]
    set b [Rtype $b minb maxb]

    # 22, 32 are one case, they have the same condition to check. See below.
    ##
    # 22 :
    # A and B are ranges from a minimum to infinity.
    # The range with the larger minimum is the true subset.
    # This implies: A is a true subset of B iff minA > minB. ** same
    ##
    # 32 :
    # A is min to a max,    i.e. of finite size.
    # B is min to infinity, i.e. of infinite size.
    # This implies: A is a true subset iff minA > minB.      ** same
    ##
    # 23 :
    # A is min to infinity, i.e. of infinite size.
    # B is min to a max,    i.e. of finite size.
    # An infinite subset of a finite set is not possible.
    # This implies: A is not a true subset of B
    ##
    # 33 :
    # Both A and B are finite ranges. A is a true subset of B iff
    # (minA >  minB) && (maxA <= maxB) or
    # (minA >= minB) && (maxA <  maxB)

    switch -exact -- $a$b {
	22 -
	32 {return [expr {[package vcompare $mina $minb] > 0}]}
	23 {return 0}
	33 {return [expr {
			  (([package vcompare $mina $minb] >  0) &&
			   ([package vcompare $maxa $maxb] <= 0)) ||
			  (([package vcompare $mina $minb] >= 0) &&
			   ([package vcompare $maxa $maxb] <  0))
		      }]}
    }
}

proc ::kettle::mdref::Rtype {a minv maxv} {
    upvar 1 $minv min $maxv max

    if {[llength $a] == 1} {
	# (1), make it a (3)
	set min   [lindex $a 0]
	set major [lindex [split $min .] 0]
	set max   $major
	# Bug 67186
	incr max
	return 3
    } else {
	# (llength a == 2)
	# (2), (3)
	foreach {min max} $a break
	return [expr {$max eq "" ? 2 : 3}]
    }
}

proc ::kettle::mdref::Evalid {e {mv {}}} {
    variable name
    if {$mv ne ""} {upvar 1 $mv message}

    set ex [string tolower $e]
    set ok [expr {$x in {package application}}]    

    if {!$ok} {
	set message "Unknown entity type \"$e\", expected application, or package"
    }
    return $ok
}


proc ::kettle::mdref::Vreqcheck {req} {
    if {![Vreqvalid $req message]} {return -code error $message}
}

proc ::kettle::mdref::Vreqvalid {req {mv {}}} {
    if {$mv ne ""} {upvar 1 $mv message}

    if {[string match *-* $req]} {
	set rx [split $req -]
    } else {
	set rx $req
    }
    if {[llength $rx] == 1} {
	if {![valid [lindex $rx 0] message]} {return 0}
    } elseif {[llength $rx] == 2} {
	foreach {min max} $rx break
	if {![valid $min message]}                 {return 0}
	if {($max ne "") && ![Vvalid $max message]} {return 0}
    } else {
	set message "Bad requirement \"$req\""
	return 0
    }
    return 1
}

proc ::kettle::mdref::Vreqstring {req} {
    if {[llength $req] == 1} {
	return [lindex $req 0]
    } elseif {[llength $req] == 2} {
	foreach {min max} $req break
	if {$max eq ""} {
	    return ${min}-
	} else {
	    return ${min}-$max
	}
    }
}

proc ::kettle::mdref::Vvalid {v {mv {}}} {
    if {$mv ne ""} {upvar 1 $mv message}

    # Defer to the underlying Tcl interpreter. While there is no
    # direct validation (sub)command we can mis-use "packagevcompare"
    # for our purposes. Provide a valid version number as second
    # argument and discard the comparison result. We are only
    # interested in the ok/error status, the latter thrown if and only
    # if the argument is a syntactically invalid version number.

    set ok [expr {[catch {
	package vcompare $v 0
    }] ? 0 : 1}]

    if {!$ok} {
	set message "Bad version \"$v\""
    }
    return $ok
}

proc ::kettle::mdref::Vnext {v} {
    # Examples:
    # * 8.4   -> 8.5
    # * 8.5.9 -> 8.5.10
    #
    # Note: We remove leading zeros (via [scan]) to prevent
    # mis-interpretation as an octal number.

    set vn [split $v .]
    scan [lindex $vn end] %d last
    return [join [lreplace $vn end end [incr last]] .]
}

# # ## ### ##### ######## ############# #####################
## Initialization

# # ## ### ##### ######## ############# #####################
return

