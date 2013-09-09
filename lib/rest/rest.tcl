# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011 Donal Fellows, BSD licensed.
## Copyright (c) 2011-2013 Modifications by ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require http
package require TclOO

debug level  rest
debug prefix rest {[debug caller] | }

# DANGER -- BRITTLE -- Revisit for each new version of http package
# HACK internals to auto-close on our side for response length 0, even
# for 'connection: close'.
if 1 {
proc ::http::Event {sock token} \
	[string map \
		 [list {For non-chunked transfer} {
		if {1 && ($state(totalsize) == 0)} {
			Log "no body, stop"
			Eof $token
			return
	    }
		# For non-chunked transfer }] \
	[info body ::http::Event]]

# And hack geturl to handle v1 API also, with different headers.
proc http::geturl {url args} \
	[string map \
		 [list {set state(-keepalive) $defaultKeepalive} {set state(-keepalive) $defaultKeepalive ; set state(totalsize) {}}] \
		 [info body ::http::geturl]]
	  }

# RESTful service core
package provide restclient 0.1

# Support class for RESTful web services. This wraps up the http package to
# make everything appear nicer.
oo::class create ::REST {

	variable base wadls acceptedmimetypestack options

	constructor {baseURL args} {
		debug.rest {}
		set base   $baseURL
		my LogWADL $baseURL

		# Option defaults first, then the user's configuration.
		array set options {
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
				return [array get options]
			}
			1 {
				return [my cget [lindex $args 0]]
			}
			default {
				array set options $args
			}
		}
		return
	}

	method cget {option} {
		debug.rest {}
		return $options($option)
	}

	# TODO: Cookies!

	method ExtractError {tok} {
		debug.rest {}
		return [http::code $tok],[http::data $tok]
	}

	method OnRedirect {tok location response} {
		debug.rest {}
		upvar 1 url url
		set url $location
		# By default, GET doesn't follow redirects; the next line would
		# change that...
		#return -code continue

		if {$options(-follow-redirections)} {
			return -code continue
		}

		set where $location
		my LogWADL $where

		set code [http::ncode $tok]
		set hdrs [http::meta  $tok]

		if {[string equal -length [string length $base/] $location $base/]} {
			set where [string range $where [string length $base/] end]
			return -code error -errorcode {REST REDIRECT} [list $code [split $where /] $hdrs $response]
		}

		return -code error -errorcode {REST REDIRECT} [list $code $where $hdrs $response]
	}

	method LogWADL url {
		return;# do nothing
		set tok [http::geturl $url?_wadl]
		set w [http::data $tok]
		http::cleanup $tok
		if {![info exist wadls($w)]} {
			set wadls($w) 1
			puts stderr $w
		}
	}

	method PushAcceptedMimeTypes args {
		debug.rest {}
		lappend acceptedmimetypestack [http::config -accept]
		http::config -accept [join $args ", "]
		return
	}
	method PopAcceptedMimeTypes {} {
		debug.rest {}
		set old [lindex $acceptedmimetypestack end]
		set acceptedmimetypestack [lrange $acceptedmimetypestack 0 end-1]
		http::config -accept $old
		return
	}

	method DoRequest {method url {type ""} {value ""}} {
		debug.rest {}

		set theheaders $options(-headers)
		if {$method eq "DELETE"} {
			lappend theheaders Content-Length 0
		}

		if {$value in [file channels]} {
			set query -querychannel
		} else {
			set query -query
		}
		if {[llength $options(-progress)]} {
			lappend req_options -queryprogress $options(-progress)
		}
		if {$options(-blocksize) ne {}} {
			lappend req_options -queryblocksize $options(-blocksize)
		}

		lappend req_options -method $method -type $type $query $value

		if {$method eq "GET"} {
			if {$type eq "application/octet-stream"} {
				debug.rest {Forced binary by type $type}
				lappend req_options -binary 1
			}
		}

		if {[llength $theheaders]} {
			lappend req_options -headers $theheaders
		}

		# Show request
		if {$options(-trace)} {
			if {$value ne {}} {
				if {[string match *form* $type] &&
					![string match *urlencoded* $type] &&
					($query eq "-query")} {
					puts $options(-trace-fd) "\nRequest  $method, $type: $url -query <BINARY_FORM-VALUE-NOT-SHOWN>"
				} else {
					puts $options(-trace-fd) "\nRequest  $method, $type: $url -query $value"
				}
			} else {
				puts $options(-trace-fd) "\nRequest  $method, $type: $url"
			}
			if {[llength $theheaders]} {
				set n [my MaxLen [dict keys $theheaders]]
				set fmt %-${n}s
				foreach {k v} $theheaders {
					puts $options(-trace-fd) "Request  Header [format $fmt $k] = ($v)"
				}
			}
		}

		set max $options(-max-redirections)
		for {set reqs 0} {$reqs < $max} {incr reqs} {
			if {[info exists tok]} {
				http::cleanup $tok
			}

			#puts "WEB:http::geturl $url ($req_options)"
			#if {$method ne "GET"} { error dont-write-yet }

			puts $options(-trace-fd) "Request  Time [clock format [clock seconds]]"

			if {[catch {
				debug.rest {http::geturl ...}
				set reqstart [clock clicks -milliseconds]
				set tok [http::geturl $url {*}$req_options]
				set reqdone [clock clicks -milliseconds]
				debug.rest {http::geturl ... $tok}
			} e o]} {
				if {[string match *refused* $e]} {
					set host [join [lrange [split $url /] 0 2] /]
					return -code error \
						-errorcode [list REST HTTP REFUSED] \
						"Server \"$host\" refused connection ($e)."
				} else {
					return {*}$o $e
				}
			}

			# Show response
			if {$options(-trace)} {
				puts $options(-trace-fd) "Response Time [clock format [clock seconds]]: [expr {$reqdone - $reqstart}] milliseconds"
				puts $options(-trace-fd) "Response Code:    [http::code   $tok]"
				puts $options(-trace-fd) "Response Code':   [http::ncode  $tok]"
				puts $options(-trace-fd) "Response Status:  [http::status $tok]"
				puts $options(-trace-fd) "Response Error:   [http::error  $tok]"
				set n [my MaxLen [dict keys [http::meta $tok]]]
				set fmt %-${n}s
				dict for {k v} [http::meta $tok] {
					puts $options(-trace-fd) "Response Headers: [format $fmt $k] = ($v)"
				}
				puts $options(-trace-fd) "Response Body:    [http::data   $tok]"
			}

			if {([http::status $tok] ne "ok") ||
				([http::error  $tok] ne "") ||
				([http::ncode  $tok] eq "")} {
				set msg "Server broke connection."
				append msg " " [http::status $tok]
				append msg " " [http::error  $tok]
				http::cleanup $tok
				return -code error \
					-errorcode [list REST HTTP BROKEN] \
					$msg
			}

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
				#set msg [my ExtractError $tok]
				set status [http::ncode $tok]
				set msg [http::data $tok]
				http::cleanup $tok
				return -code error \
					-errorcode [list REST HTTP $status] \
					$msg
			} elseif {([http::ncode $tok] > 299) ||
					  ([http::ncode $tok] == 201)} {
				set location {}

				# Headers should be handled case-insensitive.
				# Normalize to all lower-case before access.
				set meta [http::meta $tok]
				dict for {k v} $meta {
					dict unset meta $k
					dict set meta [string tolower $k] $v
				}
				#array set _ $meta ; parray _ ; unset _
				if {[catch {
					set location [dict get $meta location]
				}]} {
					if {$options(-accept-no-location) || ($method in {PUT DELETE})} {
						# Ignore the missing header
						# Simply do not redirect. Treat like
						# a 200 return.

						set code [http::ncode $tok]
						set data [http::data  $tok]
						set hdrs [http::meta  $tok]
						http::cleanup $tok
						return [list $code $data $hdrs]
					}

					http::cleanup $tok
					error "missing a location header!"
				}
				set data [http::data $tok]
				my OnRedirect $tok $location $data
			} else {
				set code [http::ncode $tok]
				set data [http::data  $tok]
				set hdrs [http::meta  $tok]
				http::cleanup $tok
				return [list $code $data $hdrs]
			}
		}
		error "too many redirections!"
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

	method Get {args} {
		return [my DoRequest GET $base/[join $args /]]
	}

	method Post {args} {
		set type [lindex $args end-1]
		set value [lindex $args end]
		set m POST
		set path [join [lrange $args 0 end-2] /]
		return [my DoRequest $m $base/$path $type $value]
	}

	method Put {args} {
		set type [lindex $args end-1]
		set value [lindex $args end]
		set m PUT
		set path [join [lrange $args 0 end-2] /]
		return [my DoRequest $m $base/$path $type $value]
	}

	method Delete args {
		set m DELETE
		my DoRequest $m $base/[join $args /]
		return
	}
}

# Local Variables:
# mode: tcl
# tab-width: 4
# End:
