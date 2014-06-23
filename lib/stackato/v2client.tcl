# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Core v2 operations
## - Pagination for list/search/filter
## - Conversion from retrieved json to v2entity instances.
## - Utility commands

## - Knows target
## - Knows user (implicit, actually know auth token)
## - Knows group (stackato)
## - Knows organization/space
##   (CF2 concepts overlapping with Stackato groups).

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require try            ;# I want try/catch/finally
package require TclOO
package require base64
package require json 1.2       ;# requiring many-json2dict
package require stackato::jmap
package require stackato::form2
package require restclient
package require url

# # ## ### ##### ######## ############# #####################
## Pull in the entity support and other foundation code.

package require stackato::v2::app
package require stackato::v2::app_event
package require stackato::v2::app_version
package require stackato::v2::buildpack
package require stackato::v2::domain
package require stackato::v2::organization
package require stackato::v2::quota_definition
package require stackato::v2::route
package require stackato::v2::service
package require stackato::v2::service_auth_token
package require stackato::v2::service_broker
package require stackato::v2::service_binding
package require stackato::v2::service_instance
package require stackato::v2::managed_service_instance
package require stackato::v2::user_provided_service_instance
package require stackato::v2::service_plan
package require stackato::v2::service_plan_visibility
package require stackato::v2::space
package require stackato::v2::stack
package require stackato::v2::user
package require stackato::v2::zone

# # ## ### ##### ######## ############# #####################

debug level  v2/client
debug prefix v2/client {[debug caller] | }

debug level  v2/memory
debug prefix v2/memory {}

namespace eval ::stackato {
    namespace export v2
    namespace ensemble create
}
namespace eval ::stackato::v2 {
    namespace export client
    namespace ensemble create
}
namespace eval ::stackato::v2::client {}

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::v2::client {
    superclass ::REST

    # # ## ### ##### ######## #############
    ## State

    variable mytarget myhost myuser myproxy myauth_token \
	mytrace myprogress myheaders myrefresh_token \
	myclientinfo myorphans

    method target       {} { return $mytarget }
    method authtoken    {} { return $myauth_token }
    method refreshtoken {} { return $myrefresh_token }
    method proxy        {} { return $myproxy }
    method user         {} { return $myuser }

    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {target_url auth_token} {
	debug.v2/client {}
	debug.v2/client {[ploc autoproxy]}

	if {$target_url eq {}} {
	    my TargetError "No target defined"
	}

	#set myclientinfo {}
	set myorphans {}
	set myhost {}
	set myuser {}
	set myproxy {}
	set mytrace 0
	set myprogress 0

	# Namespace import, sort of.
	namespace path [linsert [namespace path] end \
			    ::stackato ::stackato::log]

	set myrefresh_token {}
	set myauth_token $auth_token
	set mytarget     [url canon $target_url]

	set myheaders {}
	if {$myauth_token ne {}} {
	    lappend myheaders AUTHORIZATION $myauth_token

	    # Handle token's with and without 'bearer' prefix.
	    if {![string match {bearer *} $auth_token]} {
		puts "Ignoring CFv1 authorization token for what is now a CFv2 target"
	    } else {
		set auth_token [lindex $auth_token 1]
		my decode_token $auth_token
	    }
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
	debug.v2/client {}
    }

    # # ## ### ##### ######## #############
    ## API

    # # ## ### ##### ######## #############
    ## Versioning. Same methods as the v1 client.
    ## Different answers however.

    method isv2 {} { return yes }

    method api-version {} {
	set v [dict get [my info] version]
	debug.v2/client {==> $v}
	return $v
    }

    method is-stackato {} {
	set r [dict exists [my info] stackato]
	debug.v2/client {==> $r}
	return $r
    }

    method version {} {
	debug.v2/client { = [package present stackato::v2::client]}
	return [package present stackato::v2::client]
    }

    method full-server-version {} {
	debug.client {}
	return [dict get' [my info] vendor_version 0.0]
    }

    method server-version {} {
	debug.client {}
	set v [dict get' [my info] vendor_version 0.0]
	# drop -gXXXX suffix (git revision)
	regsub -- {-g.*$} $v {} v
	# convert a -betaX clause into bX, proper beta syntax for Tcl
	regsub -- {-beta} $v {b} v
	# drop leading 'v', dashes to dots
	set v [string map {v {} - .} $v]
	# done
	debug.client {= $v}
	return $v
    }

    method group? {} {
	# No group for v2.
	return {}
    }

    # # ## ### ##### ######## #############
    ## Target information. Cached. New writer method
    ## required to avoid redundant /info query when switching from v1
    ## client over to v2.

    # Retrieves information on the target cloud, and optionally the
    # logged in user

    method info {} {
	debug.v2/client {}
	variable myclientinfo
	# TODO: Should merge for new version IMO, general, services, user_account

	if {[info exists myclientinfo]} {
	    debug.v2/client {cached ==> $myclientinfo}
	    return $myclientinfo
	}
	set myclientinfo [my json_get /info] ; # TODO: New constants (v2)

	# Keys:
	#   Always:
	#   - allow_debug            : boolean
	#   - authorization_endpoint : url (in string)
	#   - build                  : string (value looks integer)
	#   - description            : string
	#   - name                   : string
	#   - support                : url (in string)
	#   - token_endpoint         : url (in string)
	#   - version                : integer

	#   When logged in, i.e. with proper authorization:
	#   - limits.*    : object
	#   - usage.*     : object
	#   - user        : &user (GUID)

	debug.v2/client {server ==> $myclientinfo}
	return $myclientinfo
    }

    method info= {dict} {
	debug.v2/client {}
	variable myclientinfo $dict
	return
    }

    method info_reset {} {
	debug.v2/client {}
	unset myclientinfo
	return
    }

    method cc-nginx {} {
	return [dict get' [my info] cc_nginx 0]
    }

    # # ## ### ##### ######## #############
    ## Usage information (global, and per space).

    method usage-of {url} {
	debug.v2/client {}
	my json_get $url/usage
    }

    method usage {} {
	debug.v2/client {}
	my json_get /v2/usage
    }

    # # ## ### ##### ######## #############
    ## REST tracing

    method trace? {} {
	return [my cget -trace]
    }

    method trace {trace} {
	set mytrace $trace
	# Setup tracing if needed
	if {$mytrace ne {}} {
	    #dict set myheaders X-VCAP-Trace [expr {$mytrace == 1 ? 22 : $mytrace}]
	    my configure -trace 1
	} else {
	    #dict unset myheaders X-VCAP-Trace
	    my configure -trace 0
	}
	#my configure -headers $myheaders
	return
    }

    # # ## ### ##### ######## #############
    ## Login check based on /info data.

    method logged_in? {} {
	debug.v2/client {}
	set descr [my info]
	if {![llength $descr]} {
	    # No /info, not logged in.
	    debug.v2/client {No. No information}
	    return 0
	}

	# Check existence of relevant information (user, and usage).
	try {
	    if {![my HAS $descr user]}  {
		debug.v2/client {No. User field missing}
		return 0
	    }
	    # In v2 the 'usage' field can be missing even when logged in.
	    if {0&&![my HAS $descr usage]} {
		debug.v2/client {No. Usage field missing}
		return 0
	    }
	} on error {e o} {
	    my TargetError "Login check choked on bad server response, please check if the server is responsive."
	}

	# Cache user for later
	set myuser [dict get $descr user]
	debug.v2/client {Yes -> $myuser}
	return 1
    }

    # Check if the user is logged in, and admin
    method admin? {} {
	# The V2 UAA always requires a password for log in.
	# An admin cannot just supply a name to 'sudo' to
	# somebody else.
	return 0
    }

    method refresh {rtoken} {
	debug.v2/client {}
	# Similar to a login, but with a refresh token as the
	# auth. information.

	set info [my info]

	set    authorizer [dict get $info authorization_endpoint]
	set    uaahost    [lindex [split [url domain $authorizer] /] 0]
	append authorizer /oauth/token

	set query [http::formatQuery       \
		       grant_type    refresh_token \
		       refresh_token $rtoken]

	try {
	    # Custom headers for the authorizer
	    dict set authheaders AUTHORIZATION "Basic Y2Y6"
	    dict set authheaders Accept "application/json;charset=utf-8"

	    my configure -headers $authheaders

	    my HttpTrap {
		# Using raw POST to prevent auto-application of the
		# standard REST baseurl.
		lassign [my DoRequest POST $authorizer \
			     "application/x-www-form-urlencoded;charset=utf-8" \
			     $query] \
		    code data _
	    } "UAA $uaahost"
	} finally {
	    my configure -headers $myheaders
	}

	# The response is a json object (plain dictionary).
	try {
	    set response [json::json2dict $data]
	} on error {e o} {
	    return -code error -errorcode {STACKATO SERVER DATA ERROR} \
		"Received invalid JSON from server; Error: $e"
	}

	debug.v2/client {ri = ($response)}

        # Expected keys:
        # - access_token        base64 encoded token
        # - token_type          "bearer", fixed
        # - expires_in          some sort of timestamp
        # - scope               list of permissions?
        # - jti                 ???
        dict with response {}

	# Currently only using access_token and token_type.

	# Note: Standard v2 API does not provide an ssh key.
	# Only a token. And we have to assemble it.

	debug.v2/client {token/old = ($myauth_token)}

	# Refresh all in-memory copies of the token for any future
	# rest calls, here and in the superclass. See also method
	# 'login' for the same for the first token.

	set myauth_token    "$token_type $access_token"
	dict set myheaders AUTHORIZATION $myauth_token
	my configure -headers $myheaders

	debug.v2/client {token/new = ($myauth_token)}

	my decode_token $access_token

	# Force reload of /info for proper login-check.
	my info_reset

	return $myauth_token
    }

    ######################################################
    # Apps
    ######################################################

    method upload-by-url {url zipfile {resource_manifest {}} {field application}} {
	debug.v2/client {}
	#@type zipfile = path

	#FIXME, manifest should be allowed to be null, here for compatability with old cc's
	#resource_manifest ||= []
	#my check_login_status

	set resources [jmap resources $resource_manifest]

	set dst $url

	# v2 always uses a multipart/form-data payload to upload the
	# application bits, zip file or not. Without zip file the
	# relevant form field is simply not provided. Furthermore, the
	# form field "_method" has been dropped.

	form2 start   data
	form2 field   data resources $resources
	if {$zipfile ne {}} {
	    form2 zipfile data $field $zipfile
	}
	lassign [form2 compose data] contenttype data dlength

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

	debug.v2/client {$contenttype | $dlength := $data}

	# Provide rest/http with the content-length information for
	# the non-seekable channel
	try {
	    dict set myheaders Content-Length $dlength
	    my configure -headers $myheaders

	    set tries 10

	    set myprogress 1
	    while {$tries} {
		incr tries -1
		try {
		    if {[my cc-nginx]} {
			my http_post $dst $data $contenttype
		    } else {
			my http_put $dst $data $contenttype
		    }
		} trap {REST HTTP REFUSED} {e o} - \
		  trap {REST HTTP BROKEN} {e o} {
		      if {!$tries} {
			  return {*}$o $e
		      }

		      say! \n[color red "$e"]
		      say "Retrying in a second... (trials left: $tries)"
		      after 1000
		      continue
		  }
		break
	    }
	} finally {
	    dict unset myheaders Content-Length
	    my configure -headers $myheaders
	    display ""
	    clearlast ;# (**)
	    set myprogress 0
	}
	return
    }

    method upload-by-url-zip {url zipfile} {
	debug.v2/client {}
	#@type zipfile = path

	set dst $url

	# v2 always uses a multipart/form-data payload to upload the
	# application bits, zip file or not. Without zip file the
	# relevant form field is simply not provided. Furthermore, the
	# form field "_method" has been dropped.

	#form2 start   data
	#form2 zipfile data application $zipfile
	#lassign [form2 compose data] contenttype data dlength

	set contenttype application/x-zip
	set dlength [file size $zipfile]
	set data [open $zipfile]
	fconfigure $data -translation binary

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

	debug.v2/client {$contenttype | $dlength := $data}

	# Provide rest/http with the content-length information for
	# the non-seekable channel
	try {
	    dict set myheaders Content-Length $dlength
	    my configure -headers $myheaders

	    set tries 10

	    set myprogress 1
	    while {$tries} {
		incr tries -1
		try {
		    if {[my cc-nginx]} {
			my http_post $dst $data $contenttype
		    } else {
			my http_put $dst $data $contenttype
		    }
		} trap {REST HTTP REFUSED} {e o} - \
		  trap {REST HTTP BROKEN} {e o} {
		      if {!$tries} {
			  return {*}$o $e
		      }

		      say! \n[color red "$e"]
		      say "Retrying in a second... (trials left: $tries)"
		      after 1000
		      continue
		  }
		break
	    }
	} finally {
	    dict unset myheaders Content-Length
	    my configure -headers $myheaders
	    display ""
	    clearlast ;# (**)
	    set myprogress 0
	}
	return
    }

    method Upload {token total n} {
	if {!$myprogress} return
	# This code assumes that the last say* was the prefix
	# of the upload progress display.

	set p [expr {$n*100/$total}]
	again+ ${p}%

	if {$n >= $total} {
	    display " [color green OK]" false
	    #clearlast - see (**) upload-by-url/finally
	    #display ""
	}
	return
    }

    ######################################################
    # Resources
    ######################################################

    method get_ssh_key {} {
	# TODO: Set the correct url for ssh key retrieval under CFv2 / stackato v3 here.
	return [my json_get /v2/stackato/ssh_key]
    }

    # Send in a resources manifest array to the system to have
    # it check what is needed to actually send. Returns array
    # indicating what is needed. This returned manifest should be
    # sent in with the upload if resources were removed.
    # E.g. [{:sha1 => xxx, :size => xxx, :fn => filename}]

    method check_resources {resources} {
	#@type resources = list (dict (size, sha1, fn| */string))

	# Operations coming before should have checked login status already.
	#my check_login_status

	set data [lindex \
		      [my http_put \
			   /v2/resource_match \
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

    # # ## ### ##### ######## #############

    method decode_token {token} {
	debug.v2/client {}
	debug.v2/client {[ploc json]}
	debug.v2/client {[ploc base64]}

	variable mytdata
	# Decode the token and remember the hidden information.

	# Token specification:
 	#   JSON Web Token
	#   http://tools.ietf.org/html/draft-ietf-oauth-json-web-token-11

	# Note: The token contains non-base64 characters in various
	# places.
	#
	# The dot (".") character is used as separator for the parts
	# of the token, with each part encoded separately.
	#
	# The dash ("-") and underscore ("_") characters are used as
	# encodings for "+" and "/". This is the base64url encoding.
	# See http://tools.ietf.org/html/rfc4648#section-5

	set parts [split $token .]
	# We can expect 3 parts, two json, and a trailing binary
	# piece. The last is the hash of the first two. We need only
	# the data in the second part.

	set part [lindex $parts 1]
	set part [string map {- + _ /} $part]

	set pad [expr {[string length $token] % 4}]
	if {$pad} {
	    append part [string repeat = [expr {4-$pad}]]
	}

	set text [base64::decode $part]
	debug.v2/client {hidden text ($text)}

	set parsed [json::json2dict $text]

	debug.v2/client {formatted = [stackato jmap map dict $parsed]}

	set mytdata $parsed
	return

        # Keys:
        # (1) alg        RS256  meaning unknown
        #
        # (2) aud        list of something
        #     cid        "cf"
        #     client_id  "cf"
        #     email      user email
        #     exp        token expiration, seconds since epoch
        #     grant_type password
        #     iat        token generation, seconds since epoch
        #     iss        token generation url
        #   * jti        ???
        #   * scope      list of permissions?
        #     sub        == user_id, otherwise unknown
        #   x user_id    uuid, type user
        #     user_name  name of the user, also see 'email'
        #
        # (Ad *) Seems to be the same as in the outer auth response.
        # (Ad x) Same as 'user' reported by /info
    }

    method current_user {} {
	debug.v2/client {}
	# Expects decoded token data
	variable mytdata
	if {![info exists mytdata]} { return N/A }
	return [dict get' $mytdata user_name [dict get' $mytdata user_id N/A]]
    }

    method current_user_mail {} {
	debug.v2/client {}
	# Expects decoded token data
	variable mytdata
	if {![info exists mytdata]} { return N/A }
	return [dict get' $mytdata email [dict get' $mytdata user_id N/A]]
    }

    # # ## ### ##### ######## #############
    ## Perform login by name and password

    method login {user password} {
	debug.v2/client {}
	# Standard fields. Standard result: token+sshkey, missing here, still a list.
	::list [login-by-fields [dict create username $user password $password]]
    }

    method login-by-fields {fields} {
	debug.v2/client {}
	# NOTE: This is an extreme shortcut through the morass of what
	# code I saw in the ruby client.

	# The ruby client has lots of additional classes, like
	# CFoundry:UAAClient, CF:UAA:TokenIssuer, AuthToken, etc. with
	# lots of functionality distributed across things, routed
	# through superclasses, aspects, delegated components,
	# auto-initalized on first use, etc. pp. ... Hairpulling
	# ensues.

	# The code below seems to follow, roughly, the path of
	#   client.login
	#   -> baseclient.login
	#     -> login_helpers.login
	#        -> uaaclient.authorize
	#           -> uaaclient.authenticate_with_password_grant
	#              -> token_issuer.owner_password_grant
	#                 -> REST call somewhere inside
	# resulting in a token instance.
	#
	# There is a second path through
	#  uaaclient.authenticate_with_implicit_grant -> tokenissuer.implicit_grant_with_creds
	# which has not been traced and assimilated.
	#
	# The token_data attribute/accessor inside the token instance
	# takes the token string itself apart getting at some hidden data.
	# (Base-encoded json object)
	#
	# For new we do the same directly, and keep it here, in the client.

	set info [my info]

	# Pull the target for authentication requests out of the
	# target information. In contrast to v1 where authentication
	# happens under the regular CC API v2 allows redirection to a
	# separate authentication server

	set    authorizer [dict get $info authorization_endpoint]
	set    uaahost    [lindex [split [url domain $authorizer] /] 0]
	append authorizer /oauth/token

	set query [http::formatQuery \
		       grant_type password {*}$fields]

	try {
	    # Custom headers for the authorizer
	    dict set authheaders AUTHORIZATION "Basic Y2Y6"
	    dict set authheaders Accept "application/json;charset=utf-8"

	    my configure -headers $authheaders

	    my HttpTrap {
		# Using raw POST to prevent auto-application of the
		# standard REST baseurl.
		lassign [my DoRequest POST $authorizer \
			     "application/x-www-form-urlencoded;charset=utf-8" \
			     $query] \
		    code data _
	    } "UAA $uaahost"
	} finally {
	    my configure -headers $myheaders
	}

	# The response is a json object (plain dictionary).
	try {
	    set response [json::json2dict $data]
	} on error {e o} {
	    return -code error -errorcode {STACKATO SERVER DATA ERROR} \
		"Received invalid JSON from server; Error: $e"
	}

	debug.v2/client {ri = ($response)}

        # Expected keys:
        # - access_token        base64 encoded token
        # - token_type          "bearer", fixed
        # - refresh_token       base64 encoded alter token for auth-refresh
        # - expires_in          some sort of timestamp
        # - scope               list of permissions?
        # - jti                 ???
        dict with response {}

	# Currently only using access_token and token_type.

	# Note: Standard v2 API does not provide an ssh key.
	# Only a token. And we have to assemble it. Also refresh all
	# in-memory copies of it, for use by future calls. See also
	# method 'refresh'.

	set myauth_token    "$token_type $access_token"
	dict set myheaders AUTHORIZATION $myauth_token
	my configure -headers $myheaders

	if {[info exists refresh_token]} {
	    set myrefresh_token $refresh_token
	} else {
	    set myrefresh_token {}
	}

	debug.v2/client {token = ($myauth_token)}

	my decode_token $access_token
	set myuser [my current_user]

	return $myauth_token
    }

    method change_password {new_password old_password} {
	debug.v2/client {}

	set info [my info]
	set user [dict get $info user]

	my UAA PUT /Users/$user/password \
	    [jmap map dict \
		 [dict create \
		      password    $new_password \
		      oldPassword $old_password]]

	# We ignore the response, for now
	return
    }

    method login-fields {} {
	debug.v2/client {}
	dict get [my UAA GET /login {}] prompts
    }

    method stackato-change-admin {uuid admin} {
	debug.v2/client {}

	set payload [dict create admin $admin]

	set payload [jmap map {dict {admin nbool}} $payload]

	# See also create-for-type for the general case, same highlevel post-processing flow.
	try {
	    lassign [my http_put /v2/stackato/users/$uuid $payload application/json] _ result _
	} trap {REST REDIRECT} {e o} {
	    # Ignore the redirect, and process as if we got 200 OK.
	    lassign $e code where headers result
	}

	try {
	    set response [json::json2dict $result]
	} on error {e o} {
	    return -code error -errorcode {STACKATO SERVER DATA ERROR} \
		"Received invalid JSON from server; Error: $e"
	}

	return $response
    }

    method stackato-create-user {username email given family password admin} {
	debug.v2/client {}

	set payload [dict create \
			 email       $email \
			 username    $username \
			 family_name $family \
			 given_name  $given \
			 password    $password \
			 admin       $admin]
	set payload [jmap map {dict {admin nbool}} $payload]

	# See also create-for-type for the general case, same highlevel post-processing flow.
	try {
	    lassign [my http_post /v2/stackato/users $payload application/json] _ result _
	} trap {REST REDIRECT} {e o} {
	    # Ignore the redirect, and process as if we got 200 OK.
	    lassign $e code where headers result
	}

	try {
	    set response [json::json2dict $result]
	} on error {e o} {
	    return -code error -errorcode {STACKATO SERVER DATA ERROR} \
		"Received invalid JSON from server; Error: $e"
	}

	return $response
    }

    method uaa_add_user {username email password} {
	debug.v2/client {}

	set response [my UAA POST /Users \
	  [jmap v2uconfig \
	       [dict create \
		    userName $username \
		    emails [list [dict create value $email]] \
		    name [dict create \
			      givenName  $username \
			      familyName $username] \
		    password $password]]]

	debug.v2/client {==> [jmap v2-uaa-user $response]}

	# Result is the UUID the new UAA user is known under.
	return [dict get $response id]
    }

    method uaa_get_user {uuid} {
	debug.v2/client {}
	return [my UAA GET /Users/$uuid {}]
    }

    method uaa_delete_user {uuid} {
	debug.v2/client {}
	return [my UAA DELETE /Users/$uuid {}]
    }

    method uaa_list_users {args} {
	debug.v2/client {}

	set qspec $args
	set query {}
	if {[llength $qspec]} {
	    set query ?[http::formatQuery {*}$qspec]
	}
	set result {}
	set start 1

	while {1} {
	    set data [my UAA GET /Users$query {}]

	    lappend result {*}[dict get $data resources]

	    if {[llength $result] >= [dict get $data totalResults]} break

	    incr start [dict get $data itemsPerPage]

	    dict set qspec startIndex $start
	    set query ?[http::formatQuery {*}$qspec]
	}

	return $result
    }

    method uaa_scope_get {gname} {
	debug.v2/client {}

	#lappend query attributes id
	lappend query filter    "displayName eq \"$gname\""
	lappend query startIndex 1
	set query [string map {%20 +} [http::formatQuery {*}$query]]

	set response [my UAA GET /Groups?$query {} {}]
	set response [dict get $response resources]

	if {![llength $response]} {
	    # scope not found.
	    err "Scope \"$gname\" not found"
	} elseif {[llength $response] > 1} {
	    # scope found, but multiple definitions. ambiguous.
	    err "Scope \"$gname\" found, is ambiguous"
	} else {
	    # return the scope information.
	    debug.v2/client {== [lindex $response 0]}
	    return [lindex $response 0]
	}
    }

    method uaa_scope_commit {scope} {
	debug.v2/client {}

	set id [dict get $scope id]
	# Convert back to json structure.
	set scope [jmap map {dict {
	    schemas array
	    members {array dict}
	    meta {dict {
		version number
	    }}
	}} $scope]

	my UAA PUT /Groups/$id $scope
    }

    method uua_scope_modify {scope mv script} {
	debug.v2/client {}
	upvar 1 $mv idlist

	set scope [my uaa_scope_get $scope]
	# scope       :: dict (id, schemas, displayName, members, meta).
	#   displayName :: string
	#   id          :: string [uuid]
	#   members     :: array (dict (type, value))
	#     type  :: string
	#     value :: string [uuid]
	#   meta        :: dict (version, created, lastModified)
	#     created      :: string
	#     lastModified :: string
	#     version      :: number
	#   schemas     :: array (string)

	# NOTE: The example for UAA seen rewrote the members array of
	# objects into an array of uuids for PUT. With AOK we keep it
	# as array of objects.
	set idlist [dict get $scope members]

	# ... modify to suit ...
	uplevel 1 $script

	# ... write back into the structure ...
	dict set scope members $idlist

	# ... and save back to the UAA.
	my uaa_scope_commit $scope
    }

    # # ## ### ##### ######## #############
    ## Entity Listing support
    # # ## ### ##### ######## #############

    method filtered-of {type key value {depth 0} {config {}}} {
	# Note: filtered-of is a canned form of list-of,
	#       hiding the syntax of the query from users.
	#
	# Note: For filtering on relations of an entity this
	#       runs through the get* (pseudo-)method of
	#       attributes (= ANget*, see v2base.tcl), which
	#       exposes the underlying syntax.
	#
	# WIBNI this could be consolidated into a nicer syntax not
	# exposing anything regardless of full list of relationship
	# list.
	debug.v2/client {}

	dict set config q ${key}:${value}
	if {$depth > 0} {
	    dict set config inline-relations-depth $depth
	}
	# list-of inlined
	return [my list-by-url /v2/$type $config]
    }

    method list-of {type {config {}}} {
	debug.v2/client {}
	return [my list-by-url /v2/$type $config]
    }

    method list-by-url {url {config {}}} {
	debug.v2/client {}
	debug.v2/memory { LOAD-L $url}

	set sep ?
	set force 0

	# Rewrite rules...
	foreach {src dst} {
	    depth         inline-relations-depth
	    user-provided return_user_provided_service_instances
	} {
	    if {[dict exists $config $src]} {
		dict set   config $dst [dict get $config $src]
		dict unset config $src
	    }
	}

	if {[dict exists $config inline-relations-depth] &&
	    [dict get    $config inline-relations-depth]} {
	    set force 1

	    if {[my is-stackato]} {
		dict set config orphan-relations 1
	    }
	}

	#dict set config pretty 1

	if {[dict size $config]} {
	    append url ?[http::formatQuery {*}$config]
	}

	set result {}
	set objpool {}

	while {1} {
	    debug.v2/client {<== $url}
	    set page [my json_get $url]

	    if {[dict exists $page relations]} {
		# Save the relations, if any, into the orphan cache.
		# The higher layers use has|get-orphan to retrieve
		# information at need. get-by-url inspects it as well
		# and short-circuits requests we can serve from it.
		dict for {uuid json} [dict get $page relations] {
		    dict set myorphans $uuid $json
		}
	    }

	    foreach item [dict get $page resources] {
		set obj [stackato v2 get-for $item]
		lappend result [$obj url]
		lappend objpool $obj
		#$obj dump_inlined
	    }

	    set url [dict get $page next_url]
	    if {$url eq "null"} break
	}

	if {$force} {
	    # Make all inlined objects known, not just on-demand/use
	    foreach o $objpool { $o force-inlined }
	}

	debug.v2/memory { LOADED $url}
	return $result
    }

    # # ## ### ##### ######## #############
    ## Entity support
    # # ## ### ##### ######## #############

    method has-orphan {uuid} {
	return [dict exists $myorphans $uuid]
    }

    method get-orphan {uuid} {
	debug.v2/memory { PULL__ $uuid}

	if {![dict exists $myorphans $uuid]} {
	    return -code error \
		-errorcode {STACKATO SERVER ORPHAN MISS} \
		"The requested orphan <$uuid> is not known"
	}

	debug.v2/memory {CACHED! [dict get $myorphans $uuid metadata url]}
	return [dict get $myorphans $uuid]
    }

    method get-by-url {url args} {
	debug.v2/client {}
	debug.v2/memory { LOAD__ $url}
	#TODO load - handle query args (inlined depth etc.)

	# Extract uuid from the url and check if we have the data
	# already, in our orphan cache.
	# url = /v2/TYPE/UUID/...

	if {[regexp {/v2/[^/]+/([^/?]+)} -> uuid]} {
	    debug.v2/memory {CACHED? ($uuid)}
	    if {[dict exists $myorphans $uuid]} {
		debug.v2/memory {CACHED* [dict get $myorphans $uuid metadata url]}
		# cross-check against the stored url
		if {$url eq [dict get $myorphans $uuid metadata url]} {
		    debug.v2/memory {CACHED! return}
		    return [dict get $myorphans $uuid]
		}
	    }
	}

	# append url ?[http::formatQuery pretty 1]

	try {
	    set result [my Request GET $url application/json]
	} trap {REST REDIRECT} {e o} {
	    return -code error -errorcode {STACKATO CLIENT BAD-RESPONSE} \
		"Can't parse unexpected redirection into JSON [lindex $e 1]"
	}

	try {
	    set response [json::json2dict [lindex $result 1]]
	} on error {e o} {
	    return -code error -errorcode {STACKATO SERVER DATA ERROR} \
		"Received invalid JSON from server; Error: $e"
	}

	return $response
    }

    method create-for-type {type json} {
	debug.v2/client {}
	try {
	    lassign [my Request POST /v2/$type application/json $json] _ result _
	} trap {REST REDIRECT} {e o} {
	    # Ignore the redirect, and process as if we got 200 OK.
	    lassign $e code where headers result
	}

	try {
	    set response [json::json2dict $result]
	} on error {e o} {
	    return -code error -errorcode {STACKATO SERVER DATA ERROR} \
		"Received invalid JSON from server; Error: $e"
	}

	return $response
    }

    method change-by-url {url json} {
	debug.v2/client {}
	try {
	    set result [my Request PUT $url application/json $json]
	} trap {REST REDIRECT} {e o} {
	    return -code error -errorcode {STACKATO CLIENT BAD-RESPONSE} \
		"Can't parse response into JSON [lindex $e 1]"
	}

	lassign $result _ result headers

	try {
	    set response [json::json2dict $result]
	} on error {e o} {
	    return -code error -errorcode {STACKATO SERVER DATA ERROR} \
		"Received invalid JSON from server; Error: $e"
	}

	return [list $response $headers]
    }

    method delete-by-url {url} {
	debug.v2/client {}
	my Request DELETE $url
    }

    method link {url type uuid} {
	debug.v2/client {}

	append url / ${type} s/ $uuid
	debug.v2/client { url = $url }

	try {
	    lassign [my Request PUT $url] _ result _
	} trap {REST REDIRECT} {e o} {
	    # Ignore the redirect, and process as if we got 200 OK.
	    lassign $e code where headers result
	}

	try {
	    set response [json::json2dict $result]
	} on error {e o} {
	    return -code error -errorcode {STACKATO SERVER DATA ERROR} \
		"Received invalid JSON from server; Error: $e"
	}

	return $response
    }

    method unlink {url type uuid} {
	debug.v2/client {}

	append url / ${type} s/ $uuid
	debug.v2/client { url = $url }

	try {
	    lassign [my Request DELETE $url] _ result _
	} trap {REST REDIRECT} {e o} {
	    # Ignore the redirect, and process as if we got 200 OK.
	    lassign $e code where headers result
	}

	try {
	    set response [json::json2dict $result]
	} on error {e o} {
	    return -code error -errorcode {STACKATO SERVER DATA ERROR} \
		"Received invalid JSON from server; Error: $e"
	}

	return $response
    }

    ## change -- collection-method add|replace for relations. type specific.

    # # ## ### ##### ######## #############
    ## Miscellanea

    method logs-of {url n} {
	debug.v2/client {}
	return [lindex [my http_get $url/stackato_logs?num=$n] 1]
	# result = dict (id -> instance), where
	# instance = dict (k -> v)
    }

    method logs-async-of {cmd url n} {
	debug.v2/client {}
	my http_get_async $cmd $url/stackato_logs?num=$n
	# result = handle identifying the async call
    }

    method logs_cancel {handle} {
	debug.v2/client {}
	my AsyncCancel $handle
	return
    }

    method report {} {
	debug.v2/client {}

	# S3. Changed API to report retrieval compared to S2.
	set sv [my server-version]
	debug.v2/client {sv = $sv}

	if {[package vsatisfies $sv 3.1]} {
	    # 3.1+ => /v2/stackato/report (changed location, same API).
	    return [lindex [my http_get /v2/stackato/report application/octet-stream] 1]
	} else {
	    # 3.0  => double-request via token.
	    #         1. PUT /v2/stackato/report/token/:mytoken
	    #         2. GET /v2/stackato/report/file/:mytoken
	    set token stackato-cli-[pid]-[clock clicks -milliseconds]
	    my http_put /v2/stackato/report/token/$token {}
	    return [lindex [my http_get /v2/stackato/report/file/$token application/octet-stream] 1]
	}
    }

    method instances-of {url} {
	debug.v2/client {}
	return [my json_get $url/instances]
	# result = dict (id -> instance), where
	# instance = dict (k -> v)
    }

    method crashes-of {url} {
	debug.v2/client {}
	my json_get $url/crashes
    }

    method stats-of {url} {
	debug.v2/client {}
	my json_get $url/stats
    }

    method files {url path {instance 0}} {
	debug.v2/client {}
	try {
	    lindex [my http_get $url/instances/$instance/files/[http::mapReply $path]] 1
	} trap {REST REDIRECT} {e o} {
	    set new [lindex $e 1]
	    debug.v2/client {==> $new}

	    lindex [my http_get_raw $new] 1
	}
    }

    ######################################################
    ## Application, log drains - log forwarding management.

    method drain-create-of {url name uri usejson} {
	debug.v2/client {}
	append url /stackato_drains
	set manifest [jmap drain \
			  [dict create \
			       drain $name \
			       uri   $uri \
			       json  $usejson]]
	my http_post $url $manifest application/json
	return
    }

    method drain-delete-of {url name} {
	debug.v2/client {}
	append url /stackato_drains/[http::mapReply $name]
	return [my http_delete $url]
    }

    method drain-list-of {url} {
	debug.v2/client {}
	append url /stackato_drains
	set result [my json_get $url]
	set tmp {}
	foreach item $result {
	    set n [dict get $item name]
	    # NOTE: The name we get from the server may have the
	    # actual name at the end, with type and application
	    # specific information ("appdrain" prefix + app uuid)
	    # coming before, all joined using "." as separator.
	    if {[string match "appdrain.*" $n]} {
		set n [lindex [split $n .] end]
		dict set item name $n
	    }
	    # Normalize the incoming boolean.
	    dict set item json [expr {!![dict get $item json]}]
	    lappend tmp $item
	}
	return $tmp
    }

    # # ## ### ##### ######## #############
    ## State

    # # ## ### ##### ######## #############
    ## Internal support

    method json_get {url} {
	debug.v2/client {}
	try {
	    set result [my http_get $url application/json]
	} trap {REST REDIRECT} {e o} {
	    return -code error -errorcode {STACKATO CLIENT BAD-RESPONSE} \
		"Can't parse response into JSON: [lindex $e 1]"
	}

	lassign $result _ response headers

	# Canonicalize the headers to lower-case keys
	dict for {k v} $headers {
	    dict set headers [string tolower $k] $v
	}

	set ctype [dict get $headers content-type]
	if {![string match application/json* $ctype]} {
	    return -code error -errorcode {STACKATO SERVER DATA ERROR} \
		"Expected JSON, instead received $ctype from server"
	}

	try {
	    set response [json::json2dict $response]
	} on error {e o} {
	    return -code error -errorcode {STACKATO SERVER DATA ERROR} \
		"Received invalid JSON from server; Error: $e"
	}

	return $response

	#rescue JSON::ParserError
	#raise BadResponse, "Can't parse response into JSON", body
    }

    method http_get_raw {url {content_type {}}} {
	debug.v2/client {}
	# Using lower-level method, prevents system from prefixing our
	# url with the target server. This method allows the callers
	# to access any url they desire.

	my DoRequest GET $url $content_type
    }

    method http_get {path {content_type {}}} {
	debug.v2/client {}
	my Request GET $path $content_type
    }

    method http_post {path payload {content_type {}}} {
	debug.v2/client {}
	# payload = channel|literal
	my Request POST $path $content_type $payload
    }

    method http_put {path payload {content_type {}}} {
	debug.v2/client {}
	# payload = channel|literal
	my Request PUT $path $content_type $payload
    }

    method http_delete {path} {
	debug.v2/client {}
	my Request DELETE $path
    }

    method UAA {method url query {qtype {application/json;charset=utf-8}}} {
	debug.v2/client {}
	set info [my info]

	# Pull the actual target for UAA requests out of the target
	# information. In contrast to v1 where this happens under the
	# regular CC API v2 allows redirection to a separate user
	# server. Which can be different from the initial
	# authentication server also.

	set    uaa [dict get $info token_endpoint]
	set    uaahost [lindex [split [url domain $uaa] /] 0]
	append uaa $url

	debug.v2/client {uaa = $uaa}

	set savedflag [my cget -accept-no-location]

	try {
	    # Custom headers for the ucreator
	    if {($url ne "/login") &&
		($myauth_token ne {})} {
		dict set authheaders AUTHORIZATION $myauth_token
	    }
	    dict set authheaders Accept $qtype

	    my configure -headers $authheaders -accept-no-location 1

	    my HttpTrap {
		# Using raw POST to prevent auto-application of the
		# standard REST baseurl.
		lassign [my DoRequest $method $uaa $qtype $query] \
		    code data _
	    } "UAA $uaahost"
	} finally {
	    my configure -headers $myheaders -accept-no-location $savedflag
	}

	if {$method eq "DELETE"} {
	    # Ignore response. Irrelevant. Return nothing.
	    debug.v2/client {uaa delete, done}
	    return
	}

	# The response is a json object (plain dictionary).
	try {
	    set response [json::json2dict $data]
	} on error {e o} {
	    return -code error -errorcode {STACKATO SERVER DATA ERROR} \
		"Received invalid JSON from server; Error: $e"
	}

	debug.v2/client {ri = ($response)}
	return $response
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
	    my HttpTrap {
		set result [my DoRequest $method $mytarget$path \
				$content_type $payload]
	    }
	    return $result
	}
	return
    }

    method HttpTrap {script {context {}}} {
	try {
	    return [uplevel 1 $script]

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

	} trap {REST REDIRECT} {e o} - \
	  trap {REST SSL}      {e o} - \
	  trap {HTTP URL}      {e o} {
	    # Rethrow
	    return {*}$o $e

	} trap {POSIX ECONNREFUSED} {e o} - \
	  trap {HTTP SOCK OPEN} {e o} {
	    my BadTarget $e $context

	} on error {e o} {
	    # See also HTTP SOCK OPEN above. Dependent on local
	    # modified copy of the http package.
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

    # # ## ### ##### ######## #############

    method http_get_async {cmd path {content_type {}}} {
	debug.v2/client {}
	my ARequest $cmd GET $path $content_type
    }

    method ARequest {cmd method path {content_type {}} {payload {}}} {
	debug.v2/client {}
	# payload = channel|literal

	# PAYLOAD see update_app, is dict with file channel inside ?
	# How/where is that handled.

	if {$content_type ne {}} {
	    http::config -accept $content_type
	} else {
	    http::config -accept */*
	}

	my AsyncRequest [mymethod ARD $cmd] $method $mytarget$path \
	    $content_type $payload
    }

    method ARDO {details} {
	debug.v2/client {}
	# This is a helper to get the return and error handling right
	# (within the try/finally of ARD)
	return {*}$details
    }

    method ARD {cmd code {details {}}} {
	debug.v2/client {}
	# code = reset
	#      | return (which has details)

	# reset - Passed through.
	# return - split into options and result, then handle errors
	#          like in a try. I.e. transformed, and then passed.


	if {$code eq "reset"} {
	    uplevel \#0 [list {*}$cmd reset]
	    return
	}

	catch {
	    try {
		my ARDO $details
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

	    } trap {REST REDIRECT} {e o} - \
	      trap {HTTP URL} {e o} {
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
	} e o

	uplevel \#0 [list {*}$cmd return [list {*}$o $e]]
	return
    }

    # # ## ### ##### ######## #############

    method request_failed {status} {
	# Failed for 4xx and 5xx == range 400..599
	return [expr {(400 <= $status) && ($status < 600)}]
    }

    method PEM {status data} {
	lassign $data ctype data

	debug.v2/client {}

	if {$status == 413} {
	    return "Error $status: Request too large"
	}

	try {
	    set parsed [json::json2dict $data]

	    debug.v2/client {parsed = ($parsed)}

	    if {($parsed ne {}) &&
		[my HAS $parsed error_description]} {

		set map     [list "\"" {'}]
		set desc    [string map $map [dict get $parsed error_description]]
		append desc " ($status)"
		return $desc
	    }

	    if {($parsed ne {}) &&
		[my HAS $parsed code] &&
		[my HAS $parsed description]} {

		set errcode [dict get $parsed code]
		set map     [list "\"" {'}]
		set desc    [string map $map [dict get $parsed description]]
		append desc " ($status)"

		if {$errcode == 1001} {
		    debug.v2/client {bad request}
		    return -code error \
			-errorcode {STACKATO CLIENT V2 INVALID REQUEST} \
			$desc
		}

		if {$errcode == 1002} {
		    debug.v2/client {invalid relation}
		    return -code error \
			-errorcode {STACKATO CLIENT V2 INVALID RELATION} \
			$desc
		}

		if {$errcode == 10000} {
		    debug.v2/client {unknown request}
		    return -code error \
			-errorcode {STACKATO CLIENT V2 UNKNOWN REQUEST} \
			$desc
		}

		if {$errcode == 170002} {
		    debug.v2/client {staging progress}
		    # V2 -- Staging not finished. Generate an error
		    # specifically for this. Preempt generation of the
		    # outer NotFound error.
		    return -code error \
			-errorcode {STACKATO CLIENT V2 STAGING IN-PROGRESS} \
			$desc
		}

		if {$errcode == 170001} {
		    debug.v2/client {staging failed}
		    # V2 -- Staging failed. Generate an error
		    # specifically for this. Preempt generation of the
		    # outer NotFound error.
		    return -code error \
			-errorcode {STACKATO CLIENT V2 STAGING FAILED} \
			$desc
		}

		if {$errcode == 10003} {
		    debug.v2/client {permission error}
		    # V2 - Authentication/Permission error.
		    my AuthError $desc
		}

                if {$errcode == 310} {
                    # staging error is common enough that the user
                    # need not know the http error code behind it.
                    return "$desc"
                } else {
                    return "Error $errcode: $desc"
                }
	    } else {
		if {[string match *html*    $ctype] ||
		    [string match *DOCTYPE* $data] ||
		    [string match *html*    $data]} {
		    # Error message is html dump.
		    set data {<HTML dump elided>}
		}

		return "Error (HTTP $status): $data"
	    }
	} trap {STACKATO CLIENT V2} {e o} {
	    return {*}$o $e
	} on error {e o} {
	    if {$data eq {}} {
		return "Error ($status): No Response Received"
	    } else {
		if {[string match *html*    $ctype] ||
		    [string match *DOCTYPE* $data] ||
		    [string match *html*    $data]} {
		    # Error message is html dump.
		    set data {<HTML dump elided>}
		}

		#@todo: no trace => truncate
		#return "Error (JSON $status): $e"
		return "Error (JSON $status): $data"
	    }
	}
    }

    method HAS {dict key} {
	expr {[dict exists $dict $key] &&
	      ([dict get $dict $key] ne {})}
    }

    method BadTarget {text {thetarget {}}} {
	debug.v2/client {}
	if {$thetarget eq {}} { set thetarget $mytarget }

	return -code error -errorcode {STACKATO CLIENT V2 BADTARGET} \
	    "Cannot access target '$thetarget' ($text)"
    }

    method TargetError {msg} {
	debug.v2/client {}
	return -code error -errorcode {STACKATO CLIENT V2 TARGETERROR} $msg
    }

    method NotFound {msg} {
	debug.v2/client {}
	return -code error -errorcode {STACKATO CLIENT V2 NOTFOUND} $msg
    }

    method AuthError {{msg {}}} {
	debug.v2/client {}
	return -code error -errorcode {STACKATO CLIENT V2 AUTHERROR} $msg
    }

    # forward ...
    method internal {e} {
	my InternalError $e
    }

    method InternalError {e} {
	debug.v2/client {}
	return -code error -errorcode {STACKATO CLIENT V2 INTERNAL} \
	    [list $e $::errorInfo $::errorCode]
    }

    # For debugging, error generation directly in a try. Must be
    # thrown from within method to be properly caught by the
    # try/finally.
    method E {e c} {
	return -code error -errorcode $c $e
    }

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::client 0
return
