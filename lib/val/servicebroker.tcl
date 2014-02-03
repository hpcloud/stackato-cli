## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Service Broker Name
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require cmdr::validate
package require stackato::mgr::client;# pulls v2 also
package require stackato::validate::common

debug level  validate/servicebroker
debug prefix validate/servicebroker {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export servicebroker
    namespace ensemble create
}

namespace eval ::stackato::validate::servicebroker {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::stackato::validate::common::refresh-client
    namespace import ::stackato::validate::common::expected
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::v2
}

proc ::stackato::validate::servicebroker::default  {p}   { return {} }
proc ::stackato::validate::servicebroker::release  {p x} { return }
proc ::stackato::validate::servicebroker::complete {p x} {
    refresh-client $p
    complete-enum [struct::list map [v2 service_broker list] [lambda o {
	$o @name
    }]] 0 $x

}

proc ::stackato::validate::servicebroker::validate {p x} {
    debug.validate/servicebroker {}

    refresh-client $p

    set matches [struct::list filter [v2 service_broker list] [lambda {x o} {
	string equal $x	[$o @name]
    } $x]]

    if {[llength $matches] == 1} {
	debug.validate/servicebroker {OK/canon = $x}
	return [lindex $matches 0]
    }
    debug.validate/servicebroker {FAIL}
    expected $p SERVICEBROKER "service broker" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::servicebroker 0
