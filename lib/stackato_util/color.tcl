# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require term::ansi::code::ctrl ; # ANSI terminal control codes

namespace eval ::stackato::color {
    ::term::ansi::code::ctrl::import ctrl
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::color::colorize {{flag 1}} {
    variable colorize $flag
    return
}

proc ::stackato::color::red {text} {
    Colorize sda_fgred $text
}

proc ::stackato::color::green {text} {
    Colorize sda_fggreen $text
}

proc ::stackato::color::yellow {text} {
    Colorize sda_fgyellow $text
}

proc ::stackato::color::white {text} {
    Colorize sda_fgwhite $text
}

proc ::stackato::color::blue {text} {
    Colorize sda_fgblue $text
}

proc ::stackato::color::cyan {text} {
    Colorize sda_bgcyan $text
}

proc ::stackato::color::bold {text} {
    Colorize sda_bold $text
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::color::Colorize {code text} {
    variable colorize
    if {!$colorize} {
	return $text
    } else {
	return [ctrl::$code]$text[ctrl::sda_reset]
    }
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::color {
    variable colorize 0

    namespace export colorize red green yellow bold white blue cyan
    namespace ensemble create
}

namespace eval ::stackato {
    namespace export color
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::color 0
