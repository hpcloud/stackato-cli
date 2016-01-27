# -*- tcl -*- Copyright (c) 2013 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## TEApot meta data parsing/processing.

# # ## ### ##### ######## ############# #####################
## Export (internals - )

namespace eval ::kettle::meta {
    namespace export {[a-z]*}
    namespace ensemble create

    namespace import ::kettle::io
    namespace import ::kettle::path
    namespace import ::kettle::mdref
    namespace import ::kettle::strutil
}

# # ## ### ##### ######## ############# #####################
## State

namespace eval ::kettle::meta {
    variable md     {} ; # dict: (type, name) --> meta data
    variable mduser {} ; # dict: (type, name) --> /has user definitions/

    variable mbegin "# @@ Meta Begin"
    variable mend   "# @@ Meta End"
}

# # ## ### ##### ######## ############# #####################
## API.

# Files:
# (1) Having marker (see path teapot-file)
# (3) inlined in .tcl file of a package.

# If data for a package P is found in several locations the data from
# the higher numbers has precedence. During installation of a package P
# a teapot.txt is generated, holding the data for P in external format.

proc ::kettle::meta::scan {} {
    # Overwrite self, we run only once for effect.
    proc ::kettle::meta::scan args {}

    # Heuristic search for meta data in the directory containing tcl
    # packages, in separate files. See (1).

    Init

    # Heuristic search for package meta data.
    lassign [path scan \
		 {teapot metadata}\
		 [path sourcedir] \
		 {path teapot-file}] \
	root files

    foreach f $files {
	read-external $f
    }
    return
}

proc ::kettle::meta::read-external {file} {
    variable md
    #puts E|$file
    set contents [path cat $file]
    set has      [Parse $contents]

    # Extend md storage
    lappend md {*}$has
    return
}

proc ::kettle::meta::read-internal {file etype ename} {
    variable md
    variable mduser

    #puts I|$file
    set block [lindex [GetInternal [path cat $file]] 1]
    if {$block eq {}} {
	return 0
    }

    set ekey [list $etype $ename]
    set has  [Parse $block]

    if {![dict size $has]} { return 0 }
    if {[dict size $has] > 1} {
	io err {
	    io puts "Expected meta data for a single $etype, got multiple entries instead."
	}
	return 0
    }
    if {![dict exists $has $ekey]} {
	set actual [lindex [dict keys $has] 0]
	io err {
	    io puts "Expected meta data for $etype $ename, got $actual instead."
	}
	return 0
    }

    # Extend md storage
    lappend md {*}$has
    set key [lindex [dict keys $has] 0]
    dict set mduser $key 1
    return 1
}

proc ::kettle::meta::write {dst type name ver} {
    path write $dst [join [Assemble $name $ver $type [Get $type $name __]] \n]\n
    return $dst
}

proc ::kettle::meta::format-external {type name ver md} {
    return [join [Assemble $name $ver $type $md] \n]\n
}

proc ::kettle::meta::format-internal {type name ver md} {
    variable mbegin
    variable mend
    set prefix "# "
    return \n$mbegin\n$prefix[join [Assemble $name $ver $type $md] \n$prefix]\n$mend
}

proc ::kettle::meta::insert {dst type name} {
    variable mbegin
    variable mend

    set md [Get $type $name ver]
    set pfx "# "
    set block $pfx[join [Assemble $name $ver $type $md] "\n$pfx"]

    lassign [GetInternal [path cat $dst]] header _ trailer
    path write $dst $header\n$mbegin\n$block\n$mend\n$trailer
    return
}

proc ::kettle::meta::add {type name mdkey value} {
    variable md
    set key [list $type $name]
    dict set md $key $mdkey $value
    return
}

proc ::kettle::meta::defined? {type name} {
    variable mduser
    io trace {meta-defined? $type $name}

    set key [list $type $name]
    return [dict exists $mduser $key]
}

proc ::kettle::meta::status {type name} {
    variable mduser
    variable md

    io trace {meta-status $type $name}

    set key [list $type $name]
    if {![dict exists $mduser $key]} {
	return MISSING
    }

    set m [dict get $md $key]

    set r {}
    foreach k {
	author location summary description
	subject category platform
    } {
	if {[dict exists $m $k] &&
	    ([dict get $m $k] ne "?")
	} continue
	lappend r $k
    }
    if {[llength $r]} {
	return "UNDEFINED: [join $r {, }]"
    }
    return OK
}

proc ::kettle::meta::show-status {} {
    variable md

    set keys [lsort -dict [dict keys $md]]

    if {![llength $keys]} {
	io puts "No packages/applications to show"
    }

    lappend types Entity
    lappend names Name
    lappend skip  1
    foreach key $keys {
	lassign $key type name
	lappend types $type
	lappend names $name
	lappend skip 0
    }
    set keys [linsert $keys 0 {}]

    io puts {}
    foreach k $keys t [strutil padr $types] n [strutil padr $names] s $skip {
	if {$s} {
	    set status Status
	} else {
	    lassign $k kt kn
	    set status [status $kt $kn]
	    switch -glob -- $status {
		OK      { set status [io mok   $status] }
		UNDEF*  { set status [io mcyan $status] }
		default { set status [io merr  $status] }
	    }
	}
	io puts "\t$t $n $status"
    }
    io puts {}
    return
}

proc ::kettle::meta::fix-location {var} {
    upvar 1 $var m
    # Heuristic for a location if missing.
    # Use fossil remote, stripped of account information.
    # But only if we are in a fossil checkout.

    # TODO: Handle git also

    if {![dict exists $m location] &&
	([path find.fossil [path sourcedir]] ne {})
    } {
	set remote [exec {*}[auto_execok fossil] remote]
	regsub {/[^@]*@} $remote {/} remote
	dict set m location $remote
    }
    return
}

# # ## ### ##### ######## ############# #####################
## Internals

proc ::kettle::meta::Get {type name vv} {
    upvar 1 $vv ver
    variable md
    variable mduser
    global tcl_platform

    io trace {meta-get $type $name}

    set key [list $type $name]

    if {![dict exists $mduser $key]} {
	io warn {
	    io puts "[string totitle $type] $name: No user-specified teapot meta data found."
	}
    }

    set m [dict get $md $key]

    io trace {  = $m}

    set ver [dict get $m version]
    dict unset m name
    dict unset m version
    dict unset m entity

    FixVCInformation m
    fix-location     m

    foreach k {author location} {
	if {[dict exists $m $k]} continue
	io warn {
	    io puts "[string totitle $type] $name: Missing $k information."
	}
    }

    dict set m build::by $tcl_platform(user)
    dict set m build::date \
	[clock format [clock seconds] -format {%Y-%m-%d}]

    return $m
}

proc ::kettle::meta::FixVCInformation {var} {
    upvar 1 $var m
    # Determine the type of version control this repository is under,
    # and report it and the current revision.

    set src [path sourcedir]
    set vctype unknown
    set vcrev  unknown
    foreach vc {fossil git} {
	set vcloc [path find.$vc $src]
	if {$vcloc eq {}} continue
	set vctype $vc
	set vcrev  [path revision.$vc $vcloc]
	break
    }

    dict set m vc::system   $vctype
    dict set m vc::revision $vcrev
    return
}

proc ::kettle::meta::GetInternal {str} {
    variable mbegin
    variable mend

    set collect header; #|meta|trailer
    set header  {}
    set meta    {}
    set trailer {}

    foreach line [split $str \n] {
	# Ignore everything until the beginning of the meta data
	# block.

	if {[regexp "^$mbegin" $line]} {
	    io trace {META BEGIN}
	    set collect meta
	    continue 
	} elseif {[regexp "^$mend" $line]} {
	    io trace {META END}
	    set collect trailer
	    continue 
	}

	if {$collect eq "meta"} {
	    # We are inside of the Meta data block. Strip the comment
	    # prefix from the line, i.e. transform the embedded meta
	    # information back into the regular form.
	    regsub "^\#\[ \t\]*" $line {} line
	}

	io trace {[string toupper $collect] $line}
	# state (collect) == name of variable to extend
	lappend $collect $line
    }

    return [list [join $header \n] [join $meta \n] [join $trailer \n]]
}

proc ::kettle::meta::Parse {str} {
    # str is expected to be in the 'external' teapot format.

    #puts P|$str|

    variable extracted {}
    set i [interp create -safe]

    # Action for data collection ...
    interp alias $i Meta {} ::kettle::meta::M

    # Actions for entity collection (new sections) ...

    foreach entity {
	package application
    } {
	# Not handled: documentation profile redirect
	set cmd [string totitle $entity]
	interp alias $i $cmd {} ::kettle::meta::E $entity
    }

    try {
	interp eval $i $str
	SaveLast
	Normalize
	Validate
    } on error {e o} {
	set msg [::string map {
	    {::kettle::meta::} {}
	} $e]
	io err {
	    io puts "Bad meta data syntax: $msg"
	}
	#puts $::errorInfo
    } finally {
	interp delete $i
    }

    return $extracted
}

proc ::kettle::meta::E {type name version} {
    SaveLast

    variable ctype   $type
    variable cname   $name
    variable current {}

    io trace {New $ctype : "$cname" $version}

    dict set current name    $name
    dict set current version $version
    dict set current entity  $type
    return
}

proc ::kettle::meta::M {key args} {
    variable cname
    variable current

    # Ignore everything before the start of the first entity.
    if {$cname eq ""} return

    io trace {M $key = ($args)}
    dict lappend current $key {*}$args
    return
}

proc ::kettle::meta::Init {} {
    variable md      {} ;# dict: package --> meta data
    variable current {} ;# dict: key --> value
    variable cname   {} ;# name of current entity.
    variable ctype   {} ;# type of current entity.
    return
}

proc ::kettle::meta::SaveLast {} {
    variable extracted
    variable cname
    variable ctype
    variable current

    if {$cname eq {}} return

    dict set extracted [list $ctype $cname] $current

    set ctype   {}
    set cname   {}
    set current {}
    return
}

proc ::kettle::meta::Normalize {} {
    variable extracted
    if {![dict size $extracted]} return

    dict for {key data} $extracted {
	#lassign $key type name

	# Special knowledge about dependencies, remove duplicates,
	# redundancies. Ditto for platform, in an effort to handle
	# crooked input better.

	if {[dict exists $data platform]} {
	    dict set data platform \
		[lsort -uniq [dict get $data platform]]
	}

	foreach what {require recommend} {
	    if {![dict exists $data $what]} continue
	    dict set data $what \
		[mdref normalize [dict get $data $what]]
	}

	dict set extracted $key $data
    }
    return
}

proc ::kettle::meta::Validate {} {
    variable extracted
    set errors 0

    if {![dict size $extracted]} {
	io err {
	    io puts {No entities found}
	}
	return 0
    }

    dict for {key data} $extracted {
	#lassign $key type name

	set keep 1
	set e [dict get $data entity]
	set n [dict get $data name]
	set v [dict get $data version]

	set prefix "Bad meta data for $e $n $v:"

	if {![dict exists $data platform]} {
	    io err {
		io puts "$prefix Incomplete, no platform specified"
	    }
	    set keep 0
	    incr errors
	} elseif {[llength [dict get $data platform]] > 1} {
	    io err {
		io puts "$prefix Multi-platform archives are not acceptable."
	    }
	    set keep 0
	    incr errors
	}

	foreach {what label} {
	    require   requirement
	    recommend recommendation
	} {
	    if {![dict exists $data $what]} continue

	    # Special knowledge about dependencies, check their
	    # syntax.

	    foreach ref [dict get $data $what] {
		if {[mdref valid $ref message]} continue
		io err {
		    io puts "$prefix Bad reference syntax in $label \"$ref\": $message"
		}
		set keep 0
		incr errors
	    }
	}

	if {$keep} continue
	dict unset extracted $key
    }

    if {$errors} { return 0 }
    return 1
}

proc ::kettle::meta::Assemble {name ver type meta} {
    array set   md $meta
    array unset md __* ; # Squash everything internal

    set  maxl [MaxLength md]
    set  margin 67 ; # 72 -5 (Meta )
    incr margin -$maxl

    lappend lines [list [string totitle $type] $name $ver]

    foreach k [lsort [array names md]] {
	set sk [string tolower $k]

	switch -exact -- $sk {
	    require -
	    recommend {
		# Bug 72969. Do not sort dependencies, order may be
		# important during setup.
		foreach e [mdref normalize $md($k)] {
		    # Convert internal list form of requirements into
		    # Tcl form for easier use by humans.
		    set e [mdref 2tcl $e]
		    lappend lines [ALine $k $maxl [list $e]]
		}
		continue
	    }
	}

	# Semi paragraph-formatting of everything else across multiple
	# lines.

	if {![llength $md($k)]} {
	    lappend lines [ALine $k $maxl ""]
	    continue
	}

	set buf ""
	foreach e $md($k) {
	    if {![llength $buf]} {
		lappend buf $e
		continue
	    }
	    if {([string length $buf] + [string length $e] + 1) > $margin} {
		lappend lines [ALine $k $maxl $buf]
		set buf {}
	    }
	    lappend buf $e
	}
	if {[llength $buf]} {
	    lappend lines [ALine $k $maxl $buf]
	}
    }

    #lappend lines {} ; # Forces a \n at the end of the block when joining the lines.
    return $lines

}

proc ::kettle::meta::ALine {k maxl v} {
    return "Meta [::format "%-*s" $maxl [list $k]] $v"
}

proc ::kettle::meta::MaxLength {mv} {
    upvar 1 $mv md

    set maxl 0
    foreach k [array names md] {
	set l [string length [list $k]]
	if {$l > $maxl} {set maxl $l}
    }

    return $maxl
}

# # ## ### ##### ######## ############# #####################
## Initialization

# # ## ### ##### ######## ############# #####################
return

