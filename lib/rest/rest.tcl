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
package require fileutil
package require url
package require exec

# # ## ### ##### ######## ############# #####################
## TLS setup, general place.

package require cmdr::color
package require autoproxy 1.5.3 ; # Contains the https fixes.
package require tls

http::register https 443 autoproxy::tls_socket ; # proxy aware TLS/SSL.

# # ## ### ##### ######## ############# #####################

debug level  rest
debug prefix rest {[debug caller] | }
debug.rest {[package ifneeded autoproxy [package require autoproxy]]}

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
			-rprogress           {}
			-blocksize           {}
			-rblocksize          {}
			-follow-redirections 0
			-max-redirections    5
			-headers             {}
			-trace               0
			-trace-fd            stdout
			-accept-no-location  0
			-channel             {}
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

			if {$myoptions(-channel) ne {}} {
				# Clear the channel, in case the redirection itself
				# had a response body. That body is not wanted. Only
				# the badoy of the last request not doing a
				# redirection is wanted.
				seek $myoptions(-channel) 0
				chan truncate $myoptions(-channel) 0
			}
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
			my AsyncRun $handle $method $url $max $trials $cmd $cookie $request
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
		if {[llength $myoptions(-rprogress)]} {
			lappend request -progress $myoptions(-rprogress)
		}
		if {$myoptions(-rblocksize) ne {}} {
			lappend request -blocksize $myoptions(-rblocksize)
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
			if {$myoptions(-channel) ne {}} {
				lappend request -channel $myoptions(-channel)
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
		REST::initialize
		my ShowTime $cookie

		if {[catch {
			debug.rest {http::geturl ...}

			::http::Log {REST START}
			set reqstart [clock clicks -milliseconds]

			REST::host [url domain [join [lrange [split $url /] 0 2] /]]

			# SNI processing.
			http::register https 443 [list autoproxy::tls_socket -servername [REST::host]]
			set tok [http::geturl $url {*}$request]

			http::register https 443 autoproxy::tls_socket

			my StateSet $tok x:rest:start  $reqstart
			my StateSet $tok x:rest:binary [dict exists $request -binary]

			debug.rest {http::geturl ... $tok}
			debug.rest {http::geturl ... binary=[my StateGet $tok binary]}
			debug.rest {http::geturl ... binary=[my StateGet $tok x:rest:binary]}

		} e o]} {
			::http::Log {REST DONE err}

			debug.rest {get error = ($e)}

			if {[string match *handshake* $e]} {
				set detail [REST::status]
				set host   [REST::host]
				return -code error \
					-errorcode {REST SSL} \
					"SSL problem with \"$host\": $e, $detail."

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
			if {[string equal -nocase authorization $k]} { set v <REDACTED> }
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

# # ## ### ##### ######## ############# #####################

# It's a good idea to unset any ::AUTH($chan,*) entries when they are
# no longer needed -- either after the connection has been
# established, and the authcode and autherr have been checked, or in
# the callback for cleanup/closing the socket.  Not doing so is bad
# bad bad, and should only be done in short-lived applications that
# exit after one connection.

# See also cmdr/cmdr.tcl, various debug options.
global shpre
set    shpre [http::Now]

namespace eval ::REST {
	variable acode  1
	variable amsg   ""
	variable cafile {}
	variable cadir  {}
	variable debug  off
	variable skip   off
	# Per host skipping, to generate only one warning per host, instead of series of it.
	variable skiph  {}
}

proc ::REST::initialize {} {
	debug.rest {tls [package provide tls] @ [package ifneeded tls [package provide tls]]}
	debug.rest {tls [package provide tls] = [tls::version]}

	variable cafile

	# Note: Should have a cafile, even if only the wrapped default.
	if {$cafile eq {}} {
		# May not have cafile if the cmdr triggers an early access of
		# the target, before the completion phase.
		# That is possible, for example, when an unknown option is
		# offered to an optional argument as possible value, and the
		# associated validation type needs the target. In a best
		# effort we poke into the cmdr and force @cafile to have a
		# value, this stores the data here.
		#
		# Concrete example: quota configure ... ?name?
		# OP [301584].
		debug.rest {force cafile default early}
		[stackato-cli get *config*] @cafile
	}

	debug.rest {cafile = ($cafile)}

	if {[file system $cafile] ne "native"} {
		debug.rest {save wrapped certs to disk}
		# Save wrapped certs to disk for TLS, which is not vfs-ready,
		# to read.
		#
		# NOTE: We cannot delete the file until the process ends. The
		# TLS package actually reads it only on demand, it seems. I.e.
		# deletion after setting it makes it unavailable again.  So we
		# only register it with 'exec' to be removed on exit.

		set tmp [fileutil::tempfile stackato_certs_]
		file copy -force $cafile $tmp
		exec::clear-on-exit $tmp
		set cafile $tmp
	}

	debug.rest {activate tls 1, 1.1, and 1.2}
	tls::init \
		-tls1   on \
		-tls1.1 on \
		-tls1.2 on \
		-command ::REST::verify \
		-cafile $cafile

	proc ::REST::initialize {} {}
	return
}

proc ::REST::cafile {path} {
	debug.rest {cafile := ($path)}
	variable cafile $path
	return
}

proc ::REST::host {{thehost {}}} {
	variable host
	if {[llength [info level 0]] == 2} {
		set host $thehost
	}
	return $host
}

proc ::REST::tlsskipverify {} {
	debug.rest {}
	variable skip on
	return
}

proc ::REST::tlsdebug {} {
	debug.rest {}
	variable debug on
	return
}

proc ::REST::status {} {
	variable acode
	if {$acode} { return "" }
	variable amsg
	return $amsg
}

proc ::REST::verify {cmd args} {
	debug.rest {}
	variable debug  ; # global debug flag     (--debug-tls-handshake)
	variable skip   ; # global skip of checks (--skip-ssl-validation)
	# Note. We check and report anything only once per specific host.
	variable host   ; # Name of the host we are talking to and checking
	variable skiph  ; # per-host skip (only one check per host).

	# [301584] Ensure proper values in case of early access to target,
	# before cmdr's completion phase.
	[stackato-cli get *config*] @skip-ssl-validation
	[stackato-cli get *config*] @debug-tls-handshake

	if {$debug} {
		global shpre
		set n [http::Now]
		set d [expr {$n - $shpre}]
		set prefix "[cmdr color bg-red TLS:]  [format %10d $d] [format %15d $n] "
	}

    # Based on http://wiki.tcl.tk/2630, Melissa Schrumpf.
    # Check that cmd is proper, and filter info/error.
    switch -exact -- $cmd {
		error   -
		info    {
			if {$debug} { puts $prefix\t$cmd\t$args }
			return 1
		}
		verify  {}
		default {
			if {$debug} { puts $prefix\t$cmd\t$args }
			return -code error "Bad command \"$cmd\", expected one of error, info, or verify"
		}
    }

    # Here the command is 'verify'. Now is the time to perform any
    # (additional checks!). And to bail out if so advised by user or
    # previous checks.

	if {$skip} {
		if {$debug} {
			puts $prefix\t$cmd\tskip!globally-disabled
		}
		return 1
	}

	if {[dict exists $skiph $host]} {
		if {$debug} {
			puts $prefix\t$cmd\tskip!already-checked:$host
		}
		return 1
	}
	dict set skiph $host .

    # Extract individual arguments first.
    lassign $args chan depth cert rc err

    # rc: TLS validation result:
    #     0 - some failure, details in 'err'.
    #     1 - validation ok.

	if {$debug} {
		puts $prefix\t$cmd
		puts $prefix\t$cmd\tchan\t$chan
		puts $prefix\t$cmd\tdepth\t$depth
		puts $prefix\t$cmd\trc\t$rc
		puts $prefix\t$cmd\terr\t$err
		# The cert is a dict.
		dict for {k v} $cert {
			puts $prefix\t$cmd\tcert\t$k\t=\t$v
		}
	}

	variable acode $rc
	variable amsg  $err

	if 0 {switch -glob $err {
		{unable to get local issuer cert*} -
		{cert* not trusted} {
			# suppress errors about a broken validation chain.
			set acode 1
		}
	}}

    # The information I'm interested in is whether or not the cert
    # validated.  I include the error message in case the application
    # wants to take different actions on different errors (for
    # example, accept an expired cert with a warning, but reject one
    # for which the chain does not validate.

    # TLS does not verify that the peer certificate is for the host to
    # whom we are connected:

    if {($depth == 0) &&
		($acode == 1)} {
		set subl  [split [dict get $cert subject] ","]
		set peers [Peers $chan]

		if {$debug} {
			puts $prefix\t$cmd\tcheck\t($subl)
			foreach peercn $peers {
				puts $prefix\t$cmd\tpeercn\t($peercn)
			}
		}

		foreach item $subl {
			if {$debug} { puts $prefix\t$cmd\tat\t$item }

			set iteml [split $item "="]
			if {[lindex $iteml 0]=="CN"} {
				if {$debug} { puts $prefix\t$cmd\tCN }

				set certcn   [lindex $iteml 1]
				set certhost [lindex [split $certcn "."] 0]

				if {$debug} {
					puts $prefix\t$cmd\tcertcn\t($certcn)
				}
				if {![Match $peers $certcn]} {
                    set acode 0
                    set amsg  "CN '$certcn' does not match any of '[join $peers "', '"]'"
				}
			}
		}
    }

	if {$debug} {
		puts $prefix\t$cmd\tfinal\t$acode
		puts $prefix\t$cmd\tfinmsg\t$amsg
		puts $prefix\t$cmd\t___done
	}

	# In client v3.x simply report issue.
	if {!$acode} {
		puts [cmdr color warning "SSL warning for \"$host\": $amsg"]
	}
	# In client v4.x actually abort and throw error.
	#if {$debug} { puts "$prefix\t$cmd\treturn $rc" }
    #return $rc
	#  and amsg will be used in method "Invoke" above.

    # By always accepting, even if rc is not 1, the responsibility for
    # determining the action to take goes to the application
    # connection handler.
	if {$debug} { puts "$prefix\t$cmd\treturn 1" }
    return 1
}

proc ::REST::Match {peers certcn} {
	variable debug
	if {$debug} {
		upvar 1 prefix prefix cmd cmd
	}

	if {[string match "*\\**" $certcn]} {
		if {$debug} { puts $prefix\t$cmd\twild\t$certcn }

		foreach peercn $peers {
			if {$debug} { puts $prefix\t$cmd\ttrial\t$peercn }

			if {![string match $certcn $peercn]} continue

			if {$debug} { puts $prefix\t$cmd\tmatch }
			return 1
		}
	} else {
		if {$debug} { puts $prefix\t$cmd\texact\t$certcn }

		foreach peercn $peers {
			if {$debug} { puts $prefix\t$cmd\ttrial\t$peercn }

			if {$certcn ne $peercn} continue

			if {$debug} { puts $prefix\t$cmd\tmatch }
			return 1
		}
	}

	return 0
}

proc ::REST::Peers {chan} {
	lappend peers [LogicalPeer]
	lappend peers [PhysicalPeer $chan]
	return $peers
}

proc ::REST::LogicalPeer {} {
	# Logical peer host, based on the target url.
	variable host
	return [url domain $host]
}

proc ::REST::PhysicalPeer {chan} {
	# Physical peer host, straight out of the socket data

	set peerinfo [fconfigure $chan -peername]
	set peercn   [lindex $peerinfo 1]
	set peerhost [lindex [split $peercn "."] 0]

	# on some networks -peername host will only be the hostname, not
	# the full CN.  whether it is the "right" thing to do to accept
	# these connections is left as an exercise for the reader.  I
	# decided to allow it here.  But then, I'm doing this on an
	# intranet.  I doubt I'd allow it in the wild.

	if {$peercn == $peerhost} {
		# need full cn
		set mycn      [lindex [fconfigure $chan -sockname] 1]
		set mydomainl [lrange [split $mycn "."] 1 end]
		set peercnl   [concat $peercn $mydomainl]
		set peercn    [join $peercnl "."]
	}

	return [string trim $peercn]
}

# # ## ### ##### ######## ############# #####################
## 0 --> 1 to debug Tcl errors within the callback

if {1} {
	rename ::REST::verify ::REST::verify_core
	proc ::REST::verify {args} {
		try {
			verify_core {*}$args
		} on error {e o} {
			puts $e
			error $e
		}
	}
}

# # ## ### ##### ######## ############# #####################

# Local Variables:
# mode: tcl
# tab-width: 4
# End:
