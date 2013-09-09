# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################
## Tunneling. Http Tunnels. Created only indirectly through
## the 'tunnel' package. Do not create directly.

package require Tcl 8.5
package require TclOO
package require ooutil
package require stackato::jmap
package require http

# # ## ### ##### ######## ############# #####################

namespace eval ::tunnel::http {
    variable maxtries 10
}

oo::class create ::tunnel::http {
    # - -- --- ----- -------- -------------
    constructor {args} {
	#puts stderr "[self]    HTTP born"

	dict with args {} ; # Unpack dictionary into the
	# local scope, leaves the local variables behind.
	# - tun_url
	# - dst_host
	# - dst_port
	# - auth_token
	# - onreceive
	# - onclose
	# - onopen

	#puts stderr "[self]    HTTP config tunnel $tun_url"
	#puts stderr "[self]    HTTP config d-host $dst_host"
	#puts stderr "[self]    HTTP config d-port $dst_port"
	#puts stderr "[self]    HTTP config auth   $auth_token"

	set myauth    $auth_token
	set myclosing  0
	set myclosed   0
	set mytries    0
	set myopened   0
	set mytunuri   {}
	set myreader   {}
	set mywriter   {}

	set myopen    $onopen
	set myclose   $onclose
	set myreceive $onreceive

	set initmsg [stackato::jmap map \
			 dict [dict create host $dst_host port $dst_port]]

	my start $tun_url $initmsg
	return
    }

    destructor {
	#puts stderr "[self]    HTTP dies"
	my close
	#puts stderr "[self]    HTTP gone"
	return
    }

    method close {} {
	#puts stderr "[self]    HTTP close ($myclosed|$myclosing)"

	if {$myclosed || $myclosing} return
	set myclosing 1
	#puts stderr "[self]    HTTP closing"

	if {$mywriter ne {}} { $mywriter destroy }
	if {$myreader ne {}} { $myreader destroy }

	my stop
	return
    }

    method send {data} {
	$mywriter send $data
	return
    }

    # - -- --- ----- -------- -------------
    # Create a new tunnel/connection.
    # Runs 'myopen' when everything is set up,
    # including read and write controllers.

    method start {base initmsg} {
	#puts stderr "[self]    HTTP start $mytries ($base $initmsg)"

	incr mytries
	if {$mytries > $tunnel::http::maxtries} {
	    #puts stderr "[self]    HTTP start fail too often"
	    my trigger-close
	    return
	}

	set uri $base/tunnels

	if {[catch {
	    #puts stderr "[self]    HTTP start $uri"

	    http::geturl $uri \
		-command [callback DoneStart $base $initmsg] \
		-method POST \
		-headers [list Auth-Token $myauth] \
		-query $initmsg
	} msg]} {
	    # Retry after immediate failure.
	    #puts stderr "[self]    HTTP start failure: $msg"

	    after idle [callback start $base $initmsg]
	}
	return
    }

    method DoneStart {base initmsg token} {
	set code [http::ncode $token]
	#puts stderr "[self]    HTTP DoneStart $token $code"

	if {$code ni {200 201 204}} {
	    #puts stderr "[self]    HTTP start failure, retry"

	    # Failed, try again.
	    http::cleanup $token
	    my start $base $initmsg
	    return
	}

	# 'Connection' established. The json response gives us the
	# urls to use for reading and writing data from and to the
	# 'socket'.

	set mytries 0 ; # Reset for stop.
	set response [json::json2dict [http::data $token]]
	http::cleanup $token

	set mytunuri $base[dict get $response path]
	set pathout  $base[dict get $response path_out]
	set pathin   $base[dict get $response path_in]

	#puts stderr "[self]    HTTP start connected: $mytunuri"
	#puts stderr "[self]    HTTP start connected: $pathout"
	#puts stderr "[self]    HTTP start connected: $pathin"

	set myreader [tunnel::http::Reader new $pathout [self] $myauth]
	set mywriter [tunnel::http::Writer new $pathin  [self] $myauth]

	my trigger-open
	return
    }

    # - -- --- ----- -------- -------------
    # Main method for closing the tunnel/connection.
    # Invokes 'myclose' when done.

    method stop {} {
	#puts stderr "[self]    HTTP stop $mytries"

	incr mytries
	if {$mytries > $tunnel::http::maxtries} {
	    #puts stderr "[self]    HTTP stop fail too often"
	    my trigger-close
	    return
	}

	if {$mytunuri eq {}} return

	if {[catch {
	    #puts stderr "[self]    HTTP delete $mytunuri"

	    http::geturl $mytunuri \
		-command [callback DoneStop] \
		-method DELETE \
		-headers [list Auth-Token $myauth]
	} msg]} {
	    # Retry after immediate failure.
	    #puts stderr "[self]    HTTP stop failure: $msg"

	    after idle [callback stop]
	}
	return
    }

    method DoneStop {token} {
	set code [http::ncode $token]
	#puts stderr "[self]    HTTP DoneStop $token $code"

	http::cleanup $token

	if {$code ni {200 202 204 404}} {
	    #puts stderr "[self]    HTTP stop failure, retry"

	    # Failed, try again.
	    my stop
	    return
	}

	#puts stderr "[self]    HTTP stop - close"
	my trigger-close
	[self] destroy
	return
    }

    # - -- --- ----- -------- -------------
    # Methods to run the various callbacks.

    method trigger-open {} {
	#puts stderr "[self]    HTTP trigger-open"

	set myopened 1
	if {$myopen eq {}} return
	try {
	    uplevel \#0 $myopen
	} on error {e o} {
	    #puts stderr "[self]    HTTP trigger-open FAIL $o"
	    return {*}$o $e
	}
	return
    }

    method trigger-close {} {
	#puts stderr "[self]    HTTP trigger-close"

	my close
	set myclosed 1
	if {$myclose eq {}} return
	try {
	    uplevel \#0 $myclose
	} on error {e o} {
	    #puts stderr "[self]    HTTP trigger-close FAIL $o"
	    return {*}$o $e
	}
	set myclose {}
	return
    }

    method trigger-receive {data} {
	#puts stderr "[self]    HTTP trigger-receive [string length $data]"

	try {
	    uplevel \#0 [list {*}$myreceive $data]
	} on error {e o} {
	    #puts stderr "[self]    HTTP trigger-receive FAIL $o"
	    return {*}$o $e
	}
	return
    }

    # - -- --- ----- -------- -------------

    variable mytunuri myauth myclosing myclosed mytries myopened \
	myopen myreceive myclose myreader mywriter

    # - -- --- ----- -------- -------------
}

