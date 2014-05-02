# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

## Bits and pieces of this should be moved to
## tcllib's term::ansi::ctrl::unix.
## These are in the ctrl child namespace.

# # ## ### ##### ######## ############# #####################

package provide stackato::term 0
package require Tcl 8.5
package require stackato::color
package require stackato::log
package require linenoise
package require try
package require table

namespace eval ::stackato {
    namespace export term
}
namespace eval ::stackato::term {
    namespace import ::stackato::color
    namespace import ::stackato::log::wrap
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::term::ask/string {query {default {}}} {
    try {
	set response [Interact {*}[Fit $query 10]]
    } on error {e o} {
	if {$e eq "aborted"} {
	    error Interrupted error SIGTERM
	}
	return {*}${o} $e
    }
    if {($response eq {}) && ($default ne {})} {
	set response $default
    }
    return $response
}

proc ::stackato::term::ask/string/extended {query args} {
    # accept  -history, -hidden, -complete
    # plus    -default
    # but not -prompt

    # for history ... integrate history load/save from file here?
    # -history is then not boolean, but path to history file.

    set default {}
    set config {}
    foreach {o v} $args {
	switch -exact -- $o {
	    -history -
	    -hidden -
	    -complete {
		lappend config $o $v
	    }
	    -default {
		set default $v
	    }
	    default {
		return -code error "Bad option \"$o\", expected one of -history, -hidden, -prompt, or -default"
	    }
	}
    }
    try {
	set response [Interact {*}[Fit $query 10] {*}$config]
    } on error {e o} {
	if {$e eq "aborted"} {
	    error Interrupted error SIGTERM
	}
	return {*}${o} $e
    }
    if {($response eq {}) && ($default ne {})} {
	set response $default
    }
    return $response
}

proc ::stackato::term::ask/string* {query} {
    try {
	set response [Interact {*}[Fit $query 10] -hidden 1]
    } on error {e o} {
	if {$e eq "aborted"} {
	    error Interrupted error SIGTERM
	}
	return {*}${o} $e
    }
    return $response
}

proc ::stackato::term::ask/yn {query {default yes}} {
    append query [expr {$default
			? " \[[color green Y]n\]: "
			: " \[y[color green N]\]: "}]

    lassign [Fit $query 5] header prompt
    while {1} {
	try {
	    set response \
		[Interact $header $prompt \
		     -complete {::stackato::term::Complete {yes no false true on off 0 1} 1}]
		     
	} on error {e o} {
	    if {$e eq "aborted"} {
		error Interrupted error SIGTERM
	    }
	    return {*}${o} $e
	}
	if {$response eq {}} { set response $default }
	if {[string is bool $response]} break
	puts stdout [wrap "You must choose \"yes\" or \"no\""]
    }

    return $response
}

proc ::stackato::term::ask/choose {query choices {default {}}} {
    set hasdefault [expr {$default in $choices}]

    set lc [linsert [join $choices {, }] end-1 or]
    if {$hasdefault} {
	set lc [string map [list $default [color green $default]] $lc]
    }

    append query " ($lc): "

    lassign [Fit $query 5] header prompt

    while {1} {
	try {
	    set response \
		[Interact $header $prompt \
		     -complete [list ::stackato::term::Complete $choices 0]]
	} on error {e o} {
	    if {$e eq "aborted"} {
		error Interrupted error SIGTERM
	    }
	    return {*}${o} $e
	}
	if {($response eq {}) && $hasdefault} {
	    set response $default
	}
	if {$response in $choices} break
	puts stdout [wrap "You must choose one of $lc"]
    }

    return $response
}

proc ::stackato::term::ask/menu {header prompt choices {default {}}} {
    set hasdefault [expr {$default in $choices}]

    # Full list of choices is the choices themselves, plus the numeric
    # indices we can address them by. This is for the prompt
    # completion callback below.
    set fullchoices $choices

    set n 1
    table::do t {{} Choices} {
	foreach c $choices {
	    if {$default eq $c} {
		$t add ${n}. [color green $c]
	    } else {
		$t add ${n}. $c
	    }
	    lappend fullchoices $n
	    incr n
	}
    }
    $t plain
    $t noheader

    lassign [Fit $prompt 5] pheader prompt

    while {1} {
	if {$header ne {}} {puts stdout $header}
	$t show* {puts stdout}

	try {
	    set response \
		[Interact $pheader $prompt \
		     -complete [list ::stackato::term::Complete $fullchoices 0]]
	} on error {e o} {
	    if {$e eq "aborted"} {
		error Interrupted error SIGTERM
	    }
	    return {*}${o} $e
	}
	if {($response eq {}) && $hasdefault} {
	    set response $default
	}

	if {$response in $choices} break

	if {[string is int $response]} {
	    # Inserting a dummy to handle indexing from 1...
	    set response [lindex [linsert $choices 0 {}] $response]
	    if {$response in $choices} break
	}

	puts stdout [wrap "You must choose one of the above"]
    }

    $t destroy
    return $response
}

proc ::stackato::term::Complete {choices nocase buffer} {
    if {$buffer eq {}} {
	return $choices
    }

    if {$nocase} {
	set buffer [string tolower $buffer]
    }

    set candidates {}
    foreach c $choices {
	if {![string match ${buffer}* $c]} continue
	lappend candidates $c
    }
    return $candidates
}

proc ::stackato::term::Interact {header prompt args} {
    if {$header ne {}} { puts $header }
    linenoise prompt {*}$args -prompt $prompt
}

proc ::stackato::term::Fit {prompt space} {
    # Similar to stackato::log::wrap, except wrapping is conditional
    # here, with a split following.
    global env
    if {[info exists env(STACKATO_NO_WRAP)]} {
	return [list {} $prompt]
    }

    set w [expr {[linenoise columns] - $space }]
    # we leave space for some characters to be entered.

    if {[string length $prompt] < $w} {
	return [list {} $prompt]
    }

    set prompt [textutil::adjust::adjust $prompt -length $w -strictlength 1]

    set prompt [split $prompt \n]
    set header [join [lrange $prompt 0 end-1] \n]
    set prompt [lindex $prompt end]
    # alt code for the same.
    #set header [join [lreverse [lassign [lreverse [split $prompt \n]] prompt]] \n]
    append prompt { }

    list $header $prompt
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::term {
    namespace export map \
	ask/string ask/string* ask/yn ask/choose ask/menu state

    namespace ensemble create
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::term 0
