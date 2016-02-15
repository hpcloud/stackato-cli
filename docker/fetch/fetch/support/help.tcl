## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## CMDR - Help - Help support.

# @@ Meta Begin
# Package cmdr::help 0
# Meta author   {Andreas Kupries}
# Meta location https://core.tcl.tk/akupries/cmdr
# Meta platform tcl
# Meta summary     Internal. Utilities for help text formatting and setup.
# Meta description Internal. Utilities for help text formatting and setup.
# Meta subject {command line}
# Meta require {Tcl 8.5-}
# Meta require debug
# Meta require debug::caller
# Meta require lambda
# Meta require linenoise
# Meta require textutil::adjust
# Meta require cmdr::util
# @@ Meta End

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require debug
package require debug::caller
package require lambda
package require linenoise
package require textutil::adjust
package require cmdr::util

# # ## ### ##### ######## ############# #####################

debug define cmdr/help
debug level  cmdr/help
debug prefix cmdr/help {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::cmdr {
    namespace export help
    namespace ensemble create
}

namespace eval ::cmdr::help {
    namespace export query query-actor format auto
    namespace ensemble create
}

# # ## ### ##### ######## ############# #####################

proc ::cmdr::help::query {actor words} {
    debug.cmdr/help {}
    # Resolve chain of words (command name path) to the actor
    # responsible for that command, starting from the specified actor.
    # This is very much a convenience command.

    set root   [$actor root]
    set prefix $words

    if {![$root exists *in-shell*] ||
	![$root get    *in-shell*]} {
	# Not in the shell, put executable's name into the prefix.
	set prefix [linsert $prefix 0 [$root name]]
    }

    return [[query-actor $actor $words] help $prefix]
}

proc ::cmdr::help::query-actor {actor words} {
    debug.cmdr/help {}
    # Resolve chain of words (command name path) to the actor
    # responsible for that command, starting from the specified actor.
    # This is very much a convenience command.

    set n -1
    foreach word $words {
	if {[info object class $actor] ne "::cmdr::officer"} {
	    # Privates do not have subordinates to look up.
	    # We now have a bad command name argument to help.

	    set prefix [lrange $words 0 $n]
	    return -code error \
		-errorcode [list CMDR ACTION BAD $word] \
		"The command \"$prefix\" has no sub-commands, unexpected word \"$word\""
	}

	set actor [$actor lookup $word]
	incr n
    }

    return $actor
}

# # ## ### ##### ######## ############# #####################

proc ::cmdr::help::auto {actor} {
    debug.cmdr/help {}
    # Generate a standard help command for any actor, and add it dynamically.

    # Auto create options based on the help formats found installed
    foreach c [lsort -dict [info commands {::cmdr::help::format::[a-z]*}]] {
	set format [namespace tail $c]

	# Skip the imported helper commands which are NOT formats
	if {[string match query* $format]} continue

	lappend formats --$format
	lappend options [string map [list @c@ $format] {
	    option @c@ {
		Activate @c@ form of the help.
	    } {
		presence
		when-set [lambda {p x} { $p config @format set @c@ }]
	    }}]
    }

    # Standard option for line width to format against.
    lappend options {
	option width {
	    The line width to format the help for.
	    Defaults to the terminal width, or 80 when
	    no terminal is available.
	} {
	    alias w
	    validate integer ;# better: integer > 0, or even > 10
	    generate [lambda {p} { linenoise columns }]
	}
    }
    lappend map @formats@ [linsert [join $formats {, }] end-1 and]
    lappend map @options@ [join $options \n]
    lappend map @actor@   $actor

    $actor learn [string map $map {private help {
	description {
	    Retrieve help for a command or command set.
	    Without arguments help for all commands is given.
	    The default format is --full.
	}
	@options@
	state format {
	    Format of the help to generate.
	    This field is fed by the options @formats@.
	} { default {} }
	input cmdname {
	    The entire command line, the name of the
	    command to get help for. This can be several
	    words.
	} { optional ; list }
    } {::cmdr::help::auto-help @actor@}}]
    return
}

proc ::cmdr::help::auto-help {actor config} {
    debug.cmdr/help {}

    set width  [$config @width]
    set words  [$config @cmdname]
    set format [$config @format]

    if {$format eq {}} {
	# Default depends on the presence of additional arguments, i.e. if a specific command is asked for, or not.
	if {[llength $words]} {
	    set format full
	} else {
	    set format by-category
	}
    }

    puts [format $format [$actor root] $width [cmdr util dictsort [query $actor $words]]]
    return
}

# # ## ### ##### ######## ############# #####################

namespace eval ::cmdr::help::format {
    namespace export full list short by-category
    namespace ensemble create

    namespace import ::cmdr::help::query
    namespace import ::cmdr::help::query-actor
}

# Alternate formats:
# List
# Short
# By-Category
# ... entirely different formats (json, .rst, docopts, ...)
# ... See help_json.tcl, and help_sql.tcl for examples.
#

# # ## ### ##### ######## ############# #####################
## Full list of commands, with full description (text and parameters)

proc ::cmdr::help::format::full {root width help} {
    debug.cmdr/help {}

    # help = dict (name -> command)
    set result {}
    dict for {cmd desc} $help {
	lappend result [Full $width $cmd $desc]
    }
    return [join $result \n]
}

proc ::cmdr::help::format::Full {width name command} {
    # Data structure: see config.tcl,  method 'help'.
    # Data structure: see private.tcl, method 'help'.

    dict with command {} ; # -> desc, options, arguments, parameters

    # Short line.
    lappend lines \
	[string trimright \
	     "[join $name] [HasOptions $options][Arguments $arguments $parameters]"]

    if {$desc ne {}} {
	# plus description
	set w [expr {$width - 5}]
	set w [expr {$w < 1 ? 1 : $w}]
	lappend lines [textutil::adjust::indent \
			   [textutil::adjust::adjust $desc \
				-length $w -strictlength 1] \
			   {    }]
    }

    # plus per-option descriptions (sort by flag name)
    if {[dict size $options]} {
	set onames {}
	set odefs  {}
	foreach {oname ohelp} [::cmdr util dictsort $options] {
	    lappend onames $oname
	    lappend odefs  $ohelp
	}
	DefList $width $onames $odefs
    }

    # plus per-argument descriptions (keep in cmdline order)
    if {[llength $arguments]} {
	set anames {}
	set adefs  {}
	foreach aname $arguments {
	    set v [dict get $parameters $aname]
	    dict with v {} ; # -> code, description, label
	    lappend anames $label
	    lappend adefs  $description
	}
	DefList $width $anames $adefs
    }
    lappend lines ""
    return [join $lines \n]
}

# # ## ### ##### ######## ############# #####################
## List of commands. Nothing else.

proc ::cmdr::help::format::list {root width help} {
    debug.cmdr/help {}

    # help = dict (name -> command)
    set result {}
    dict for {cmd desc} $help {
	lappend result [List $width $cmd $desc]
    }
    return [join $result \n]
}

proc ::cmdr::help::format::List {width name command} {
    # Data structure: see config.tcl,  method 'help'.
    # Data structure: see private.tcl, method 'help'.

    dict with command {} ; # -> desc, options, arguments, parameters

    # Short line.
    lappend lines \
	[string trimright \
	     "    [join $name] [HasOptions $options][Arguments $arguments $parameters]"]
    return [join $lines \n]
}

# # ## ### ##### ######## ############# #####################
## List of commands with basic description. No parameter information.

proc ::cmdr::help::format::short {root width help} {
    debug.cmdr/help {}

    # help = dict (name -> command)
    set result {}
    dict for {cmd desc} $help {
	lappend result [Short $width $cmd $desc]
    }
    return [join $result \n]
}

proc ::cmdr::help::format::Short {width name command} {
    # Data structure: see config.tcl,  method 'help'.
    # Data structure: see private.tcl, method 'help'.

    dict with command {} ; # -> desc, options, arguments, parameters

    # Short line.
    lappend lines \
	[string trimright \
	     "[join $name] [HasOptions $options][Arguments $arguments $parameters]"]

    if {$desc ne {}} {
	# plus description
	set w [expr {$width - 5}]
	set w [expr {$w < 1 ? 1 : $w}]
	lappend lines [textutil::adjust::indent \
			   [textutil::adjust::adjust $desc \
				-length $w -strictlength 1] \
			   {    }]
    }
    lappend lines ""
    return [join $lines \n]
}

# # ## ### ##### ######## ############# #####################
## Show help by category/ies

proc ::cmdr::help::format::by-category {root width help} {
    debug.cmdr/help {}

    # I. Extract the category information from the help structure and
    #    generate the tree of categories with their commands.

    lassign [SectionTree $help] subc cmds

    # II. Order the main categories. Allow for user influences.
    set categories [SectionOrder $root $subc]

    # III. Take the category tree and do the final formatting.
    set lines {}
    foreach c $categories {
	ShowCategory $width lines [::list $c] ""
    }
    return [join $lines \n]
}

proc ::cmdr::help::format::ShowCategory {width lv path indent} {
    upvar 1 $lv lines cmds cmds subc subc

    # Print category header
    lappend lines "$indent[lindex $path end]"

    # Indent the commands and sub-categories a bit more...
    append indent "    "
    set    sep    "    "

    # Get the commands in the category, preliminary formatting
    # (labels, descriptions).

    foreach def [lsort -dict -unique [dict get $cmds $path]] {
	lassign $def syntax desc
	lappend names $syntax
	lappend descs $desc
    }
    set labels [cmdr util padr $names]

    # With the padding all labels are the same length. We can
    # precompute the blank and the width to format the descriptions
    # into.

    regsub -all {[^\t]}  "$indent[lindex $labels 0]$sep" { } blank
    set w [expr {$width - [string length $blank]}]

    # Print the commands, final formatting.
    foreach label $labels desc $descs {
	set desc [textutil::adjust::adjust $desc \
		      -length $w \
		      -strictlength 1]
	set desc [textutil::adjust::indent $desc $blank 1]

	lappend lines $indent$label$sep$desc
    }

    lappend lines {}
    if {![dict exists $subc $path]} return

    # Print the sub-categories, if any.
    foreach c [lsort -dict -unique [dict get $subc $path]] {
	ShowCategory $width lines [linsert $path end $c] $indent
    }
    return
}

# # ## ### ##### ######## ############# #####################
## Common utility commands.

proc ::cmdr::help::format::DefList {width labels defs} {
    upvar 1 lines lines

    set labels [cmdr util padr $labels]

    set  nl [string length [lindex $labels 0]]
    incr nl 5
    set blank [string repeat { } $nl]

    lappend lines ""
    foreach l $labels def $defs {
	# FUTURE: Consider paragraph breaks in $def (\n\n),
	#         and format them separately.
	set w [expr {$width - $nl}]
	set w [expr {$w < 1 ? 1 : $w}]
	lappend lines "    $l [textutil::adjust::indent \
		       [textutil::adjust::adjust $def \
			    -length $w -strictlength 1] \
		       $blank 1]"
    }
    return
}

proc ::cmdr::help::format::Arguments {arguments parameters} {
    set result {}
    foreach a $arguments {
	set v [dict get $parameters $a]
	dict with v {} ; # -> code, desc, label
	switch -exact -- $code {
	    +  { set text "<$label>" }
	    ?  { set text "\[<${label}>\]" }
	    +* { set text "<${label}>..." }
	    ?* { set text "\[<${label}>...\]" }
	}
	lappend result $text
    }
    return [join $result]
}

proc ::cmdr::help::format::HasOptions {options} {
    if {[dict size $options]} {
	return "\[OPTIONS\] "
    } else {
	return {}
    }
}

proc ::cmdr::help::format::SectionTree {help {fmtname 1}} {

    array set subc {} ;# category path -> list (child category path)
    array set cmds {} ;# category path -> list (cmd)
    #                    cmd = tuple (label description)

    dict for {name def} $help {
	dict with def {} ; # -> desc, arguments, parameters, sections

	if {![llength $sections]} {
	    lappend sections Miscellaneous
	}

	if {$fmtname} {
	    append name " " [Arguments $arguments $parameters]
	}
	set    desc [lindex [split $desc .] 0]
	set    cmd  [::list $name $desc]

	foreach category $sections {
	    lappend cmds($category) $cmd
	    set parent [lreverse [lassign [lreverse $category] leaf]]
	    lappend subc($parent) $leaf
	}
    }

    #parray subc
    #parray cmds

    ::list [array get subc] [array get cmds]
}

proc ::cmdr::help::format::SectionOrder {root subc} {

    # IIa. Natural order first.
    set categories [lsort -dict -unique [dict get $subc {}]]

    # IIb. Look for and apply user overrides.
    if {[$root exists *category-order*]} {
	# Record natural order
	set n 0
	foreach c $categories {
	    dict set map $c $n
	    incr n -10
	}
	# Special treatment of generated category, move to end.
	if {"Miscellaneous" in $categories} {
	    dict set map Miscellaneous -10000
	}
	# Overwrite natural with custom ordering.
	dict for {c n}  [$root get *category-order*] {
	    if {$c ni $categories} continue
	    dict set map $c $n
	}
	# Rewrite into tuples.
	foreach {c n} $map {
	    lappend tmp [::list $n $c]
	}

	#puts [join [lsort -decreasing -integer -index 0 $tmp] \n]

	# Sort tuples into chosen order, and rewrite back to list of
	# plain categories.
	set categories {}
	foreach item [lsort -decreasing -integer -index 0 $tmp] {
	    lappend categories [lindex $item 1]
	}
    } else {
	# Without bespoke ordering only the generated category gets
	# treated specially.
	set pos [lsearch -exact $categories Miscellaneous]
	if {$pos >= 0} {
	    set categories [linsert [lreplace $categories $pos $pos] end Miscellaneous]
	}
    }

    return $categories
}


# # ## ### ##### ######## ############# #####################
## Ready
package provide cmdr::help 1.0.1
