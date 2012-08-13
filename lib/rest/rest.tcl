# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011 Donal Fellows, BSD licensed.
## Copyright (c) 2011-2012 Modifications by ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require http
package require TclOO

#puts [package ifneeded http [package present http]]

# RESTful service core
package provide restclient 0.1

# Support class for RESTful web services. This wraps up the http package to
# make everything appear nicer.
oo::class create ::REST {

	variable base wadls acceptedmimetypestack options

	constructor {baseURL args} {
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
		}
		my configure {*}$args
		return
	}

	method configure {args} {
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
		return $options($option)
	}

	# TODO: Cookies!

	method ExtractError {tok} {
		return [http::code $tok],[http::data $tok]
	}

	method OnRedirect {tok location} {
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
			return -code error -errorcode {REST REDIRECT} [list $code [split $where /] $hdrs]
		}

		return -code error -errorcode {REST REDIRECT} [list $code $where $hdrs]
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
		lappend acceptedmimetypestack [http::config -accept]
		http::config -accept [join $args ", "]
		return
	}
	method PopAcceptedMimeTypes {} {
		set old [lindex $acceptedmimetypestack end]
		set acceptedmimetypestack [lrange $acceptedmimetypestack 0 end-1]
		http::config -accept $old
		return
	}

	method DoRequest {method url {type ""} {value ""}} {
		if {$value in [file channels]} {
			set query -querychannel
			if {[llength $options(-progress)]} {
				lappend req_options -queryprogress $options(-progress)
			}
			if {$options(-blocksize) ne {}} {
				lappend req_options -queryblocksize $options(-blocksize)
			}
		} else {
			set query -query
			if {[llength $options(-progress)]} {
				lappend req_options -queryprogress $options(-progress)
			}
			if {$options(-blocksize) ne {}} {
				lappend req_options -queryblocksize $options(-blocksize)
			}
		}

		lappend req_options -method $method -type $type $query $value
		if {[llength $options(-headers)]} {
			lappend req_options -headers $options(-headers)
		}

		# Show request
		if {$options(-trace)} {
			if {$value ne {}} {
				if {[string match *form* $type]} {
					puts "\nRequest  $method, $type: $url -query <BINARY_FORM-VALUE-NOT-SHOWN>"
				} else {
					puts "\nRequest  $method, $type: $url -query $value"
				}
			} else {
				puts "\nRequest  $method, $type: $url"
			}
			if {[llength $options(-headers)]} {
				foreach {k v} $options(-headers) {
					puts "Header $k:\t$v"
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

			if {[catch {
				set tok [http::geturl $url {*}$req_options]
			} e o]} {
				set host [join [lrange [split $url /] 0 2] /]
				return -code error \
					-errorcode [list REST HTTP REFUSED] \
					"Server \"$host\" refused connection ($e)."
			}

			# Show response
			if {$options(-trace)} {
				puts "Response Code:    [http::code   $tok]"
				puts "Response Code':   [http::ncode  $tok]"
				puts "Response Status:  [http::status $tok]"
				puts "Response Error:   [http::error  $tok]"
				puts "Response Headers: [http::meta   $tok]"
				puts "Response Body:    [http::data   $tok]"
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
					http::cleanup $tok
					error "missing a location header!"
				}
				my OnRedirect $tok $location
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
