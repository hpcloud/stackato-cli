# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require try            ;# I want try/catch/finally
package require TclOO
package require stackato::const
package require stackato::color
package require stackato::client::cli::config
package require lambda
package require restclient
package require tls          ; # SSL support (https)
package require stackato::form
package require stackato::log
package require dictutil
package require ooutil
package require stackato::jmap
package require struct::list
package require ncgi
package require debug

package require autoproxy 1.5.3 ; # Contains the https fixes.
http::register https 443 autoproxy::tls_socket ; # proxy aware TLS/SSL.

debug level  client
debug prefix client {}
Debug.client {[package ifneeded autoproxy [package require autoproxy]]}
debug prefix client {[::debug::snit::call] | }

namespace eval ::stackato::client {}

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::client {
    superclass ::REST
    # # ## ### ##### ######## #############

    constructor {{target_url {}} {auth_token {}}} {
	Debug.client {}

	if {$target_url eq {}} {
	    set target_url $stackato::const::DEFAULT_TARGET
	}

	set myclientinfo {}
	set myhost {}
	set myuser {}
	set myproxy {}
	set mytrace 0
	set myprogress 0

	# Namespace import, sort of.
	namespace path [linsert [namespace path] end \
			    ::stackato ::stackato::client::cli ::stackato::log]

	set myauth_token $auth_token
	set mytarget     [config urlcanon $target_url]

	set myheaders {}
	if {$myauth_token ne {}} {
	    lappend myheaders AUTHORIZATION $myauth_token
	}

	proc ::http::Log {args} {}
	proc ::http::Log {args} { return
	    set prefix "[::stackato::color cyan HTTP:] "
	    set text $prefix[join [split [join $args] \n] "\n$prefix"]
	    ::stackato::log say $text
	}

	# Initialize the integrated REST client. Late initialization
	# of the proxy-settings.

	if {
	    [string match https://* $mytarget] &&
	    [info exists ::env(https_proxy)]
	} {
	    set nop {}
	    catch { set nop $::env(no_proxy) }
	    autoproxy::init $::env(https_proxy) $nop
	} else {
	    autoproxy::init
	}
	next $mytarget \
	    -progress [callback Upload] \
	    -blocksize 1024 \
	    -headers $myheaders

	# NOTE: IN create_app's http_post the server does a redirect
	# we must not follow. It is unclear if other commands rely on
	# us following a redirection.  -follow-redirections 1
    }

    destructor {
	Debug.client {}
    }

    # # ## ### ##### ######## #############
    ## API

    method version {} {
	Debug.client { = [package present stackato::client]}
	return [package present stackato::client]
    }

    ######################################################
    # Target info
    ######################################################

    # Retrieves information on the target cloud, and optionally the logged in user
    method info {} {
	Debug.client {}
	# TODO: Should merge for new version IMO, general, services, user_account

	if {$myclientinfo ne {}} { return $myclientinfo }
	set myclientinfo [my json_get $stackato::const::INFO_PATH]

	return $myclientinfo
    }


    method info_reset {} {
	Debug.client {}
	set myclientinfo {}
	return
    }

    method raw_info {} {
	Debug.client {}
	return [my http_get $stackato::const::INFO_PATH]
    }

    # Global listing of services that are available on the target system
    method services_info {} {
	Debug.client {}
	my check_login_status
	# @todo - cache retrieved result ?
	set si [my json_get $stackato::const::GLOBAL_SERVICES_PATH]
	#puts |$si|
	return $si
    }

    method logs {name n} {
	Debug.client {}
	my check_login_status

	set url $stackato::const::APPS_PATH/[ncgi::encode $name]/stackato_logs?num=$n
	return [lindex [my http_get $url] 1]
    }

    method report {} {
	Debug.client {}
	my check_login_status

	return [lindex [my http_get $stackato::const::STACKATO_PATH/report] 1]
    }

    method usage {all userOrGroup} {
	Debug.client {}
	my check_login_status

	set url $stackato::const::STACKATO_PATH/usage
	set sep ?
	if {$all} {
	    append url ${sep}all=1
	    set sep &
	}
	if {$userOrGroup ne {}} {
	    append url ${sep}group=[ncgi::encode $userOrGroup]
	    set sep &
	}

        return [my json_get $url]
    }

    ######################################################
    # Apps
    ######################################################

    method apps {} {
	Debug.client {}
	my check_login_status
	return [my json_get $stackato::const::APPS_PATH]
    }

    method create_app {name {manifest {}}} {
	Debug.client {}
	#@type manifest = ?? /@todo
	# @todo - callers - manifest structure.

	my check_login_status

	dict set manifest name $name
	#checker -scope line exclude badOption
	if {[dict get' $manifest instances {}] eq {}} {
	    dict set manifest instances 1
	}

	try {
	    my http_post \
		$stackato::const::APPS_PATH \
		[jmap manifest $manifest] \
		application/json

	    # We ignore the redirection the server is sending is us in
	    # its response.
	} trap {REST REDIRECT} {e o} {}
	return
    }

    method update_app {name manifest} {
	Debug.client {}
	#@type manifest = ?? /@todo
	# @todo - callers - manifest structure.

	#puts |$manifest|

	my check_login_status

	my http_put \
	    $stackato::const::APPS_PATH/[ncgi::encode $name] \
	    [jmap manifest $manifest] \
	    application/json
	return
    }

    method upload_app {name zipfile {resource_manifest {}}} {
	Debug.client {}
	#@type zipfile = path

	#FIXME, manifest should be allowed to be null, here for compatability with old cc's
	#resource_manifest ||= []
	my check_login_status

	set resources [jmap resources $resource_manifest]

	set dst $stackato::const::APPS_PATH/[ncgi::encode $name]/application

	# Without a zipfile we have to provide the relevant form
	# fields (resources, _method) x-www-form-url-encoded.

	set tries 10

	if {$zipfile eq {}} {
	    set query [http::formatQuery \
			   resources $resources \
			   _method   put]

	    set myprogress 1
	    while {$tries} {
		incr tries -1
		try {
		    my http_post $dst $query application/x-www-form-urlencoded
		}  \
		    trap {REST HTTP REFUSED} {e o} - \
		    trap {REST HTTP BROKEN} {e o} {
			if {!$tries} { return {*}$o $e }
			say! [color red "$e"]
			say "Retrying in a second... (trials left: $tries)"
			continue
		    }
		break
	    }
	    set myprogress 0
	    return
	}

	# When a zipfile is present however the upload has to use
	# multipart/form-data to convey the form.

	form start   data
	form field   data _method put
	form field   data resources $resources
	form zipfile data application $zipfile

	lassign [form compose data] contenttype data dlength

	if {0} {
	    # Debugging ... Stream to temp file for review, and stream
	    # upload from the same file because the cat and subordinates
	    # are destroyed by the fcopy.
	    set c [open UPLOAD_FORM w]
	    fconfigure $c -translation binary
	    fcopy $data $c
	    close $data
	    close $c
	    set data [open UPLOAD_FORM r]
	    fconfigure $data -translation binary

	    set dlength [file size UPLOAD_FORM]
	}

	Debug.client {$contenttype | $dlength := $data}

	# Provide rest/http with the content-length information for
	# the non-seekable channel
	dict set myheaders content-length $dlength
	my configure -headers $myheaders

	set myprogress 1
	while {$tries} {
	    incr tries -1
	    try {
		my http_post $dst $data $contenttype
	    } \
		trap {REST HTTP REFUSED} {e o} - \
		trap {REST HTTP BROKEN} {e o} {
		    if {!$tries} { return {*}$o $e }

		    say! \n[color red "$e"]
		    say "Retrying in a second... (trials left: $tries)"
		    after 1000
		    continue
		}
	    break
	}

	dict unset myheaders content-length
	my configure -headers $myheaders

	set myprogress 0
	return
    }

    method delete_app {name} {
	Debug.client {}
	my check_login_status
	my http_delete $stackato::const::APPS_PATH/[ncgi::encode $name]
	return
    }

    method app_info {name} {
	Debug.client {}
	my check_login_status
	return [my json_get $stackato::const::APPS_PATH/[ncgi::encode $name]]
    }

    method app_update_info {name} {
	Debug.client {}
	my check_login_status
	return [my json_get $stackato::const::APPS_PATH/[ncgi::encode $name]/update]
    }

    method app_stats {name} {
	Debug.client {}
	my check_login_status
	set stats_raw [my json_get \
			   $stackato::const::APPS_PATH/[ncgi::encode $name]/stats]

	set stats {} ;# []array
	foreach {k entry} $stats_raw {
	    # entry = []hash
	    # Skip entries with no stats
	    if {![dict exists $entry stats]} continue
	    dict set entry instance $k;# to_s.to_i - can fail, assignment doesn't.
	    # :state to_sym - irrelevant.
	    lappend stats [list $k $entry]
	}

	# Sort by 'instance', then strip this key.
	return [struct::list map [lsort -index 0 $stats] [lambda x {
	    lindex $x 1
	}]]
    }

    method app_instances {name} {
	Debug.client {}
	my check_login_status
	return [my json_get $stackato::const::APPS_PATH/[ncgi::encode $name]/instances]
    }

    method app_crashes {name} {
	Debug.client {}
	my check_login_status
	return [my json_get  $stackato::const::APPS_PATH/[ncgi::encode $name]/crashes]
    }

    # List the directory or download the actual file indicated by the
    # path.
    method app_files {name path {instance 0}} {
	Debug.client {}
	my check_login_status

	set url "$stackato::const::APPS_PATH/[ncgi::encode $name]/instances/$instance/files/[ncgi::encode $path]"
	set url [string map {// /} $url]
	return [lindex [my http_get $url] 1]
    }

    method app_run {name cmd instance {timeout {}}} {
	Debug.client {}
	my check_login_status
	set cmd [ncgi::encode $cmd]
	if {$timeout ne {}} {
	    append cmd ?timeout=$timeout
	}
	set url "$stackato::const::APPS_PATH/[ncgi::encode $name]/instances/$instance/run/$cmd"
	return [lindex [my http_get $url] 1]
    }


    ######################################################
    # Services
    ######################################################

    # listing of services that are available in the system
    method services {} {
	my check_login_status
	return [my json_get $stackato::const::SERVICES_PATH]
    }

    method create_service {service name} {
	my check_login_status

	set services [my services_info]
	#services ||= []
	set service_hash {};#nil
	#service = service.to_s

	# FIXME!
	foreach {service_type value} $services {
	    foreach {vendor version} $value {
		foreach {version_str service_descr} $version {
		    if {$service ne [dict get $service_descr vendor]} continue
		    set service_hash [dict create \
					  type    [dict get $service_descr type] \
					  tier    free \
					  vendor  $service \
					  version $version_str]
		    break
		}
	    }
	}

	if {$service_hash eq {}} { my ServiceCreationError $service }

	dict set service_hash name $name
	#@type service = dict */string

	try {
	    my http_post \
		$stackato::const::SERVICES_PATH \
		[jmap service $service_hash] \
		application/json

	    # We ignore the redirection the server is sending is us in
	    # its response.
	} trap {REST REDIRECT} {e o} {}
	return
    }

    method delete_service {name} {
	my check_login_status
	set svcs [my services];# || []

	set names [struct::list map $svcs [lambda x {
	    dict get $x name
	}]]

	if {$name ni $names} { my ServiceError $name }

	my http_delete $stackato::const::SERVICES_PATH/[ncgi::encode $name]
	return
    }

    method bind_service {service appname} {
	my check_login_status
	set app [my app_info $appname]

	dict lappend app services $service

	my update_app $appname $app
	return
    }

    method unbind_service {service appname} {
	my check_login_status
	set app [my app_info $appname]
	set services [dict get' $app services {}]

	struct::list delete services $service
	dict set app services $services

	my update_app $appname $app
	return
    }

    ######################################################
    # Resources
    ######################################################

    # Send in a resources manifest array to the system to have
    # it check what is needed to actually send. Returns array
    # indicating what is needed. This returned manifest should be
    # sent in with the upload if resources were removed.
    # E.g. [{:sha1 => xxx, :size => xxx, :fn => filename}]

    method check_resources {resources} {
	#@type resources = list (dict (size, sha1, fn| */string))

	my check_login_status

	set data [lindex \
		      [my http_post \
			   $stackato::const::RESOURCES_PATH \
			   [jmap resources $resources] \
			   application/json] \
		      1]

	try {
	    set response [json::json2dict $data]
	} on error {e o} {
	    return -code error -errorcode {STACKATO SERVER DATA ERROR} \
		"Received invalid JSON from server; Error: $e"
	}

	return $response
    }

    ######################################################
    # User login/password
    ######################################################

    # login and return an auth_token
    # Auth token can be retained and used in creating
    # new clients, avoiding login.
    method login {user password} {
	Debug.client {}

	# Password empty => Admin user. Not transmitting such a password.
	# See c_user.tcl [bug 93843] for the code causing the implication.

	# Bug 90337 :: Review on next CF integration.
	# See also lib/rest/rest.tcl, and bug 90034.

	# Here we are accepting 502 Bad Gateway as error.  And have to
	# specifically check for it, as REST was modified to return
	# the error code 5xx as regular responses instead of actual
	# errors thrown. Note that the payload for 502 is not JSON, so
	# not throwing it as error will simply cause a json parsing
	# error immediately after, by json2dict, which likely will
	# confuse users.

	set uinfo {}
	dict set uinfo ssh_privkey 1
	if {$password ne {}} {
	    dict set uinfo password $password
	}

	lassign [my http_post \
		     $stackato::const::USERS_PATH/[ncgi::encode $user]/tokens \
		     [jmap map dict $uinfo] \
		     application/json] \
	    code data _

	if {$code == 502} {
	    return -code error \
		-errorcode [list REST HTTP $code] \
		$data
	}

	try {
	    set response_info [json::json2dict $data]
	} on error {e o} {
	    return -code error -errorcode {STACKATO SERVER DATA ERROR} \
		"Received invalid JSON from server; Error: $e"
	}
	#@type response_info = dict ("token" -> string)
	#puts |$response_info|

	Debug.client {ri = ($response_info)}

	if {$response_info ne {}} {
	    set myuser       $user
	    set myauth_token [dict get $response_info token]

	    Debug.client {token = ($myauth_token)}

	    if {[dict exists $response_info sshkey]} {
		set sshkey [dict get $response_info sshkey]

		Debug.client {sshkey = ($sshkey)}

		return [list $myauth_token $sshkey]
	    }
	}
	return [list $myauth_token]
    }

    # sets the password for the current logged user
    method change_password {new_password} {
	my check_login_status
	set user_info [my json_get $stackato::const::USERS_PATH/[ncgi::encode $myuser]]
	if {$user_info ne {}} {
	    dict set user_info password $new_password
	    my http_put \
		$stackato::const::USERS_PATH/[ncgi::encode $myuser] \
		[jmap user1 $user_info] \
		application/json
	}
	return
    }

    # gets all server side information about a specific user.
    method user_info {user} {
	my check_login_status
	return [my json_get $stackato::const::USERS_PATH/[ncgi::encode $user]]
    }

    ######################################################
    # Groups
    ######################################################

    method add_group {groupname} {
	my http_post \
	    $stackato::const::GROUPS_PATH \
	    [jmap map dict \
		 [dict create name $groupname]] \
	    application/json
	return
    }

    method delete_group {groupname} {
	my check_login_status
	my http_delete $stackato::const::GROUPS_PATH/[ncgi::encode $groupname]
	return
    }

    method groups {} {
	my check_login_status
	return [my json_get $stackato::const::GROUPS_PATH]
    }

    method group_add_user {groupname email} {
	my check_login_status
	my http_post \
	    $stackato::const::GROUPS_PATH/[ncgi::encode $groupname]/users \
	    [jmap map dict \
		 [dict create email $email]] \
	    application/json
	return
    }

    method group_remove_user {groupname email} {
	my check_login_status
	my http_delete \
	    $stackato::const::GROUPS_PATH/[ncgi::encode $groupname]/users/[ncgi::encode $email]
	return
    }

    method group_list_users {groupname} {
	my check_login_status
	return [my json_get $stackato::const::GROUPS_PATH/[ncgi::encode $groupname]/users]
    }

    method group_limits_get {groupname} {
	my check_login_status
	return [my json_get $stackato::const::GROUPS_PATH/[ncgi::encode $groupname]/limits]
    }

    method group_limits_set {groupname limits} {
	my check_login_status
	my http_post \
	    $stackato::const::GROUPS_PATH/[ncgi::encode $groupname]/limits \
	    [jmap map dict $limits] \
	    application/json
	return
    }

    ######################################################
    # System administration
    ######################################################

    method proxy=    {proxy} { my proxy_for $proxy }
    method proxy_for {proxy} {
	set myproxy $proxy

	if {$myproxy ne {}} {
	    dict set   myheaders PROXY-USER $myproxy
	} else {
	    dict unset myheaders PROXY-USER
	}

	my configure -headers $myheaders
	return
    }

    method trace {trace} {
	set mytrace $trace
	# Setup tracing if needed
	if {$mytrace ne {}} {
	    dict set myheaders X-VCAP-Trace \
		[expr {$mytrace == 1 ? 22 : $mytrace}]
	    my configure -trace 1
	} else {
	    dict unset myheaders X-VCAP-Trace
	    my configure -trace 0
	}
	my configure -headers $myheaders
	return
    }

    method group {group} {
	Debug.client {$group}

	if {$group ne {}} {
	    dict set   myheaders X-Stackato-Group $group
	} else {
	    dict unset myheaders X-Stackato-Group
	}
	my configure -headers $myheaders
	return
    }

    method users {} {
	my check_login_status
	return [my json_get $stackato::const::USERS_PATH]
    }

    method add_user {user_email password} {
	lassign [my http_post \
		     $stackato::const::USERS_PATH \
		     [jmap map dict \
			  [dict create \
			       email    $user_email \
			       password $password]] \
		     application/json] \
	    code data _

	# Bug 90445 :: Review on next CF integration.
	# See also lib/rest/rest.tcl, bug 90034, 90337.

	if {$code == 502} {
	    return -code error \
		-errorcode [list REST HTTP $code] \
		$data
	}

	return
    }

    method delete_user {user_email} {
	my check_login_status
	my http_delete $stackato::const::USERS_PATH/[ncgi::encode $user_email]
	return
    }

    ######################################################
    # Validation Helpers
    ######################################################

    # Checks that the target is valid
    method target_valid? {} {
	try {
	    set descr [my info]
	    if {$descr eq {}}          { return 0 }
	    if {![my HAS $descr name]}    { return 0 }
	    if {![my HAS $descr build]}   { return 0 }
	    if {![my HAS $descr version]} { return 0 }
	    if {![my HAS $descr support]} { return 0 }
	    return 1
	} on error {} {
	    #puts TV/$::errorInfo
	    return 0
	}
    }

    # Checks that the auth_token is valid
    method logged_in? {} {
	Debug.client {}
	set descr [my info]
	if {[llength $descr]} {
	    try {
		if {![my HAS $descr user]}  {
		    Debug.client {No. User field missing}
		    return 0
		}
		if {![my HAS $descr usage]} {
		    Debug.client {No. Usage field missing}
		    return 0
		}
	    } on error {e o} {
		my TargetError "Login check choked on bad server response, please check if the server is responsive."
	    }
	    set myuser [dict get $descr user]
	    Debug.client {Yes -> $myuser}
	    return 1
	}
	# result when no info present ?
	Debug.client {No. No information}
	return 0
    }

    # Check if the user is logged in, and admin
    method admin? {} {
	if {![my logged_in?]} { return 0 }
	set ci [my info]
	if {![dict exists $ci admin]} { return 0 }
	return [dict get $ci admin]
    }

    # # ## ### ##### ######## #############
    ## Internal commands.

    method json_get {url} {
	try {
	    set result [my http_get $url application/json]
	} trap {REST REDIRECT} {e o} {
	    return -code error -errorcode {STACKATO CLIENT BAD-RESPONSE} \
		"Can't parse response into JSON [lindex $e 1]"
	}

	try {
	    set response [json::json2dict [lindex $result 1]]
	} on error {e o} {
	    return -code error -errorcode {STACKATO SERVER DATA ERROR} \
		"Received invalid JSON from server; Error: $e"
	}

	return $response

	#rescue JSON::ParserError
	#raise BadResponse, "Can't parse response into JSON", body
    }

    method http_get_raw {url {content_type {}}} {
	# Using lower-level method, prevents system from prefixing our
	# url with the target server. This method allows the callers
	# to access any url they desire.

	my DoRequest GET $url $content_type
    }

    method http_get {path {content_type {}}} {
	my Request GET $path $content_type
    }

    method http_post {path payload {content_type {}}} {
	# payload = channel|literal
	my Request POST $path $content_type $payload
    }

    method http_put {path payload {content_type {}}} {
	# payload = channel|literal
	my Request PUT $path $content_type $payload
    }

    method http_delete {path} {
	my Request DELETE $path
    }

    method Request {method path {content_type {}} {payload {}}} {
	# payload = channel|literal

	# PAYLOAD see update_app, is dict with file channel inside ?
	# How/where is that handled.

	try {
	    if {$content_type ne {}} {
		http::config -accept $content_type
	    } else {
		http::config -accept */*
	    }

	    set result [my DoRequest $method $mytarget$path \
			    $content_type $payload]
	    return $result

	} trap {REST HTTP} {e o} {
	    # e = response body, possibly json
	    # o = dict, -errorcode has status in list, last element.

	    set rstatus [lindex [dict get $o -errorcode] end]
	    set rbody   $e

	    if {[my request_failed $rstatus]} {
		# FIXME, old cc returned 400 on not found for file access
		if {$rstatus in {404 400}} {
		    my NotFound [my PEM $rstatus $rbody]
		} else {
		    my TargetError [my PEM $rstatus $rbody]
		}
	    }

	    # else rethrow
	    return {*}$o $e

	} trap {REST REDIRECT} {e o} {
	    # Rethrow
	    return {*}$o $e

	} trap {POSIX ECONNREFUSED} {e o} {
	    my BadTarget $e

	} on error {e o} {
	    if {
		[string match {*couldn't open socket*} $e]
	    } {
		# XXX Determine the error-code behind the message, so
		# XXX that we can trap it (better than string match).
		my BadTarget $e
	    }

	    my InternalError $e

	    #@todo rescue URI::Error, SocketError => e
	    #raise BadTarget, "Cannot access target (%s)" % [ e.message ]
	}
	return
    }

    method request_failed {status} {
	# Failed for 4xx and 5xx == range 400..599
	return [expr {(400 <= $status) && ($status < 600)}]
    }

    method PEM {status data} {
	try {
	    set parsed [json::json2dict $data]
	    if {($parsed ne {}) &&
		[my HAS $parsed code] &&
		[my HAS $parsed description]} {
		set map {{"} {'}} ;#"
		set desc [string map $map [dict get $parsed description]]
		set errcode [dict get $parsed code]
                if {$errcode == 310} {
                    # staging error is common enough that the user
                    # need not know the http error code behind it.
                    return "$desc"
                } else {
                    return "Error $errcode: $desc"
                }
	    } else {
		return "Error (HTTP $status): $data"
	    }
	} on error e {
	    if {$data eq {}} {
		return "Error ($status): No Response Received"
	    } else {
		#@todo: no trace => truncate
		#return "Error (JSON $status): $e"
		return "Error (JSON $status): $data"
	    }
	}
    }

    method check_login_status {} {
	Debug.client { ($myuser)}
	if {($myuser eq {}) &&
	    ![my logged_in?]} {
	    my AuthError
	}
    }

    method Upload {token total n} {
	if {!$myprogress} return
	# This code assumes that the last say* was the prefix
	# of the upload progress display.

	set p [expr {$n*100/$total}]
	again+ ${p}%

	if {$n >= $total} {
	    display " [color green OK]"
	    clearlast
	    #display ""
	}
	return
    }

    # # ## ### ##### ######## #############

    method HAS {dict key} {
	expr {[dict exists $dict $key] &&
	      ([dict get $dict $key] ne {})}
    }

    method ServiceError {name} {
	Debug.client {}
	my TargetError "Service \[$name\] is not a valid service choice"
    }

    method ServiceCreationError {service} {
	Debug.client {}
	my TargetError "\[$service\] is not a valid service choice"
    }

    method BadTarget {text} {
	Debug.client {}
	return -code error -errorcode {STACKATO CLIENT BADTARGET} \
	    "Cannot access target ($text)"
    }

    method TargetError {msg} {
	Debug.client {}
	return -code error -errorcode {STACKATO CLIENT TARGETERROR} $msg
    }

    method NotFound {msg} {
	Debug.client {}
	return -code error -errorcode {STACKATO CLIENT NOTFOUND} $msg
    }

    method AuthError {} {
	Debug.client {}
	return -code error -errorcode {STACKATO CLIENT AUTHERROR} {}
    }

    method InternalError {e} {
	Debug.client {}
	return -code error -errorcode {STACKATO CLIENT INTERNAL} \
	    [list $e $::errorInfo $::errorCode]
    }

    # # ## ### ##### ######## #############
    ## State

    variable mytarget myhost myuser myproxy myauth_token \
	mytrace STACKATO_HTTP_ERROR_CODES myprogress myheaders \
	myclientinfo

    method target    {} { return $mytarget }
    method authtoken {} { return $myauth_token }
    method proxy     {} { return $myproxy }
    method user      {} { return $myuser }

    # # ## ### ##### ######## #############
}

proc ::stackato::client::AuthError {} {
    Debug.client {::stackato::client::AuthError}
    return -code error -errorcode {STACKATO CLIENT AUTHERROR} \
	{Authentication error}
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::client 0.3.2
