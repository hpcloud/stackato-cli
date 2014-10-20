# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations.
## Color management.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require table
package require tclyaml
package require cmdr::color
package require stackato::log
package require stackato::yaml
package require stackato::mgr::cfile

namespace eval ::stackato::cmd {
    namespace export color
    namespace ensemble create
}
namespace eval ::stackato::cmd::color {
    namespace export listing def undef test import
    namespace ensemble create

    namespace import ::cmdr::color
    namespace import ::stackato::log::display
    namespace import ::stackato::log::err
    namespace import ::stackato::log::say
    namespace import ::stackato::mgr::cfile

    # More direct access to the yaml constructor commands.
    namespace import ::stackato::yaml::cmap ; rename cmap Cmapping
    namespace import ::stackato::yaml::cseq ; rename cseq Csequence
    namespace import ::stackato::yaml::cval ; rename cval Cscalar

}

debug level  cmd/color
debug prefix cmd/color {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Command implementations.

proc ::stackato::cmd::color::def {config} {
    debug.cmd/color {}

    set color [$config @color]
    set spec  [$config @specification]

    # in-memory first. This does the argument validation as well.
    try {
	color define $color $spec
    } trap {CMDR COLOR} {e o} {
	err $e
    }

    # Read, modify and write the yaml configuration for persistence.

    set colors [Load]
    dict set colors $color $spec
    Store $colors

    return
}

proc ::stackato::cmd::color::undef {config} {
    debug.cmd/color {}



    return
}

proc ::stackato::cmd::color::test {config} {
    debug.cmd/color {}

    set spec [$config @specification]

    try {
	color define .TEST. $spec
    } trap {CMDR COLOR} {e o} {
	err $e
    }

    display "Testing '$spec': [color .TEST. [$config @string]]"
    # TODO: in-memory color db - definition removal
    return
}

proc ::stackato::cmd::color::listing {config} {
    debug.cmd/color {}

    [table::do t {Color Definition Example} {
	foreach c {
	    black        
	    red          
	    green        
	    yellow       
	    blue         
	    magenta      
	    cyan         
	    white        
	    default
	    bg-black     
	    bg-red       
	    bg-green     
	    bg-yellow    
	    bg-blue      
	    bg-magenta   
	    bg-cyan      
	    bg-white     
	    bg-default   
	    bold         
	    dim          
	    italic       
	    underline    
	    blink        
	    revers       
	    hidden       
	    strike       
	    no-bold      
	    no-dim       
	    no-italic    
	    no-underline 
	    no-blink     
	    no-revers    
	    no-hidden    
	    no-strike    
	} {
	    $t add $c [color get-def $c] [color $c 0123456789]
	}
	$t add ----- --------- ----------
	foreach c {
	    bad     
	    confirm 
	    error   
	    good    
	    name    
	    neutral 
	    note    
	    prompt  
	    warning
	    trace
	    log-sys
	    log-app
	} {
	    $t add $c [color get-def $c] [color $c 0123456789]
	}
    }] show display
    return
}


# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::color::import {} {
    debug.cmd/color {}
    foreach {k v} [Load] {
	debug.cmd/color {def $k = $v}
	try {
	    color define $k $v
	} trap {CMDR COLOR} {e o} {
	    err "Color import failure: $e"
	}
    }
    return
}

proc ::stackato::cmd::color::Load {} {
    debug.cmd/color {}

    ::set path [cfile get colors]
    if {![fileutil::test $path efr]} {
	debug.cmd/color {default}
	return {}
    }

    set contents [lindex [tclyaml readTags file $path] 0 0]
    set contents [stackato::yaml strip-mapping-key-tags $contents]
    set contents [stackato::yaml strip-tags             $contents]
    return $contents
}

proc ::stackato::cmd::color::Store {dict} {
    debug.cmd/color {}
    ::set path [cfile get colors]

    set tmp {}
    dict for {k v} $dict {
	lappend tmp [Cscalar $k] [Cscalar $v]
    }
    tclyaml writeTags file $path [Cmapping {*}$tmp]
    cfile fix-permissions $path
    return
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::cmd::color {}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::color 0