# # ## ### ##### ######## ############# #####################

oo::class create ::tunnel::http::Reader {
    constructor {url conn auth_token} {
	#puts stderr "[self]    HTTP READ born $url $conn $auth_token"

	set mybase   $url
	set myconn   $conn
	set myauth   $auth_token
	set mytries  0
	set myclosed 0
	set mytoken  {}

	# Start the read cycle.
	my get
	return
    }

    destructor {
	#puts stderr "[self]    HTTP READ dies"
	my close
	#puts stderr "[self]    HTTP READ gone"
	return
    }

    method close {} {
	#puts stderr "[self]    HTTP READ close ($myclosed)"
	set myclosed 1

	if {$mytoken eq {}} return

	http::reset   $mytoken
	http::cleanup $mytoken
	return
    }

    method get {{seq 1}} {
	#puts stderr "[self]    HTTP READ get\#$seq &$mytries c$myclosed"

	if {$myclosed} return

	incr mytries
	if {$mytries > $tunnel::http::maxtries} {
	    #puts stderr "[self]    HTTP READ get fail too often"
	    $myconn trigger-close
	    # The above eventually destroys this object.
	    return
	}

	if {[catch {
	    #puts stderr "[self]    HTTP READ get $mybase/$seq"

	    set mytoken [http::geturl $mybase/$seq \
			     -command [callback DoneGet $seq] \
			     -binary 1 -method GET \
			     -headers [list Auth-Token $myauth]]
	} msg]} {
	    # Retry after immediate failure.
	    #puts stderr "[self]    HTTP READ get failure: $msg"

	    after idle [callback get $seq]
	}
	return
    }

    method DoneGet {seq token} {
	set code [http::ncode $token]
	#puts stderr "[self]    HTTP READ DoneGet $token $code c$myclosed"

	# Ignore callbacks while in destruction, or gone.
	if {$myclosed} return

	set mytoken {}

	switch -exact -- $code {
	    200 {
		set data [http::data $token]
		http::cleanup $token

		#puts stderr "[self]    HTTP READ push [string length $data]"

		# Push retrieved data
		$myconn trigger-receive $data

		# And start next round
		set mytries 0
		incr seq
		my get $seq
	    }
	    404 {
		# EOF, close connection.
		#puts stderr "[self]    HTTP READ get eof"

		http::cleanup $token
		$myconn trigger-close
		# Eventually destroys this object.
	    }
	    default {
		# Restart failed attempt at reading.
		#puts stderr "[self]    HTTP READ restart"

		http::cleanup $token
		my get $seq
	    }
	}
	return
    }

    # - -- --- ----- -------- -------------

    variable myclosed myconn mybase myauth mytries mytoken

    # - -- --- ----- -------- -------------
}

