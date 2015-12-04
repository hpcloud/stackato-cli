# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations. Target introspection.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require cmdr::color
package require cmdr::pager
package require stackato::jmap
package require stackato::log
package require stackato::mgr::auth
package require stackato::mgr::app
package require stackato::mgr::cgroup
package require stackato::mgr::client
package require stackato::mgr::context
package require stackato::mgr::cfile
package require stackato::mgr::corg
package require stackato::mgr::cspace
package require stackato::mgr::ctarget
package require stackato::mgr::manifest
package require stackato::mgr::self
package require stackato::mgr::ws
package require stackato::misc
package require stackato::v2
package require stackato::validate::debug
package require stackato::validate::spacename
package require stackato::yaml
package require table
package require dictutil

debug level  cmd/query
debug prefix cmd/query {[debug caller] | }

namespace eval ::stackato::cmd {
    namespace export query
    namespace ensemble create
}
namespace eval ::stackato::cmd::query {
    namespace import ::stackato::mgr::context
    rename context ctx

    namespace import ::stackato::mgr::manifest
    rename manifest manifestmgr

    namespace export \
	frameworks general runtimes services usage \
	applications manifest appinfo context stacks \
	target-version trace map-named-entity \
	named-entities raw-rest list-packages app-versions \
	list-options
    namespace ensemble create

    namespace import ::cmdr::color
    namespace import ::stackato::jmap
    namespace import ::stackato::log::display
    namespace import ::stackato::log::err
    namespace import ::stackato::log::psz

    namespace import ::stackato::log::epoch-of
    namespace import ::stackato::log::since
    namespace import ::stackato::log::pretty-since

    namespace import ::stackato::mgr::auth
    namespace import ::stackato::mgr::app
    namespace import ::stackato::mgr::cgroup
    namespace import ::stackato::mgr::client
    namespace import ::stackato::mgr::cfile
    namespace import ::stackato::mgr::corg
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::mgr::ctarget
    namespace import ::stackato::mgr::self
    namespace import ::stackato::mgr::ws
    namespace import ::stackato::misc
    namespace import ::stackato::v2
    namespace import ::stackato::validate::debug
    namespace import ::stackato::validate::spacename
    namespace import ::stackato::yaml
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::query::context {config} {
    display [ctx format-large]
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::query::target-version {config} {
    debug.cmd/query {}
    set client [client plain]
    display "Server  [$client full-server-version]"
    display "Version [$client server-version ]"
    display "API     [$client api-version]"
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::query::raw-rest {config} {
    debug.cmd/query {}

    set client  [$config @client]
    set op      [$config @operation]
    set ws      [$config @web-socket]
    set url     [$config @path]
    set headers [$config @header]
    set verbose [$config @show-extended]
    set port    [$config @port]

    # Prepend a missing leading /
    # Should possibly go into validation type.
    if {![string match /* $url]} {
	set url /$url
    }

    set form {}
    foreach item [$config @form] {
	dict set form {*}$item
    }
    if {[dict size $form]} {
	append url ?[http::formatQuery {*}$form]
    }

    if {$ws && ($op ne "GET")} {
	# Reject web-socket operation for anything but GET.
	err "Operation $op does not support --web-socket mode."
    }

    if {$ws} {
	set target [ctarget get]
	#puts 1|$target|

	set target [url ws [url canon $target]]
	regsub {^wss:} $target {ws:} target ;# Force non-SSL connection.
	#puts 2|$target|

	if {$port ne {}} {
	    append target :$port
	}

	debug.cmd/query {target = $target}
	debug.cmd/query {url    = $url}

	dict set a text    [namespace code rr-ws-text]
	dict set a binary  [namespace code rr-ws-binary]
	dict set a connect [namespace code rr-ws-connect]
	if {[$config @reconnect]} {
	    dict set a close [namespace code [list rr-ws-keep $target $url]]
	}

	ws open $target $url $a
	ws wait
	return

	set continue yes
	while {$continue} {
	    set continue [$config @reconnect]
	    websocket::open $url [namespace code WSHandler] {*}$options
	    #puts 4|WAITING
	    vwait ::forever
	}
	debug.cmd/query {/done}
	return {*}$::forever
    }

    set old [$client cget -headers]
    set new $old
    foreach item $headers {
	lappend new {*}$item
    }
    $client configure -headers $new

    set cmd [dict get {
	GET    http_get
	HEAD   http_get
	PUT    http_put
	POST   http_post
	DELETE http_delete
    } $op]

    lappend cmd $url

    if {$op in {PUT POST}} {
	# Handle a payload.

	set data [$config @data]
	if {$data in {- stdin}} {
	    set data [read stdin]
	}
	lappend cmd $data

    } elseif {[$config @data set?]} {
	# Reject a payload
	err "Operation $op does not allow specification of --data"
    }

    try {
	lassign [$client {*}$cmd] code response headers
    } on error {e o} {
	display "Response Code:    $e"
    } on ok {e o} {
	if {$verbose} {
	    display "Response Code:    $code"

	    set n      [MaxLen [dict keys $headers]]
	    set fmt    %-${n}s
	    set prefix {Response Headers:}

	    dict for {k v} $headers {
		display "$prefix [format $fmt $k] = ($v)"
	    }
	}
	ShowResponse $config $verbose $response
    } finally {
	$client configure -headers $old
    }

    debug.cmd/query {/done}
    return
}

proc ::stackato::cmd::query::ShowResponse {config verbose response} {
    set out [$config @output]
    if {$out in {- stdout}} {
	if {$verbose} {
	    display "Response Body:    $response"
	} else {
	    display $response
	}
	return
    }

    set chan [open $out w]
    fconfigure $chan -translation binary -encoding binary
    puts -nonewline $chan $response

    if {$verbose} {
	display "Response Body:    See $out"
    }
    return
}

proc ::stackato::cmd::query::rr-ws-connect {} {
    puts [color note "connected (press Ctrl-C to abort)"]
}

proc ::stackato::cmd::query::rr-ws-text {msg} {
    puts "TEXT: $msg"
    flush stdout
}

proc ::stackato::cmd::query::rr-ws-binary {msg} {
    puts [http::Hexl {DATA: } $msg]
    flush stdout
}

proc ::stackato::cmd::query::rr-ws-keep {target url } {
    dict set a text    [namespace code rr-ws-text]
    dict set a binary  [namespace code rr-ws-binary]
    dict set a connect [namespace code rr-ws-connect]
    dict set a close   [namespace code [list rr-ws-keep $target $url]]
    ws open $target $url $a
}

proc ::stackato::cmd::query::WSHandler {sock type msg} {

    # type in
    # * binary     - data binary
    # * close      - connection close pending
    # * connect    - connection is open
    # * disconnect - connection closed by remote
    # * error      - general error
    # * ping       - liveness
    # * text       - data, text

    switch -exact -- $type {
	error {
	    # Abort the event loop in 'raw-rest'.
	    set ::forever [list -code error \
			       -errorcode {STACKATO CLIENT CLI CLI-EXIT} \
			       "Error: $msg"]
	    return
	}
	connect {
	    puts [color note "connected (press Ctrl-C to abort)"]
	}
	disconnect {}
	close {
	    puts [color note "Note: $msg"]
	    # Abort event loop in raw-rest, regular return
	    set ::forever [list -code ok {}]
	}
	binary {
	    # Binary frame
	    puts [http::Hexl {DATA: } $msg]
	    flush stdout
	}
	text {
	    # Text frame
	    puts "TEXT: $msg"
	    flush stdout
	}
	ping {}
	default {
	    # ping

	    puts S=$sock
	    puts T=$type
	    puts M=($msg)
	}
    }
}

proc ::stackato::cmd::query::MaxLen {list} {
    set max 0
    foreach s $list {
	set n [string length $s]
	if {$n <= $max} continue
	set max $n
    }
    return $max
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::query::list-options {config} {
    debug.cmd/query {}

    lappend lines "Debug options to inspect cli internals at various levels"
    lappend lines ""

    lappend lines --debug-http-log
    lappend lines --debug-http-data
    lappend lines --debug-http-token
    lappend lines --debug-tls-handshake

    lappend lines ""

    foreach section [debug levels] {
	lappend lines "--debug $section"
    }

    cmdr pager [join $lines \n]
    return
}

proc ::stackato::cmd::query::list-packages {config} {
    debug.cmd/query {}

    foreach p [lsort -dict [self packages]] {
	try {
	    set v [package require $p]
	    set w [string trim [package ifneeded $p $v]]

	    dict set ok $p 1
	} on error {e o} {
	    set v $e
	    set w {}
	    dict set ok $p 0
	}
	lappend info $p [list $v $w]
    }

    if {[$config @json]} {
	display [jmap map {dict {* array}} $info]
	return
    }

    if {[$config @all]} {
	[table::do t {Package Version Loader} {
	    foreach {p vw} $info {
		lassign $vw v w
		if {0 && ![dict get $ok $p]} {
		    set p [color bad $p]
		    set v [color bad $v]
		}
		$t add $p $v $w
	    }
	}] show display
    } else {
	[table::do t {Package Version} {
	    foreach {p vw} $info {
		lassign $vw v __
		if {0 && ![dict get $ok $p]} {
		    set p [color bad $p]
		    set v [color bad $v]
		}
		$t add $p $v
	    }
	}] show display
    }
    return
}

proc ::stackato::cmd::query::named-entities {config} {
    debug.cmd/query {}

    # Keep synchronized with ::stackato::validate::entity::validate
    set types [v2 types]
    struct::list delete types managed_service_instance
    struct::list delete types user_provided_service_instance
    struct::list delete types feature_flag
    struct::list delete types config/environment_variable_group

    if {[$config @json]} {
	display [jmap map array $types]
	return
    }

    display [lsort -dict $types]
    return
}

proc ::stackato::cmd::query::map-named-entity {config} {
    debug.cmd/query {}

    set type [$config @type]
    set name [$config @name]

    # Chop trailing plural s, if any.
    regsub {s$} $type {} type

    # Note: How to handle entities without @name ?
    if {$type ni {user service_plan}} {
	switch -exact -- $type {
	    route { set k host }
	    service_auth_token -
	    service { set k label }
	    default { set k name }
	}
	set matches [v2 sort id [v2 $type list 0 q $k:$name] -dict]
    } else {
	# Pull list of all entities and filter locally.
	set matches [v2 sort id [struct::list filter [v2 $type list] [lambda {pattern o} {
	    string equal $pattern [$o @name]
	} $name]] -dict]
    }

    if {[$config @json]} {
	set ids [struct::list map $matches [lambda o {
	    $o id
	}]]
	display [jmap map array $ids]
	return
    }

    if {![llength $matches]} {
	err "[string totitle $type] \"$name\" not found"
    }

    [table::do t {Name UUID} {
	foreach o $matches {
	    $t add $name [$o id]
	}
    }] show display
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::query::trace {config} {
    debug.cmd/query {}

    if {![file exists [cfile get rest]]} {
	err "No trace available"
    }
    if {![file readable [cfile get rest]]} {
	err "Not permitted to read the trace"
    }

    set in [open [cfile get rest] r]

    debug.cmd/query {input   = $in = [fconfigure $in -encoding] [fconfigure $in -translation] :: [cfile get rest]}
    debug.cmd/query {output  = stdout = [fconfigure stdout -encoding] [fconfigure stdout -translation]}

    fconfigure $in -translation binary

    # Bug 103786. The windows console misbehaves (prints garbage) when
    # we force the channel to binary. Its reported encoding is
    # 'unicode', so we are making this an exception to the rule.
    if {[fconfigure stdout -encoding] ni {unicode}} {
	fconfigure stdout -translation binary
    }

    debug.cmd/query {input'  = $in = [fconfigure $in -encoding] [fconfigure $in -translation] :: [cfile get rest]}
    debug.cmd/query {output' = stdout = [fconfigure stdout -encoding] [fconfigure stdout -translation]}
    debug.cmd/query {short=[$config @short]}

    if {[$config @short]} {
	# Show only the actual requests, without details.
	while {![eof $in]} {
	    gets $in line
	    if {![regexp {(GET)|(PUT)|(POST)|(DELETE)} $line]} continue
	    puts stdout $line
	}
    } else {
	fcopy $in stdout
    }

    close $in
    debug.cmd/query {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::query::app-versions {config} {
    debug.cmd/query {}
    manifestmgr user_1app each $config ::stackato::cmd::query::AppVersions
    return
}

proc ::stackato::cmd::query::AppVersions {config theapp} {
    debug.cmd/query {}

    set theapp [$config @application]

    if {![$theapp @app_versions defined?]} {
	err "The chosen target does not support application versioning"
    }

    set versions [$theapp @app_versions]

    if {[$config @json]} {
	display [json::write array \
		     {*}[struct::list map $versions \
			     [lambda v { $v as-json }]]]
	return
    }

    [table::do t {Version Created Description} {
	#  Instances Memory - currently internal
	foreach v [v2 sort @version_count $versions -integer -decreasing] {
	    set n [$v name]
	    set c [pretty-since [since [epoch-of [$v created]]]]
	    set d [$v @description]
	    #set i [$v @instances]
	    #set m [$v @memory]

	    $t add $n $c $d ;# $i $m
	}
    }] show display
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::query::appinfo {config} {
    debug.cmd/query {}
    manifestmgr user_1app each $config ::stackato::cmd::query::Appinfo
    return
}

proc ::stackato::cmd::query::Appinfo {config theapp} {
    debug.cmd/query {}

    set client [$config @client]
    if {[$client isv2]} {
	AppinfoV2 $config
    } else {
	AppinfoV1 $config $client
    }
}

proc ::stackato::cmd::query::AppinfoV1 {config client} {
    debug.cmd/query {}
    set app [$client app_info [$config @application]]

    if {[$config @json]} {
	display [jmap appinfo $app]
	return
    }

    display [$config @application]
    [table::do t {Key Value} {
	$t add Uris         [join [Uprefix [lsort -dict [dict get $app uris]]] \n]
	$t add State        [app state-color [dict get $app state]]
	$t add Health       [app health-color [misc health $app]]
	$t add Instances    [dict get $app instances]
	$t add Memory       [psz [MB [dict get $app resources memory]]]
	$t add {Disk Quota} [psz [MB [dict get $app resources disk]]]
	$t add Services     [join [lsort -dict [dict get $app services]] \n]
	$t add Environment:

	foreach item [lsort -dict [dict get $app env]] {
	    regexp {^([^=]*)=(.*)$} $item -> k v
	    $t add "- $k" $v
	}

	$t add Drains [join [lsort -dict [DrainListV1 $client $app]] \n]

    }] show display
    return
}

proc ::stackato::cmd::query::AppinfoV2 {config} {
    debug.cmd/query {}

    set theapp [$config @application]

    debug.cmd/query { $theapp = [$theapp as-json]}

    if {[$config @json]} {
	display [$theapp as-json]
	return
    }

    try {
	set htitle Health
	set health [app health-color [$theapp health]]
    }  trap {STACKATO CLIENT V2 STAGING IN-PROGRESS} {e o} {
	set htitle [color warning {** Health}]
	set health [color warning "** Staging not completed"]
    } trap {STACKATO CLIENT V2 STAGING FAILED} {e o} {
	set htitle [color bad {** Health}]
	set health [color bad "** Failed to stage"]
    }

    display [ctx format-short " -> [$theapp @name]"]
    [table::do t {Key Value} {
	if {[$theapp @distribution_zone defined?]} {
	    set z [$theapp @distribution_zone]
	    # z :: name <=> guid. NOT entity.
	} else {
	    # placement zone not supported by target.
	    set z [color note "N/A (not supported by target)"]
	}

	foreach {var attr hilit op} {
	    bldp  buildpack            name {}
	    dbld  detected_buildpack   name {}
	    htim  health_check_timeout {}   {}
	    ssoe  sso_enabled          {}   {}
	    desc  description          {}   {}
	    mini  min_instances        {}   {}
	    maxi  max_instances        {}   {}
	    mint  min_cpu_threshold    {}   {}
	    maxt  max_cpu_threshold    {}   {}
	    auts  autoscale_enabled    {}   {}
	    rere  restart_required     {}   {}
	    dimg  docker_image         name {}
	    stack stack                name {Get @name}
	    pkuat package_updated_at   {}   {}
	} {
	    if {[$theapp @$attr defined?]} {
		upvar 0 $var thevar
		# Extract from app instance
		set thevar [$theapp @$attr]
		# Transform, if required.
		if {[llength $op]} { set thevar [{*}$op $thevar] }
		# Colorize, if required
		if {($hilit ne {}) && ($thevar ne {})} {
		    set thevar [color $hilit $thevar]
		}
	    } else {
		# Attribute not supported by target.
		set $var [color note "N/A (not supported by target)"]
	    }
	}

	$t add Description      $desc
	$t add Routes           [join [Uprefix [lsort -dict [$theapp uris]]] \n]
	$t add {Placement Zone} $z
	$t add {SSO Enabled}    [Bool note {} $ssoe]

	$t add State                [app state-color [$theapp @state]]
	$t add {Restart required}   [Bool note {} $rere]
	$t add $htitle              $health
	$t add {- Check Timeout}    $htim
	$t add Stack                $stack
	$t add Buildpack            $bldp
	$t add {Detected Buildpack} $dbld
	$t add {Last uploaded}      $pkuat ;# Maybe TODO reparse and format into local timezone.
	$t add {Docker Image}       $dimg
	$t add Instances            [$theapp @total_instances]
	$t add Memory               [psz [MB [$theapp @memory]]]
	$t add {Disk Quota}         [psz [MB [$theapp @disk_quota]]]

	$t add Services    [join [lsort -dict [$theapp services]] \n]
	$t add Environment
	dict for {k v} [dict sort [$theapp @environment_json]] {
	    $t add "- $k" $v
	}

	$t add Drains [join [lsort -dict [DrainListV2 $theapp]] \n]

	$t add {Auto Scaling}
	$t add {- Enabled}       $auts
	$t add {- Min Instances} $mini
	$t add {- Max Instances} $maxi
	$t add {- Min CPU}       $mint
	$t add {- Max CPU}       $maxt

	if {![$theapp @app_versions defined?]} {
	    $t add Versioning "N/A (not supported by target)"
	} else {
	    # Show abbreviated version information.
	    $t add Versioning {}
	    set versions [$theapp @app_versions]
	    foreach v [v2 sort @version_count $versions -integer -decreasing] {
		set n [$v name]
		set c [pretty-since [since [epoch-of [$v created]]]]
		set d [$v @description]
		set i [$v @instances]
		set m [$v @memory]

		$t add "- $n" "$c '$d'" ;#internal, no show: " \#$i ${m}M"
	    }
	}
    }] show display
    return
}

proc ::stackato::cmd::query::Bool {ycolor ncolor x} {
    set x [expr {$x ? "yes":"no"}]
    if { $x && ($ycolor ne {})} { return [color $ycolor $x] }
    if {!$x && ($ncolor ne {})} { return [color $ncolor $x] }
    return $x
}

proc ::stackato::cmd::query::Get {args} {
    set obj [lindex $args end]
    return [$obj {*}[lrange $args 0 end-1]]
}

proc ::stackato::cmd::query::MB {x} {
    expr {$x * 1024 * 1024}
}

proc ::stackato::cmd::query::Plus {label key} {
    upvar 1 t t theapp theapp
    if {[string match {::apply *} $key]} {
	$t add $label [{*}$key $theapp]
    } else {
	$t add $label [$theapp {*}$key]
    }
}

proc ::stackato::cmd::query::DrainListV1 {client app} {
    if {![client chasdrains $client]} { return {} }

    set drains {}
    set appname [dict getit $app name]
    foreach d [$client app_drain_list $appname] {
	lappend drains "[dict get $d name] @ [dict get $d uri]"
    }
    return $drains
}

proc ::stackato::cmd::query::DrainListV2 {app} {
    if {![client chasdrains [client plain]]} { return {} }

    set drains {}
    foreach d [$app drain-list] {
	lappend drains "[dict get $d name] @ [dict get $d uri]"
    }
    return $drains
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::query::manifest {config} {
    debug.cmd/query {}

    # HACK: Cross access into other package's internals.
    ##
    # TODO/FUTURE: Create a cmdr/manifest and proper procedures in
    # mgr/manifest for it, then move the debug commands over. See
    # also cmd/app: the-upload-manifest.

    if {[manifestmgr have]} {
	upvar #0 ::stackato::mgr::manifest::manifest M
	yaml dump-retag $M
    } else {
	display "No configuration found"
    }
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::query::stacks {config} {
    debug.cmd/query {}
    # --token, --token-file, --target handled by cmdr framework
    # through when-complete and force.

    if {![$config @json]} {
	display "\nStacks: [ctx format-target]"
    }

    set client [$config @client]
    set stacks [v2 sort @name [v2 stack list] -dict]

    if {[$config @json]} {
	display [jmap v2-stacks [struct::list map $stacks [lambda s {
	    dict create \
		name [$s @name] \
		description [$s @description]
	}]]]
	return
    }

    if {![llength $stacks]} {
	display [color note "No Stacks"]
	return
    }

    [table::do t {Name Description} {
	foreach s $stacks {
	    $t add [$s @name] [$s @description]
	}
    }] show display
    return
}

proc ::stackato::cmd::query::frameworks {config} {
    debug.cmd/query {}
    # --token, --token-file, --target handled by cmdr framework
    # through when-complete and force.

    set client     [$config @client]
    set frameworks [client frameworks $client]

    if {[$config @json]} {
	display [jmap frameworks $frameworks]
	return
    }

    if {![llength $frameworks]} {
	display [color note "No Frameworks"]
	return
    }

    table::do t {Name} {
	foreach {name subframe} $frameworks {
	    if {[llength $subframe]} {
		foreach s $subframe {
		    $t add "$name - $s"
		}
	    } else {
		$t add $name
	    }
	}
    }
    display ""
    $t show display
    return
}

proc ::stackato::cmd::query::general {config} {
    debug.cmd/query {}

    set client [$config @client]

    # Make the current group available, if any, ensuring validity
    if {[$client logged_in?]} {
	client confer-group $client 0
	$client info_reset
    }

    set info [$client info]

    if {[$client isv2]} {
	debug.cmd/query {drop usage/limits, bogus under v3}
	# Drop usage/limits data, bogus for a v3 target.
	dict unset info usage
	dict unset info limits
    }

    if {[$config @json]} {
	#@type info = dict:
	#    name build support version description /string
	#    user/dict: 
	#    usage/dict: apps memory services /string
	#    limits/dict: sa + app_uris
	#    frameworks/dict: <any>/dict:
	#        appservers/array(dict)
	#        runtimes/array(dict)
	#        detection/array(dict)
	#	     */string
	
	display [jmap clientinfo $info]
	return
    }

    dict validate $info
    dict with info {
	if {[dict exists $info vendor_version]} {
	    display "\n$description $vendor_version"
	} else {
	    display "\n$description"
	}
	display "For support visit $support"
	display ""
	display "Target:   [ctarget get] (API v$version)"
	display "Client:   v[package present stackato::cmdr]"
    }

    if {[dict exists $info user] ||
	[dict exists $info groups]} {
	display ""
	if {[dict exists $info user]} {
	    set theuser [$client current_user]
	    display "User:     $theuser"
	}
	if {[dict exists $info groups]} {
	    set groups [dict get $info groups]
	    set current [cgroup get]
	    if {$current ne {}} {
		set pos [lsearch -exact $groups $current]
		if {$pos >= 0} {
		    lset groups $pos \[$current\]
		}
	    }
	    display "Groups:   [join $groups "\n          "]"
	}
    }

    if {[dict exist $info usage] &&
	[dict exist $info limits]} {
	set usage  [dict get $info usage] 
	set limits [dict get $info limits]

	dict with limits {
	    set tmem  [psz [expr {$memory*1024*1024}]]
	    set tser  $services
	    if {[catch { set tapps $apps }]} { set tapps 0 }
	}

	dict with usage {
	    set mem  [psz [expr {$memory*1024*1024}]]
	    set ser  $services
	    if {[catch { set apps $apps }]} { set apps 0 }
	}

	display "Usage:    Memory   ($mem of $tmem total)"
	display "          Services ($ser of $tser total)"

	if {[dict exists $limits apps]} {
	    display "          Apps     ($apps of $tapps total)"
	}
    }

    client license-status $client 0 {License:  }
    return
}

proc ::stackato::cmd::query::runtimes {config} {
    debug.cmd/query {}
    # --token, --token-file, --target handled by cmdr framework
    # through when-complete and force.

    set client   [$config @client]
    set runtimes [client runtimes $client]

    if {[$config @json]} {
	display [jmap runtimes $runtimes]
	return
    }

    if {![llength $runtimes]} {
	display [color note "No Runtimes"]
	return
    }

    table::do t {Name Description Version} {
	dict for {_ rt} $runtimes {
	    $t add \
		[dict getit $rt name] \
		[dict getit $rt description] \
		[dict getit $rt version]
	}
    }
    display ""
    $t show display
    return
}

proc ::stackato::cmd::query::usage {config} {
    debug.cmd/query {}
    # --token, --token-file, --target, --group handled
    # by cmdr framework through when-complete and force.

    set client      [$config @client]
    set all         [$config @all]
    set userOrGroup [$config @userOrGroup]

    # Note: Either @all or @userOrGroup is set, but not both.

    if {[$client isv2]} {
	set info [UsageV2 $client $config $all $userOrGroup]
	# 3.0.1: s.b, not confirmed
	# 3.2.1: s.b, not confirmed
	# 3.4.2: usage:mem is [B], scale/convert down to [KB]!
	# 3.6:   s.a.

	set um [dict get $info usage mem]
	set um [expr {$um / 1024.0}]
	dict set info usage mem $um

    } else {
	set info [UsageV1 $client $config $all $userOrGroup]
    }

    debug.cmd/query {info = ($info)}

    if {[$config @json]} {
	#@type info = dict:
	# allocated:mem: KB
	# usage:mem:     KB

	display [jmap usageinfo $info]
	return
    }

    display "Allocated Memory: [psz [expr {1024*[dict get $info allocated mem]}]]"
    display "Used Memory:      [psz [expr {1024*[dict get $info usage     mem]}]]"
    return
}

proc ::stackato::cmd::query::UsageV1 {client config all userOrGroup} {
    debug.cmd/query {}
    return [$client usage $all $userOrGroup]
}

proc ::stackato::cmd::query::UsageV2 {client config all space} {
    debug.cmd/query {}
    if {$all} {
	# Global usage
	return [$client usage]
    } else {
	if {$space ne {}} {
	    # Specified space, validate and convert the name.
	    set space [spacename validate [$config @userOrGroup self] $space]
	} else {
	    # Current space.
	    set space [cspace get-auto [$config @userOrGroup self]]
	}
	return [$space usage]
    }
}

proc ::stackato::cmd::query::applications {config} {
    debug.cmd/query {}
    # --token, --token-file, --target, --group handled
    # by cmdr framework through when-complete and force.

    set client [$config @client]

    if {[$client isv2]} {
	AppListV2 $config
    } else {
	AppListV1 $config $client
    }
    return
}

proc ::stackato::cmd::query::AppListV2 {config} {
    debug.cmd/query {v2}

    if {![$config @json]} {
	display "\nApplications: [ctx format-target]"
    }

    set cs [cspace get]

    # While we pretty much always have a current space, not having one
    # is possible, so the else branch can happen.
    if {![$config @all] && ($cs ne {})} {
	try {
	    $cs summarize
	    set applications [$cs @apps]
	} trap {STACKATO CLIENT V2 AUTHERROR} {e o} {
	    set applications [v2 app list 2 include-relations routes,domain,service_bindings,service_instance]
	}
    } else {
	set applications [v2 app list 2 include-relations routes,domain,service_bindings,service_instance]
    }

    # TODO: query/apps - Filter by name/url

    set applications [v2 sort @name $applications -dict]

    if {[$config @json]} {
	set tmp {}
	foreach a $applications {
	    lappend tmp [$a as-json]
	}
	display [json::write array {*}$tmp]
	return
    }

    if {![llength $applications]} {
	display [color note "No Applications"]
	return
    }

    set full [$config @full]
    if {$full} {
	set titles {Application \# Mem Disk Health Restart URLs Services Drains}
    } else {
	set titles {Application \# Mem Disk Health URLs Services}
    }

    [table::do t $titles {
	foreach app $applications {
	    try {
		set health [app health-color [$app health]]
	    } trap {STACKATO CLIENT V2 STAGING FAILED}      {e o} - \
	      trap {STACKATO CLIENT V2 STAGING IN-PROGRESS} {e o} {
		debug.cmd/query {not staged}
		  set health [color bad 0%]
	    }

	    set name         [color name [$app @name]]
	    set numinstances [$app @total_instances]
	    set mem          [psz [MB [$app @memory]]]     ;# @[unit MB]
	    set disk         [psz [MB [$app @disk_quota]]] ;# @[unit MB]
	    set uris         [join [Uprefix [lsort -dict [$app uris]]] \n]
	    set services     [join [lsort -dict [$app services]] \n]

	    if {$full} {
		if {[$app @restart_required defined?] &&
		    [$app @restart_required]} {
		    set restart [color note Required]
		} else {
		    set restart ""
		}

		set drains [join [lsort -dict [DrainListV2 $app]] \n]

		$t add $name $numinstances $mem $disk $health $restart $uris $services $drains
	    } else {
		$t add $name $numinstances $mem $disk $health $uris $services
	    }
	}
    }] show display

    debug.cmd/query {/done v2}
    return
}

proc ::stackato::cmd::query::AppListV1 {config client} {
    # CF v1 API...

    set applications [$client apps]
    #@type apps = list (...) /@todo fill element type

    set applications [misc sort-aod name $applications -dict]

    if {[$config @json]} {
	# Same hack as done in service_dbshell,
	# for consistent output.
	set applications [struct::list map $applications [lambda {fc app} {
	    if {[dict exists $app services_connect_info]} {
		set sci [dict get $app services_connect_info]
		set newsci {}
		foreach s $sci {
		    lappend newsci [{*}$fc $s]
		}
		dict set app services_connect_info $newsci
	    }
	    return $app
	} ::stackato::misc::fix-credentials]]

	display [jmap apps $applications]
	return
    }

    display ""
    if {![llength $applications]} {
	display [color note "No Applications"]
	return
    }

    [table::do t {Application \# Health URLs Services Drains} {
	foreach app $applications {
	    set health [misc health $app]
	    if {[string is double -strict $health]} {
		append health %
	    }
	    $t add \
		[dict getit $app name] \
		[dict getit $app instances] \
		[app health-color $health] \
		[join [Uprefix [lsort -dict [dict getit $app uris]]] \n] \
		[join [lsort -dict [dict getit $app services]] \n] \
		[join [lsort -dict [DrainListV1 $client $app]] \n]
	}
    }] show display
    return
}

proc ::stackato::cmd::query::Uprefix {ulist} {
    set res {}
    foreach u $ulist {
	lappend res http://$u
    }
    return $res
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::query 0

