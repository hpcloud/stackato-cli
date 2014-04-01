## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Application names, Lexically ok.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate
package require cmdr::validate::common
package require stackato::validate::common

debug level  validate/appname-lex
debug prefix validate/appname-lex {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export appname-lex
    namespace ensemble create
}

namespace eval ::stackato::validate::appname-lex {
    namespace export default validate complete release ok
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::cmdr::validate::common::fail
}

proc ::stackato::validate::appname-lex::default  {p }  { return {} }
proc ::stackato::validate::appname-lex::release  {p x} { return }
proc ::stackato::validate::appname-lex::complete {p x} { return {} }

proc ::stackato::validate::appname-lex::validate {p x} {
    debug.validate/appname-lex {}

    if {![ok $p $x]} {
	fail $p APPNAME-LEX "application name (\[a-zA-Z0-9-\]*)" $x
    }
    return $x
}

proc ::stackato::validate::appname-lex::ok {p x} {
    debug.validate/appname-lex {}

    if {[regexp {[^a-zA-Z0-9-]} $x]} {
	return 0
    } else {
	return 1
    }
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::appname-lex 0