# # ## ### ##### ######## ############# #####################

oo::class create ::tunnel::http::Writer {

    constructor {url conn auth_token} {
	#puts stderr "[self]    HTTP WRITE born $url $conn $auth_token"

	set mybase    $url
	set myconn    $conn
	set myauth    $auth_token
	set mytries   0
	set myclosed  0
	set mywriting 0
	set myseq     1
	set mybuffer  {}
	set mytoken   {}
	return
    }

    destructor {
	#puts stderr "[self]    HTTP WRITE dies"
	my close
	#puts stderr "[self]    HTTP WRITE gone"
	return
    }

    method send {data} {
	#puts stderr "[self]    HTTP WRITE send [string length $data]"
	# Avoid empty writes, and during destruction.
	if {$myclosed} return
	if {![string length $data]} return
	append mybuffer $data
	my send-buffer
	return
    }

    method close {} {
	#puts stderr "[self]    HTTP WRITE close ($myclosed)"
	set myclosed 1

	if {$mytoken eq {}} return

	http::reset   $mytoken
	http::cleanup $mytoken
	return
    }

    method send-buffer {} {
	#puts stderr "[self]    HTTP WRITE send-buffer\#$myseq &$mytries c$myclosed"

	if {$myclosed} return
	if {$mywriting} return

	# Send failed too often ? Close whole connection.
	incr mytries
	if {$mytries > $tunnel::http::maxtries} {
	    #puts stderr "[self]    HTTP WRITE send-buffer fail too often"
	    $myconn trigger-close
	    return
	}

	set data $mybuffer
	set mybuffer ""
	set mywriting 1

	if {[catch {
	    #puts stderr "[self]    HTTP WRITE put $mybase/$myseq"

	    set mytoken [http::geturl $mybase/$myseq \
			     -command [callback DoneSend $data] \
			     -binary 1 -method PUT \
			     -headers [list Auth-Token $myauth] \
			     -query $data]
	} msg]} {
	    # Retry after immediate failure.
	    #puts stderr "[self]    HTTP WRITE put failure: $msg"

	    set mywriting 0
	    after idle [callback send-buffer]
	}
	return
    }

    method DoneSend {data token} {
	set code [http::ncode $token]
	#puts stderr "[self]    HTTP WRITE DoneSend $token $code c$myclosed"

	# Ignore callbacks while in destruction, or gone.
	if {$myclosed} return

	set mytoken {}
	http::cleanup $token

	switch -exact -- $code {
	    200 - 202 - 204 {
		#puts stderr "[self]    HTTP WRITE written"

		incr myseq
		set mytries   0
		set mywriting 0

		if {$mybuffer ne {}} {
		    my send-buffer
		}
	    }
	    404 {
		# EOF, close connection
		#puts stderr "[self]    HTTP WRITE send eof"

		$myconn trigger-close
		# Eventually destroys this object.
	    }
	    default {
		# Restart failed attempt at writing
		#puts stderr "[self]    HTTP WRITE restart"

		# Keep sequence number, and do not reset trial count,
		# but push the unwritten data back to the buffer.
		set mybuffer $data$mybuffer
		set mywriting 0

		if {$mybuffer ne {}} {
		    my send-buffer
		}
	    }
	}
	return
    }

    # - -- --- ----- -------- -------------

    variable myclosed myconn mybase myauth mytries mybuffer mywriting myseq mytoken

    # - -- --- ----- -------- -------------
}

# # ## ### ##### ######## ############# #####################
package provide tunnel::http 0
