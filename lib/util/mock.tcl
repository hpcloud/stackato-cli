# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require http

# - tcllib candidate -> http::intercept

rename http::geturl http::__geturl__

proc http::geturl {url args} {
    variable ::mock::cache
    variable ::mock::count

    http::Log [info level 0]

    set req [::mock::R $url $args]

    # Count number of times the request is made.
    incr count($req)

    #puts $req
    #parray cache

    # Check the mockup database for the request. If present generate a
    # http token filled with its response data, as if it had been
    # returned from a web server.

    if {[info exists cache($req)]} {
	set token [namespace current]::[incr http(uid)]
	variable $token
	upvar 0 $token state
	reset $token

	#puts ///////////////$token

	array set state $cache($req)

	#parray state
	#puts ///////////////////////
	return $token
    }

    # Request not found in the mockup. Run through original command,
    # i.e. perform actual fetching, except if not allowed to talk to
    # the web.

    variable ::mock::networkenabled
    if {!$networkenabled} {
	return -code error -errorcode {MOCK REJECT} \
	    "Bad HTTP request [info level 0]"
    }

    return [uplevel 1 [list http::__geturl__ $url {*}$args]]
}

namespace eval ::mock {
    variable networkenabled 0
    variable cache ; array set cache {}
    variable count ; array set count {}
}

proc ::mock::parse {response} {
    array set state {}
    set lines [split $response \n]

    set first [struct::list shift lines]
    # first = HTTP/x.y STATUS TEXT
    regexp {^HTTP/\d+\.\d+ (\d{3}( .*)?)$} $first -> state(http)

    while {[llength $lines]} {
	set line [struct::list shift lines]

	#puts %%%|$line|

	# snarfed from http ... single line
	# until empty line, remainder is (body).

	# Process header lines
	if {[regexp -nocase {^([^:]+):(.+)$} $line x key value]} {
	    switch -- [string tolower $key] {
		content-type {
		    set state(type) [string trim [string tolower $value]]
		    # grab the optional charset information
		    regexp -nocase {charset\s*=\s*(\S+?);?} \
			$state(type) -> state(charset)
		}
		content-length {
		    set state(totalsize) [string trim $value]
		}
		content-encoding {
		    set state(coding) [string trim $value]
		}
		transfer-encoding {
		    set state(transfer) \
			[string trim [string tolower $value]]
		}
		proxy-connection -
		connection {
		    set state(connection) \
			[string trim [string tolower $value]]
		}
	    }
	    lappend state(meta) $key [string trim $value]
	} else {
	    #puts %%%[llength $lines]
	    #puts %%%/$lines/

	    # and regenerate the body.
	    set state(body) [join $lines \n]
	    set lines {}
	}
    }

    set state(status) ok
    return [array get state]
}

proc ::mock::watch {type url args} {
    variable cache
    set key ${type}-$url
    set cache($key) $args
    return
}

proc ::mock::result {type url response} {
    variable cache
    set key ${type}-$url
    set cache($key) [parse $response]
    return
}

proc ::mock::reset {} {
    variable cache
    array unset cache *
    variable count
    array unset count *
    return
}

proc ::mock::called {type url} {
    variable count
    set key ${type}-$url
    return $count($key)
}

proc ::mock::R {url options} {
    array set _ $options
    if {![info exists _(-method)]} { set _(-method) GET }
    return $_(-method)-${url}
}
