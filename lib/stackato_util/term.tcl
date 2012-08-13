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
package require stackato::readline

namespace eval ::stackato::term {
    namespace import ::stackato::color
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::term::ask/string {query {default {}}} {
    puts -nonewline stdout $query
    flush stdout
    set response [stackato::readline::gets]
    if {($response eq {}) && ($default ne {})} {
	set response $default
    }
    return $response
}

proc ::stackato::term::ask/string* {query} {
    puts -nonewline stdout $query
    flush stdout
    return [stackato::readline::gets*]
}

proc ::stackato::term::ask/yn {query {default yes}} {
    append query [expr {$default
			? " \[[color green Y]n\]: "
			: " \[y[color green N]\]: "}]
    while {1} {
	puts -nonewline stdout $query
	flush stdout
	set response [stackato::readline::gets]
	if {$response eq {}} { set response $default }
	if {[string is bool $response]} break
	puts stdout "You must choose \"yes\" or \"no\""

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
    while {1} {
	puts -nonewline stdout $query
	flush stdout
	set response [stackato::readline::gets]
	if {($response eq {}) && $hasdefault} {
	    set response $default
	}
	if {$response in $choices} break
	puts stdout "You must choose one of $lc"
    }

    return $response
}

proc ::stackato::term::ask/menu {header prompt choices {default {}}} {
    set hasdefault [expr {$default in $choices}]

    set n 1
    table::do t {{} Choices} {
	foreach c $choices {
	    if {$default eq $c} {
		$t add ${n}. [color green $c]
	    } else {
		$t add ${n}. $c
	    }
	    incr n
	}
    }
    $t plain
    $t noheader
    while {1} {
	if {$header ne {}} {puts stdout $header}
	$t show* {puts stdout}
	puts -nonewline stdout $prompt
	flush stdout

	set response [stackato::readline::gets]
	if {($response eq {}) && $hasdefault} {
	    set response $default
	}

	if {$response in $choices} break

	if {[string is int $response]} {
	    # Inserting a dummy to handle indexing from 1...
	    set response [lindex [linsert $choices 0 {}] $response]
	    if {$response in $choices} break
	}

	puts stdout "You must choose one of the above"
    }

    $t destroy
    return $response
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
