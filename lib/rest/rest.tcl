# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011 Donal Fellows, BSD licensed.
## Copyright (c) 2011-2012 Modifications by ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require s-http ;# local copy of http with our hacks, and much more placed Log'ging activity.
package require TclOO
package require ooutil

debug level  rest
debug prefix rest {[debug caller] | }

# RESTful service core
package provide restclient 0.1

# Support class for RESTful web services. This wraps up the http
# package to make everything appear nicer.

oo::class create ::REST {

	variable mybase mywadls myacceptedmimetypestack myoptions \
		mycounter mymap mycookie

	# mybase                  : string - Base url of all REST calls. The target to talk to.
	# mywadls                 : array  - wadl messages already printed, prevent duplicate printing
	# myacceptedmimetypestack : list   - stack of accepted mime-types - NOT USED
	# myoptions               : array  - configurable options (see constructor)
	#
	# Handling of async requests
	#
	# mycounter - Counter for requests
	# mymap     - mapping from request handle to token
	# mycookie  - Visible request counter for the tracing.

	method rebase {base} {
		debug.rest {}
		set mybase $base
		my LogWADL $base
		return
	}

	constructor {baseURL args} {
		debug.rest {}
		set mybase $baseURL
		my LogWADL $baseURL

		# Option defaults first, then the user's configuration.
		array set myoptions {
			-progress            {}
			-blocksize           {}
			-follow-redirections 0
			-max-redirections    5
			-headers             {}
			-trace               0
			-trace-fd            stdout
			-accept-no-location  0
		}
		my configure {*}$args
		return
	}

	method configure {args} {
		debug.rest {}
		switch -- [llength $args] {
			0 {
				return [array get myoptions]
			}
			1 {
				return [my cget [lindex $args 0]]
			}
			default {
				array set myoptions $args
			}
		}
		return
	}

	method cget {option} {
		debug.rest {}
		return $myoptions($option)
	}

	# TODO: Cookies!

	method ExtractError {tok} {
		debug.rest {}
		return [http::code $tok],[http::data $tok]
	}

	method GetNewLocation {tok} {
		set location {}

		# Headers should be handled case-insensitive.
		# Normalize to all lower-case before access.
		set meta [http::meta $tok]
		dict for {k v} $meta {
			dict unset meta $k
			dict set meta [string tolower $k] $v
		}
		#array set _ $meta ; parray _ ; unset _
		return [dict get $meta location]
	}

	method OnRedirect {location} {
		debug.rest {}
		upvar 1 url url handle handle tok tok cmd cmd cookie cookie

		# Rewrite destination in calling context
		set url $location
		# By default, GET doesn't follow redirects; the next line would
		# change that...
		#http::cleanup $tok
		#return

		if {$myoptions(-follow-redirections)} {
			http::cleanup $tok
			return 1
		}

		set where $location
		my LogWADL $where

		set response [my Data     $tok]
		set code     [http::ncode $tok]
		set hdrs     [http::meta  $tok]

		if {[string equal -length [string length $mybase/] $location $mybase/]} {
			set where [string range $where [string length $mybase/] end]
			set where [split $where /]
		}

		my Raise $cookie [list $code $where $hdrs $response] \
			REST REDIRECT
		return 0
	}

	method LogWADL url {
		return;# do nothing
		set tok [http::geturl $url?_wadl]
		set w [http::data $tok]
		http::cleanup $tok
		if {![info exist mywadls($w)]} {
			set mywadls($w) 1
			puts stderr $w
		}
	}

	method PushAcceptedMimeTypes args {
		debug.rest {}
		lappend myacceptedmimetypestack [http::config -accept]
		http::config -accept [join $args ", "]
		return
	}

	method PopAcceptedMimeTypes {} {
		debug.rest {}
		set old [lindex $myacceptedmimetypestack end]
		set myacceptedmimetypestack [lrange $myacceptedmimetypestack 0 end-1]
		http::config -accept $old
		return
	}

	method AsyncRequest {cmd method url {type ""} {value ""}} {
		debug.rest {}

		set request [my Assemble $method $url $type $value]
		set max     $myoptions(-max-redirections)
		set trials  0

		return [my AsyncRun [my New] $method $url $max $trials $cmd {*}$request]
	}

	method AsyncRun {handle method url max trials cmd cookie request} {
		debug.rest {}
		set origr $request

		lappend request -command [mymethod AsyncDone $handle $method $url $max $trials $cmd $cookie $origr]

		if {$trials >= $max} {
			my Done $cookie error "too many redirections!"
			return
		}

		if {[catch {
			set tok [my Invoke $url $cookie $request]
			set mymap($handle) $tok
		} e o]} {
			my Done $cookie return [list {*}$o $e]
			set handle {}
		}

		debug.rest {==> $handle}
		return $handle
	}

	method AsyncDone {handle method url max trials cmd cookie request tok} {
		debug.rest {}
		# Async request has completed.
		my StateSet $tok x:rest:done  [clock clicks -milliseconds]
		::http::Log {REST DONE ok}

		if {[http::status $tok] eq "reset"} {
			# Canceled. Stop. See AsyncCancel.
			my Done $cookie reset
			return
		}

		my ShowResponse $tok $cookie

		if {[my CheckBrokenConnection]} {
			debug.rest {/ERROR BROKEN}
			return
		}
		if {[my CheckStatus]} {
			debug.rest {/ERROR STATUS}
           return
		}

		debug.rest {redirection?}

		if {([http::ncode $tok] > 299) ||
			([http::ncode $tok] == 201)} {

			debug.rest {redirection!}

			if {[catch {
				debug.rest {redirection - get location}
				set location [my GetNewLocation $tok]
			}]} {
				debug.rest {redirection - no location}

				if {$myoptions(-accept-no-location) ||
					($method in {PUT DELETE})} {
					debug.rest {redirection - no location is OK}

					# Ignore the missing location header.
					# Do not redirect. Treat like a 200 return.
				   my Complete $cookie
				   return
				}

				debug.rest {redirection - no location /FAIL}

				my Raise $cookie "missing a location header!" \
					REST LOCATION MISSING
				return
			}

			debug.rest {redirection - has location}

			if {![my OnRedirect $location]} {
				debug.rest {redirection - STOP}
				return
			}

			debug.rest {redirection - follow}

			incr trials
			my AsyncRun $handle $url $max $trials $cmd $cookie $request
			return
		}

		debug.rest {no redirection, done}

		my Complete $cookie
		return
	}

	method AsyncCancel {handle} {
		debug.rest {}
		set tok $mymap($handle)
		http::reset $tok
		# Forces AsyncDone
		return
	}

	method DoRequest {method url {type ""} {value ""}} {
		debug.rest {}

		# Implement the sync calls on top of the async core.

		# Allocate and import a variable we can wait on, in the
		# instance namespace.
		set var [self namespace]::[my New]
		upvar \#0 $var waiter
		set waiter {}

		my AsyncRequest \
			[mymethod DoRequestComplete $var] \
			$method $url $type $value
		# handle ignored, no cancellation allowed/possible.

		if {$waiter eq {}} {
			# async, wait for completion.
			debug.rest {waiting $var}
			vwait $var
			debug.rest {waiting $var done: $waiter}
		} ; # else already set, no waiting.

		# Retrieve results, and release variable.
		set r $waiter
		unset $var

		# Handle the waiter results: reset, and return
		# reset: Cannot happen here.

		lassign $r code details
		if {$code eq "reset"} {
			error "Unexpected cancellation"
		}

		return {*}$details
	}

	method DoRequestComplete {var args} {
		debug.rest {}

		# args = reset 
		#      | return return-args
		# return-args = list, options + result

		upvar \#0 $var waiter
		set waiter $args
		return
	}

	method Get {args} {
		return [my DoRequest GET $mybase/[join $args /]]
	}

	method Post {args} {
		set type [lindex $args end-1]
		set value [lindex $args end]
		set m POST
		set path [join [lrange $args 0 end-2] /]
		return [my DoRequest $m $mybase/$path $type $value]
	}

	method Put {args} {
		set type [lindex $args end-1]
		set value [lindex $args end]
		set m PUT
		set path [join [lrange $args 0 end-2] /]
		return [my DoRequest $m $mybase/$path $type $value]
	}

	method Delete args {
		set m DELETE
		my DoRequest $m $mybase/[join $args /]
		return
	}

	# ## #### ######## ################

	method Assemble {method url type value} {
		debug.rest {}

		if {[llength $myoptions(-progress)]} {
			lappend request -queryprogress $myoptions(-progress)
		}

		if {$myoptions(-blocksize) ne {}} {
			lappend request -queryblocksize $myoptions(-blocksize)
		}

		lappend request -method $method -type $type
		set theheaders $myoptions(-headers)

		if {$value in [file channels]} {
			set qmode chan
			lappend request -querychannel $value
		} else {
			set qmode string
			lappend request -query $value

			if {($value eq {}) && ($method eq "PUT")} {
				lappend theheaders Content-Length 0
			}
		}

		if {$method eq "GET"} {
			if {$type eq "application/octet-stream"} {
				debug.rest {Forced binary by type $type}
				lappend request -binary 1
			}
		}

		if {$method eq "DELETE"} {
			lappend theheaders Content-Length 0
		}

		if {[llength $theheaders]} {
			lappend request -headers $theheaders
		}

		set cookie [my ShowRequest $method $url $value $type \
						$qmode $theheaders]

		return [list $cookie $request]
	}

	method Invoke {url cookie request} {
		debug.rest {}
		my ShowTime $cookie

		if {[catch {
			debug.rest {http::geturl ...}

			::http::Log {REST START}
			set reqstart [clock clicks -milliseconds]

			set tok [http::geturl $url {*}$request]

			my StateSet $tok x:rest:start  $reqstart
			my StateSet $tok x:rest:binary [dict exists $request -binary]

			debug.rest {http::geturl ... $tok}
			debug.rest {http::geturl ... binary=[my StateGet $tok binary]}
			debug.rest {http::geturl ... binary=[my StateGet $tok x:rest:binary]}

		} e o]} {
			::http::Log {REST DONE err}

			debug.rest {get error = ($e)}

			if {[string match *handshake* $e]} {
				set host [join [lrange [split $url /] 0 2] /]
				return -code error \
					-errorcode {REST SSL} \
					"SSL/TLS problem with \"$host\": $e."

			} elseif {[string match *refused* $e]} {
				set host [join [lrange [split $url /] 0 2] /]
				return -code error \
					-errorcode {REST HTTP REFUSED} \
					"Server \"$host\" refused connection ($e)."
			} else {
				return {*}$o $e
			}
		}

		return $tok
	}

	# ## #### ######## ################

	method CheckBrokenConnection {} {
		debug.rest {}
		upvar 1 handle handle tok tok cmd cmd cookie cookie

		if {([http::status $tok] ne "ok") ||
			([http::error  $tok] ne "") ||
			([http::ncode  $tok] eq "")} {
			set    msg "Server broke connection."
			append msg " " [http::status $tok]
			append msg " " [http::error  $tok]

			my Raise $cookie $msg REST HTTP BROKEN

			debug.rest {/BROKEN}
			return 1
		}

		debug.rest {/OK}
		return 0
	}

	method CheckStatus {} {
		debug.rest {}
		upvar 1 handle handle tok tok cmd cmd cookie cookie

		# Bug 9034, 90337. For a time we treated errors in range
		# 5xx as regular responses. Especially when occuring
		# during app staging and start. Except in some places
		# (like 'login') a 502 was valid.

		# Now we are back to treating them as error, as we
		# originally did, contrary to VMC. Because VMC got changed
		# to treat them as errors as well too, and we can go back
		# to the same, matching it again.

		# The client's method 'login' has a hack on this patch
		# which regenerates 502 as a REST HTTP error. This hack is
		# currently left in the code. It should be inactive.

		if {[http::ncode $tok] > 399} {
			set status [http::ncode $tok]
			set msg    [http::data  $tok]
			set meta   [http::meta  $tok]
			dict for {k v} $meta {
				dict unset meta $k
				dict set meta [string tolower $k] $v
			}
			set meta [dict get' $meta content-type {}]
			my Raise $cookie [list $meta $msg] REST HTTP $status
			debug.rest {/FAIL}
			return 1
		}

		debug.rest {/OK}
		return 0
	}

	method Raise {cookie m args} {
		debug.rest {}
		upvar 1 handle handle tok tok cmd cmd
		my Done $cookie return [list -code error -errorcode $args $m]
		return
	}

	method Complete {cookie} {
		debug.rest {}
		upvar 1 handle handle tok tok cmd cmd

		set code [http::ncode $tok]
		set hdrs [http::meta  $tok]
		set data [my Data $tok]

		my Done $cookie return [list -code ok [list $code $data $hdrs]]
		return
	}

	method Done {cookie args} {
		debug.rest {}
		upvar 1 handle handle tok tok cmd cmd
		my ShowDone $cookie [lindex $args 0]
		unset -nocomplain mymap($handle)
		if {[info exists tok] && ($tok ne {})} {
			http::cleanup $tok
		}
		uplevel \#0 $cmd $args
		return
	}

	method Data {tok} {
		upvar 1 handle handle cmd cmd

		set hdrs [http::meta  $tok]
		set data [http::data  $tok]

		debug.rest {binary       = [my StateGet $tok binary]}
		debug.rest {binary/cli   = [my StateGet $tok x:rest:binary]}
		debug.rest {content-type = [my StateGet $tok type]}
		debug.rest {charset      = [my StateGet $tok charset]}

		if {[my StateGet $tok x:rest:binary]} {
			debug.rest {Return [string length $data], binary}
			return $data
		}

		# ATTENTION. Responses of type "application/json" have to be
		# recoded as per their charset. I.e. they are text data,
		# despite the http package thinking them to be binary.
		#
		# NOTE: We do not use the "charset" element in the token as
		# the charset to code into. The default this element may
		# contain (== ::http::defaultCharset) is wrong. The a/j
		# default is utf-8.
		#
		# Therefore to get this right we have to look for the charset
		# in the "type" element by ourselves and use our own default
		# if we did not find anything there.

		if {[string match application/json* [my StateGet $tok type]]} {
			# default charset for a/j is utf-8, or whatever is specified by the type.
			if {![regexp -- {charset=(.*)$} [my StateGet $tok type] --> enc]} {
				set enc utf-8
			}

			debug.rest {Recode  to HTTP $enc}
			set enc [http::CharsetToEncoding $enc]
			debug.rest {Recode  to Tcl  $enc : [string length $data]}

			set data [encoding convertfrom $enc $data]
			debug.rest {Recoded to Tcl  $enc : [string length $data]}
		}

		debug.rest {Return [string length $data]}
		return $data
	}

	# ## #### ######## ################

	method New {} {
		return r[incr mycounter]
	}

	method NewCookie {} {
		return X[format %08d [incr mycookie]]
	}

	method StateSet {tok var val} {
		upvar #0 $tok state
		set state($var) $val
		return
	}

	method StateGet {tok var} {
		upvar #0 $tok state
		return $state($var)
	}

	# ## #### ######## ################

	method ShowDone {cookie detail} {
		if {!$myoptions(-trace)} return
		set fd $myoptions(-trace-fd)

		puts  $fd "Request@ $cookie Done $detail"
		flush $fd
		return
	}

	method ShowRequest {method url value type qmode theheaders} {
		if {!$myoptions(-trace)} return
		set fd $myoptions(-trace-fd)

		set cookie [my NewCookie]

		puts $fd "\nRequest@ $cookie [self] [self class]"
		if {$value ne {}} {
			if { [string match *form*       $type] &&
				![string match *urlencoded* $type] &&
				($qmode eq "string")} {
				puts $fd "Request  $cookie $method, $type: $url -query <BINARY_FORM-VALUE-NOT-SHOWN>"
			} else {
				puts $fd "Request  $cookie $method, $type: $url -query $value"
			}
		} else {
			puts $fd "Request  $cookie $method, $type: $url"
		}

		my ShowDict $fd "Request  $cookie Header" $theheaders
		flush $fd
		return $cookie
	}

	method ShowTime {cookie} {
		if {!$myoptions(-trace)} return
		set fd $myoptions(-trace-fd)
		puts $fd "Request  $cookie Time [clock format [clock seconds]]"
		flush $fd
		return
	}

	method ShowResponse {tok cookie} {
		# For use by 'my Raise' within 'my Data'.
		upvar 1 handle handle cmd cmd

		if {!$myoptions(-trace)} {
			return $tok
		}

		set fd $myoptions(-trace-fd)

		set start [my StateGet $tok x:rest:start]
		set done  [my StateGet $tok x:rest:done]

		puts $fd "Response $cookie Time [clock format [clock seconds]]: [expr {$done - $start}] milliseconds"
		puts $fd "Response $cookie Code:    [http::code   $tok]"
		puts $fd "Response $cookie Code':   [http::ncode  $tok]"
		puts $fd "Response $cookie Status:  [http::status $tok]"
		puts $fd "Response $cookie Error:   [http::error  $tok]"
		puts $fd "Response $cookie Binary:  [my StateGet $tok binary]"

		my ShowDict $fd "Response $cookie Headers:" [http::meta $tok]

		puts  $fd "Response $cookie Body:    [my Data $tok]"
		flush $fd
		return $tok
	}

	method ShowDict {fd prefix dict} {
		set n [my MaxLen [dict keys $dict]]
		set fmt %-${n}s

		dict for {k v} $dict {
			puts $fd "$prefix [format $fmt $k] = ($v)"
		}
		return
	}

	method MaxLen {list} {
		set max 0
		foreach s $list {
			set n [string length $s]
			if {$n <= $max} continue
			set max $n
		}
		return $max
	}

	# ## #### ######## ################
}

# Local Variables:
# mode: tcl
# tab-width: 4
# End:
