# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations.
## Application management commands.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require browse
package require cd
package require dictutil
package require exec
package require json
package require lambda
package require sha1 2
package require fileutil::traverse
package require struct::list
package require struct::set
package require table
package require zipfile::decode
package require zipfile::encode
package require cmdr
package require cmdr::ask
package require cmdr::color
package require stackato::jmap
package require stackato::log
package require stackato::mgr::app
package require stackato::mgr::cfile
package require stackato::mgr::cgroup
package require stackato::mgr::client ;# pulled v2 in also
package require stackato::mgr::context
package require stackato::mgr::cspace
package require stackato::mgr::corg
package require stackato::mgr::ctarget
package require stackato::mgr::exit
package require stackato::mgr::framework
package require stackato::mgr::instmap
package require stackato::mgr::logstream
package require stackato::mgr::manifest
package require stackato::mgr::self
package require stackato::mgr::service
package require stackato::mgr::ssh
package require stackato::misc
package require stackato::validate::appname
package require stackato::validate::memspec
package require stackato::validate::routename
package require stackato::validate::stackname
package require stackato::validate::zonename

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::cmd {
    namespace export app
    namespace ensemble create
}
namespace eval ::stackato::cmd::app {
    namespace export \
	create delete push update map unmap health delete1 \
	start1 stop1 start stop restart logs crashlogs crashes \
	stats instances mem disk scale files tail run securecp \
	securesh dbshell open_browser env_list env_add env_delete \
	drain_add drain_delete drain_list rename map-urls \
	check-app-for-restart upload-files the-upload-manifest \
	list-events start-single activate migrate restage \
	restart-instance debug-dir
    namespace ensemble create

    namespace import ::cmdr::ask
    namespace import ::cmdr::color
    namespace import ::stackato::log::again+
    namespace import ::stackato::log::banner
    namespace import ::stackato::log::clear
    namespace import ::stackato::log::clearlast
    namespace import ::stackato::log::display
    namespace import ::stackato::log::err
    namespace import ::stackato::log::feedback
    namespace import ::stackato::log::psz
    namespace import ::stackato::log::quit
    namespace import ::stackato::log::uptime
    namespace import ::stackato::misc
    namespace import ::stackato::jmap
    namespace import ::stackato::mgr::app
    namespace import ::stackato::mgr::cfile
    namespace import ::stackato::mgr::cgroup
    namespace import ::stackato::mgr::client
    namespace import ::stackato::mgr::context
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::mgr::corg
    namespace import ::stackato::mgr::ctarget
    namespace import ::stackato::mgr::exit
    namespace import ::stackato::mgr::framework
    namespace import ::stackato::mgr::instmap
    namespace import ::stackato::mgr::logstream
    namespace import ::stackato::mgr::manifest
    namespace import ::stackato::mgr::self
    namespace import ::stackato::mgr::service
    namespace import ::stackato::mgr::ssh
    namespace import ::stackato::validate::appname
    namespace import ::stackato::validate::memspec
    namespace import ::stackato::validate::routename
    namespace import ::stackato::validate::stackname
    namespace import ::stackato::validate::zonename
    namespace import ::stackato::v2

    variable resetinfo "If needed use option --reset to apply the ignored local changes."
}

debug level  cmd/app
debug prefix cmd/app {[debug caller] | }
debug level  cmd/app/ignored
debug prefix cmd/app/ignored {[debug caller] | }
debug level  cmd/app/wait
debug prefix cmd/app/wait {[debug caller] | }
# TODO: FUTURE: Use levels to control detail?!

# # ## ### ##### ######## ############# #####################
## Command implementations.

proc ::stackato::cmd::app::the-upload-manifest {config} {
    # See also cmd/query:manifest.
    # TODO/FUTURE: Create a cmdr/manifest and proper procedures in
    # mgr/manifest for it, then move the debug commands over.

    manifest current= [$config @application] yes

    set mcfile [fileutil::tempfile stackato-mc-]
    cfile fix-permissions $mcfile 0644

    manifest currentInfo $mcfile [$config @tversion]

    set mdata [fileutil::cat $mcfile]
    file delete -- $mcfile

    puts $mdata
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::list-events {config} {
    debug.cmd/app {}

    if {![$config @application set?]} {
	# No application specified. Go for space listing.
	::stackato::cmd::app::ListEvents $config {}
	return
    }

    if {[$config @application] eq "."} {
	# Fake 'undefined' for 'user_1app' below, which then becomes
	# the current app as per the manifest.
	$config @application reset
    }

    manifest user_1app each $config ::stackato::cmd::app::ListEvents
    return
}

proc ::stackato::cmd::app::ListEvents {config theapp} {
    debug.cmd/app {}
    # V2 only.
    # client v2 = theapp is entity instance

    if {$theapp eq {}} {
	# Space set of events.
	debug.cmd/app {space events}

	set thespace [cspace get]
	if {$thespace eq {}} {
	    err "Unable to show space events. No space specified."
	}

	set events [$thespace @app_events]
	set label "For space [$thespace full-name]"
    } else {
	# Application set of events.
	debug.cmd/app {app events}
	set events [$theapp @events]
	set label "For application [$theapp @name]"
    }

    set events [v2 sort @timestamp $events -dict]

    if {[$config @json]} {
	debug.cmd/app {show json}
	set tmp {}
        foreach e $events {
	    lappend tmp [$e as-json]
	}
	display [json::write array {*}$tmp]
	return
    }

    debug.cmd/app {show table}
    display $label
    [table::do t {Time Instance Index Description Status} {
	foreach e $events {
	    $t add \
		[$e @timestamp] \
		[$e @instance_guid] \
		[$e @instance_index] \
		[$e @exit_description] \
		[$e @exit_status]
	}
    }] show display

    debug.cmd/app {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::rename {config} {
    debug.cmd/app {}
    manifest user_1app each $config ::stackato::cmd::app::Rename
    return
}

proc ::stackato::cmd::app::Rename {config theapp} {
    debug.cmd/app {}
    # V2 only.
    # client v2 = theapp is entity instance

    set new [$config @name]

    if {![$config @name set?]} {
	$config @name undefined!
    }
    if {$new eq {}} {
	err "An empty application name is not allowed"
    }

    display "Renaming application \[[color name [$theapp @name]]\] to '[color name $new]' ... " false
    $theapp @name set $new
    $theapp commit
    display [color good OK]

    debug.cmd/app {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::start {config} {
    debug.cmd/app {}

    # Higher user_all errors which leave the manifest mgr reset are
    # reported here, leaving the logstream inactive. Without this the
    # start1 sequence below may do that, breaking the logstream
    # stop. This way a 'no application' error bails us out in a way
    # which prevent the superfluous attempt at stopping without having
    # to figure out if a thrown error requires stopping or not.

    manifest user_all each $config {::stackato::mgr logstream start}

    try {
	# Reaching this the stream is active and requires stopping in
	# case of trouble.
	manifest user_all each $config ::stackato::cmd::app::start1
    } finally {
	manifest user_all each $config {::stackato::mgr logstream stop-m}
    }
    return
}

proc ::stackato::cmd::app::start1 {config theapp {push false}} {
    debug.cmd/app {}

    # client v1 = theapp is name
    # client v2 = theapp is entity instance

    set client [$config @client]

    if {[$client isv2]} {
	debug.cmd/app {/v2: $theapp ('[$theapp @name]' in [$theapp @space full-name] of [ctarget get])}
	# CFv2 API...
	StartV2 $config $theapp $push

    } else {
	debug.cmd/app {/v1: '$theapp'}
	# CFv1 API...
	StartV1 $config $theapp $push
    }
}

proc ::stackato::cmd::app::start-single {config theapp {push false}} {
    try {
	start1 $config $theapp $push
    } finally {
	logstream stop $config
    }
}

proc ::stackato::cmd::app::StartV2 {config theapp push} {
    debug.cmd/app {}
    # Note: app existence already verified by validation type.

    set appname [$theapp @name]

    if {[$theapp started?]} {
	display [color warning "Application '$appname' already started"]
	debug.cmd/app {/done, already started}
	return
    }

    display "Starting Application \[[color name $appname]\] ... "

    if {[$config @tail] && [[$config @client] is-stackato]} {
	# Start logyard streaming before sending the start request, to
	# avoid loss of the first log entries. Note that the logyard is
	# a stackato-specific feature.

	logstream start $config $theapp any ; # The one place where a non-fast log stream is ok.
    }

    debug.cmd/app {poke CC}
    try {
	$theapp start! ;#async
    } trap {STACKATO CLIENT V2 STAGING IN-PROGRESS} {e o} {
	display "    Staging in progress: $e"
    }  trap {STACKATO CLIENT V2 STAGING FAILED} {e o} {
	err $e
    }

    # Now loop and wait for the start to actually occur.
    # stream stop occurs inside (if necessary).

    WaitV2 $config $theapp $push

    set url [$theapp uri]
    if {$url ne {}} {
	set label "http://$url/ deployed"
    } else {
	set label "$appname deployed to [ctarget get]"
    }
    display $label
    return
}

proc ::stackato::cmd::app::WaitV2 {config theapp push {threshold -1}} {
    debug.cmd/app {}

    set timeout    [$config @timeout]
    set client     [$config @client]
    set appname    [$theapp @name]
    set imap       {}
    set start_time [clock seconds]

    debug.cmd/app {timeout  $timeout}
    debug.cmd/app {starting $start_time}

    # Use the standard CFv2 stager log if and only if no logyard
    # streaming is present and active, the target supports it as well,
    # and the user wanted logging at all.

    debug.cmd/app {CF log ?}
    debug.cmd/app {  @tail   = [$config @tail]}
    debug.cmd/app {  logyard = [logstream active]}
    debug.cmd/app {  x-a-s-l = [$theapp have-header x-app-staging-log]}
    debug.cmd/app {}

    if {($threshold < 0)    &&
	[$config @tail]     &&
	![logstream active] &&
	[$theapp have-header x-app-staging-log]} {
	WaitV2Log $theapp [$theapp header x-app-staging-log]
    }

    try {
	set hasstarted no
	set maxcounter 11
	set downcounter $maxcounter

	while 1 {
	    debug.cmd/app/wait {ping CC}

	    set s [clock clicks -milliseconds]
	    try {
		set imap [$theapp instances]
		debug.cmd/app/wait {map0 = $imap}

		set ni   [dict size $imap]
		set imap [DropOld $threshold $imap]
		debug.cmd/app/wait {map1 = $imap}

		set ignored [expr {$ni - [dict size $imap]}]
		debug.cmd/app/wait {ni = $ni, nleft = [dict size $imap], ignored = $ignored }

		if {![logstream active]} {
		    PrintStatusSummary $imap $ignored
		}

		if {[OneRunning $imap]} {
		    display [color good OK]
		    return
		}

	    } trap {STACKATO CLIENT V2 STAGING IN-PROGRESS} {e o} {
		debug.cmd/app/wait {staging in progress}
		# Staging in progress.
		if {[$config @tail] && ![logstream active]} {
		    display "    Staging in progress"
		}
	    }
	    set e [clock clicks -milliseconds]
	    set delta [expr {$e - $s}]

	    # Wait until at least one instance shows signs of starting
	    # before treating all-inactive as problem. At the
	    # beginning we have a period where all are down before
	    # getting started by the system.

	    set hasstarted [expr {$hasstarted || [AnyStarting $imap]}]
	    if {$hasstarted && [NoneActive $imap]} {
		debug.cmd/app/wait {all down @ $downcounter/$maxcounter}
		# All instances are DOWN, and we saw STARTING before.
		# NOTE: Do not abort immediately. This might be a
		# transient state, or bad reporting. We abort if and
		# only if we see this state maxcounter times
		# consecutively.
		incr downcounter -1
		if {$downcounter <= 0} {
		    debug.cmd/app {start failed ($downcounter)}
		    if {$push && [cmdr interactive?]} {
			display [color bad "Application failed to start"]
			if {[ask yn {Should I delete the application ? }]} {
			    if {[logstream active]} {
				logstream stop $config
			    }
			    app delete $config $client $theapp false
			}
		    }
		    err "Application failed to start"
		}
		debug.cmd/app/wait {all down - continue}
	    } else {
		debug.cmd/app/wait {down counter reset = $maxcounter}
		# Reset the failure counter, as we are either in the
		# initial down-phase, or at least one instance is
		# active (starting or running).
		set downcounter $maxcounter
	    }

	    # Limit waiting to a second, if we have to wait at all.
	    # (wait < 0 => delta was over a second spent on the REST call, don't wait with next query)
	    set wait [expr {1000 - $delta}]
	    if {$wait > 0} { After $wait }

	    # Reset the timeout while the log is active, i.e. new
	    # entries were seen since the last check here.
	    if {[logstream new-entries]} {
		debug.cmd/app/wait {timeout /reset}
		set start_time [clock seconds]
	    }

	    set delta [expr {[clock seconds] - $start_time}]
	    if {$delta > $timeout} {
		debug.cmd/app/wait {timeout /triggered}
		# Real time, as good as we can. Simply counting loop
		# iterations here is no good, as the loop itself may take
		# substantially longer than one second, especially when it
		# comes to tailing the startup log. Furthermore an unready
		# container imposes a multi-second wait as well before
		# timing out.

		try {
		    PrintStatusSummary [$theapp instances]
		} trap {STACKATO CLIENT V2 STAGING IN-PROGRESS} {e o} {
		    # Ignore stager issue now that we have timed out already.
		}
		err "Application is taking too long to start ($delta seconds since last log entry), check your logs"
	    }
	} ;# while
    } trap {STACKATO CLIENT V2 STAGING FAILED} {e o} {
	err "Application failed to stage: $e"
    } finally {
	debug.cmd/app/wait {stop log stream}

	if {[logstream active]} {
	    logstream stop $config
	}
    }

    debug.cmd/app/wait {/done}
    return
}

proc ::stackato::cmd::app::After {delay} {
    # Do a synchronous after with full execution of other events.
    # I.e. a plain after <delay> is not correct, as it suppresses
    # other events (file events = concurrent log stream rest
    # requests).

    after $delay {set ::stackato::cmd::app::ping .}
    vwait ::stackato::cmd::app::ping
    return
}

proc ::stackato::cmd::app::WaitV2Log {theapp url} {
    debug.cmd/app {}

    set size 0
    while {1} {
	try {
	    lassign [[$theapp client] http_get_raw $url] code data headers
	    set data  [string range  $data $size end]
	    set new   [string length $data]

	    if {!$new} { after 100 ; continue }
	    incr size $new

	    puts -nonewline stdout $data
	    flush stdout
	} trap {REST HTTP 404} {e o} {
	    break ; #the loop
	}
    }

    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::DropOld {threshold imap} {
    debug.cmd/app/wait {}
    if {$threshold < 0} {
	debug.cmd/app/wait {no filtering}
	return $imap
    }

    debug.cmd/app/wait {drop any before [Epoch $threshold]}
    set tmp {}
    dict for {n i} $imap {
	set since [$i since]
	debug.cmd/app/wait {has [format %2d $n] $i [format %.4f $since] = [Epoch $since]}

	if {$since <= $threshold} continue
	dict set tmp $n $i
    }
    return $tmp
}

proc ::stackato::cmd::app::Youngest {imap} {
    debug.cmd/app/wait {}
    set threshold -1
    dict for {n i} $imap {
	set since [$i since]
	debug.cmd/app/wait {max [format %2d $n] $i [format %.4f $since] = [Epoch $since]}

	if {$since <= $threshold} continue
	set threshold $since
    }

    debug.cmd/app/wait {==> $threshold ([Epoch $threshold])}
    return $threshold
}

proc ::stackato::cmd::app::AnyFlapping {imap} {
    debug.cmd/app/wait {}
    dict for {n i} $imap {
	if {[$i flapping?]} { return yes }
    }
    return no
}

proc ::stackato::cmd::app::AnyStarting {imap} {
    debug.cmd/app/wait {}
    dict for {n i} $imap {
	if {[$i starting?]} { return yes }
    }
    return no
}

proc ::stackato::cmd::app::NoneActive {imap} {
    debug.cmd/app/wait {}
    # Has (Starting|Running) <=> All (Flapping|Down)
    dict for {n i} $imap {
	if {[$i starting?]} { return no }
	if {[$i running?]}  { return no }
    }
    return yes
}

proc ::stackato::cmd::app::AllRunning {imap} {
    debug.cmd/app/wait {}
    dict for {n i} $imap {
	if {![$i running?]} { return no }
    }
    return yes
}

proc ::stackato::cmd::app::OneRunning {imap} {
    debug.cmd/app/wait {}
    dict for {n i} $imap {
	if {[$i running?]} { return yes }
    }
    return no
}

proc ::stackato::cmd::app::PrintStatusSummary {imap {ignored 0}} {
    debug.cmd/app/wait {}
    # Gather: total instances, plus counts of the various states. Make a report.

    if {$ignored > 0} {
	set suffix " [color red "\[$ignored\]"]"
    } else {
	set suffix {}
    }

    set all 0
    foreach s [v2 appinstance states] { dict set count $s 0 }

    dict for {n i} $imap {
	dict incr count	[$i state]
	incr all
    }

    set ok [dict get $count RUNNING]
    dict unset count RUNNING

    set sum {}
    foreach s [v2 appinstance states] {
	if {![dict exists $count $s]} continue
	set c [dict get $count $s]
	if {$c == 0} continue
	lappend sum [StateColor $s "$c [string tolower $s]"]
    }

    display "    $ok/$all instances: [join $sum {, }]$suffix"
    return
}

proc ::stackato::cmd::app::StateColor {s text} {
    switch -exact -- $s {
	DOWN     { set text [color bad     $text] }
	FLAPPING { set text [color bad     $text] }
	STARTING { set text [color neutral $text] }
	RUNNING  { set text [color good    $text] }
	default  {}
    }
    return $text
}

proc ::stackato::cmd::app::StartV1 {config appname push} {
    debug.cmd/app {}

    set timeout [$config @timeout]
    set client  [$config @client]

    set app [$client app_info $appname]
    if {$app eq {}} {
	display [color bad "Application '$appname' could not be found"]
	return
    }

    if {"STARTED" eq [dict getit $app state]} {
	display [color warning "Application '$appname' already started"]
	return
    }

    # The regular client messages are disabled if we are displaying
    # the app log stream side-by-side. This stream also includes
    # staging/starting events (among others)

    if {![logstream get-use $client]} {
	set banner "Staging Application \[[color name $appname]\] on \[[color name [Context $client]]\] ... "
	display $banner false
    }

    logstream start $config $appname any ; # The one place where a non-fast log stream is ok.

    debug.cmd/app {REST request STARTED...}
    dict set app state STARTED
    $client update_app $appname $app

    if {![logstream get-use $client]} {
	display [color good OK]
    }

    logstream stop $config slow

    if {![logstream get-use $client]} {
	set banner "Starting Application \[[color name $appname]\] on \[[color name [Context $client]]\] ... "
	display $banner false
    }

    set count 0
    set log_lines_displayed 0
    set failed false
    set start_time [clock seconds]

    debug.cmd/app {timeout  $timeout}
    debug.cmd/app {starting $start_time}

    while {1} {
	if {![logstream active] &&
	    ($count <= [app ticker])} {
	    display . false
	}

	After [expr {1000 * [app base]}]

	try {
	    if {[client app-started-properly? \
		     $client $appname \
		     [expr {$count > [app health]}]]} break

	    if {[llength [CrashInfo $config $appname false $start_time]]} {
		# Check for the existence of crashes
		if {[logstream active]} {
		    logstream stop $config
		    display [color bad "\nError: Application \[$appname\] failed to start, see log above.\n"]
		} else {
		    display [color bad "\nError: Application \[$appname\] failed to start, logs information below.\n"]
		    GrabCrashLogs $config $appname 0 true yes
		}
		if {$push} {
		    display ""
		    if {[cmdr interactive?]} {
			if {[ask yn {Should I delete the application ? }]} {
			    app delete $config $client $appname false
			}
		    }
		}
		set failed true
		break
	    } elseif {$count > [app tail]} {
		set log_lines_displayed \
		    [GrabStartupTail $client $appname $log_lines_displayed]
	    }
	} trap SIGTERM           {e o} - \
	  trap {TERM INTERUPT}   {e o} - \
	  trap {STACKATO CLIENT} {e o} - \
	  trap {REST HTTP}       {e o} - \
	  trap {REST SSL}        {e o} - \
	  trap {HTTP URL}        {e o} {
	    return {*}$o $e

	} on error e {
	    # Rethrow as internal error, with a full stack trace.
	    return -code error -errorcode {STACKATO CLIENT INTERNAL} \
		[list $e $::errorInfo $::errorCode]
	}

	incr count

	# Reset the timeout while the log is active, i.e. new
	# entries were seen since the last check here.
	if {[logstream new-entries]} {
	    set start_time [clock seconds]
	}

	set delta [expr {[clock seconds] - $start_time}]
	if {$delta > $timeout} {
	    # Real time, as good as we can. Simply counting loop
	    # iterations here is no good, as the loop itself may take
	    # substantially longer than one second, especially when it
	    # comes to tailing the startup log. Furthermore an unready
	    # container imposes a multi-second wait as well before
	    # timing out.

	    display "[color warning "\nApplication"] '[color name $appname]' [color warning "is taking too long to start ($delta seconds), check your logs"]"
	    set failed 1
	    break
	}
    } ;# while 1

    if {[logstream active]} {
	logstream stop $config
    }

    if {$failed} {
	#checker -scope line exclude badInt
	exit quit
    }

    if {![logstream get-use $client]} {
	if {[feedback]} {
	    clear
	    display "$banner[color good OK]"
	} else {
	    display [color good OK]
	}
    } else {
	set url [lindex [dict get $app uris] 0]
	if {$url ne {}} {
	    set label "http://$url/ deployed"
	} else {
	    set label "$appname deployed to [ctarget get]"
	}
	display $label
    }
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::activate {config} {
    debug.cmd/app {}
    manifest user_1app each $config ::stackato::cmd::app::Activate
    return
}

proc ::stackato::cmd::app::Activate {config theapp} {
    # Support for versioning is checked in the 'appversion' validation
    # type used for the @version validation.

    set theversion [$config @appversion]
    set codeonly   [$config @code-only]

    display "Switching to version [$theversion name] of [$theapp @name] ..." false
    $theversion activate $codeonly
    display [color good OK]
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::stop {config} {
    debug.cmd/app {}
    manifest user_all each $config ::stackato::cmd::app::stop1 1
    return
}

proc ::stackato::cmd::app::stop1 {config theapp} {
    debug.cmd/app {}

    # client v1 = theapp is name
    # client v2 = theapp is entity instance

    set client [$config @client]

    if {[$client isv2]} {
	debug.cmd/app {/v2: $theapp ('[$theapp @name]' in [$theapp @space full-name] of [ctarget get])}
	# CFv2 API...
	StopV2 $config $theapp

    } else {
	debug.cmd/app {/v1: '$theapp'}
	# CFv1 API...
	StopV1 $config $theapp
    }

    debug.cmd/app {/done}
}

proc ::stackato::cmd::app::StopV2 {config theapp} {
    debug.cmd/app {}
    # Note: app existence already verified by validation type.

    set appname [$theapp @name]

    if {[$theapp stopped?]} {
	display "[color warning "Application"] '[color name $appname]' [color warning "already stopped"]"
	debug.cmd/app {/done, already stopped}
	return
    }

    display "Stopping Application \[[color name $appname]\] ... " false
    $theapp stop!
    display [color good OK]

    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::StopV1 {config appname} {
    debug.cmd/app {}

    set client [$config @client]

    set app [$client app_info $appname]
    if {$app eq {}} {
	display [color bad "Application '$appname' could not be found"]
	debug.cmd/app {/done, invalid}
	return
    }

    if {"STOPPED" eq [dict getit $app state]} {
	display "[color warning "Application"] '[color name $appname]' [color warning "already stopped"]"
	debug.cmd/app {/done, already stopped}
	return
    }

    if {![logstream get-use $client]} {
	display "Stopping Application \[[color name $appname]\] ... " false
    }

    dict set app state STOPPED
    logstream start $config $appname

    $client update_app $appname $app

    logstream stop $config

    if {![logstream get-use $client]} {
	display [color good OK]
    }

    debug.cmd/app {/done, ok}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::restage {config} {
    debug.cmd/app {}

    # Required
    # config @application (single)
    # config @client

    # Assert single-ness. Need different code here for multiple apps
    # chosen by user.
    if {[$config @application list]} {
	[$config @client] internal "Unexpected list-type @application"
    }

    # Notes:

    # - If the user specified the application to operate on then all
    #   calls of 'user_all' will use exactly that application.

    # - Otherwise the system operates on all applications in the manifest.
    #   The user will not be asked for a name if no applications are found.
    #   That is a fail case. Similarly if there apps in the manifest, but
    #   without name.

    manifest user_all each $config {::stackato::mgr logstream start}
    try {
	manifest user_all each $config ::stackato::cmd::app::Restage
    } finally {
	manifest user_all each $config {::stackato::mgr logstream stop-m}
    }

    debug.cmd/app {OK}
    return
}

proc ::stackato::cmd::app::Restage {config theapp} {
    debug.cmd/app {}
    # client v2 = theapp is entity instance

    set client [$config @client]

    debug.cmd/app {/v2: $theapp ('[$theapp @name]' in [$theapp @space full-name] of [ctarget get])}

    set appname [$theapp @name]

    display "Restaging application \[[color name $appname]\] ... " false
    $theapp restage!
    display [color good OK]

    debug.cmd/app {/done}
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::migrate {config} {
    debug.cmd/app {}

    # Required
    # config @application (single)
    # config @client

    # Assert single-ness. Need different code here for multiple apps
    # chosen by user.
    if {[$config @application list]} {
	[$config @client] internal "Unexpected list-type @application"
    }

    # See also '::stackato::validate::instance::default'
    if {[$config @application] eq "."} {
	# Fake 'undefined' for 'user_all' below.
	$config @application reset
    }

    manifest user_all each $config ::stackato::cmd::app::Migrate

    debug.cmd/app {OK}
    return
}

proc ::stackato::cmd::app::Migrate {config theapp} {
    debug.cmd/app {}
    # client v2 = theapp is entity instance

    set client [$config @client]

    debug.cmd/app {/v2: $theapp ('[$theapp @name]' in [$theapp @space full-name] of [ctarget get])}

    set appname  [$theapp @name]
    set dstspace [$config @destination]

    display "Migrating Application \[[color name $appname]\] to '[color name [$dstspace full-name]]' ... " false
    $theapp migrate! $dstspace
    display [color good OK]

    debug.cmd/app {/done}
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::restart {config} {
    debug.cmd/app {}

    # Required
    # config @application (single)
    # config @client

    # Assert single-ness. Need different code here for multiple apps
    # chosen by user.
    if {[$config @application list]} {
	[$config @client] internal "Unexpected list-type @application"
    }

    # Notes:
    # - If the user specified the application to operate on then all
    #   calls of 'user_all' will use exactly that application.
    # - Otherwise the system operates on all applications in the manifest.
    #   The user will not be asked for a name if no applications are found.
    #   That is a fail case. Similarly if there apps in the manifest, but
    #   without name.

    manifest user_all each $config {::stackato::mgr logstream start}

    try {
	manifest user_all each $config ::stackato::cmd::app::stop1 1
	manifest user_all each $config ::stackato::cmd::app::start1
    } finally {
	manifest user_all each $config {::stackato::mgr logstream stop-m}
    }

    debug.cmd/app {OK}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::restart-instance {config} {
    debug.cmd/app {}

    # Required
    # config @application (single)
    # config @client

    # Assert single-ness. Need different code here for multiple apps
    # chosen by user.
    if {[$config @application list]} {
	[$config @client] internal "Unexpected list-type @application"
    }

    # Notes:
    # - If the user specified the application to operate on then all
    #   calls of 'user_all' will use exactly that application.
    # - Otherwise the system operates on all applications in the manifest.
    #   The user will not be asked for a name if no applications are found.
    #   That is a fail case. Similarly if there apps in the manifest, but
    #   without name.

    manifest user_all each $config {::stackato::mgr logstream start}

    try {
	manifest user_all each $config ::stackato::cmd::app::RestartInstance
    } finally {
	manifest user_all each $config {::stackato::mgr logstream stop-m}
    }

    debug.cmd/app {OK}
    return
}

proc ::stackato::cmd::app::RestartInstance {config theapp} {
    debug.cmd/app {}

    set appname  [$theapp @name]
    set instance [$config @theinstance]
    set index    [$instance index]

		logstream start $config $theapp any ; # A place where a non-fast log stream is ok.

    display "Restarting instance [color name $index] of application \[[color name $appname]\] ... "
    $instance restart

    LogUnbound $config {*Instance is ready*}
    # OK (or warning) generated by LogUnbound.
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::check-app-for-restart {config theapp} {
    debug.cmd/app {}

    set client [$config @client]

    # client v1 = theapp is name
    # client v2 = theapp is entity instance

    if {[$client isv2]} {
	if {![$theapp started?]} {
	    display [color good OK]
	    return
	}
    } else {
	set app [$client app_info $theapp]

	if {[dict getit $app state] ne "STARTED"} {
	    display [color good OK]
	    return
	}
    }

    display ""
    Restart1 $config $theapp
    # @application, @client
    return
}

proc ::stackato::cmd::app::Restart1 {config theapp} {
    debug.cmd/app {}

    logstream start $config $theapp

    try {
	 stop1  $config $theapp
	 start1 $config $theapp
    } finally {
	logstream stop $config
    }

    debug.cmd/app {OK}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::logs {config} {
    debug.cmd/app {}
    set client [$config @client]

    if {[logstream isfast $config]} {
	manifest user_1app each $config ::stackato::cmd::app::LogsStream
    } else {
	manifest user_1app each $config ::stackato::cmd::app::LogsFiles
    }
    return
}

proc ::stackato::cmd::app::LogsStream {config theapp} {
    debug.cmd/app {}

    # Convert the external config object into the dictionary expected
    # by the manager.

    # See also ::stackato::mgr::logstream::start (consolidate)
    dict set mconfig _config   $config
    dict set mconfig client    [$config @client]
    dict set mconfig json      [$config @json]
    dict set mconfig nosts     [$config @no-timestamps]
    dict set mconfig pattern   [$config @source]
    dict set mconfig pinstance [expr {[$config @instance set?] ? [$config @instance] : ""}]
    dict set mconfig pnewer    [$config @newer]
    dict set mconfig plogfile  [$config @filename]
    dict set mconfig plogtext  [$config @text]
    dict set mconfig max       [$config @num]
    dict set mconfig appname   $theapp ;# name or entity, per CF version
    dict set mconfig sysname   [dict get' [[$config @client] info] name stackato]

    if {[$config @follow]} {
	debug.cmd/app {/follow aka tail}
	# Disable 'Interupted' output for ^C
	#checker -scope line exclude badInt
	exit trap-term-silent

	logstream tail $mconfig
	return
    }

    # Single-shot log retrieval...
    debug.cmd/app {/single-shot}
    logstream show1 $mconfig
    return
}

proc ::stackato::cmd::app::LogsFiles {config appname} {
    debug.cmd/app {}
    # @all, @instance - Exclusionary

    if {[$config @all]} {
	return [GrabAllLogs $config $appname]
    }

    set instance [$config @instance]
    GrabLogs $config $appname $instance
}

proc ::stackato::cmd::app::GrabAllLogs {config appname} {
    debug.cmd/app {}

    set client                  [$config @client]
    set instances_info_envelope [$client app_instances $appname]

    # @todo what else can instances_info_envelope be ? Hash map ?
    # if instances_info_envelope.is_a?(Array)      return

    set instances_info [dict get' $instances_info_envelope instances {}]
    foreach entry $instances_info {
	GrabLogs $config $appname [dict getit $entry index]
    }

    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::GrabLogs {config appname instance} {
    debug.cmd/app {}

    set client [$config @client]
    set prefix [$config @prefix]

    foreach path [LogFilePaths $client $appname $instance \
		      /logs] {
	set content {}
	try {
	    set content [$client app_files $appname $path $instance]
	    DisplayLogfile $prefix $path $content $instance

	} trap {STACKATO CLIENT NOTFOUND} {e o} {
	    display [color bad $e]
	} trap {STACKATO CLIENT TARGETERROR} {e o} {
	    if {[string match *retrieving*404* $e]} {
		display [color bad "($instance)$path: No such file or directory"]
	    }
	} on error {e o} {
	    # nothing, continue
	}
    }

    debug.cmd/app {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::crashlogs {config} {
    debug.cmd/app {}
    manifest user_1app each $config ::stackato::cmd::app::CrashLogs
    return
}

proc ::stackato::cmd::app::CrashLogs {config appname} {
    debug.cmd/app {}
    GrabCrashLogs $config $appname [$config @instance]
    return
}

proc ::stackato::cmd::app::GrabCrashLogs {config appname instance {was_staged false} {tailed no}} {
    debug.cmd/app {}

    # stage crash info
    if {!$was_staged} {
	CrashInfo $config $appname false
    }

    if {[logstream isfast $config]} {
	# Like s logs...
	LogsStream $config $appname
	return
    }

    # else: pre-2.3 log retrieval (files).

    if {$instance eq {}} { set instance 0 }

    set client [$config @client]
    set prefix [$config @prefix]

    set map [instmap get]
    set instance [dict get' $map $instance $instance]

    foreach path [LogFilePaths $client $appname $instance \
		      /logs /app/logs /app/log] {
	if {$tailed && [string match *staging* $path]} continue

	set content {}
	try {
	    set content [$client app_files $appname $path $instance]
	    DisplayLogfile $prefix $path $content $instance

	} trap {STACKATO CLIENT NOTFOUND} {e o} {
	    display [color bad $e]
	} trap {STACKATO CLIENT TARGETERROR} {e o} {
	    if {[string match *retrieving*404* $e]} {
		display [color bad "($instance)$path: No such file or directory"]
	    }
	} on error {e o} {
	    # nothing, continue
	}
    }
}

proc ::stackato::cmd::app::GrabStartupTail {client appname {since 0}} {
    debug.cmd/app {}

    try {
	set new_lines 0
	set path "logs/stderr.log"
	set content [$client app_files $appname $path]

	if {$content ne {}} {
	    if {$since < 0} {
		# Late file appearance, start actual tailing.
		set since 0
	    }
	    if {!$since} {
		display "\n==== displaying stderr log ====\n\n"
	    }

	    set response_lines [split $content \n]
	    set tail           [lrange $response_lines $since end]
	    set new_lines      [llength $tail]

	    if {$new_lines} {
		display [join $tail \n]
	    }
	}

	incr since $new_lines
    } trap {STACKATO CLIENT TARGETERROR} {e o} {
	# do not modify 'since' (== 0)
	# ignore error, hope that this is a transient condition
    } trap {STACKATO CLIENT NOTFOUND} {e o} {
	if {$since >= 0} {
	    display [color bad $e]
	    display "Continuing to watch for its appearance..."
	}
	return -1
    }

    return $since
}

proc ::stackato::cmd::app::DisplayLogfile {prefix path content {instance 0} {banner {}}} {
    debug.cmd/app {}
    if {$banner eq {}} { set banner  "====> $path <====" }
    if {$content eq {}} return
    
    display $banner

    if {$prefix} {
	set prefix [color neutral "\[$instance: $path\] -"]
	foreach line [split [string trimright $content] \n] {
	    display "$prefix $line"
	}
    } else {
	display [string trimright $content]
    }
    display {}      
}

proc ::stackato::cmd::app::LogFilePaths {client appname instance args} {
    debug.cmd/app {}
    set res {}
    foreach path $args {
	catch {
	    set content [$client app_files $appname $path $instance]
	    foreach line [split $content \n] {
		# Lines are of the format <filename><spaces><size>.
		#
		# As the <filename> may contain spaces as well (*)
		# I look for the last one, which is just before
		# <size>, then chop this off and trim the
		# remaining spaces found after the <filename>.
		# Without (*) I could have simply done
		# [lindex $line 0]. Which seems to be done by vmc.

		lappend res \
		    $path/[string trimright \
			       [string range $line 0 \
				    [string last { } $line]]]
	    }
	}
    }
    return $res
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::crashes {config} {
    debug.cmd/app {}
    manifest user_1app each $config ::stackato::cmd::app::Crashes
    return
}

proc ::stackato::cmd::app::Crashes {config theapp} {
    debug.cmd/app {}
    # config @client, @json
    return [CrashInfo $config $theapp]
}

proc ::stackato::cmd::app::CrashInfo {config theapp {print_results true} {since 0}} {
    debug.cmd/app {}

    # client v1 = theapp is name
    # client v2 = theapp is entity instance

    set client [$config @client]

    if {[$client isv2]} {
	debug.cmd/app {/v2: $theapp ('[$theapp @name]' in [$theapp @space full-name] of [ctarget get])}
	# CFv2 API...
	set crashed [$theapp crashes]
	set appname [$theapp @name]
    } else {
	debug.cmd/app {/v1: '$theapp'}
	# CFv1 API...
	set crashed [dict getit [$client app_crashes $theapp] crashes]
	set appname $theapp
    }

    # list (dict (instance since))

    set crashed [struct::list filter $crashed [lambda {since c} {
	expr { [dict getit $c since] >= $since }
    } $since]]

    set instance_map {}

    # return display JSON.pretty_generate(apps) if @options[:json]

    set crashed [lsort -command [lambda {a b} {
	expr {int ([dict getit $a since] - [dict getit $b since])}
    }] $crashed]

    # TODO: crashinfo - Optimize a bit, to not generate the table when not needed.

    set counter 0
    table::do t {Name {Instance ID} {Crashed Time}} {
	foreach crash $crashed {
	    incr counter
	    set name "${appname}-$counter"

	    set instance [dict getit $crash instance]
	    set since    [Epoch [dict getit $crash since]]

	    dict set instance_map $name $instance

	    $t add $name $instance $since
	}
    }

    instmap set $instance_map
    instmap save

    if {$print_results} {
	if {[$config @json]} {
	    $t destroy
	    display [jmap crashed $crashed]
	    return
	} else {
	    display ""
	    if {![llength $crashed]} {
		display "No crashed instances for \[[color name $appname]\]"
		$t destroy
	    } else {
		$t show display
	    }
	}
    }

    return $crashed
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::delete {config} {
    debug.cmd/app {}

    # config @client
    # config @application - list
    # config @force
    # config @all

    set client [$config @client]
    set force  [$config @force]
    set all    [$config @all]

    # Check for and handle deletion of --all applications.
    if {$all} {
	set thespace      [cspace get]
	set should_delete [expr {$force || ![cmdr interactive?]}]
	if {!$should_delete} {
	    if {[$client isv2]} {
		if {$thespace eq {}} {
		    err "Unable to delete apps in the space. No space specified."
		}
	    }
	    set msg "Delete [color note ALL] Applications from \[[color name [Context $client]]\] ? "
	    set should_delete [ask yn $msg no]
	}
	if {$should_delete} {
	    if {[$client isv2]} {
		if {$thespace eq {}} {
		    err "Unable to delete apps in the space. No space specified."
		}
		set thespace [cspace get]
		set apps [$thespace @apps]
		foreach app $apps {
		    app delete $config $client $app $force
		}
	    } else {
		set apps [$client apps]
		foreach app $apps {
		    app delete $config $client [dict getit $app name] $force
		}
	    }
	}
	return
    }

    # Delete user choices, or single app from manifest.
    # Multiple apps in manifest cause abort.

    manifest user_1app each $config \
	[list ::stackato::cmd::app::Delete $force 0]

    return
}

proc ::stackato::cmd::app::delete1 {config theapp} {
    debug.cmd/app {}
    Delete 0 0 $config $theapp
    return
}

proc ::stackato::cmd::app::Delete {force rollback config theapp} {
    debug.cmd/app {}
    set client [$config @client]
    app delete $config $client $theapp $force $rollback
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::map {config} {
    # config @application
    # config @url
    debug.cmd/app {}
    manifest user_1app each $config ::stackato::cmd::app::Map
    return
}

proc ::stackato::cmd::app::Map {config theapp} {
    debug.cmd/app {}

    set client [$config @client]

    if {[$client isv2]} {
	# client v2 = theapp is entity instance
	Map2 $config $theapp
    } else {
	# client v1 = theapp is name
	Map1 $config $theapp
    }

    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::Map1 {config appname} {
    # CFv1 API...
    debug.cmd/app {}

    set client [$config @client]
    set app    [$client app_info $appname]

    display "Application \[[color name $appname]\] ... "

    set n [llength [$config @url]]

    foreach url [lsort -dict [$config @url]] {
	set url [string tolower $url]
	debug.cmd/app {+ url = $url}
	dict lappend app uris $url

	display "  Map http://$url"
    }

    display "Commit ..."
    $client update_app $appname $app

    MapFinal mapped $n
    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::Map2 {config theapp} {
    # CFv2 API...
    set appname [$theapp @name]
    debug.cmd/app {$theapp ('$appname' in [$theapp @space full-name] of [ctarget get])}

    display "Application \[[color name [$theapp @name]]\] ... "

    set n [llength [$config @url]]

    map-urls $config $theapp [$config @url]

    MapFinal mapped $n
    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::map-urls {config theapp urls {rollback 0} {sync 1}} {
    debug.cmd/app {}

    if {$sync} {
	foreach url [lsort -dict $urls] {
	    set url [string tolower $url]
	    display "  Map http://$url ... " false

	    debug.cmd/app {+ url = $url}

	    set route [Url2Route $config $theapp $url $rollback]

	    debug.cmd/app {      = $route (in [$route @space full-name])}

	    $theapp @routes add $route

	    debug.cmd/app {+ ----- done}
	    display [color good OK]
	}
    } else {
	# No mapping to be done.
	foreach url [lsort -dict $urls] {
	    set url [string tolower $url]
	    debug.cmd/app {I url = $url}

	    display "  Map http://$url ... (Change Ignored)"
	}
    }

    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::unmap-urls {config theapp urls {sync 1}} {
    debug.cmd/app {}

    foreach url [lsort -dict $urls] {
	set url [string tolower $url]
	debug.cmd/app {- url = $url}

	if {$sync} {
	    display "  Unmap http://$url ... " false

	    set r [routename validate [$config @url self] $url]
	    $theapp @routes remove $r
	    display [color good OK]
	} else {
	    display "  Unmap http://$url ... (Change Ignored)"
	}
    }

    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::kept-urls {theapp urls {sync 1}} {
    debug.cmd/app {}

    foreach u $urls {
	display "  Kept  http://$u ... "
    }

    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::Url2Route {config theapp url rollback} {
    debug.cmd/app {}

    # The url can be host+domain, or just a domain.  In case of the
    # latter we create a route "" which the target will fill for us
    # with a proper name.

    set thedomain [GetDomain $url]
    if {$thedomain ne {}} {
	# url = domain
	set host ""
	set domain $url
    } else {
	# url = host+domain, split into parts
	set url    [split $url .]
	set host   [lindex $url 0 ]
	set domain [join [lrange $url 1 end] .]

	set thedomain [GetDomain $domain]
	if {$thedomain eq {}} {
	    set space [[cspace get] @name]

	    # The error message is dependent on the target-version, as
	    # that determines which of two sets of cli commands govern
	    # the handling of domains
	    # (3.0: map|unmap, and 3.2: create|delete).

	    if {[package vsatisfies [[$config @client] server-version] 3.1]} {
		# 3.2+ => Domains are handled at org-level with "create-domain".
		set cmd   create-domain
		set wherelong  "org '[[corg get] @name]'"
		set whereshort $wherelong
	    } else {
		# 3.0 => Domains are handled at space-level with "map-domain".
		set cmd   map-domain
		set wherelong  "space '$space'"
		set whereshort "space"
	    }

	    set matches [llength [v2 domain list-by-name $domain]]
	    if {$matches} {
		# domain exists, not mapped into the space.
		set msg "Not mapped into the space '$space'. [self please $cmd] to add the domain to the $whereshort."
	    } else {
		# domains does not exist at all.
		set msg "Does not exist. [self please $cmd] to create the domain and add it to the $wherelong."
	    }
	    set msg "Unknown domain '$domain': $msg"
	    display "" ; # Force new line.
	    display [color bad $msg]

	    # Force application rollback, per caller's instruction.
	    if {$rollback} {
		Delete 0 1 $config $theapp
	    }

	    err "Reminder: $msg, forced the rollback"
	}
    }

    debug.cmd/app {host    = $host}
    debug.cmd/app {domain  = $domain}

    # 2. Find route by host(-name), in all routes (server-side),
    #    then filter by domain, locally.

    set routes [v2 route list-by-host $host 1]

    set routes [struct::list filter $routes [lambda {d o} {
	string equal $d [$o @domain @name]
    } $domain]]

    if {[llength $routes]} {
	debug.cmd/app {use existing route}
	set route [lindex $routes 0]
    } else {
	debug.cmd/app {create new route}

	set route [v2 route new]
	$route @domain set $thedomain
	$route @host   set $host
	$route @space  set [cspace get]
	$route commit
    }

    return $route
}

proc ::stackato::cmd::app::GetDomain {domain} {
    set matches [[cspace get] @domains filter-by @name $domain]
    # The list of domains mapped into a space should be small. The
    # fact that we are doing a client-side search/filter here should
    # therefore not be a scaling problem.
    if {[llength $matches] != 1} {
	return {}
    } else {
	return [lindex $matches 0]
    }
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::unmap {config} {
    # config @application
    # config @url
    debug.cmd/app {}
    manifest user_1app each $config ::stackato::cmd::app::Unmap
    return
}

proc ::stackato::cmd::app::Unmap {config theapp} {
    debug.cmd/app {}

    set client [$config @client]

    # client v1 = theapp is name
    # client v2 = theapp is entity instance

    if {[$client isv2]} {
	Unmap2 $config $theapp
    } else {
	Unmap1 $config $theapp
    }

    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::Unmap1 {config appname} {
    debug.cmd/app {}

    set client [$config @client]
    set app    [$client app_info $appname]

    set uris [dict get' $app uris {}]
    debug.cmd/app {uris = [join $uris \n\t]}

    display "Application \[[color name $appname]\] ... "

    set url [$config @url]
    set url [string tolower $url]
    regsub -nocase {^http(s*)://} $url {} url

    debug.cmd/app {- url = $url}

    display "  Unmap $url" false

    if {$url ni $uris} {
	display " ... " false
	err "Invalid url $url"
    }
    display ""
    struct::list delete uris $url

    dict set app uris $uris
    $client update_app $appname $app

    MapFinal unmapped 1
    return
}

proc ::stackato::cmd::app::Unmap2 {config theapp} {
    debug.cmd/app {}

    set appname [$theapp @name]

    display "Application \[[color name $appname]\] ... "

    debug.cmd/app {/regular}
    # Unmap the specified routes from the application.
    set route [$config @url]
    set name [$route name]

    display "  Unmap $name ... " false
    $theapp @routes remove $route
    display [color good OK]

    MapFinal unmapped 1
    return
}

proc ::stackato::cmd::app::MapFinal {action n} {
    display [color good "Successfully $action $n url[expr {$n==1 ? "":"s"}]"]
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::stats {config} {
    debug.cmd/app {}
    manifest user_all each $config ::stackato::cmd::app::Stats
    return
}

proc ::stackato::cmd::app::Stats {config theapp} {
    debug.cmd/app {}

    set client [$config @client]
    # v1 : theapp ==> name     (string)
    # v2 : theapp ==> instance (object)

    if {[$client isv2]} {
	StatsV2 $config $theapp
    } else {
	StatsV1 $config $client $theapp
    }
    return
}

proc ::stackato::cmd::app::StatsV1 {config client theapp} {
    debug.cmd/app {/v1: '$theapp'}
    # CFv1 API...

    set appname $theapp
    set stats   [misc sort-aod instance [$client app_stats $theapp] -dict]
    #@type stats = list (dict (*/string, usage/dict)) /@todo

    debug.cmd/app {= [jmap stats $stats]}

    if {[$config @json]} {
	display [jmap stats $stats]
	return
    }

    if {![llength $stats]} {
	display "[color warning "No running instances for"] \[[color name $appname]\]"
	return
    }

    display $appname
    [table::do t {Instance {CPU (Cores)} {Memory (limit)} {Disk (limit)} Uptime} {
	foreach entry $stats {
	    set index [dict getit $entry instance]
	    set stat  [dict getit $entry stats]
	    set hp    "[dict getit $stat host]:[dict getit $stat port]"

	    set uptime [uptime [dict getit $stat uptime]]
	    set usage [dict get' $stat usage {}]
	    if {$usage ne {}} {
		set cpu  [dict getit $usage cpu]
		set mem  [expr {[dict getit $usage mem] * 1024}] ;# mem usage comes in K's
		set disk [dict getit $usage disk]                ;# disk usage in B's
	    } else {
		set cpu  {}
		set mem  {}
		set disk {}
	    }
	    set mem_quota  [dict getit $stat mem_quota]  ; # mem/disk quotas are in B's
	    set disk_quota [dict getit $stat disk_quota]

	    set mem  "[psz $mem] ([psz $mem_quota 0])"
	    set disk "[psz $disk] ([psz $disk_quota 0])"

	    if {$cpu eq {}} { set cpu NA }
	    set cpu "$cpu% ([dict getit $stat cores])"

	    $t add $index $cpu $mem $disk $uptime
	}
    }] show display
    return
}

proc ::stackato::cmd::app::StatsV2 {config theapp} {
    debug.cmd/app {/v2: $theapp ('[$theapp @name]' in [$theapp @space full-name] of [ctarget get])}
    # CFv2 API...

    set appname [$theapp @name]
    set stats   [dict sort [$theapp stats]]

    debug.cmd/app {= [jmap v2-stats $stats]}

    if {[$config @json]} {
	display [jmap v2-stats $stats]
	return
    }

    if {![llength $stats]} {
	display "[color warning "No running instances"] for \[[color name $appname]\]"
	return
    }

    display [context format-short " -> $appname"]
    [table::do t {Instance State {CPU} {Memory (limit)} {Disk (limit)} Started Crashed Uptime} {
	foreach {index data} $stats {
	    set state [dict get $data state]

	    set stats [dict get' $data stats {}]
	    set crashed [dict get' $data since {}]
	    if {$crashed ne {}} {
		set crashed [Epoch $crashed]
	    }

	    if {$stats ne {}} {
		set uptime [uptime [dict get $stats uptime]]
		# Quotas are delivered in B (both mem and disk).
		set mq [psz [dict get $stats mem_quota]]
		set dq [psz [dict get $stats disk_quota]]

		set usage [dict get' $stats usage {}]
		if {$usage ne {}} {
		    set started [dict get $usage time]
		    # mem usage is delivered in B
		    # Ref bug 104709, see also
		    # https://github.com/ActiveState/stackato-cli/issues/2
		    # for a contrary opinion.
		    set m [psz [dict get $usage mem]]
		    # disk usage is delivered in B
		    set d [psz [dict get $usage disk]]
		    set cpu [dict get $usage cpu]

		} else {
		    set started N/A
		    set m N/A
		    set d N/A
		    set cpu N/A
		}
	    } else {
		set started {}
		set uptime N/A
		set m N/A ; set mq N/A
		set d N/A ; set dq N/A
		set cpu N/A
	    }

	    set mem   "$m ($mq)"
	    set disk  "$d ($dq)"

	    $t add $index [StateColor $state $state] \
		$cpu $mem $disk $started $crashed $uptime
	}
    }] show display
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::health {config} {
    debug.cmd/app {}

    # config @client
    # config @application - list
    # config @all

    set client [$config @client]
    set all    [$config @all]

    # Check for and handle reporting on --all applications.
    if {$all} {
	if {[$client isv2]} {
	    set apps [[cspace get] @apps]
	} else {
	    set apps [$client apps]
	}

	Health $config {*}$apps
	return
    }

    manifest user_all merge $config ::stackato::cmd::app::Health
    return
}

proc ::stackato::cmd::app::Health {config args} {
    debug.cmd/app {}
    # v1 - applist = names
    # v2 - applist = objects

    display [context format-short]

    set client [$config @client]

    if {[$client isv2]} {
	# @application = list of instances
	[table::do t {Application Health} {
	    foreach app [v2 sort @name $args -dict] {
		$t add [$app @name] [$app health]
	    }
	}] show display
    } else {
	[table::do t {Application Health} {
	    foreach appname [lsort -dict $args] {
		if {$appname eq {}} continue
		set app [$client app_info $appname]
		$t add $appname [misc health $app]
	    }
	}] show display
    }
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::scale {config} {
    # @application
    # @scale, @mem, @disk

    debug.cmd/app {}
    manifest user_all each $config ::stackato::cmd::app::Scale
    return
}

proc ::stackato::cmd::app::Scale {config theapp} {

    set client [$config @client]
    if {[$client isv2]} {
	set appname [$theapp @name]
	set appinfo {} ; # dummy
	# theapp = entity instance, contains the app data.
    } else {
	set appname $theapp
	set appinfo [$client app_info $appname]
    }

    set changes     0
    set needrestart 0

    ChangeInstances    $config $client $theapp appinfo changes
    ChangeMem          $config $client $theapp appinfo needrestart
    ChangeDisk         $config $client $theapp appinfo needrestart
    ChangeAutoScale    $config $client $theapp appinfo changes

    if {$changes || $needrestart} {
	display "Committing changes ... " \
	    [logstream get-use $client]

	logstream start $config $theapp

	if {[$client isv2]} {
	    $theapp commit
	} else {
	    $client update_app $appname $appinfo
	}

	if {![logstream get-use $client]} {
	    display [color good OK]
	}

	if {$needrestart && [AppIsRunning $config $theapp $appinfo]} {
	    debug.cmd/app {restart application}
	    Restart1 $config $theapp
	}

	logstream stop $config
    } else {
	display [color note {No changes}]
    }
    return
}

proc ::stackato::cmd::app::ChangeAutoScale {config client theapp av cv} {
    debug.cmd/app {}
    upvar 1 $av app $cv changes

    ChangeMinInstances $config $client $theapp app changes
    ChangeMaxInstances $config $client $theapp app changes
    ChangeMinThreshold $config $client $theapp app changes
    ChangeMaxThreshold $config $client $theapp app changes
    ChangeAutoEnabled  $config $client $theapp app changes

    debug.cmd/app {/done}
    return
}

# TODO: See if we can generalize the internals of these commands.
proc ::stackato::cmd::app::ChangeMinInstances {config client theapp av cv} {
    debug.cmd/app {}
    upvar 1 $av app $cv changes

    if {![$config @min-instances set?]} {
	debug.cmd/app {not set}
	return
    }
    if {![$client isv2]} {
	err "Client internal error. Should not be able to change this for an S2 target"
    }

    if {![$theapp @min_instances defined?]} {
	display "  Changing Application Min Instances not supported by target ..."
	return
    }

    # client v2 : theapp ==> instance (object)
    debug.cmd/app {/v2: $theapp ('[$theapp @name]' in [$theapp @space full-name] of [ctarget get])}

    set current [$theapp @min_instances]
    set new     [$config @min-instances]

    debug.cmd/app { current (app) = $current }
    debug.cmd/app { new     (cfg) = $new }

    if {$current == $new} {
	debug.cmd/app {/done /no-change}
	return
    }

    display "  Changing Application Min Instances to $new ..."

    $theapp @min_instances set $new
    incr changes

    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::ChangeMaxInstances {config client theapp av cv} {
    debug.cmd/app {}
    upvar 1 $av app $cv changes

    if {![$config @max-instances set?]} {
	debug.cmd/app {not set}
	return
    }
    if {![$client isv2]} {
	err "Client internal error. Should not be able to change this for an S2 target"
    }

    if {![$theapp @min_instances defined?]} {
	display "  Changing Application Max Instances not supported by target ..."
	return
    }

    # client v2 : theapp ==> instance (object)
    debug.cmd/app {/v2: $theapp ('[$theapp @name]' in [$theapp @space full-name] of [ctarget get])}

    set current [$theapp @max_instances]
    set new     [$config @max-instances]

    debug.cmd/app { current (app) = $current }
    debug.cmd/app { new     (cfg) = $new }

    if {$current == $new} {
	debug.cmd/app {/done /no-change}
	return
    }

    display "  Changing Application Max Instances to $new ..."

    $theapp @max_instances set $new
    incr changes

    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::ChangeMinThreshold {config client theapp av cv} {
    debug.cmd/app {}
    upvar 1 $av app $cv changes

    if {![$config @min-cpu set?]} {
	debug.cmd/app {not set}
	return
    }
    if {![$client isv2]} {
	err "Client internal error. Should not be able to change this for an S2 target"
    }

    if {![$theapp @min_instances defined?]} {
	display "  Changing Application Min CPU Threshold not supported by target ..."
	return
    }

    # client v2 : theapp ==> instance (object)
    debug.cmd/app {/v2: $theapp ('[$theapp @name]' in [$theapp @space full-name] of [ctarget get])}

    set current [$theapp @min_cpu_threshold]
    set new     [$config @min-cpu]

    debug.cmd/app { current (app) = $current }
    debug.cmd/app { new     (cfg) = $new }

    if {$current == $new} {
	debug.cmd/app {/done /no-change}
	return
    }

    display "  Changing Application Min CPU Threshold to $new ..."

    $theapp @min_cpu_threshold set $new
    incr changes

    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::ChangeMaxThreshold {config client theapp av cv} {
    debug.cmd/app {}
    upvar 1 $av app $cv changes

    if {![$config @max-cpu set?]} {
	debug.cmd/app {not set}
	return
    }
    if {![$client isv2]} {
	err "Client internal error. Should not be able to change this for an S2 target"
    }

    if {![$theapp @min_instances defined?]} {
	display "  Changing Application Max CPU Threshold not supported by target ..."
	return
    }

    # client v2 : theapp ==> instance (object)
    debug.cmd/app {/v2: $theapp ('[$theapp @name]' in [$theapp @space full-name] of [ctarget get])}

    set current [$theapp @max_cpu_threshold]
    set new     [$config @max-cpu]

    debug.cmd/app { current (app) = $current }
    debug.cmd/app { new     (cfg) = $new }

    if {$current == $new} {
	debug.cmd/app {/done /no-change}
	return
    }

    display "  Changing Application Max CPU Threshold to $new ..."

    $theapp @max_cpu_threshold set $new
    incr changes

    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::ChangeAutoEnabled {config client theapp av cv} {
    debug.cmd/app {}
    upvar 1 $av app $cv changes

    if {![$config @autoscale set?]} {
	debug.cmd/app {not set}
	return
    }

    if {![$client isv2]} {
	err "Client internal error. Should not be able to change this for an S2 target"
    }

    if {![$theapp @autoscale_enabled defined?]} {
	display "  Changing Application Autoscale not supported by target ..."
	return
    }

    # client v2 : theapp ==> instance (object)
    debug.cmd/app {/v2: $theapp ('[$theapp @name]' in [$theapp @space full-name] of [ctarget get])}

    set current [$theapp @autoscale_enabled]
    set new     [$config @autoscale]

    debug.cmd/app { current (app) = $current }
    debug.cmd/app { new     (cfg) = $new }

    # boolean, explicit xor to account for different string reps.
    if {( $current && $new) ||
	(!$current && !$new)} {
	debug.cmd/app {/done /no-change}
	return
    }

    display "  Changing Application Autoscale to $new ..."

    $theapp @autoscale_enabled set $new
    incr changes

    debug.cmd/app {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::instances {config} {
    # @application
    # @scale
    debug.cmd/app {}
    manifest user_all each $config ::stackato::cmd::app::Instances
    return
}

proc ::stackato::cmd::app::Instances {config theapp} {
    debug.cmd/app {}

    # client v1 : theapp ==> name     (string)
    # client v2 : theapp ==> instance (object)

    ShowInstances $config $theapp
    return
}

proc ::stackato::cmd::app::ChangeInstances {config client theapp av cv} {
    upvar 1 $av app $cv changes
    debug.cmd/app {}

    if {![$config @instances set?]} {
	debug.cmd/app {not set}
	return
    }

    # client v1 : theapp ==> name     (string)
    # client v2 : theapp ==> instance (object)

    if {[$client isv2]} {
	set appname [$theapp @name]
	debug.cmd/app {/v2: $theapp ('$appname' in [$theapp @space full-name] of [ctarget get])}
	# CFv2 API...

	set current_instances [$theapp @total_instances]
    } else {
	# CFv1 API...
	set appname $theapp
	# app provided by caller.
	set current_instances [dict getit $app instances]
    }

    set instances [$config @instances]

    # Number with sign is relative scaling.
    set relative [string match {[-+]*} [$config @instances string]]

    debug.cmd/app {relative=$relative}

    set new_instances \
	[expr {
	       $relative
	       ? $current_instances + $instances
	       : $instances}]

    if {$new_instances < 1} {
	err "There must be at least 1 instance."
    }

    debug.cmd/app { current = $current_instances }
    debug.cmd/app { new     = $new_instances }

    if {$current_instances == $new_instances} {
	return
    }

    set up_or_down [expr {$new_instances > $current_instances
			  ? "up"
			  : "down"}]

    display "  Scaling Application instances $up_or_down to $new_instances ..."

    if {[$client isv2]} {
	$theapp @total_instances set $new_instances
    } else {
	dict set app instances $new_instances
    }

    incr changes
    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::ShowInstances {config theapp} {
    debug.cmd/app {}

    set client [$config @client]
    # v1 : theapp ==> name     (string)
    # v2 : theapp ==> instance (object)

    if {[$client isv2]} {
	SIv2 $config $theapp
    } else {
	SIv1 $config $theapp $client
    }
    return
}

proc ::stackato::cmd::app::SIv1 {config theapp client} {
    debug.cmd/app {/v1: '$theapp'}
    # CFv1 API...

    set instances_info_envelope [$client app_instances $theapp]

    # @todo what else can instances_info_envelope be ? Hash map ?
    # if instances_info_envelope.is_a?(Array)      return

    set instances_info [dict get' $instances_info_envelope instances {}]
    #@type instances_info = list (dict) /@todo determine more.

    set instances_info [misc sort-aod index $instances_info -dict]

    if {[$config @json]} {
	display [jmap instances $instances_info]
	return
    }

    if {![llength $instances_info]} {
	display "[color warning "No running instances for"] \[[color name $theapp]\]"
	return
    }

    [table::do t {Index State {Start Time}} {
	foreach entry $instances_info {
	    set index [dict getit $entry index]
	    set state [dict getit $entry state]
	    set since [Epoch [dict getit $entry since]]
	    $t add $index [StateColor $state $state] $since
	}
    }] show display

    return
}

proc ::stackato::cmd::app::SIv2 {config theapp} {
    debug.cmd/app {/v2: $theapp ('[$theapp @name]' in [$theapp @space full-name] of [ctarget get])}
    # CFv2 API...

    try {
	set instances [$theapp instances]
    } trap {STACKATO CLIENT V2 STAGING IN-PROGRESS} {e o} {
	# Staging in progress.
	err "Unable to show instances: $e"
	return
    } trap {STACKATO CLIENT V2 STAGING FAILED} {e o} {
	err "Unable to show instances: Application failed to stage"
    }

    set instances [dict sort $instances -dict]

    if {[$config @json]} {
	dict for {k v} $instances {
	    dict set instances $k [$v as-json]
	}
	display [jmap v2-instances $instances]
	return
    }

    if {![llength $instances]} {
	display "[color warning "No running instances for"] \[[color name [$theapp @name]]\]"
	return
    }

    display [context format-short " -> [$theapp @name]"]
    [table::do t {Index State {Start Time}} {
	foreach {index i} $instances {
	    set state [$i state]
	    set since [Epoch [$i since]]

	    $t add $index [StateColor $state $state] $since
	}
    }] show display

    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::mem {config} {
    # @application
    # @mem
    debug.cmd/app {}
    manifest user_all each $config ::stackato::cmd::app::Mem
    return
}

proc ::stackato::cmd::app::Mem {config theapp} {
    debug.cmd/app {}

    # client v1 : theapp ==> name     (string)
    # client v2 : theapp ==> instance (object)

    set client [$config @client]

    if {[$client isv2]} {
	set appname      [$theapp @name]
	set current      [$theapp @memory]
    } else {
	set appname   $theapp
	set app       [$client app_info $theapp]
	debug.cmd/app {app info = [jmap appinfo $app]}
	set current   [dict getit $app resources memory]
    }

    set currfmt [memspec format $current]

    debug.cmd/app {current memory limit = $currfmt}

    display "Current Memory Reservation \[[color name $appname]\]: $currfmt"
    return
}

proc ::stackato::cmd::app::ChangeMem {config client theapp av cv} {
    upvar 1 $av app $cv changes
    debug.cmd/app {}

    if {![$config @mem set?]} return

    # @mem - New memory. In MB, full validated.

    # client v1 : theapp ==> name     (string)
    # client v2 : theapp ==> instance (object)

    if {[$client isv2]} {
	set appname      [$theapp @name]
	set current      [$theapp @memory]
	set numinstances [$theapp @total_instances]

    } else {
	set appname $theapp
	# app supplied by caller
	debug.cmd/app {app info = [jmap appinfo $app]}

	set current      [dict getit $app resources memory]
	set numinstances [dict getit $app instances]
    }

    set currfmt [memspec format $current]
    set memsize [$config @mem]

    set memfmt [memspec format $memsize]
    set delta  [expr {($memsize - $current)}] ;# per instance
    set dtotal [expr {$delta * $numinstances}]

    # memsize - MB, validated
    # current - MB
    # currfmt - formatted

    debug.cmd/app {current   quota/instance = $current}
    debug.cmd/app {                         = $currfmt}
    debug.cmd/app {requested quota/instance = $memsize}
    debug.cmd/app {                         = $memfmt}
    debug.cmd/app {quota delta/instance     = $delta}
    debug.cmd/app {                         = [memspec format $delta]}
    debug.cmd/app {instances                = $numinstances}
    debug.cmd/app {quota delta/total        = $dtotal}
    debug.cmd/app {                         = [memspec format $dtotal]}

    if {$memsize == $current} {
	return
    }

    display "  Updating Memory Reservation \[[color name $appname]\] to $memfmt ... "

    # check memsize here for capacity
    # in v2 this is done fully server side, no local check.
    if {![$client isv2]} {
	client check-capacity $client $dtotal mem
    }

    debug.cmd/app {reservation/instance changed $currfmt ==> $memfmt}

    if {[$client isv2]} {
	$theapp @memory set $memsize
    } else {
	dict set app resources memory $memsize
    }

    incr changes
    return
}

# Used only by App(Mem|Disk).
# Not used by Change(Mem|Disk) anymore.
proc ::stackato::cmd::app::InteractiveMemoryEntry {config slot type currfmt {label {}}} {
    debug.cmd/app {}

    if {$label eq {}} {
	set label "Enter $type Reservation \[$currfmt\]"
    }

    while {1} {
	set newfmt \
	    [ask string/extended "${label}: " \
		 -complete ::stackato::validate::memspec::complete]

	# Plain <Enter> ==> default.
	if {$newfmt eq {}} {
	    set newfmt $currfmt
	}

	debug.cmd/app {  user = $newfmt}

	if {![catch {
	    set new [stackato::validate memspec validate [$config $slot self] $newfmt]
	} msg]} break

	display "Expected memory (<int>, <int>M, <float>G), got \"$newfmt\": $msg"
    }

    return $new
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::disk {config} {
    # @application
    debug.cmd/app {}
    manifest user_all each $config ::stackato::cmd::app::Disk
    return
}

proc ::stackato::cmd::app::Disk {config theapp} {
    debug.cmd/app {}

    # client v1 : theapp ==> name     (string)
    # client v2 : theapp ==> instance (object)

    set client [$config @client]

    if {[$client isv2]} {
	set appname      [$theapp @name]
	set current      [$theapp @disk_quota]
    } else {
	set appname   $theapp
	set app       [$client app_info $theapp]
	debug.cmd/app {app info = [jmap appinfo $app]}
	set current   [dict getit $app resources disk]
    }

    set currfmt [memspec format $current]

    debug.cmd/app {current disk limit = $currfmt}

    display "Current Disk Reservation \[[color name $appname]\]: $currfmt"
    return
}

proc ::stackato::cmd::app::ChangeDisk {config client theapp av cv} {
    upvar 1 $av app $cv changes
    debug.cmd/app {}

    if {![$config @disk set?]} return

    # @disk - New disk. In MB, full validated.

    # client v1 : theapp ==> name     (string)
    # client v2 : theapp ==> instance (object)

    if {[$client isv2]} {
	set appname      [$theapp @name]
	set current      [$theapp @disk_quota]
	set numinstances [$theapp @total_instances]

    } else {
	set appname   $theapp
	# app supplied by caller
	debug.cmd/app {app info = [jmap appinfo $app]}

	set current      [dict getit $app resources disk]
	set numinstances [dict getit $app instances]
    }

    set currfmt [memspec format $current]
    set memsize [$config @disk]

    set memfmt [memspec format $memsize]
    set delta  [expr {($memsize - $current)}] ;# per instance
    set dtotal [expr {$delta * $numinstances}]

    # memsize - MB, validated
    # current - MB
    # currfmt - formatted

    debug.cmd/app {current   quota/instance = $current}
    debug.cmd/app {                         = $currfmt}
    debug.cmd/app {requested quota/instance = $memsize}
    debug.cmd/app {                         = $memfmt}
    debug.cmd/app {quota delta/instance     = $delta}
    debug.cmd/app {                         = [memspec format $delta]}
    debug.cmd/app {instances                = $numinstances}
    debug.cmd/app {quota delta/total        = $dtotal}
    debug.cmd/app {                         = [memspec format $dtotal]}

    if {$memsize == $current} {
	return
    }

    display "  Updating Disk Reservation \[[color name $appname]\] to $memfmt ... "

    debug.cmd/app {reservation/instance changed $currfmt ==> $memfmt}

    if {[$client isv2]} {
	$theapp @disk_quota set $memsize
    } else {
	dict set app resources disk $memsize
    }

    incr changes
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::files {config} {
    # @application (appname-dot)
    # @apath, @instance, @prefix, @all
    debug.cmd/app {}

    # See also '::stackato::validate::instance::default'
    if {[$config @application] eq "."} {
	# Fake 'undefined' for 'user_all' below.
	$config @application reset
    }

    manifest user_all each $config {::stackato::cmd::app::Files 0}
    return
}

proc ::stackato::cmd::app::tail {config} {
    # @application (appname-dot)
    # @apath, @instance, @prefix, @all
    debug.cmd/app {}

    # See also '::stackato::validate::instance::default'
    if {[$config @application] eq "."} {
	# Fake 'undefined' for 'user_all' below.
	$config @application reset
    }

    manifest user_all each $config {::stackato::cmd::app::Files 1}
    return
}

proc ::stackato::cmd::app::Files {tail config theapp} {
    debug.cmd/app {}

    # @client
    # @instance
    # @all
    # @apath

    set client [$config @client]
    set path   [$config @apath] ;# Not @path, which is from the manifest
                                 # block and points to the application
                                 # directory.

    debug.cmd/app {path = ($path)}

    # client v1 = theapp is name
    # client v2 = theapp is entity instance
    debug.cmd/app {$client is-v2 [$client isv2]}

    try {
	if {[$config @all]} {
	    set prefix [$config @prefix]

	    debug.cmd/app {/all}
	    debug.cmd/app {prefix = ($prefix)}

	    if {[$client isv2]} {
		return [AllFilesV2 $client $prefix $theapp $path]
	    } else {
		return [AllFiles $client $prefix $theapp $path]
	    }
	}

	set instance [$config @instance]

	debug.cmd/app {/single}
	debug.cmd/app {instance = ($instance)}

	if {[$client isv2]} {
	    # v2 => instance object
	    ShowFile2 $tail $instance $path
	} else {
	    # v1 => instance index
	    ShowFile1 $tail $client $theapp $path $instance
	}

    } trap {STACKATO CLIENT V2 UNKNOWN REQUEST} e {
	if {[string match *404* $e]} {
	    display [color bad "([$instance index])$path: No such file or directory"]
	} else {
	    return {*}$o $e
	}
    } trap {STACKATO CLIENT NOTFOUND} e {
	display [color bad $e]
    } trap {STACKATO CLIENT TARGETERROR} {e o} {
	if {[string match *retrieving*404* $e]} {
	    display [color bad "($instance)$path: No such file or directory"]
	} else {
	    return {*}$o $e
	}
    }
    return
}

proc ::stackato::cmd::app::AllFilesV2 {client prefix theapp path} {
    debug.cmd/app {}

    set imap [dict sort [$theapp instances]]

    dict for {idx instance} $imap {
	try {
	    set content [$instance files $path]

	    DisplayLogfile $prefix $path $content $idx \
		[color neutral "====> \[$idx: $path\] <====\n"]

	}  trap {STACKATO CLIENT NOTFOUND} e {
	    display [color bad $e]
	} trap {STACKATO CLIENT TARGETERROR} {e o} {
	    if {[string match *retrieving*404* $e]} {
		display [color bad "($idx)$path: No such file or directory"]
	    } else {
		return {*}$o $e
	    }
	}
    }
    return
}

proc ::stackato::cmd::app::AllFiles {client prefix appname path} {
    debug.cmd/app {}

    set instances_info_envelope [$client app_instances $appname]

    # @todo what else can instances_info_envelope be ? Hash map ?
    #      return if instances_info_envelope.is_a?(Array)

    set instances_info [dict get' $instances_info_envelope instances {}]

    foreach entry $instances_info {
	set idx [dict getit $entry index]
	try {
	    set content [$client app_files $appname $path $idx]
	    DisplayLogfile $prefix $path $content $idx \
		[color neutral "====> \[$idx: $path\] <====\n"]

	}  trap {STACKATO CLIENT NOTFOUND} e {
	    display [color bad $e]
	} trap {STACKATO CLIENT TARGETERROR} {e o} {
	    if {[string match *retrieving*404* $e]} {
		display [color bad "($idx)$path: No such file or directory"]
	    } else {
		return {*}$o $e
	    }
	}
    }
    return
}

proc ::stackato::cmd::app::ShowFile1 {tail client theapp path instance} {
    debug.cmd/app {}
    set full [expr {!$tail}]

    set content [$client app_files $theapp $path $instance]
    display $content $full

    if {$full} return
    # This becomes slower as the file grows larger (quadratic)

    set n [string length $content]
    while {1} {
	set content [$client app_files $theapp $path $instance]

	set new     [string length $content]
	if {$new <= $n} { after 1000 ; continue }

	incr n
	display [string range $content $n end] false
	set n $new
    }
    # not reached
}

proc ::stackato::cmd::app::ShowFile2 {tail instance path} {
    debug.cmd/app {}
    set full [expr {!$tail}]

    set content [$instance files $path]
    display $content $full

    if {$full} return
    # This becomes slower as the file grows larger (quadratic)

    set n [string length $content]
    while {1} {
	set content [$instance files $path]

	set new     [string length $content]
	if {$new <= $n} { after 1000 ; continue }

	incr n
	display [string range $content $n end] false
	set n $new
    }
    # not reached
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::create {config} {
    debug.cmd/app {}

    # @application type 'notappname' ('string' derivate).
    # Not a v2/application instance.

    set client [$config @client]

    if {![$client isv2]} {
	# Force fixed defaults for framework/runtime
	# If nothing is specified.

	# NOTE: This ignores manifest information if there is any.

	if {![$config @framework set?]} {
	    $config @framework set node
	}
	if {![$config @runtime set?]} {
	    $config @runtime set node
	}
    }

    manifest user_all each $config \
	{::stackato::cmd::app::Create true no no}
    # interact = yes, starting = no
    return
}

proc ::stackato::cmd::app::Create {interact starting defersd config appname} {
    debug.cmd/app {}

    # push is a combination of app creation followed by a file upload.
    # this part is handles the app creation and is also available through the
    # external 'create-app' command.

    # Notes:
    # - config @application has validation type 'notappname'.
    #   => int.rep is (always) a string.
    #   => appname is exactly that, never a v2/app instance.
    #
    # - Given the validation type there is no need to check
    #   its non-existence here. (Note that we will always have a race
    #   against other users creating an application with the same
    #   name. No amount of checking will prevent that).

    set client [$config @client]
    set path   [manifest path]

    debug.cmd/app {client       = $client}
    debug.cmd/app {appname      = $appname}
    debug.cmd/app {path         = $path}

    manifest name= $appname
    manifest path= $path

    if {[$client isv2]} {
	debug.cmd/app {/v2: '$appname'}
	# CFv2 API...
	set theapp [CreateAppV2 $interact $starting $defersd $config $appname $path]
	# result is the v2/app instance

	debug.cmd/app {/v2: $theapp ('[$theapp @name]' in [$theapp @space full-name] of [ctarget get])}
    } else {
    	debug.cmd/app {/v1: '$appname'}
	# CFv1 API...
	set theapp [CreateAppV1 $interact $starting $defersd $config $client $appname $path]
	# result is the appname.
    }

    # v1: app name, v2: app instance
    return $theapp
}

proc ::stackato::cmd::app::CreateAppV2 {interact starting defersd config appname path} {
    debug.cmd/app {}

    set theapp [v2 app new]
    ConfigureAppV2 $theapp 0 $interact $starting $defersd $config $appname $path

    debug.cmd/app {/done ==> ($theapp)}
    return $theapp
}

proc ::stackato::cmd::app::ConfigureAppV2 {theapp update interact starting defersd config appname path} {
    debug.cmd/app {}

    set thespace [cspace get]
    if {$thespace eq {}} {
	if {$update} {
	    set action configure
	} else {
	    set action create
	}
	err "Unable to $action application \"$appname\". No space available to attach it to."
    }

    # Framework/Runtime - Not applicable in V2
    # Detection (which buildpack) is now done serverside.
    # (Buildpack mechanism, asking all known BPs)

    # See also GetManifestV2 for push-as-update.
    # Extensions here must be added there also.

    set buildpack [AppBuildpack $config]
    debug.cmd/app {buildpack     = $buildpack}

    set stack [AppStack $config]
    debug.cmd/app {stack         = $stack}

    set dockerimage [AppDockerImage $config $theapp $update]
    debug.cmd/app {docker-image  = $dockerimage}

    # Placement Zone
    set zone [AppZone $config]
    debug.cmd/app {zone          = $zone}

    # Auto-Scaling Configuration, and related
    set mini [AppMinInstances $config]
    debug.cmd/app {min instances = $mini}
    set maxi [AppMaxInstances $config]
    debug.cmd/app {max instances = $maxi}
    set mint [AppMinThreshold $config]
    debug.cmd/app {min threshold = $mint}
    set maxt [AppMaxThreshold $config]
    debug.cmd/app {max threshold = $maxt}

    set instances [AppInstances $config]
    debug.cmd/app {instances     = $instances}

    set autoscale [AppAutoscaling $config]
    debug.cmd/app {autoscale     = $autoscale}

    # Validate unified auto-scaling configuration, i.e. --instances,
    # --autoscaling, --(min|max)-*.

    set description [AppDescription $config]
    debug.cmd/app {description   = $description}

    set ssoe [AppSSOE $config]
    debug.cmd/app {sso-enabled   = $ssoe}

    set htime [AppHealthTimeout $config]
    debug.cmd/app {health-timeout= $htime}

    set command   [AppStartCommand $config {}]
    debug.cmd/app {command      = $command}

    set urls      [AppUrl $config $appname {}] ;# No framework
    debug.cmd/app {urls         = $urls}

    set mem_quota [AppMem $config $starting {} $instances {}] ; # No framework, nor runtime
    debug.cmd/app {mem_quota    = $mem_quota}

    set disk_quota [AppDisk $config $path $dockerimage]
    debug.cmd/app {disk_quota    = $disk_quota}

    # # ## ### ##### ######## ############# #####################
    ## Write section, create instance, fill in the data, commit to
    ## server, lastly fill in relationships ...

    # @console          - Ignore
    # @debug            - ???
    # @environment_json - See below
    # @state            - Ignore
    $theapp @disk_quota      set $disk_quota
    $theapp @memory          set $mem_quota
    $theapp @name            set $appname
    $theapp @space           set $thespace

    if {$instances ne {}} {
	debug.cmd/app {apply instances ($instances)}
	$theapp @total_instances set $instances
    }

    if {$command ne {}} {
	debug.cmd/app {apply command ($command)}
	$theapp @command set $command
    }
    if {$stack ne {}} {
	debug.cmd/app {apply stack $stack}
	$theapp @stack set $stack
    }
    if {$dockerimage ne {}} {
	debug.cmd/app {apply docker-image $dockerimage}
	# NOTE [301224] We force the app entity to record a change
	# even if the docker image did not change. This ensures later
	# on (see <%%%>) that the data is saved across rollbacks and
	# triggers a commit.
	$theapp @docker_image set {}
	$theapp @docker_image set $dockerimage
    }
    if {($zone ne {})} {
	# incoming zone      :: entity
	# app zone attribute :: string
	# => convert
	debug.cmd/app {apply zone $zone}
	$theapp @distribution_zone set [$zone @name]
    }

    # Configure auto scaling
    if {$mini ne {}} {
	debug.cmd/app {apply min instances $mini}
	$theapp @min_instances set $mini
    }
    if {$maxi ne {}} {
	debug.cmd/app {apply mmax instances $maxi}
	$theapp @max_instances set $maxi
    }
    if {$mint ne {}} {
	debug.cmd/app {apply min threshold $mint}
	$theapp @min_cpu_threshold set $mint
    }
    if {$maxt ne {}} {
	debug.cmd/app {apply max threshold $maxt}
	$theapp @max_cpu_threshold set $maxt
    }
    if {$autoscale ne {}} {
	debug.cmd/app {apply autoscale $autoscale}
	$theapp @autoscale_enabled set $autoscale
    }

    # Configure other
    if {$description ne {}} {
	debug.cmd/app {apply description "$description"}
	$theapp @description set $description
    }
    if {$htime ne {}} {
	debug.cmd/app {apply health-timeout "$htime"}
	$theapp @health_check_timeout set $htime
    }
    if {$ssoe ne {}} {
	debug.cmd/app {apply sso-enabled "$ssoe"}
	$theapp @sso_enabled set $ssoe
    }
    if {$buildpack ne {}} {
	debug.cmd/app {apply buildpack $buildpack}
	$theapp @buildpack set $buildpack
    }

    # # ## ### ##### ######## ############# #####################
    ## Write

    set changes 0
    if {$update} {
	debug.cmd/app {update}

	set sync [$config @reset]
	set action [expr {$sync ? "Syncing" : "Comparing"}]
	set dockerbits {}

	debug.cmd/app {sync = $sync}
	display "$action Application \[[color name $appname]\] to \[[context format-short " -> $appname"]\] ... "

	# Scan of label and values, compute field widths.
	set max  0
	set maxv 0
	dict for {attr details} [$theapp journal] {
	    set n [string length [string trimright [$theapp @$attr label]]]
	    if {$n > $max} { set max $n }
	    set new [$theapp @$attr]
	    if {$attr eq "stack"} { set new [$new @name] }
	    set n [string length $new]
	    if {$n > $maxv} { set maxv $n }
	}

	# Scan again, now rendering.
	debug.cmd/app {changes ...}
	dict for {attr details} [dict sort [$theapp journal]] {
	    debug.cmd/app {   $attr = ($details)}

	    # <%%%> Changes to the @docker_image do not count as
	    # config change! This attribute is the equivalent to the
	    # /bits of a regular app.
	    if {$attr eq "docker_image"} {
		set dockerbits [$theapp @$attr]
		continue
	    }

	    lassign $details was old
	    set new [$theapp @$attr]

	    # Reference attribute. Deref "old" and "new" to get the
	    # names to display instead of obj commands and entity uid.
	    if {$attr eq "stack"} {
		# new = obj instance, old = uuid
		set new [color name  [format %-${maxv}s [$new @name]]]
		if {$was} {
		    set old [color name [[v2 deref $old] @name]]
		}
	    } else {
		set new [format %-${maxv}s $new]
	    }

	    incr changes

	    set label [format %-${max}s [string tolower [string trimright [$theapp @$attr label]]]]
	    if {!$sync} {
		set verb   keeping
		set prefix [color warning {Warning, ignoring local change of}]
	    } else {
		set verb   was
		set prefix [color note Setting]
	    }
	    if {!$was} {
		display "    $prefix $label: $new ($verb <undefined>)"
	    } else {
		display "    $prefix $label: $new ($verb $old)"
	    }
	}
	if {!$sync} {
	    debug.cmd/app {not sync}

	    # Undo changes, ignored.
	    if {$changes} {
		debug.cmd/app {  reset changes}
		variable resetinfo
		display [color note $resetinfo]
	    } else {
		debug.cmd/app {  no changes}

		# <%%%> No changes. Check if we are docker-based. If
		# yes, fake a change for the image, to force a reload
		# on the target. Analogous to simply upload the /bits
		# of a regular app.
		try {
		    debug.cmd/app {fake change of dockerbits}
		    set dockerbits [$theapp @docker_image]
		} on error {e o} {
		    debug.cmd/app {fake change setup failed: $e}
		    set dockerbits {}
		}
	    }

	    $theapp rollback
	    set changes 0

	    # <%%%> Restore @docker_image changes across the rollback
	    debug.cmd/app { dockerbits = ($dockerbits)}
	    if {$dockerbits ne {}} {
		debug.cmd/app {  force change, restore bits, or faked change}
		$theapp @docker_image set {}
		$theapp @docker_image set $dockerbits
		incr changes
		# force commit!
	    }
	}
    } else {
	debug.cmd/app {  force change for push}
	incr changes ; # push forces commit
    }

    if {$update} {
	debug.cmd/app {read old EV}
	set oldenv [dict sort [$theapp @environment_json]]

	# Environment binding.
	AppEnvironment defered $config $theapp "preserve"

	set newenv [$theapp @environment_json]
    } else {
	debug.cmd/app {fake old EV as empty}
	# New application, has no environment yet.
	set oldenv {}

	# Environment binding.
	AppEnvironment defered $config $theapp "replace"

	try {
	    set newenv [$theapp @environment_json]
	} trap {STACKATO CLIENT V2 UNDEFINED ATTRIBUTE environment_json} {e o} {
	    # Still no env (nothing set), fake again.
	    set newenv {}
	}
    }

    if {[dict sort $newenv] ne $oldenv} {
	debug.cmd/app {  accepted environment change}
	incr changes
    }

    if {$changes} {
	debug.cmd/app {changes!}
	if {$interact} {
	    SaveManifestInitial $config
	}

	if {!$update} {
	    display "Creating Application \[[color name $appname]\] as \[[context format-short " -> $appname"]\] ... " false
	} else {
	    display {Committing ... } false
	}

	debug.cmd/app {  commit!}
	$theapp commit
	display [color good OK]
    } elseif {$sync} {
	debug.cmd/app {sync, no changes}
	display {No changes}
    }

    # Capture issues with all actions done after app creation
    # (!update) for rollback -- Bug 101992
    try {
	# # ## ### ##### ######## ############# #####################
	## Relationships: urls, services, drains

	if {$update} {
	    # Compare, show, apply (on sync)

	    set old [$theapp uris]
	    lassign [struct::set intersect3 $urls $old] \
		unchanged added removed

	    unmap-urls $config $theapp $removed $sync
	    kept-urls          $theapp $unchanged
	    map-urls   $config $theapp $added 0 $sync

	    if {!$sync && ([llength $added] || [llength $removed])} {
		variable resetinfo
		display [color note $resetinfo]
	    }
	} else {
	    # Push, add all. Rollback app creation in case of trouble.
	    # Note that this is not caught in the trap clauses below.
	    # (code: STACKATO CLIENT CLI CLI-EXIT)
	    map-urls $config $theapp $urls 1
	}

	# When coming from Push we cannot do this here, but have to wait
	# until after RegenerateManifest has incorporated any name changes
	# in full.
	if {!$defersd} {
	    # Run for 'create-app', and push-as-update.
	    AppServices $config $theapp
	    AppDrains   $config $theapp
	}

    } trap {STACKATO CLIENT V2 INVALID REQUEST} {e o} - \
      trap {STACKATO CLIENT V2 UNKNOWN REQUEST} {e o} - \
      trap {STACKATO CLIENT V2 AUTHERROR}       {e o} - \
      trap {STACKATO CLIENT V2 TARGETERROR}     {e o} {
	# Bug 101992
	if {!$update} {
	    # Errors after creation must cause rollback of the
	    # application. Internal errors are an exception to this
	    # however. Keeping the state is likely useful and rollback
	    # would disturb it. It might not even be possible,
	    # depending on the exact nature of the problem.

	    display [color bad $e]
	    Delete 0 1 $config $theapp
	    set e "Reminder: $e, forced the rollback"
	}
	# Rethrow.
	return {*}$o $e
    }

    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::CreateAppV1 {interact starting defersd config client appname path} {
    debug.cmd/app {}

    set manifest [ManifestOfAppV1 $starting $config $appname $path]

    if {$interact} {
	SaveManifestInitial $config
    }

    display "Creating Application \[[color name $appname]\] in \[[ctarget get]\] ... " false
    set response [$client create_app $appname $manifest]
    display [color good OK]

    if {[$config @json]} {
	puts [jmap map dict $response]
    }

    # # ## ### ##### ######## ############# #####################

    # Services check, and binding.
    # When coming from Push we cannot do this here, but have to wait
    # until after RegenerateManifest has incorporated any name changes
    # in full.
    if {!$defersd} {
	# Run for 'create-app', and push-as-update.
	AppServices $config $appname
	AppDrains   $config $appname
    }

    # Environment binding.
    AppEnvironment commit $config $appname replace

    # # ## ### ##### ######## ############# #####################

    debug.cmd/app {/done ==> ($appname)}
    return $appname
}

proc ::stackato::cmd::app::ManifestOfAppV1 {starting config appname path} {
    debug.cmd/app {}

    # # ## ### ##### ######## ############# #####################
    ## Collect all the necessary data

    set instances [AppInstances $config]
    debug.cmd/app {instances     = $instances}

    set frameobj [AppFramework $config]
    debug.cmd/app {framework    = $frameobj}

    set runtime   [AppRuntime $config $frameobj]
    debug.cmd/app {runtime      = $runtime}

    set command   [AppStartCommand $config $frameobj]
    debug.cmd/app {command      = $command}

    set urls      [AppUrl $config $appname $frameobj]
    debug.cmd/app {urls         = $urls}

    set mem_quota [AppMem $config $starting $frameobj $instances $runtime]
    debug.cmd/app {mem_quota    = $mem_quota}

    set disk_quota [AppDisk $config $path {}]
    debug.cmd/app {disk_quota    = $disk_quota}

    # Standards: nodejs/node -- Ho to get ?
    set framework [$frameobj name]

    # # ## ### ##### ######## ############# #####################
    # Create the manifest and send it to the cloud controller
	
    set manifest [dict create \
		      name      $appname \
		      staging   [dict create \
				     framework $framework \
				     runtime   $runtime] \
		      uris      $urls \
		      instances $instances  \
		      resources [dict create \
				     memory $mem_quota \
				     disk   $disk_quota]]

    if {$command ne {}} {
	dict set manifest staging command $command
    }

    $frameobj destroy

    debug.cmd/app {/done ==> $manifest}
    return $manifest
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::push {config} {
    debug.cmd/app {}

    # @application not validated here, always a string.
    # Checks are done here, and influence the chosen operation.

    # Update -- Without manifest we get configuration information
    # from the server, and save it as manifest.

    manifest resetout

    AppPath $config

    # Decision table.
    #
    #		cmdline	mani?	app/man	app/tar	notes/actions
    #N, N0		-------	-----	-------	-------	-------------
    #	N0u	 n	 n	 n	 n	Ask Name, Push/Setup  with (Save Config before File Upload; 3)
    #	N0p	 n	 n	 n	y	Ask Name, Update/Sync with (Save Config before File Upload; 2)
    # N*			-----	-------	-------	-------------
    #	N*p	 n	y	y	 n	Iterated Manifest Entries, Push/Setup
    #	N*u	 n	y	y	y	Iterated Manifest Entries, Update/Sync
    #Y		-------	-----	-------	-------	-------------
    #	Ye	y	*	 n	*	Fail "Could not find in manifest"	/Push
    #				-------	-------	-------------
    #	Yp	y	y	y	 n	Chosen Manifest Entry, Push/Setup
    #	Yu	y	y	y	y	Chosen Manifest Entry, Update/Sync
    #		-------	-------- ------ -------	-------------

    # cmdline (bool) = application name specified on command line
    # mani?   (bool) = manifest file found (and has apps)
    # app/man (bool) = named application found in manifest
    # app/tar (bool) = named application found in the target

    if {[$config @application set?]} {
	debug.cmd/app {single, must be in manifest}

	# (Y)
	ExecPU $config \
	    [ExecSetupSingle $config \
		 [$config @application]]

	debug.cmd/app {/done, single}
	return
    }

    # (N)
    debug.cmd/app {no single specified, go manifest}
    debug.cmd/app {manifest have? [manifest have]}
    debug.cmd/app {manifest apps: [manifest count]}

    if {[manifest have] && [manifest count]} {
	# (N*)
	debug.cmd/app {have manifest, have applications, iterate}

	if {[manifest count] == 1} {
	    debug.cmd/app {iterate single}

	    # single application to handle. May have --as.
	    ExecPU $config \
		[ExecSetupSingle $config \
		     [lindex [manifest select_apps yes] 0]]

	} else {
	    debug.cmd/app {iterate many}
	    # multiple applications. --as is not allowed.

	    if {[$config @as set?]} {
		err "Cannot use --as with multiple applications."
	    }

	    manifest foreach_app name {
		ExecPU $config $name
	    }
	}

	RunDebugger $config

	debug.cmd/app {/done, all}
	return
    }

    # (N0)

    debug.cmd/app {no manifest, or no applications, go interactive}

    # Ask for name.
    set appname [AppName $config]

    manifest current= $appname

    if {[AppIsKnown $config $appname theapp]} {
	# (N0u) Named application exists. Update it.
	# Get config from server and save.
	::stackato::cmd::app::Update $config $theapp 1
    } else {
	# (N0p) Named application not found server side. Push it.
	# Get config interactively and save.
	::stackato::cmd::app::Push $config $theapp 1
    }

    RunDebugger $config

    debug.cmd/app {/done, single, interactive}
    return
}

proc ::stackato::cmd::app::update {config} {
    debug.cmd/app {}
    err "This command is deprecated. Use 'push' for both application creation and update."
    return
}

proc ::stackato::cmd::app::ExecSetupSingle {config appname} {
    debug.cmd/app {}

    manifest current= $appname yes ; #Ye inside

    # See also AppName for the situation where we are creating an app
    # without manifest.
    #
    # Check if application to use on target differs from the
    # application selected in the manifest. If yes, tweak the
    # in-memory manifest to match.
    if {[$config @as set?]} {
	debug.cmd/app {rename: ([$config @as])}

	set appname [$config @as]
	manifest rename-current-as $appname
    }
    return $appname
}

proc ::stackato::cmd::app::ExecPU {config appname} {
    debug.cmd/app {}

    manifest min-version-checks

    client license-status [$config @client]

    if {[AppIsKnown $config $appname theapp]} {
	# (N*u) Application exists. Update it.
	Update $config $theapp
    } else {
	# (N*p) Application not found server side. Push it.
	Push $config $theapp
    }
    return
}

proc ::stackato::cmd::app::AppIsKnown {config appname theappvar} {
    debug.cmd/app {}
    upvar 1 $theappvar theapp
    set ok [appname known [$config @client] $appname theapp]
    if {!$ok} { set theapp $appname }
    return $ok
}

proc ::stackato::cmd::app::AppIsRunning {config theapp appinfo} {
    debug.cmd/app {}
    set client [$config @client]
    return [expr {
		  ( [$client isv2] && [$theapp started?]) ||
		  (![$client isv2] && [dict getit $appinfo state] eq "STARTED")
	      }]
}

proc ::stackato::cmd::app::Push {config appname {interact 0}} {
    debug.cmd/app {}
    # appname - always app name, application does not exist, will be created.

    set client    [$config @client]
    set starting  [expr {![$config @no-start]}]

    # For a new application check that we have space for it on the
    # target.
    client check-app-limit $client

    set theapp [Create $interact $starting 1 $config $appname]
    # Note: defered set! We have to create services and drains
    # after Regen below, to get any name changes into them.
    # v1: app name, v2: app instance

    try {
	RegenerateManifest $config $theapp $appname $interact 1
	# Note: sd set, to run AppServices|Drains in the proper place
	# ordering depends on 'interact'.
    } trap {STACKATO CLIENT V2 INVALID REQUEST} {e o} - \
      trap {STACKATO CLIENT V2 UNKNOWN REQUEST} {e o} - \
      trap {STACKATO CLIENT V2 AUTHERROR}       {e o} - \
      trap {STACKATO CLIENT V2 TARGETERROR}     {e o} {
        # Bug 101992
	# Errors after creation must cause rollback of the
	# application. Internal errors are an exception to this
	# however. Keeping the state is likely useful and rollback
	# would disturb it. It might not even be possible, depending
	# on the exact nature of the problem.
	display [color bad $e]
	Delete 0 1 $config $theapp
	set e "Reminder: $e, forced the rollback"
	# Rethrow.
	return {*}$o $e
    }

    RunPPHooks $appname create

    # Stage and upload the app bits.
    try {
	Upload $config $theapp $appname
    } on error {e o} {
	# On upload failure, delete the app.
	#      no force, rollback
	display [color bad $e]
	Delete 0         1        $config $theapp 
	set e "Reminder: $e, forced the rollback"
	# Rethrow.
	return {*}$o $e
    }

    # Start application after staging, if not suppressed.
    if {$starting} {
	start-single $config $theapp true
    }

    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::Update {config theapp {interact 0}} {
    debug.cmd/app {}

    # theapp - v1 - app name
    #          v2 - app instance

    # Pull server information.
    set client [$config @client]
    set api    [expr {[$client isv2] ? "V2" : "V1"}]

    if {[$client isv2]} {
	set appname [$theapp @name]
	set app {} ;# dummy to satisfy GetManifestXX below.
    } else {
	set appname $theapp
	set app [$client app_info $appname]
    }

    manifest name= $appname
    manifest path= [manifest path]

    if {$interact} {
	# No manifest, or application not found in the manifest.
	# Pull the information from the server.
	# Later ask if we should save this.
	GetManifest$api $client $theapp $app
    }

    RegenerateManifest $config $theapp $appname $interact

    display "Updating application '[color name $appname]'..."

    if {[$client isv2]} {
	set action [SyncV2 $config $appname $theapp $interact]
    } else {
	set action [SyncV1 $client $config $appname $app $interact]
    }

    debug.cmd/app {Action = ($action)}

    RunPPHooks $appname update

    if {$action eq "skip"} {
	# For the zero-downtime switch we have to know the time of the
	# youngest instance, so that we can now when a new instance is
	# started (after that). See WaitV2 below for the use.
	set threshold [Youngest [$theapp instances]]
	debug.cmd/app/wait {Threshold = $threshold}
    }

    Upload $config $theapp $appname

    debug.cmd/app {Action = ($action)}
    switch -exact -- $action {
	skip {
	    # The target supports a zero-downtime switchover. A restart is
	    # not only not required, but contra-indicated. Do nothing. But
	    # watch the instances for the first newly started.

	    display "Triggered a zero-downtime switchover in the target."

	    if {[$config @tail] && [[$config @client] is-stackato]} {
		# Start a logstream to monitor the switchover, which
		# happens asynchronously.

		logstream start $config $theapp any ; # A place where a non-fast log stream is ok.
	    }

	    WaitV2 $config $theapp 0 $threshold

	    set url [$theapp uri]
	    if {$url ne {}} {
		set label "http://$url/ deployed"
	    } else {
		set label "$appname deployed to [ctarget get]"
	    }
	    #append label ", using a zero-downtime switchover"
	    display $label
	}
	start {
	    start-single $config $theapp
	}
	restart {
	    Restart1 $config $theapp
	}
	default {
	    display "Note that \[[color name $appname]\] was not automatically started because it was STOPPED before the update."
	    display "You can start it manually [self please [list start $appname] using]"
	}
    }

    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::LogUnbound {config {endpattern {}}} {
    debug.cmd/app {}

    # We wait 3 minutes (hardwired, for now) for the first new log
    # entries to occur, indicating that switchover has started, and
    # then use the regular --timeout on the stream to determine when
    # to stop watching.
    #
    # Note that we _cannot_ use the instance status information for
    # this. With the zero-downtime this will report a mix of old and
    # new instances and is worthless in terms of deducing the overall
    # application state, nor of the switchover state.

    if {![logstream wait-for-active 700 1800]} {
	# 1,800 [sec] = 3 [min] * 60 [sec/min]
	err "Giving up watching the log, as no entries were received for 3 minutes."
    }

    if {[logstream wait-for-inactive 700 [$config @timeout] $endpattern]} {
	display "Ending the watcher, as [color note {no new log entries}] were received within the last [$config @timeout] seconds."
    } else {
	display [color good OK]
    }
    return
}

proc ::stackato::cmd::app::RunDebugger {config} {
    debug.cmd/app {}
    global env
    variable dhost
    variable dport

    # Nothing to do without -d
    if {![$config @d]} return

    # Nothing to do without a debugger command.
    if {![info exists env(STACKATO_DEBUG_COMMAND)] ||
	($env(STACKATO_DEBUG_COMMAND) eq {})} return

    set cmd $env(STACKATO_DEBUG_COMMAND)

    if {($dhost eq {}) || ($dport eq {})} {
	display [color bad "Unable to run $cmd"]
	display [color bad "Host/port information is missing"]
	return
    }

    lappend map %HOST% $dhost
    lappend map %PORT% $dport

    set cmd [string map $map $cmd]

    cd::indir [manifest path] {
	::exec >@ stdout 2>@ stderr {*}$cmd
    }
    return
}

proc ::stackato::cmd::app::RunPPHooks {appname action} {
    debug.cmd/app {}

    global env tcl_platform
    set saved [array get env]

    set env(STACKATO_APP_NAME)    $appname
    set env(STACKATO_CLIENT)      [self exe]
    set env(STACKATO_HOOK_ACTION) $action

    # Bug(zilla) 106151
    if {[info exists env(SHELL)]} {
	# Check for a shell first.
	set base [list $env(SHELL) -c]

    } elseif {($tcl_platform(platform) eq "windows") &&
	      [info exists env(COMSPEC)]} {
	# On Windows comspec is another possibility.
	# (We allow the shell above, because we might be in a
	# unix-like environment like Cygwin, or Msys)

	set base [list $env(COMSPEC) /c]
    } else {
	# Last try, look for a /bin/sh, and use when found.

	set sh [auto_execok /bin/sh]
	if {[llength $sh]} {
	    set base [list {*}$sh -c]

	} else {
	    # Nothing panned out, giving up with a proper error instead of
	    # a stack trace.

	    if {$tcl_platform(platform) eq "windows"} {
		err "Neither SHELL nor COMSPEC found, unable to run the pre-push hooks for ${action}."
	    } else {
		err "No SHELL found, unable to run the pre-push hooks for ${action}."
	    }
	}
    }

    try {
	foreach cmd [manifest hooks pre-push] {
	    display "[color note pushing:] -----> $cmd"
	    set cmd [list {*}$base $cmd]
	    cd::indir [manifest path] {
		exec::run "[color note pushing:]       " {*}$cmd
	    }
	}
    } finally {
	array unset env
	array set env $saved
    }
    return
}


proc ::stackato::cmd::app::SyncV1 {client config appname app interact} {
    debug.cmd/app {}

    # Early stop.
    set action none ;# post update restart = no
    if {[dict getit $app state] eq "STARTED"} {
	stop1 $config $appname
	set action start
    } elseif {[$config @force-start]} {
	# Application is inactive, and user requests start after update.
	set action start
    }

    if {$interact} {
	# No manifest. Sync is from the server to us.
	# Nothing for us to do.
	return $action
    }

    set sync [$config @reset]

    # Manifest data exists. Sync to server, if requested (--reset),
    # otherwise only compare and warn about differences.
    # Read/Modify/Write cycle

    # Read/... See caller.
    set cmd [expr {$sync ? "Syncing" : "Comparing"}]
    display "$cmd Application \[[color name $appname]\] to \[[ctarget get]\] ... "

    # Now the local information.
    set m [ManifestOfAppV1 0 $config $appname [manifest path]]
    # Rewrite to match app-info structure.
    dict set   m staging model [dict get $m staging framework]
    dict unset m staging framework
    dict set   m staging stack [dict get $m staging runtime]
    dict unset m staging runtime

    # Compare, show, change/apply.
    # The latter only if --reset is used, == $sync.

    set changes 0
    set blnk  {   }
    set delta 0
    set journal {}

    foreach {kp label islist special} {
	{staging model}    {Framework} 0 0
	{staging stack}    {Runtime  } 0 1
	instances          {Instances} 0 0
	{resources memory} {Memory   } 0 0
	{resources disk}   {Disk     } 0 0
	uris               {Url      } 1 0
    } {
	set current [dict get $app {*}$kp]
	set new     [dict get $m   {*}$kp]

	if {$islist} {
	    set current [lsort -dict $current]
	    set new     [lsort -dict $new]
	}

	# Ignore non-changes
	if {$new == $current} continue

	# Bug 100245. Ignore special string indicating a framework
	# specific runtime. That is no change as well.
	if {$special && ($new eq {})} continue

	if {!$sync} {
	    set lmod   {   }
	    set verb   keeping
	    set prefix [color warning {Warning, ignoring local change of}]
	} else {
	    set lmod   Not
	    set verb   was
	    set prefix [color note Setting]
	}

	if {!$islist} {
	    # Regular attribute.
	    display "    $prefix $label: $new ($verb $current)"
	} else {
	    # List attribute: urls.

	    lassign [struct::set intersect3 $new $current] \
		unchanged added removed

	    foreach u $removed   { display "$prefix $label: $lmod Removed $u" }
	    foreach u $unchanged { display "$prefix $label: $blnk Keeping $u" }
	    foreach u $added     { display "$prefix $label: $lmod Added   $u" }
	}

	# Apply?
	incr delta
	if {!$sync} continue
	incr changes

	# Remember changes for application later (after we get a new
	# app-info to detect/handle environment changes. We cannot use
	# 'app' directly, as its created time will be too old, leading
	# to a lock failure on the target.
	lappend journal $kp $new
    }

    # Environment bindings. Controlled by separate option --env-mode
    set newapp [AppEnvironment defered $config $appname preserve]

    # Note: app, newapp are CFv1 data.
    # Their 'env' is a list of A=B assignments.
    # Not a dictionary

    if {[lsort -dict [dict get $newapp env]] ne [lsort -dict [dict get $app env]]} {
	incr changes
    }
    set app $newapp

    if {$changes} {
	# Apply the journal to the latest app-info we got.
	foreach {kp new} $journal {
	    dict set app {*}$kp $new
	}

	# .../Write
	$client update_app $appname $app
	display [color good OK]
    } else {
	display "    [color note {No changes}]"
    }

    if {!$sync && $delta} {
	variable resetinfo
	display [color note $resetinfo]
    }

    # Services check, and binding, after.
    # Hardwired. Analoguous to AppEnv preserve mode
    AppServices $config $appname
    AppDrains   $config $appname

    return $action
}

proc ::stackato::cmd::app::SyncV2 {config appname theapp interact} {
    debug.cmd/app {}

    if {!$interact} {
	# Manifest data exists. Sync to server.

	# Can update while app might be running.
	# 1 0 0 - update, !interact, !starting, !defersd
	ConfigureAppV2 $theapp 1 0 0 0 \
	    $config $appname [manifest path]

    } else {
	# No, not nothing. Not with docker-based apps around.  Run a fake
	# change of the docker-image, if there is one, as that is the
	# /bits equivalent we have to always perform.
	#
	# else nothing for there is no manifest (information), and we
	# sync'd from the server, not the other way around
	#
	# OP [301559].
	# We have to run the part of ConfigureAppV2 handling the
	# --docker-image option as well, for if we don't it will get
	# ignored, which is obviously wrong. This part was missed in
	# commit 1a7c990a41 when the original issue of handling docker
	# images in this code path was fixed for [301224].

	set dockerimage [AppDockerImage $config $theapp 1]
	debug.cmd/app {docker-image  = $dockerimage}

	if {$dockerimage ne {}} {
	    debug.cmd/app {apply docker-image $dockerimage}
	    # NOTE [301224] We force the app entity to record a change
	    # even if the docker image did not change. This ensures later
	    # on (see <%%%>) that the data is saved across rollbacks and
	    # triggers a commit.
	    $theapp @docker_image set {}
	    $theapp @docker_image set $dockerimage
	}

	try {
	    # This should abort/do nothing if either the target has no
	    # such attribute, or its value is empty (regular app).
	    debug.cmd/app {fake change of dockerbits}
	    set dockerbits [$theapp @docker_image]

	} on error {e o} {
	    debug.cmd/app {fake change setup failed: $e}

	} on ok {e o} {
	    debug.cmd/app {  dockerbits = ($dockerbits)}
	    if {$dockerbits ne {}} {
		debug.cmd/app {  force change, faked change}
		$theapp @docker_image set {}
		$theapp @docker_image set $dockerbits

		display "Committing to docker image \"[color name [DisplayDIR $dockerbits]]\" ... " false
		debug.cmd/app {  commit!}
		$theapp commit
		display [color good OK]
	    }
	}
    }

    debug.cmd/app {}

    if {[$theapp started?]} {
	if {[[$config @client] zero-downtime]} {
	    debug.cmd/app {0-down active}
	    # The target supports a zero-downtime switchover. A
	    # restart is not only not required, but
	    # contra-indicated. Force the caller to do nothing.
	    # The upload of the application bits will trigger
	    # the CC 0-downtime switchover.
	    return "skip"
	} else {
	    return "restart"
	}
    } elseif {[$config @force-start]} {
	# Application is inactive, and user requests start after update.
	return "start"
    } else {
	return "none"
    }
}

proc ::stackato::cmd::app::GetManifestV1 {client __ app} {
    debug.cmd/app {}

    set drains [$client app_drain_list [dict get $app name]]

    set svc {}
    set bound [dict get $app services]
    if {[llength $bound]} {
	foreach item [$client services] {
	    dict set known [dict get $item name] [dict get $item vendor]
	}
	foreach sname $bound {
	    dict set details type [dict get $known $sname]
	    dict set svc $sname $details
	}
    }

    #manifest command=  N/A
    #manifest path=
    manifest disk=      [dict get $app resources disk]
    manifest env=       [Env2Dict [dict get $app env]]
    manifest framework= [dict get $app staging model]
    manifest instances= [dict get $app instances]
    manifest mem=       [dict get $app resources memory]
    manifest runtime=   [dict get $app staging stack]
    manifest services=  $svc
    manifest url=       [dict get $app uris]
    manifest drains=    $drains

    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::GetManifestV2 {client theapp __} {
    debug.cmd/app {}

    set drains [$theapp drain-list]

    set svc {}
    foreach si [$theapp @service_bindings @service_instance] {
	if {[catch {
	    set sp [$si @service_plan]
	}]} {
	    dict set svc [$si @name] credentials [$si @credentials]
	} else {
	    dict set svc [$si @name] [$sp manifest-info]
	}
    }

    #manifest framework= N/A
    #manifest path=
    #manifest runtime=   N/A
    manifest disk=      [$theapp @disk_quota]
    manifest env=       [$theapp @environment_json]
    manifest instances= [$theapp @total_instances]
    manifest mem=       [$theapp @memory]
    manifest services=  $svc
    manifest url=       [$theapp uris]
    manifest drains=    $drains

    foreach {attr method} {
	@distribution_zone    zone=
	@description          description=
	@sso_enabled          ssoenabled=
	@health_check_timeout health-timeout=
	@max_instances        maxInstances=
	@min_instances        minInstances=
	@max_cpu_threshold    maxCpuThreshold=
	@min_cpu_threshold    minCpuThreshold=
	@autoscale_enabled    autoscaling=
	@docker_image         docker-image=
    } {
	catch {
	    set v [$theapp $attr]
	    if {$v ne {}} {
		manifest $method $v
	    }
	}
    }

    set bp [$theapp @buildpack]
    if {($bp ne {}) && ($bp ne "null")} {
	manifest buildpack= $bp
    }

    set cmd [$theapp @command]
    if {($cmd ne {}) && ($cmd ne "null")} {
	manifest command= $cmd
    }

    catch {
	set stack [$theapp @stack @name]
	if {$stack ne {}} {
	    manifest stack= $stack
	}
    }

    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::RegenerateManifest {config theapp appname interact {sd 0}} {
    debug.cmd/app {}

    # Services and Drains.

    # For 'Update' this is done later, by the SyncV2 our caller
    # invokes after us. ==> !sd

    # For 'Push' this is done here (==> sd) to get proper ordering in
    # case of name changes (--as).
    #
    # * For interact services are asked for interactively. Must be
    #   done before saving the manifest, and there are no name-changes
    #   to take into account.
    #
    # * For !interact a name-change is possible and operation has to
    #   be done after reloading the manifest fully incorporating such
    #   changes into the system. Without symbol resolution was done on
    #   the old name, possibly giving is a bogus service|drain name.

    debug.cmd/app {/interact=$interact}
    if {$interact} {
	# This transforms the collected outmanifest into the main
	# manifest to use. The result may be saved to the application
	# as well.

	debug.cmd/app {/sd=$sd}
	if {$sd} {
	    AppServices $config $theapp
	    AppDrains   $config $theapp
	}

	debug.cmd/app {/save}
	SaveManifestFinal $config
	# Above internally has a manifest reload from the saved
	# interaction.

	# Re-select the application we are working with.
	debug.cmd/app {/reselect $appname}
	manifest current= $appname yes

    } else {
	# Bug 93955. Reload manifest. See also file manifest.tcl,
	# proc 'LoadBase'. This is where the collected outmanifest
	# data is merged in during this reload.
	debug.cmd/app {/reload manifest}
	manifest setup \
	    [$config @path set?] \
	    [$config @path] \
	    [$config @manifest] \
	    reset

	# Re-select the application we are working with.
	debug.cmd/app {/reselect $appname}
	manifest current= $appname yes

	debug.cmd/app {/sd=$sd}
	if {$sd} {
	    AppServices $config $theapp
	    AppDrains   $config $theapp
	}
    }

    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::SaveManifestInitial {config {mode full}} {
    debug.cmd/app {}

    if {![cmdr interactive?] ||
	![ask yn \
	      "Would you like to save this configuration?" \
	      no]} {
	debug.cmd/app {Not saved}
	variable savemode no
	return
    }

    set dst [$config @manifest]

    # Saving a manifest may happen when there is no manifest present yet.
    if {$dst eq {}} {
	debug.cmd/app {Falling back to manifest base}
	set dst [manifest mbase]/stackato.yml
    }

    debug.cmd/app {dst = $dst}

    # FUTURE: TODO - Rewrite the app-dir and other path information in
    # the file to be relative to the destination location, instead of
    # keeping the absolute path it was saved with, to make moving the
    # application in the filesystem easier.

    if {$mode eq "full"} {
	set tmp [fileutil::tempfile stackato_m_]
	manifest save $tmp
	file rename -force -- $tmp $dst
	debug.cmd/app {Saved}

	display "  Saved to \"[fileutil::relative [pwd] $dst]\""
    }

    variable savemode yes
    variable savedst $dst
    return
}

proc ::stackato::cmd::app::SaveManifestFinal {config} {
    debug.cmd/app {}
    variable savemode
    set action Resaved

    # We can reach this code without having run *Initial, via
    # 'push' --> 'Update' --> 'RegenerateManifest' --> here.
    # We run only a basic initialization, i.e. no actual saving,
    # just determination of yes/no, and destination. Avoid saving
    # twice.
    if {$savemode eq "check"} {
	SaveManifestInitial $config basic
	set action Saved
    }

    # Move the saved information into the main data
    # structures. Note that we have to ensure the structure is
    # properly transformed.

    # Easiest way of doing this is to save to a file and then
    # re-initalize the system by loading from that. Saving the
    # manifest is then just copying the temp file to the proper
    # place.

    set tmp [fileutil::tempfile stackato_m_]
    manifest save $tmp

    # Reload. Remove the out-manifest tough, as it is now the main
    # manifest here, and must not be merged with itself a 2nd time.
    # The other path in the caller (RegenerateManifest) must do such a
    # merge against the existing main manifest.
    manifest resetout
    manifest setup [$config @path set?] [$config @path] $tmp reset

    if {!$savemode} {
	file delete -- $tmp
	debug.cmd/app {Not saved}

	# Reset save-state
	variable savemode check
	variable savedst  {}
	return
    }

    # Import chosen destination from SaveManifestInitial
    variable savedst

    debug.cmd/app {dst = $savedst}

    # FUTURE: TODO - Rewrite the app-dir and other path information in
    # the file to be relative to the destination location, instead of
    # keeping the absolute path it was saved with, to make moving the
    # application in the filesystem easier.

    file rename -force -- $tmp $savedst
    debug.cmd/app {Saved}

    display "  $action configuration to \"[fileutil::relative [pwd] $savedst]\""

    # Reset save-state
    variable savemode check
    variable savedst  {}
    return
}

proc ::stackato::cmd::app::AppPath {config} {
    debug.cmd/app {}

    # Can't ask user, or --path was specified anyway.
    if {![cmdr interactive?]} return
    if {[$config @path set?]} return

    set proceed \
	[ask yn \
	     {Would you like to deploy from the current directory ? }]

    if {!$proceed} {
	# TODO: interactive deployment path => custom completion.
	set path [ask string {Please enter in the deployment path: }]
	set user 1
    } else {
	set path [pwd]
	set user 0
    }

    set path [file normalize $path]

    CheckDeployDirectory $path

    # May reload manifest structures
    manifest setup $user $path [$config @manifest]
    return
}

proc ::stackato::cmd::app::AppName {config} {
    debug.cmd/app {}

    set client  [$config @client]

    # See also ExecSetupSingle. This is similar, except we have no
    # manifest. The default appname would come out of fallbacks, like
    # the directory name, or from the user. The --as option can
    # preempt this.
    if {[$config @as set?]} {
	debug.cmd/app {rename: ([$config @as])}

	set appname [$config @as]
    } else {
	# (3) May ask the user, use deployment path as default ...

	set appname [manifest askname]
    }

    # Fail without or bad name
    if {$appname eq {}} {
	err "Application Name required."
    }

    if {[string first . $appname] >= 0} {
	err "Bad Application Name (Illegal character \".\")."
    }

    return $appname
}

proc ::stackato::cmd::app::AppInstances {config} {
    debug.cmd/app {}

    # Note: Can pull manifest data only here.
    # During cmdr processing current app is not known.
    if {[$config @instances set?]} {
	set instances [$config @instances]
	debug.cmd/app {option   = $instances}
    } else {
	set instances [manifest instances]
	debug.cmd/app {manifest = $instances}
    }

    if {($instances eq {}) && [[$config @client] is-stackato]} {
	# Nothing specified, target will use a default.
	# In case of a CF target we skip this and force (see below).
	return $instances
    }

    if {($instances eq {}) || ($instances < 1)} {
	display "Forcing use of minimum instances requirement: 1"
	set instances 1
    }

    display "Instances:         $instances"
    manifest instances= $instances
    return $instances
}

proc ::stackato::cmd::app::AppStack {config} {
    debug.cmd/app {}

    # Note: Can pull manifest data only here.
    # During cmdr processing current app is not known.
    if {[$config @stack set?]} {
	set stack [$config @stack]
	# stack = entity instance
	debug.cmd/app {option   = [$stack @name]}
    } else {
	set stack [manifest stack]
	# stack = string
	debug.cmd/app {manifest = $stack}
	# Convert name into object, if possible
	if {$stack ne {}} {
	    set stack [stackname validate [$config @stack self] $stack]
	}
    }
    # stack = entity instance

    if {$stack ne {}} {
	manifest stack= [$stack @name]
    }
    return $stack
}

proc ::stackato::cmd::app::AppBuildpack {config} {
    debug.cmd/app {}

    # Note: Can pull manifest data only here.
    # During cmdr processing current app is not known.
    if {[$config @buildpack set?]} {
	set buildpack [$config @buildpack]
	debug.cmd/app {option   = $buildpack}
    } else {
	set buildpack [manifest buildpack]
	debug.cmd/app {manifest = $buildpack}
    }

    if {$buildpack ne {}} {
	display "BuildPack:         $buildpack"
    }

    manifest buildpack= $buildpack
    return $buildpack
}

proc ::stackato::cmd::app::AppZone {config} {
    debug.cmd/app {}

    # Note: Can pull manifest data only here.
    # During cmdr processing current app is not known.
    if {[$config @placement-zone set?]} {
	set zone [$config @placement-zone]
	# zone = entity instance
	debug.cmd/app {option   = [$zone @name]}
    } else {
	set zone [manifest zone]
	# zone = string
	debug.cmd/app {manifest = $zone}
	# Convert name into object, if possible
	if {$zone ne {}} {
	    set zone [zonename validate [$config @placement-zone self] $zone]
	}
    }
    # zone = entity instance

    if {$zone ne {}} {
	display "Zone:              [$zone @name]"
	manifest zone= [$zone @name]
    }
    return $zone
}

proc ::stackato::cmd::app::AppDockerImage {config theapp update} {
    debug.cmd/app {}

    # Note: Can pull manifest data only here.
    # During cmdr processing current app is not known.
    if {[$config @docker-image set?]} {
	set dimage [$config @docker-image]
	# dimage = string
	debug.cmd/app {option   = $dimage}
    } else {
	set dimage [manifest docker-image]
	# dimage = string
	debug.cmd/app {manifest = $dimage}
    }
    # dimage = string

    if {$dimage ne {}} {
	if {0&&$update} {
	    if {![$theapp @docker_image defined?] ||
		([$theapp @docker_image] eq {})} {
		err "Cannot change regular application to docker-based on update."
	    }
	}
	# Can't check for the attribute, this may be an empty app
	# entity from basic client-side construction. Which tells us
	# nothing about the target.
	if {0&&![$theapp @docker_image defined?]} {
	    err "--docker-image not supported by the target."
	}
	display "Docker Image:      [color name [DisplayDIR $dimage]]"
	manifest docker-image= $dimage
    } else {
	if {0&&$update} {
	    if {[$theapp @docker_image defined?] &&
		([$theapp @docker_image] ne {})} {
		err "Cannot change docker-based application to regular on update."
	    }
	}
    }
    return $dimage
}

proc ::stackato::cmd::app::debug-dir {config} {
    debug.cmd/app {}
    puts [DisplayDIR [$config @ref]]
    return
}

proc ::stackato::cmd::app::DisplayDIR {imageref} {
    debug.cmd/app {}
    # Squash password information in a docker image ref to prevent it
    # from getting seen in log files and the like,

    regsub {(.*://)?([^@]*)@} $imageref {\1***@} imageref
    return $imageref
}

proc ::stackato::cmd::app::AppAutoscaling {config} {
    debug.cmd/app {}

    # Note: Can pull manifest data only here.
    # During cmdr processing current app is not known.
    if {[$config @autoscale set?]} {
	set autoscaling [$config @autoscale]
	debug.cmd/app {option   = $autoscaling}
    } else {
	set autoscaling [manifest autoscaling]
	debug.cmd/app {manifest = $autoscaling}
    }

    if {$autoscaling ne {}} {
	display "Autoscaling:       $autoscaling"
	manifest autoscaling= $autoscaling
    }

    return $autoscaling
}

proc ::stackato::cmd::app::AppMinInstances {config} {
    debug.cmd/app {}

    # Note: Can pull manifest data only here.
    # During cmdr processing current app is not known.
    if {[$config @min-instances set?]} {
	set min_instances [$config @min-instances]
	debug.cmd/app {option   = $min_instances}
    } else {
	set min_instances [manifest minInstances]
	debug.cmd/app {manifest = $min_instances}
    }

    if {$min_instances ne {}} {
	display "Min Instances:     $min_instances"
	manifest minInstances= $min_instances
    }

    return $min_instances
}

proc ::stackato::cmd::app::AppMaxInstances {config} {
    debug.cmd/app {}

    # Note: Can pull manifest data only here.
    # During cmdr processing current app is not known.
    if {[$config @max-instances set?]} {
	set max_instances [$config @max-instances]
	debug.cmd/app {option   = $max_instances}
    } else {
	set max_instances [manifest maxInstances]
	debug.cmd/app {manifest = $max_instances}
    }

    if {$max_instances ne {}} {
	display "Max Instances:     $max_instances"
	manifest maxInstances= $max_instances
    }

    return $max_instances
}

proc ::stackato::cmd::app::AppMinThreshold {config} {
    debug.cmd/app {}

    # Note: Can pull manifest data only here.
    # During cmdr processing current app is not known.
    if {[$config @min-cpu set?]} {
	set min_threshold [$config @min-cpu]
	debug.cmd/app {option   = $min_threshold}
    } else {
	set min_threshold [manifest minCpuThreshold]
	debug.cmd/app {manifest = $min_threshold}
    }

    if {$min_threshold ne {}} {
	display "Min CPU Threshold: $min_threshold"
	manifest minCpuThreshold= $min_threshold
    }

    return $min_threshold
}

proc ::stackato::cmd::app::AppMaxThreshold {config} {
    debug.cmd/app {}

    # Note: Can pull manifest data only here.
    # During cmdr processing current app is not known.
    if {[$config @max-cpu set?]} {
	set max_threshold [$config @max-cpu]
	debug.cmd/app {option   = $max_threshold}
    } else {
	set max_threshold [manifest maxCpuThreshold]
	debug.cmd/app {manifest = $max_threshold}
    }

    if {$max_threshold ne {}} {
	display "Max CPU Threshold: $max_threshold"
	manifest maxCpuThreshold= $max_threshold
    }

    return $max_threshold
}

proc ::stackato::cmd::app::AppDescription {config} {
    debug.cmd/app {}

    # Note: Can pull manifest data only here.
    # During cmdr processing current app is not known.
    if {[$config @description set?]} {
	set description [$config @description]
	debug.cmd/app {option   = $description}
    } else {
	set description [manifest description]
	debug.cmd/app {manifest = $description}
    }

    if {$description ne {}} {
	display "Description:       $description"
	manifest description= $description
    }

    return $description
}

proc ::stackato::cmd::app::AppHealthTimeout {config} {
    debug.cmd/app {}

    # Note: Can pull manifest data only here.
    # During cmdr processing current app is not known.
    if {[$config @health-timeout set?]} {
	set htime [$config @health-timeout]
	debug.cmd/app {option   = $htime}
    } else {
	set htime [manifest health-timeout]
	debug.cmd/app {manifest = $htime}
    }

    if {$htime ne {}} {
	display "Health Timeout:    $htime"
	manifest health-timeout= $htime
    }

    return $htime
}

proc ::stackato::cmd::app::AppSSOE {config} {
    debug.cmd/app {}

    # Note: Can pull manifest data only here.
    # During cmdr processing current app is not known.
    if {[$config @sso-enabled set?]} {
	set ssoe [$config @sso-enabled]
	debug.cmd/app {option   = $ssoe}
    } else {
	set ssoe [manifest ssoenabled]
	debug.cmd/app {manifest = $ssoe}
    }

    if {$ssoe ne {}} {
	display "SSO Enabled:       $ssoe"
	manifest ssoenabled= $ssoe
    }

    return $ssoe
}

proc ::stackato::cmd::app::AppRuntime {config frameobj} {
    debug.cmd/app {}

    set client  [$config @client]

    # Note: Can pull manifest data only here.
    # During cmdr processing current app is not known.
    if {[$config @runtime set?]} {
	set runtime [$config @runtime]
	debug.cmd/app {option   = ($runtime)}
    } else {
	set runtime [manifest runtime]
	debug.cmd/app {manifest = ($runtime)}
    }

    # FUTURE? Push fully into the command line processor.
    # (If we can, see above about 'current app').

    set runtimes [client runtimes $client]
    debug.cmd/app {supported = [join $runtimes "\nsupported = "]}

    # Last, see if we should ask the user for it.
    # (Required by the framework, and user allowed interaction)

    if {
	($runtime eq {}) &&
	[$frameobj prompt_for_runtime?] &&
	[cmdr interactive?]
    } {
	set runtime [ask menu "What runtime?" "Select Runtime: " \
			 [lsort -dict [dict keys $runtimes]] \
			 [$frameobj default_runtime [manifest path]]]
    }

    # Lastly, if a runtime was specified, verify that the targeted
    # server actually supports it.

    if {$runtime ne {}} {
	debug.cmd/app {runtime/         = ($runtime)}
	debug.cmd/app {checking support}

	set map [RuntimeMap $runtimes]
	set low [string tolower $runtime]

	if {[dict exists $map $runtime]} {
	    set rt [dict get $map $runtime]

	} elseif {[dict exists $map $low]} {
	    set rt [dict get $map $low]

	} else {
	    err "The specified runtime \[$runtime\] is not supported by the target."
	}

	if {[llength $rt] > 1} {
	    foreach r $rt {
		lappend text "  $r ([dict get $runtimes $r description])"
	    }
	    err "Ambiguous runtime \[$runtime\], choose one of:\n[join $text ,\n]\n"
	}

	set runtime [lindex $rt 0]

	# Map specification of user label of runtime back to
	# internal code.
	if {[dict exists $map $runtime]} {
	    set runtime [dict get $map $runtime]
	    debug.cmd/app {= $runtime}
	}
    }

    if {$runtime ne {}} {
	manifest runtime= $runtime
	display "Runtime:           [dict get $runtimes $runtime description]"
    } else {
	display "Runtime:           <framework-specific default>"
    }

    set as [manifest app-server]
    if {$as ne {}} {
	display "App-Server:      $as"
    }

    return $runtime
}

proc ::stackato::cmd::app::AppStartCommand {config frameobj} {
    debug.cmd/app {}

    if {($frameobj ne {}) && ![$frameobj require_start_command?]} {
	debug.cmd/app {None}
	return {}
    }

    set defined [$config @command set?]
    if {$defined} {
	set command [$config @command]
	set defined [expr {$command ne {}}]
	debug.cmd/app {command/cmdline = ($command)}
    }

    # Check the configuration
    if {!$defined} {
	set command [manifest command]
	debug.cmd/app {command/manifest = ($command)}
	set defined [expr {$command ne {}}]
    }
    
    # Query the user.
    if {!$defined && ($frameobj ne {}) && [cmdr interactive?]} {
	set command [ask string {Start command: }]
	debug.cmd/app {command/interact = ($command)}
	set defined [expr {$command ne {}}]
    }

    if {!$defined} {
	if {$frameobj ne {}} {
	    set basic "The framework \[[color name [$frameobj name]]\] needs a non-empty start command."
	} else {
	    # v2 target. Command is not required. Accept missing status and go on.
	    debug.cmd/app {v2 target, accept as missing}
	    return {}
	}

	if {[cmdr interactive?]} {
	    err $basic
	} else {
	    err "$basic\nPlease add a \"command\" key to your stackato.yml"
	}
    }

    manifest command= $command
    display "Command:           $command"

    debug.cmd/app {==> ($command)}
    return $command
}

proc ::stackato::cmd::app::AppUrl {config appname frameobj} {
    debug.cmd/app {}

    # Note: Can pull manifest data only here.
    # During cmdr processing current app is not known.
    if {[$config @url set?]} {
	set urls [$config @url]
	set appdefined 0
	# This is ok, because in this branch urls.empty() is not possible.
	debug.cmd/app {options  = [join $urls "\n= "]}
    } else {
	set urls [manifest urls appdefined]
	debug.cmd/app {manifest ($appdefined) = [join $urls "\n= "]}
    }

    debug.cmd/app {url          = $urls}

    set stock None

    if {![llength $urls] && !$appdefined} {
	set stock [DefaultUrl $config $frameobj]
	debug.cmd/app {default      = $stock}
    }

    if {![llength $urls] && !$appdefined &&
	[cmdr interactive?] &&
	(($frameobj eq {}) ||
	 [$frameobj require_url?])} {
	variable yes_set

	set url [ask string "Application Deployed URL \[[color yes $stock]\]: "]
	# Common error case is for prompted users to answer y or Y or
	# yes or YES to this ask() resulting in an unintended URL of
	# y. Special case this common error.
	if {$url in $yes_set} {
	    #silently revert to the stock url
	    set url $stock
	}
	if {$url ne {}} {
	    set urls [list $url]
	}	    
    }

    if {$stock eq "None"} {
	set stock {}
    }
    if {![llength $urls] && ($stock ne {})} {
	set urls [list $stock]
    }

    # TODO: u == stock => save as stock_template

    # Show urls, in canonical form. Return the canonical forms
    # also, rendering any other processing case-insensitive.
    set tmp {}
    foreach u $urls {
	set u [string tolower $u]
	lappend tmp $u
	display "Application Url:   http://$u"
    }
    set urls $tmp

    if {![llength $urls]} {
	display [color note "No Application Urls"]
    }

    #manifest url= $urls
    return $urls
}

proc ::stackato::cmd::app::DefaultUrl {config frameobj} {
    debug.cmd/app {}

    if {[$config @domain set?]} {
	debug.cmd/app {User specified domain.}

	set domain [$config @domain]

	set stock_template "\${name}.$domain"
	set stock [list scalar $stock_template]
	manifest resolve stock
	set stock [lindex $stock 1]

	# NOTE: We do _not_ have to consider a 'domain' key specified
	# in the stackato.yml here. Because if such happens it was
	# used to generate an url together with the application name
	# (like we do here), and thus this procedure, "DefaultUrl"
	# will not be called upon at all anymore.

    } elseif {[[$config @client] isv2]} {
	debug.cmd/app {CFv2 - space-specific}
	# For a Stackato 3 target use the domain mapped to the current
	# space as the base of the default url.

	set stock_template "\${name}.\${space-base}"
	set stock [list scalar $stock_template]
	manifest resolve stock
	set stock [lindex $stock 1]

    } elseif {($frameobj eq {}) || [$frameobj require_url?]} {
	debug.cmd/app {CFv1 - target-specific}
	# For a Stackato 2 target use the target location as base of
	# the default url, if required by the framework or framework
	# unknown.

	set stock_template "\${name}.\${target-base}"
	set stock [list scalar $stock_template]
	manifest resolve stock
	set stock [lindex $stock 1]
    } else {
	debug.cmd/app {No default}
	# No default url available/wanted.
	set stock None
    }

    debug.cmd/app {==> $stock}
    return $stock
}

proc ::stackato::cmd::app::AppFramework {config} {
    debug.cmd/app {}

    set client  [$config @client]

    set supported [client frameworks $client]
    debug.cmd/app {server supports : [join $supported "\n[::debug caller] |  | server supports : "]}

    # No framework forced.

    if {[$config @no-framework]} {
	debug.cmd/app {no framework /options - empty}
	# Empty framework if user said to ignore all settings.
	return [AppFrameworkComplete \
		    [framework create] {} 0]
    }

    # Determine the framework name by checking the command line,
    # the configuration, per auto-detection, or, as last fallback,
    # ask the user.

    # Future: Try to push into cmdr dispatcher.

    # (1) command line option --framework

    if {[$config @framework set?]} {
	set framework [$config @framework]

	debug.cmd/app {options = $framework}
	return [AppFrameworkComplete \
		    [framework lookup $framework] \
		    $supported]
    }

    # (2) configuration (stackato.yml, manifest.yml)

    set framework [manifest framework]
    if {$framework ne {}} {
	debug.cmd/app {manifest = $framework}

	return [AppFrameworkComplete \
		    [framework create $framework $framework \
			 [manifest framework-info]] \
		    $supported]
    }

    # (3) Heuristic detection, confirm result

    debug.cmd/app {detect by heuristics, in ([manifest path])}
    set framework_correct 0
    set frameobj [framework detect [manifest path] $supported]

    if {($frameobj ne {}) &&
	[cmdr interactive?]} {
	set framework_correct \
	    [ask yn "Detected a [color name [$frameobj description]], is this correct ? "]
    }

    # (4) Ask the user.
    if {[cmdr interactive?] &&
	(($frameobj eq {}) ||
	 !$framework_correct)} {
	if {$frameobj eq {}} {
	    display "[color warning WARNING] Can't determine the Application Type."
	}

	# incorrect, kill object
	if {!$framework_correct} {
	    catch { $frameobj destroy }
	    set frameobj {}
	    set df {}
	} else {
	    set df [$frameobj key]
	}

	set fn [ask menu "What framework?" "Select Application Type: " \
		    [lsort -dict [framework known $supported]] $df]

	catch { $frameobj destroy }
	set frameobj [framework lookup $fn]
	if {$frameobj eq {}} {
	    # While the chosen framework is supported by the
	    # server, the client doesn't know anything about it.
	    # We are now filling in some fake defaults for name,
	    # key, description. Memory is not set, use the
	    # internal default, see framework.tcl, default_mem.

	    set frameobj [framework create $fn $fn \
			      [dict create description "$fn (Server code)"]]
	}

	display "Selected [$frameobj description]"
    }

    return [AppFrameworkComplete $frameobj $supported]
}

proc ::stackato::cmd::app::AppFrameworkComplete {frameobj supported {check 1}} {
    debug.cmd/app {}

    if {$frameobj eq {}} {
	err "Application Type undetermined for path '[manifest path]'"
    }

    if {$check && ([$frameobj name] ni $supported)} {
	err "The specified framework \[[$frameobj name]\] is not supported by the target.\n[self please frameworks] to get the list of supported frameworks."
    }

    display "Framework:         [$frameobj name]"

    manifest framework= [$frameobj name]

    # Special case check for generic frameworks. Ensure that a
    # processes/web specification exists. This is a very small
    # step in validating a stackato.yml.
    if {[$frameobj name] eq "generic"} {
	if {[manifest p-web] eq {}} {
	    err "Usage of framework \[Generic\] requires the\n\
                 specification of a processes: web: hook in stackato.yml"
	}
    }

    return $frameobj
}

proc ::stackato::cmd::app::AppMem {config starting frameobj instances runtime} {
    debug.cmd/app {}

    set client [$config @client]

    # Note: Can pull manifest data only here.
    # During cmdr processing current app is not known.
    if {[$config @mem set?]} {
	set mem [$config @mem]
	debug.cmd/app {option   = ($mem)}
    } else {
	set mem [manifest mem]
	debug.cmd/app {manifest = ($mem)}
    }

    if {$mem eq {}} {
	if {$frameobj ne {}} {
	    set mem [$frameobj memory $runtime]
	    debug.cmd/app {framework default = ($mem)}
	} else {
	    set mem 256
	}

	if {[cmdr interactive?]} {
	    set mem [InteractiveMemoryEntry $config @mem Memory $mem]
	    debug.cmd/app {user choice = ($mem)}
	} else {
	    # Push through the config, and validation.
	    $config @mem set $mem
	    set mem [$config @mem]
	}
    }

    set min [app min-memory]

    if {$mem < $min} {
	display "Forcing use of minimum memory requirement: ${min}M"
	set mem $min
    }

    # Check capacity now, if the app will be started as part of the
    # push.
    if {!$starting && ![$client isv2]} {
	# Calculate required capacity based on defaults, if needed.
	if {($instances eq {}) || ($instances < 1)} {
	    set instances 1
	}
	set dtotal [expr {$mem * $instances}]
	client check-capacity $client $dtotal push
    }

    manifest mem= $mem
    return $mem
}

proc ::stackato::cmd::app::AppDisk {config path dockerimage} {
    debug.cmd/app {}

    set client [$config @client]

    # Note: Can pull manifest data only here.
    # During cmdr processing current app is not known.
    if {[$config @disk set?]} {
	set disk [$config @disk]
	debug.cmd/app {option   = ($disk)}
    } else {
	set disk [manifest disk]
	debug.cmd/app {manifest = ($disk)}
    }

    if {$disk eq {}} {
	set disk 2048
	debug.cmd/app {general default = ($disk)}

	if {[cmdr interactive?]} {
	    set disk [InteractiveMemoryEntry $config @disk Disk $disk]
	    debug.cmd/app {user choice = ($disk)}
	} else {
	    # Push through the config, and validation.
	    $config @disk set $disk
	    set disk [$config @disk]
	}
    }

    if {$dockerimage eq {}} {
	set min [application-size $path]
    } else {
	set min 0
    }
    incr min 10

    if {$disk < $min} {
	display "Forcing use of minimum disk requirement: ${min}M"
	set disk $min
    }

    manifest disk= $disk
    return $disk
}

proc ::stackato::cmd::app::AppDrains {config theapp} {
    debug.cmd/app {}
    # theapp -- v1: app name, v2: app instance

    set client [$config @client]
    if {[$client isv2]} {
	set appname [$theapp @name]
    } else {
	set appname $theapp
    }

    set mdrains [manifest drain]
    debug.cmd/app {drains = ($mdrains)}

    if {![llength $mdrains]} return

    if {[$client isv2]} {
	set json  [$theapp drain-list]
    } else {
	set have [$client server-version]
	if {![package vsatisfies $have 2.9]} {
	    display "  Ignoring drain specifications."
	    display "  Have version $have, need 2.10 or higher"

	    debug.cmd/app {/done, skip}
	    return
	}

	set json [$client app_drain_list $theapp]
    }

    set known {}
    # list (dict (name uri json))
    # convert to dict keyed by name.
    # match structure of 'mdrains'.
    foreach item $json {
	set n [dict get $item name]
	set u [dict get $item uri]
	set j [dict get $item json]
	dict set known $n url  $u
	dict set known $n json $j
    }

    foreach {k v} $mdrains {
	debug.cmd/app { drain $k = ($v)}
	# v = dict (uri json)

	# v is a dictionary describing the drain. Due to the
	# normalization done by the manifest processor we will never
	# see the simple style here, where v is directly the url of
	# the drain.

	# The keys of interest to us are:
	# - json	boolean
	# - url	string, the url to use. Optional. Default false.

	set url   [string tolower [string trimright [dict get  $v url] /]]
	set json  [expr {!![dict get' $v json 0]}]
	set djson [expr {$json ? "-json " : ""}]

	set cmd    Adding
	set detail {}

	if {[dict exists $known $k]} {
	    # Drain exists, check for change.
	    # On change delete and recreate.
	    # Otherwise skip.

	    set u [string tolower [string trimright [dict get $known $k url] /]]
	    set j [expr {!![dict get $known $k json]}]

	    if {$u eq $url && $j == $json} {
		display "  Skipping drain \[[color name $k]\], already present, unchanged"
		continue
	    }
	    # drain exists, has changed. delete, then recreate below.
	    if {[$client isv2]} {
		$theapp drain-delete $k
	    } else {
		$client app_drain_delete $theapp $k
	    }

	    set cmd    Recreating
	    set detail {as }
	    # Fall into creation below.
	}

	display "  $cmd drain \[[color name $k]\] $detail$djson$url " 0
	if {[$client isv2]} {
	    $theapp drain-create $k $url $json
	} else {
	    $client app_drain_create $theapp $k $url $json
	}
	display [color good OK]
    }

    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::AppServices {config theapp} {
    debug.cmd/app {}
    # theapp -- v1: app name, v2: app instance

    set client [$config @client]
    if {[$client isv2]} {
	set appname [$theapp @name]
    } else {
	set appname $theapp
    }

    set services [manifest services]
    debug.cmd/app {services = ($services)}

    set hd [$config @d]
    debug.cmd/app {harbor-debug = $hd}

    if {![llength $services]} {
	# No configuration data, do the services interactively, if
	# possible.
	if {[cmdr interactive?]} {
	    BindServices $client $theapp $appname
	}
    }
    if {[llength $services] || $hd} {
	# Process stackato.yml service information ...

	set known [ListKnown $client]
	set bound [ListBound $client $theapp]

	# Knowledge leak: We know the structure of $services as
	# :: dict (servicename -> dict ("type" -> vendor))
	# v2                          + label|vendor|provider|plan|

	foreach {sname sconfig} $services {
	    set vendor [dict get' $sconfig label \
			    [dict get' $sconfig type \
				 [dict get' $sconfig vendor \
				      {}]]]
	    debug.cmd/app {select label = ($vendor)}

	    if {$vendor eq "user-provided"} {
		# This is an UPSI. Create directly.

		debug.cmd/app {UPSI}

		if {![dict exists $sconfig credentials]} {
		    err "Manifest is missing the credentials for the user-provided service \"$sname\"."
		}

		set creds [dict get $sconfig credentials]
		debug.cmd/app {UPSI creds = ($creds)}

		CreateAndBind $client \
		    {} $sname $creds $theapp \
		    $known $bound

	    } else {
		debug.cmd/app {MSI}

		if {$sconfig eq {}} {
		    # We have only the service name.
		    # It must exist, and we can only bind it.

		    CreateAndBind $client \
			{} $sname {} $theapp \
			$known $bound
		} else {
		    # We have a config, find the corresponding plan.
		    # Create the service if missing. Check against plan
		    # if not.

		    set theplan [LocateService $client $sconfig]
		    debug.cmd/app {MSI plan = $theplan}

		    CreateAndBind $client \
			$theplan $sname {} $theapp \
			$known $bound
		}
	    }
	}

	if {$hd} {
	    # Create and bind harbor service <appname>-debug for debugging.
	    set sname ${appname}-debug

	    set theharbor [LocateService $client {type harbor}]
	    # NOTE: We might need more information here for v2,
	    # i.e. provider and plan.  These default to provider ==
	    # 'core' && plan == 'D100', which might be wrong for this
	    # service type.

	    set theservice [CreateAndBind $client \
				$theharbor $sname {} $theapp \
				$known $bound]

	    set cred [GetCredentials $client $theservice]

	    if {$cred eq {}} {
		display "Debugging now enabled on [color bad unknown] port."
		# Failed to transmit credentials is handled in GetCredentials (GetCred1 actually).

		# Signal to RunDebugger that we do not have the information it needs.
		SaveDebuggerInfo {} {}
	    } elseif {![dict exists $cred port]} {
		display "Debugging now enabled on [color bad unknown] port."
		display [color bad "Service failed to transmit its port information"]
		display [color bad "Please contact the administrator for \[[color name [ctarget get]]\]"]

		# Signal to RunDebugger that we do not have the information it needs.
		SaveDebuggerInfo {} {}
	    } else {
		set port [dict get $cred port]
		set host [dict get $cred host]
		display "[color good {Debugging now enabled}] on host [color name $host], port [color name $port]"

		# Stash information for RunDebugger.
		SaveDebuggerInfo $host $port
	    }
	}
    }
    return
}

proc ::stackato::cmd::app::LocateService {client spec} {
    debug.cmd/app {}
    # spec = manifest data for a service.
    # Knowledge leak, we know the structure here.
    # Generally: dict (key -> value)

    if {[$client isv2]} {
	set result [LocateService2 $client $spec]
    } else {
	set result [LocateService1 $client $spec]
    }

    debug.cmd/app {==> ($result)}
    return $result
}

proc ::stackato::cmd::app::LocateService1 {client spec} {
    debug.cmd/app {}
    # spec = manifest data for a service.
    # Knowledge leak, we know the structure here.
    # Generally: dict (key -> value)
    # v1: key "type" => name of service/vendor.
    return [dict get $spec type]
}

proc ::stackato::cmd::app::LocateService2 {client spec} {
    debug.cmd/app {}
    # spec = manifest data for a service.
    # Knowledge leak, we know the structure here.
    # Generally: dict (key -> value)
    # v2: key "label"|"type"|"vendor"| => name of service(type).
    #         (order of preference).
    #     key "version"               => restrict type, if present.
    #     key "provider"              => restrict type, if present.
    #     key "plan"                  => plan under service type.

    # See the validation types "servicetype" and "serviceplan" for
    # equivalent code, based on different input (cmdr config).
    #
    # TODO/FUTURE: See if we can consolidate and refactor here and
    # there.

    # All service types, plus associated plans, through a chain of
    # filters and transformers.
    set services [LS2_All]
    set services [LS2_Active         $services]
    set services [LS2_Label    $spec $services]
    set services [LS2_Version  $spec $services]
    set services [LS2_Provider $spec $services]
    set plans    [LS2_ToPlans        $services]
    set plans    [LS2_Plan     $spec $plans]

    # Reject specification if ambiguous, or not matching anything.
    set n [llength $plans]
    if {!$n} {
	err "Unable to locate service plan matching [jmap map dict $spec]"
    } elseif {$n > 1} {
	err "Found $n plans matching [jmap map dict $spec], unable to choose."
    }

    # assert: n == 1
    set plan [lindex $plans 0]

    debug.cmd/app {plan = ($plan)}
    return $plan
}

proc ::stackato::cmd::app::LS2_All {} {
    debug.cmd/app {}
    set services [v2 service list 1]

    debug.cmd/app {==> <[llength $services]>=($services)}
    return $services
}

proc ::stackato::cmd::app::LS2_Active {services} {
    debug.cmd/app {}
    if {![llength $services]} { return $services }

    # Drop inactive service types
    set services [MatchTrue $services @active]

    debug.cmd/app {==> <[llength $services]>=($services)}
    return $services
}

proc ::stackato::cmd::app::LS2_Label {spec services} {
    debug.cmd/app {}
    if {![llength $services]} { return $services }

    set label [dict get' $spec label \
		   [dict get' $spec type \
			[dict get' $spec vendor \
			     {}]]]

    debug.cmd/app {match ($label)}
    set services [Match= $services @label $label]

    debug.cmd/app {==> <[llength $services]>=($services)}
    return $services
}

proc ::stackato::cmd::app::LS2_Version {spec services} {
    debug.cmd/app {}
    if {![llength $services]} { return $services }

    # Not specified, ignore as filter.
    if {![dict exists $spec version]} { return $services }

    set version [dict get $spec version]

    debug.cmd/app {match ($version)}
    set services [Match= $services @version $version]

    debug.cmd/app {==> <[llength $services]>=($services)}
    return $services
}

proc ::stackato::cmd::app::LS2_Provider {spec services} {
    debug.cmd/app {}
    if {![llength $services]} { return $services }

    # Specified ?
    #   Match exactly that.
    # Not specified ?
    #   Match for 'core', then for empty string
    #   The second is required because "provider"
    #   essentially gone for V2 services.

    if {![dict exists $spec provider]} {
	foreach provider {core {}} {
	    debug.cmd/app {match ($provider)}
	    set sx [Match= $services @provider $provider]
	    debug.cmd/app {matched [llength $sx]}
	    if {[llength $sx]} break
	}
	set services $sx

    } else {
	set provider [dict get $spec provider]

	debug.cmd/app {match ($provider)}
	set services [Match= $services @provider $provider]
    }

    debug.cmd/app {==> <[llength $services]>=($services)}
    return $services
}

proc ::stackato::cmd::app::LS2_ToPlans {services} {
    debug.cmd/app {}
    if {![llength $services]} { return {} }

    set plans {}
    foreach s $services {
	lappend plans {*}[$s @service_plans]
    }

    debug.cmd/app {==> <[llength $plans]>=($plans)}
    return $plans
}

proc ::stackato::cmd::app::LS2_Plan {spec plans} {
    debug.cmd/app {}
    if {![llength $plans]} { return $plans }

    # Specified ?
    #   Match exactly that.
    # Not specified ?

    #   Match for 'default', then for 'free', then for any singlet
    #   plan. This is all restricted to free plans however, to avoid
    #   costing the user money on a paid plan by accident.

    if {![dict exists $spec plan]} {
	set plans [MatchTrue $plans @free]

	foreach plan {default free} {
	    debug.cmd/app {match ($plan)}
	    set px [Match= $plans @name $plan]
	    debug.cmd/app {matched [llength $px]}
	    if {[llength $px]} break
	}
	if {![llength $px]} {
	    if {[llength $plans] == 1} {
		debug.cmd/app {matched singlet, any name}
		set px $plans
	    }
	}
	set plans $px

    } else {
	set plan [dict get $spec plan]

	debug.cmd/app {match ($plan)}
	set plans [Match= $plans @name $plan]
    }

    debug.cmd/app {==> <[llength $plans]>=($plans)}
    return $plans
}

proc ::stackato::cmd::app::Match= {objlist field pattern} {
    debug.cmd/app {}
    return [struct::list filter $objlist [lambda {field pattern obj} {
	string equal $pattern [$obj $field]
    } $field $pattern]]
}

proc ::stackato::cmd::app::MatchTrue {objlist field} {
    debug.cmd/app {}
    return [struct::list filter $objlist [lambda {field obj} {
	$obj $field
    } $field]]
}

proc ::stackato::cmd::app::GetCredentials {client theservice} {
    if {[$client isv2]} {
	return [GetCred2 $theservice]
    } else {
	return [GetCred1 $client $theservice]
    }
}

proc ::stackato::cmd::app::GetCred1 {client theservice} {
    set si [$client get_service $theservice]

    if {![dict exists $si credentials]} {
	display [color bad "Service failed to transmit its credentials"]
	display [color bad "Please contact the administrator for \[[color name [ctarget get]]\]"]
	return {}
    } else {
	return [dict get $si credentials]
    }
}

proc ::stackato::cmd::app::GetCred2 {theservice} {
    return [$theservice @credentials]
}

proc ::stackato::cmd::app::ListKnown {client {all 0}} {
    debug.cmd/app {}
    # See also cmd::servicemgr::list-instances

    # result  = dict (label --> details)
    # details = list (bind-info manifest-info)

    if {[$client isv2]} {
	return [ListKnown2]
	# bind-info     = service-instance instance
	# manifest-info = dict (label, plan, version, provider)
    } else {
	return [ListKnown1 $client $all]
	# bind-info     =!all service name
	#               | all full service structure
	# manifest-info = dict (type -> service type)

    }
}

proc ::stackato::cmd::app::ListKnown1 {client all} {
    debug.cmd/app {}
    set res {}
    foreach s [$client services] {
	debug.cmd/app { known :: $s}

	set name [dict getit $s name]
	set type [dict getit $s vendor]
	set detail [expr {$all ? $s : $name}]
	set     details {}
	lappend details $detail
	lappend details [dict create type $type]

	debug.cmd/app {++ $name = ($details)}
	dict set res $name $details
    }

    debug.cmd/app {==> ($res)}
    return $res
}

proc ::stackato::cmd::app::ListKnown2 {} {
    debug.cmd/app {}
    # 3 levels deep, get all related things on both sides, i.e.
    # - service-bindings and applications, and
    # - plans and services.
    set res {}
    set thespace [cspace get]

    # Bug 103446: Clear the cache to pick up any services created by a
    # preceding application in the same push command
    # (multi-application push).
    $thespace @service_instances decache

    foreach service [$thespace @service_instances get* {
	depth         3
	user-provided true
    }] {
	set     details {}
	lappend details $service
	try {
	    lappend details [$service @service_plan manifest-info]
	} on error {e o} {
	    lappend details [dict create credentials [$service @credentials]]
	}
	dict set res [$service @name] $details
    }
    return $res
}

proc ::stackato::cmd::app::ListBound {client theapp} {
    if {[$client isv2]} {
	return [ListBound2 $theapp]
	# result = list ( s-i name )
    } else {
	return [ListBound1 $client $theapp]
	# result = list ( s-i instance )
    }
}

proc ::stackato::cmd::app::ListBound1 {client theapp} {
    return [dict get' [$client app_info $theapp] services {}]
}

proc ::stackato::cmd::app::ListBound2 {theapp} {
    return [$theapp @service_bindings @service_instance]
}

proc ::stackato::cmd::app::AppEnvironment {cmode config theapp defaultmode} {
    # cmode = commit mode - relevant to v2, only.
    # values: defered, commit, N/A
    debug.cmd/app {}
    global env

    set client [$config @client]

    set oenv [AE_CmdlineGet  $config]
    set menv [AE_ManifestGet $config]

    if {![dict size $menv] &&
	![dict size $oenv]} {
	debug.cmd/app {/done, do nothing}
	if {[$client isv2]} {
	    return {}
	} else {
	    return [$client app_info $theapp]
	}
    }

    set mode [$config @env-mode]
    if {$mode eq {}} { set mode $defaultmode }
    # modes: preserve, append, replace.
    debug.cmd/app {mode = $mode}

    lassign [AE_ApplicationGet $client $theapp $mode] appenv app
    # v1: app = app data, v2: app empty, irrelevant

    # Process the manifest environment specifications. Associated oenv
    # settings are used and then removed (= implicitly marked as done).
    foreach {k v} $menv {
	debug.cmd/app {  Aenv $k = ($v)}

	# Note: user settings (oenv) override preserve mode,
	# get applied regardless.
	if {![dict exists $oenv $k] &&
	    ($mode eq "preserve") &&
	    [dict exists $appenv $k]} {
	    # In preserve mode, stronger than append, we do NOT
	    # overwrite existing variables with manifest
	    # information.
	    display "  Preserving Environment Variable \[[color name $k]\]"
	    continue
	}

	lassign [AE_DetermineValue $k $v $oenv] value hidden
	# Mark as done.
	dict unset oenv $k

	# ===========================================================
	# inlined proc 'EnvAdd', see this file.
	#set appenv [lsearch -inline -all -not -glob $appenv ${k}=*]

	set cmd Adding
	if {($mode eq "append") && [dict exists $appenv $k]} {
	    set cmd Overwriting
	}
	dict set appenv $k $value

	if {$hidden} {
	    # Reformat for display to prevent us from showing the
	    # hidden value now.
	    regsub -all . $value * value
	}
	set item [color name ${k}]=$value
	display "  $cmd Environment Variable \[$item\]"
    }

    # Process all leftover command line environment variables,
    # i.e. those not done by the previous loop. They are always
    # written, regardless of mode.

    foreach {k v} $oenv {
	set cmd Adding
	if {[dict exists $appenv $k]} {
	    set cmd Overwriting
	}

	dict set appenv $k $v
	set item [color name ${k}]=$v
	display "  $cmd Environment Variable \[$item\]"
    }

    # Commit ...
    if {[$client isv2]} {
	set res [AE_WriteV2 $cmode $theapp $appenv]
    } else {
	set res [AE_WriteV1 $cmode $client $theapp $app $appenv]
    }

    debug.cmd/app {/done ==> ($res)}
    return $res
}

proc ::stackato::cmd::app::AE_ManifestGet {config} {
    debug.cmd/app {}

    set menv [manifest env]

    # Inject environment variables for the Komodo debugger into
    # the application.

    if {[$config @stackato-debug set?]} {
	lassign [$config @stackato-debug] host port
	## (*) Special, see (**).
	lappend menv STACKATO_DEBUG_PORT_NUMBER $port
	lappend menv STACKATO_DEBUG_HOST        $host
    }

    debug.cmd/app {==> ($menv)}
    return $menv
}

proc ::stackato::cmd::app::AE_ApplicationGet {client theapp mode} {
    debug.cmd/app {}

    set appenv {}

    if {[$client isv2]} {
	set app {}
	try {
	    set theenv [$theapp @environment_json]
	} trap {STACKATO CLIENT V2 UNDEFINED ATTRIBUTE} {e o} {
	    set theenv {}
	}
    } else {
	set app [$client app_info $theapp]
	set theenv [dict get $app env]
    }

    if {$mode ne "replace"} {
	# append|preserve
	debug.cmd/app {A|P: Baseline = ($theenv)}

	# Use existing environment as baseline
	if {[$client isv2]} {
	    set appenv $theenv
	} else {
	    set appenv [Env2Dict [dict get $app env]]
	}
    }

    debug.cmd/app {==> ($appenv)}
    return [list $appenv $app]
}

proc ::stackato::cmd::app::AE_CmdlineGet {config} {
    debug.cmd/app {}

    # Convert from the list of pairs provided by cmdr to a regular
    # dictionary.
    #
    # FUTURE: push this into the envassign validation type, if
    # possible.

    set result {}
    foreach item [$config @env] {
	lassign $item k v
	lappend result $k $v
    }

    debug.cmd/app {==> ($result)}
    return $result
}

proc ::stackato::cmd::app::AE_DetermineValue {varname vardef oenv} {
    debug.cmd/app {}

    global env ;# Process environment (we can 'inherit' from).

    # (*) Note: The specials defined at (*) provide the value, not a
    # manifest variable definition. Treat them accordingly,
    # bypassing the whole other processing.
    if {$varname in {STACKATO_DEBUG_HOST STACKATO_DEBUG_PORT_NUMBER}} {
	debug.cmd/app {==> h0 ($vardef)}
	return [list $vardef 0]
    }

    # "vardef" is a dictionary describing the variable. Due to the
    # normalization done by the manifest loading logic we will never
    # see the old-style here, where v is directly the value of the
    # variable.

    # The keys of interest to us are:
    # - required	boolean
    # - inherit		boolean
    # - default		string, the value to use if nothing is entered
    # - prompt		string, label to use when prompting entry
    # - choices		list of strings, allowed values for the variable
    # - hidden		boolean, true => choices not allowed

    # Step 1. Determine the (default) value from the various places.

    unset -nocomplain value ;# start with NULL, aka 'undefined'.

    set required [dict get' $vardef required 0]
    set inherit  [dict get' $vardef inherit  0]
    set hidden   [dict get' $vardef hidden   0]

    if {![dict exists $vardef default] && !$required} {
	err "Bad description of variable \"$varname\", not required, default value missing."
    }
    if {$hidden && [dict exists $vardef choices]} {
	err "Bad description of variable \"$varname\", hidden forbids use of choices."
    }
    if {[dict exists $vardef default]} {
	set value [dict get $vardef default]
    }
    if {$inherit && [info exists env($varname)]} {
	set value $env($varname)
    }
    if {[dict exists $oenv $varname]} {
	set value [dict get $oenv $varname]
    }

    # Select action based on the decision table below, for the
    # various properties of the variable's value (D here)
    #
    #    Specified      Required        Interactive     Action
    #    ---------      --------        -----------     ------
    # A  no             no              no              ignore
    # B  no             no              yes                     prompt, empty string is default
    # C  no             yes             no              fail
    # D  no             yes             yes                     prompt, empty string is default
    # E  yes            no              no              use
    # F  yes            no              yes                     prompt, D is default
    # G  yes            yes             no              use
    # H  yes            yes             yes                     prompt, D is default
    #    ---------      --------        -----------     -------

    if {![info exists value] &&
	![cmdr interactive?]} {
	if {$required} {
	    # (C) Not specified, required, non-interactive.
	    err "Required variable \"$varname\" not set"
	} else {
	    # (A) Not specified, not required, non-interactive.
	    debug.cmd/app {  Aenv /missing /not-required /no-prompt => ignore}
	    continue
	}
    }

    if {![info exists value]} {
	# (B, D) Empty string as default for prompt.
	debug.cmd/app {  Aenv /default empty}
	set value ""
    }

    debug.cmd/app {  Aenv value = ($value)}

    if {[cmdr interactive?]} {
	# (B,D,F,H) Prompt, with various defaults

	debug.cmd/app {  Aenv query user}

	# (a) Get the label for the prompting out of the
	# description, or use a standard phrase.
	set prompt [dict get' $vardef prompt "Enter $varname"]

	# (b) Free form text, or choices from a list.
	if {[dict exists $vardef choices]} {
	    set choices [dict get $vardef choices]
	    set value [ask choose $prompt $choices $value]
	} else {
	    while {1} {
		if {$hidden} {
		    set response [ask string* "$prompt: "]
		} else {
		    set response [ask string "$prompt \[[color yes $value]\]: "]
		}
		if {$required && ($response eq "") && ($value eq "")} {
		    display [color bad "$varname requires a value"]
		    continue
		}
		break
	    }
	    if {$response ne {}} { set value $response }
	}
    } ; # else (E, G) non-interactive, simply use our value.

    # Validate value regardless of source.
    if {[dict exists $vardef choices]} {
	set choices [dict get $vardef choices]
	if {$value ni $choices} {
	    set choices [linsert '[join $choices {', '}]' end-1 or]
	    err "Expected one of $choices for \"$varname\", got \"$value\""
	}
    }

    debug.cmd/app {==> h$hidden ($value)}
    return [list $value $hidden]
}

proc ::stackato::cmd::app::AE_WriteV1 {cmode client appname app envdict} {
    debug.cmd/app {}

    display "Updating environment ... " 0

    # Convert dictionary into the CF v1 structure, a list of assignments.
    set ae {}
    dict for {k v} $envdict { lappend ae ${k}=$v }

    dict set app env $ae

    if {[string equal $cmode commit]} {
	$client update_app $appname $app
	display [color good OK]
	return $app
    }

    # Defered, return the modified structure.
    return $app
}

proc ::stackato::cmd::app::AE_WriteV2 {mode theapp envdict} {
    debug.cmd/app {}

    if {[string equal $mode commit]} {
	display "Updating environment ... " 0
	$theapp @environment_json set $envdict
	$theapp commit
	display [color good OK]
    } else {
	$theapp @environment_json set $envdict
    }
    return
}

proc ::stackato::cmd::app::CheckDeployDirectory {path} {
    debug.cmd/app {}
    if {![file exists $path]} {
	err "Deployment path does not exist: $path"
    }

    if {[file isdirectory $path]} {
	# Bug 90777. Reject empty directories.
	if {[llength [glob -nocomplain -directory $path * .*]] < 3} {
	    # Note: glob finds . and ..
	    err {Deployment path is an empty directory}
	}
    } ;# else: A file is acceptable. TODO: Check that it is a zip archive?!

    set path   [file nativename [file normalize $path]]
    set tmpdir [file nativename [file normalize [fileutil::tempdir]]]
    
    if {$path ne $tmpdir} return

    err "Can't deploy applications from staging directory: \[$tmpdir\]"
}

proc ::stackato::cmd::app::RuntimeMap {runtimes} {
    debug.cmd/app {}
    set map  {}
    set full {}

    # Remember the target names, to keep them unambiguous.
    foreach {name info} $runtimes {
	dict set full $name .
	dict lappend map $name                  $name
	dict lappend map [string tolower $name] $name
    }

    foreach {name info} $runtimes {
	set desc [dict get $info description]

	foreach p [Prefixes $name] {
	    if {[dict exists $full $p]} continue
	    dict lappend map $p $name
	    set p [string tolower $p]
	    if {[dict exists $full $p]} continue
	    dict lappend map $p $name
	}
	foreach p [Prefixes $desc] {
	    if {[dict exists $full $p]} continue
	    dict lappend map $p $name
	    set p [string tolower $p]
	    if {[dict exists $full $p]} continue
	    dict lappend map $p $name
	}
	foreach p [Prefixes [string map {{ } {}} $desc]] {
	    if {[dict exists $full $p]} continue
	    dict lappend map $p $name
	    set p [string tolower $p]
	    if {[dict exists $full $p]} continue
	    dict lappend map $p $name
	}
    }

    # Reduce duplicates
    dict for {k vlist} $map {
	dict set map $k [lsort -dict -unique $vlist]
    }

    # Map of strings to runtimes they represent.
    return $map
}

proc ::stackato::cmd::app::Prefixes {s} {
    debug.cmd/app {}
    set p   {}
    set res {}
    foreach c [split $s {}] {
	append p $c
	lappend res $p
    }
    return $res
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::CreateAndBind {client vendor service details theapp {known {}} {bound {}}} {
    debug.cmd/app {}

    # vendor  = v1: service name  | requested service type|plan
    #           v2: plan instance |
    #           v2! plan can be empty => no creation, no matching.

    # Under v2 vendor eq "" indicates UPSI and details == credentials.
    #          vendor ne "" is MSI, and details is ignored.

    # Both vendor == credentials == "" means that the service must exist.
    # It cannot be created, only found and bound. Checking of requested
    # vs. existing plan is not possible either.

    # service = instance name (to be) | requested service, by name

    # known = dict (s-i name -> (s-i name,     minfo)) v1
    #         dict (s-i name -> (s-i instance, minfo)) v2
    # minfo irrelevant here, and ignored.

    # bound = list (s-i name)     v1
    #         list (s-i instance) v2

    # Unknown services are created and bound, known services just bound.

    display "Service [color name $service]:"

    if {[dict exists $known $service]} {
	# Requested service is known.
	# Need existing type|plan

	set theservice [lindex [dict get $known $service] 0]
	# v1: name, v2: instance

	# Verify that the found service matches the expectations of
	# the application. I.e. not just the proper name, but also the
	# proper service-plan and -type. It is a bit complicated to
	# deal with the MSI vs UPSI difference as well.

	if {[$client isv2]} {
	    # v2: theservice - instance, s-i, existing
	    #     theplan    - instance, s-plan, existing
	    #     vendor     - instance, s-plan, requested

	    if {($vendor eq {}) && ($details eq {})} {
		# Checking requires either MSI, or UPSI.
		# This is neither, not known. No checking possible.
		display [color warning "  No configuration found in the manifest."]
		display [color warning "  Unable to check against the actual service."]
	    } else {
		if {[catch {
		    set theplan [$theservice @service_plan]
		}]} {
		    # This branch is v2 only!! theservice has no plan, i.e. is
		    # an UPSI. Check that we are given an UPSI as well, and
		    # that it is the same (in terms of credentials).

		    if {$vendor ne {}} {
			ServiceConflict $service [$vendor name] user-provided
		    } elseif {[dict sort $details] ne [dict sort [$theservice @credentials]]} {
			ServiceConflict $service user-provided user-provided { and different credentials}
		    }
		} else {
		    # theservice has a plan, i.e. is an MSI. Check that we
		    # were are given an MSI as well, and that it is the same
		    # in terms of plans.

		    if {$vendor eq {}} {
			ServiceConflict $service user-provided [$theplan name]
		    } elseif {![$vendor == $theplan]} {
			ServiceConflict $service [$vendor name] [$theplan name]
		    }
		}
	    }
	} else {
	    # v1: theservice - name | existing service instance
	    #     theplan    - name | existing type
	    #     vendor     - name | requested type|plan

	    debug.cmd/app {/v1}
	    debug.cmd/app { service = $theservice}
	    debug.cmd/app { - spec  = [dict get $known $service]}
	    debug.cmd/app { - minfo = [lindex [dict get $known $service] 1]}
	    debug.cmd/app { - stype = [dict get [lindex [dict get $known $service] 1] type]}
	    debug.cmd/app { vendor  = $vendor}
	    # known.(s-i-name).[1].(type) -> s-type.

	    set theplan [dict get [lindex [dict get $known $service] 1] type]
	    if {$vendor ne $theplan} {
		ServiceConflict $service $vendor $theplan
	    }
	}
    } else {
	# Unknown, create
	# v1: name, v2: instance

	if {($vendor eq {}) && ($details eq {})} {
	    # Neither MSI, nor UPSI, no spec at all. Creation not possible.
	    err "  Unable to create service without configuration."
	}

	if {$vendor ne {}} {
	    # MSI
	    set theservice [service create-with-banner $client $vendor $service 1]
	} else {
	    # UPSI
	    set theservice [service create-udef-with-banner $client $details $service 1]
	}
    }

    if {$theservice ni $bound} {
	service bind-with-banner $client $theservice $theapp
    }

    debug.cmd/app {==> ($theservice)}
    return $theservice
}

proc ::stackato::cmd::app::ServiceConflict {service need have {suffix {}}} {
    err "  The application's request for a $need service \"$service\" conflicts with a $have service of the same name${suffix}."
}

proc ::stackato::cmd::app::BindServices {client theapp appname} {
    ## Note: Assumed to be called only when prompting is ok. Making
    ## it unnecessary to perform the same check here, again.

    debug.cmd/app {}

    # v1: theapp - app name, v2: theapp - app instance
    # appname - app name, always

    set user_services [ListKnown $client 1]
    set services      [ListPlans $client]

    debug.cmd/app {existing      = $user_services}
    debug.cmd/app {provisionable = $services}

    set bound {}
    # dict (service (instance) name --> manifest data)

    # Bind existing services, if any.
    if {
	[llength $user_services] &&
	[ask yn "Bind existing services to '[color name $appname]' ? " no]
    } {
	lappend bound {*}[ChooseExistingServices $client $theapp $user_services]
    }

    # Bind new services, if any provisionable.
    if {
	[llength $services] &&
	[ask yn "Create services to bind to '[color name $appname]' ? " no]
    } {
	lappend bound {*}[ChooseNewServices $client $theapp $services]
    }

    if {[llength $bound]} {
	manifest services= $bound
    }
    return
}

proc ::stackato::cmd::app::ListPlans {client} {
    # See also cmd::servicemgr::list-plans
    # result = dict ( label --> details )
    # details = list (create-info manifest-info)

    if {[$client isv2]} {
	return [ListPlans2]
	# label         = plan name + service label
	# create-info   = plan instance
	# manifest-info = dict (label, plan, version, provider)
    } else {
	return [ListPlans1 $client]
	# label = service type
	# create-info = service type
	# manifest-info = dict ("type" -> service type)
    }
}

proc ::stackato::cmd::app::ListPlans1 {client} {
    set res {}
    foreach {service_type value} [$client services_info] {
	foreach {vendor version} $value {
	    set     details {}
	    lappend details $vendor
	    lappend details [dict create type $vendor]
	    dict set res $vendor $details
	}
    }
    return $res
}

proc ::stackato::cmd::app::ListPlans2 {} {
    set res {}
    # chosen depth delivers plans, their services, and instances.
    # restrict relations to ignore the last.
    foreach plan [v2 service_plan list 1 include-relations service] {
	set     details {}
	lappend details $plan
	lappend details [$plan manifest-info]
	dict set res [$plan name] $details
    }
    return $res
}

proc ::stackato::cmd::app::ChooseExistingServices {client theapp user_services} {
    ## Note: Assumed to be called only when prompting is ok. Making
    ## it unnecessary to perform the same check here, again.

    debug.cmd/app {}

    # user_services = dict (label --> detail)
    # detail        = list (bind-info manifest-info)

    #set vmap [VendorMap $client $user_services]
    #set cmap [Choices   $client $user_services]
    #set none "<None of the above>"
    #lappend choices $none

    set bound {}
    while {1} {
	set choices [lsort -dict [dict keys $user_services]]

	set name [ask menu \
		      "Which one ?" "Choose: " \
		      $choices]

	# Convert choice to s-instance and manifest data.
	lassign [dict get $user_services $name] theservice mdetails

	service bind-with-banner $client $theservice $theapp

	# Save for manifest.
	lappend bound $name $mdetails

	if {![ask yn "Bind another ? " no]} break

	# Remove the chosen service from the possible selections.
	# Binding twice is nonsensical.
	dict unset user_services $name
    }

    return $bound
}

proc ::stackato::cmd::app::VendorMap {client instances} {
    set vmap {}
    if {[$client isv2]} {
	foreach si $instances {
	    dict set vmap \
		[$si @name] \
		[$si @service_plan name]
	}
    } else {
	foreach si $instances {
	    dict set vmap \
		[dict getit $si name] \
		[dict getit $si vendor]
	}
    }
    return $vmap
}

proc ::stackato::cmd::app::Choices {client instances} {
    set cmap {}
    if {[$client isv2]} {
	foreach si $instances {
	    dict set cmap [$si @name] $si
	}
    } else {
	foreach si $instances {
	    set name [dict getit $si name]
	    dict set cmap $name $name
	}
    }
    return $cmap
}

proc ::stackato::cmd::app::ChooseNewServices {client theapp services} {
    # v1: theapp - app name, v2: theapp - app instance

    ## Note: Assumed to be called only when prompting is ok. Making
    ## it unnecessary to perform the same check here, again.

    debug.cmd/app {}

    # services = dict (label -> detail)
    # detail   = list (create-info manifest-info)
    set choices [lsort -dict [dict keys $services]]

    #set none "<None of the above>"
    #lappend service_choices $none

    set bound {}
    while {1} {
	set choice [ask menu \
			"What kind of service ?" "Choose: " \
			$choices]

	# Convert choice into service type or (v2) plan, and
	# information for a manifest.
	lassign [dict get $services $choice] theplan mdetails

	set default_name [service random-name-for $choice]
	set service_name \
	    [ask string \
		 "Specify the name of the service \[[color yes $default_name]\]: " \
		 $default_name]

	CreateAndBind $client $theplan $service_name {} $theapp

	lappend bound $service_name $mdetails

	if {![ask yn "Create another ? " no]} break
    }

    return $bound
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::dbshell {config} {
    debug.cmd/app {}
    manifest user_all each $config ::stackato::cmd::app::DbShell
    return
}

proc ::stackato::cmd::app::DbShell {config theapp} {
    debug.cmd/app {}

    set client [$config @client]
    if {[$client isv2]} {
	set service [DbShellV2 $config $theapp]
    } else {
	set service [DbShellV1 $client $config $theapp]
    }

    ssh run $config [list dbshell $service] $theapp 0
    return
}

proc ::stackato::cmd::app::DbShellV1 {client config theapp} {
    debug.cmd/app {}

    set app [$client app_info $theapp]

    debug.cmd/app {app info = [jmap appinfo $app]}

    set services [dict get $app services]

    debug.cmd/app {services = [jmap map array $services]}

    # No services. Nothing to convert.
    if {![llength $services]} {
	err "No services are bound to application \[$theapp\]"
    }

    if {[$config @service set?]} {
	set servicename [$config @service]
    } else {
	# No service specified, auto-select it.

	# Go through the services and eliminate all which are not
	# supported. The list at (x$x) below must be kept in sync with
	# what is supported by the server side dbshell script.

	set ps [$client services]
	debug.cmd/app {provisioned = [jmap services [dict create provisioned $ps]]}

	# XXX see also c_services.tcl, method tunnel, ProcessService. Refactor and share.
	# Extract the name->vendor map
	set map {}
	foreach p $ps {
	    lappend map [dict get $p name] [dict get $p vendor]
	}

	set supported {}
	foreach service $services {
	    set vendor [dict get $map $service]
	    # (x$x)
	    if {![AcceptDbshell $vendor]} continue
	    lappend supported $service
	}
	set services $supported

	# end XXX

	if {[llength $services] > 1} {
	    err "More than one service found; you must specify the service name.\nWe have: [join $services {, }]"
	} else {
	    # Just one service is possible, take it.
	    set servicename [lindex $services 0]
	}
    }

    # Search for service with matching name.
    if {$servicename ni $services} {
	err "Service \[$servicename\] is not known."
    }

    return $servicename
}

proc ::stackato::cmd::app::DbShellV2 {config theapp} {
    debug.cmd/app {}
    # All services bound to the chosen application.
    set services [$theapp @service_bindings @service_instance]

    debug.cmd/app {services = $services}

    # No services. Nothing to convert.
    if {![llength $services]} {
	err "No services are bound to application \[[$theapp @name]\]"
    }

    if {[$config @service set?]} {
	set servicename [$config @service]

	set services [struct::list filter $services [lambda {x s} {
	    string equal $x [$s @name]
	} $servicename]]

	if {![llength $services]} {
	    err "Service \[$servicename\] is not known."
	} elseif {[llength $services] > 1} {
	    err "More than one service found; the name ambiguous."
	}
    } else {
	# No service specified, auto-select it.

	# Go through the services and eliminate all which are not
	# supported. The list at (x$x) below must be kept in sync with
	# what is supported by the server side dbshell script.

	# XXX see also c_services.tcl, method tunnel, ProcessService. Refactor and share.
	# Extract the name->vendor map

	set supported {}
	set snames    {}
	foreach service $services {
	    if {[catch {
		set p [$service @service_plan]
	    }]} continue
	    set vendor [$p @service @label]
	    # (x$x)
	    if {![AcceptDbshell $vendor]} continue
	    lappend supported $service
	    lappend snames    [$service @name]
	}
	set services $supported
	# end XXX

	if {[llength $services] > 1} {
	    err "More than one service found; you must specify the service name.\nWe have: [join [lsort -dict $snames] {, }]"
	} elseif {![llength $services]} {
	    err "No services supporting dbshell found."
	}
    }

    # Just one service is possible, take it.
    set service [lindex $services 0]

    # NOTE: While this is for CFv2 the 'dbshell' argument is still the
    # service's name, not its uuid. We are acessing from within an
    # application it is bound to, and the application's environment
    # identifies the service by name. As applications can (I believe)
    # only be bound to services in the same space and service names
    # are (I believe) unique within the space, even if not across
    # spaces this means of identification is ok.

    return [$service @name]
}

proc ::stackato::cmd::app::AcceptDbshell {vendor} {
    # See also ::stackato::cmd::servicemgr::AcceptTunnel, consolidate
    expr {$vendor in {
	oracledb mysql redis mongodb postgresql
    }}
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::open_browser {config} {
    debug.cmd/app {}

    set appname [$config @application]
    debug.cmd/app {appname = ($appname)}

    if {$appname eq "api"} {
	# Special code to open the current target's console.
	set url [ctarget get]

	debug.cmd/app {open/target ($url)}
	browse url $url
	return
    }

    if {[regexp {^https?://} $appname]} {
	# Argument is not an appname, but an url already.
	# Browse directly to it.

	debug.cmd/app {open/url ($appname)}
	browse url $appname
	return
    }

    # Convert appname to url, then browse to it.
    debug.cmd/app {open/for-app ($appname)}
    manifest user_all each $config ::stackato::cmd::app::OpenBrowser
    return
}

proc ::stackato::cmd::app::OpenBrowser {config theapp} {
    debug.cmd/app {}

    set client [$config @client]

    # client v1, v2 = theapp is name (because of specials)

    if {[$client isv2]} {
	debug.cmd/app {/v2}

	set theapp [appname validate [$config @application self] $theapp]
	set uri [$theapp uri]
	set appname [$theapp @name]
    } else {
	debug.cmd/app {/v1}

	set app [$client app_info $theapp]
	set uri [lindex [dict get $app uris] 0]
	set appname $theapp
    }

    debug.cmd/app {raw ($uri)}

    if {$uri eq {}} {
	err "Application \[$appname\] has no url to open."
    }

    set uri [url canon $uri]
    regsub {^https} $uri http uri

    debug.cmd/app {==> '$uri'}

    browse url $uri
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::run {config} {
    debug.cmd/app {}
    # Same backend as 'ssh' below.
    # No special "api" and the like.
    manifest quiet
    manifest user_all each $config ::stackato::cmd::app::SSH
    return
}

proc ::stackato::cmd::app::securesh {config} {
    debug.cmd/app {}
    manifest quiet

    # Handle the special "api" first.
    if {[$config @application set?] &&
	[$config @application] eq "api"} {
	ssh cc $config [$config @command]
	return
    }

    manifest user_all each $config ::stackato::cmd::app::SSH
    return
}

proc ::stackato::cmd::app::SSH {config theapp} {
    debug.cmd/app {}
    # @dry

    if {$theapp eq {}} {
	err "No application specified"
    }

    set args [$config @command]
    if {[$config @all]} {
	if {![llength $args]} {
	    err "No command to run, required for --all"
	}

	if {[[$config @client] isv2]} {
	    set appname [$theapp @name]
	} else {
	    set appname $theapp
	}

	foreach {n i} [$theapp instances] {
	    if {![$config @banner]} {
		ssh run $config $args $theapp $n
	    } else {
		display "=== run $appname\#$n: $args ==="
		ssh run $config $args $theapp $n
		display ""
	    }
	}
    } else {
	set instance [$config @instance]

	if {[[$config @client] isv2]} {
	    set instance [$instance index]
	}

	ssh run $config $args $theapp $instance
    }
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::securecp {config} {
    debug.cmd/app {}
    manifest quiet
    manifest user_all each $config ::stackato::cmd::app::SCP
    return
}

proc ::stackato::cmd::app::SCP {config theapp} {
    debug.cmd/app {}

    set paths    [$config @paths]
    set instance [$config @instance]

    if {[llength $paths] < 2} {
	$config notEnough ;# scp. proper additional check
    }

    if {[[$config @client] isv2]} {
	set instance [$instance index]
    }

    ssh copy $config $paths $theapp $instance
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::env_add {config} {
    debug.cmd/app {}
    manifest user_all each $config ::stackato::cmd::app::EnvAdd
    return
}

proc ::stackato::cmd::app::EnvAdd {config theapp} {
    debug.cmd/app {}

    set client [$config @client]
    set k      [$config @varname]
    set v      [$config @value]

    # client v1 = theapp is name
    # client v2 = theapp is entity instance

    if {[$client isv2]} {
	debug.cmd/app {/v2: $theapp ('[$theapp @name]' in [$theapp @space full-name] of [ctarget get])}
	# CFv2 API...
	set env [$theapp @environment_json]
	# env is dictionary

	set item [color name ${k}]=$v

	dict set env $k $v

	display "Adding Environment Variable \[$item\] ... " false

	$theapp @environment_json set $env
	$theapp commit

    } else {
	debug.cmd/app {/v1: '$theapp'}
	# CFv1 API...

	set app [$client app_info $theapp]
	set env [dict get' $app env {}]

	set item ${k}=$v

	set     newenv [lsearch -inline -all -not -glob $env ${k}=*]
	lappend newenv $item

	set item [color name ${k}]=$v
	display "Adding Environment Variable \[$item\] ... " false

	dict set app env $newenv
	$client update_app $theapp $app
    }

    check-app-for-restart $config $theapp
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::env_delete {config} {
    debug.cmd/app {}
    manifest user_all each $config ::stackato::cmd::app::EnvDelete
    return
}

proc ::stackato::cmd::app::EnvDelete {config theapp} {
    debug.cmd/app {}

    set client  [$config @client]
    set varname [$config @varname]

    # client v1 = theapp is name
    # client v2 = theapp is entity instance

    if {[$client isv2]} {
	debug.cmd/app {/v2: $theapp ('[$theapp @name]' in [$theapp @space full-name] of [ctarget get])}
	# CFv2 API...
	set env [$theapp @environment_json]
	# env is dictionary

	dict unset env $varname

	display "Deleting Environment Variable \[[color name $varname]\] ... " false

	$theapp @environment_json set $env
	$theapp commit

    } else {
	debug.cmd/app {/v1: '$theapp'}
	# CFv1 API...

	set app [$client app_info $theapp]
	set env [dict get' $app env {}]

	set newenv [lsearch -inline -all -not -glob $env ${varname}=*]

	display "Deleting Environment Variable \[[color name $varname]\] ... " false

	if {$newenv eq $env} {
	    display [color good OK]
	    return
	}

	dict set app env $newenv
	$client update_app $theapp $app
    }

    check-app-for-restart $config $theapp
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::env_list {config} {
    debug.cmd/app {}
    manifest user_all each $config ::stackato::cmd::app::EnvList
    return
}

proc ::stackato::cmd::app::EnvList {config theapp} {
    debug.cmd/app {}

    # client v1 = theapp is name
    # client v2 = theapp is entity instance

    set client [$config @client]

    if {[$client isv2]} {
	debug.cmd/app {/v2: $theapp ('[$theapp @name]' in [$theapp @space full-name] of [ctarget get])}
	# CFv2 API...
	set env  [$theapp @environment_json]
	set senv [$theapp system-env]
	# env is dictionary

    } else {
	debug.cmd/app {/v1: '$theapp'}
	# CFv1 API...

	set app [$client app_info $theapp]
	set env  [Env2Dict [dict get' $app env {}]]
	set senv {}
    }

    set env [dict sort $env]
    if {[$client isv2]} {
	set senv [dict sort $senv]
    }

    debug.cmd/app {env = ($env)}

    if {[$config @json]} {
	display [jmap env $env]
	if {[$client isv2]} {
	    display [jmap env $senv]
	}
	return
    }

    if {![dict size $env] && ![dict size $senv]} {
	display [color note "No Environment Variables"]
	return
    }

    if {[$client isv2]} {
	if {[dict size $env]} {
	    display "User:"
	    [table::do t {Variable Value} {
		dict for {k v} $env {
		    $t add $k $v
		}
	    }] show display
	}

	if {[dict size $senv]} {
	    display "System:"
	    [table::do t {Variable Value} {
		dict for {k v} $senv {
		    $t add $k $v
		}
	    }] show display
	}
    } else {
	[table::do t {Variable Value} {
	    dict for {k v} $env {
		$t add $k $v
	    }
	}] show display
    }
    return
}

proc ::stackato::cmd::app::Env2Dict {env} {
    # Convert a v1 list of a=b environment variable assignments into a
    # dictionary., the common internal structure.
    set tmp {}
    foreach e $env {
	regexp {^([^=]*)=(.*)$} $e -> k v
	dict set tmp $k $v
    }
    return $tmp
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::drain_add {config} {
    debug.cmd/app {}
    manifest user_all each $config ::stackato::cmd::app::DrainAdd
    return
}

proc ::stackato::cmd::app::DrainAdd {config theapp} {
    debug.cmd/app {}

    set client [$config @client]
    set drain  [$config @drain]
    set uri    [$config @uri]
    set json   [$config @json]

    display "Adding [expr {$json?"json ":""}]drain \[[color name $drain]\] ... " false

    if {[$client isv2]} {
	$theapp drain-create $drain $uri $json
    } else {
	$client app_drain_create $theapp $drain $uri $json
    }

    display [color good OK]
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::drain_delete {config} {
    debug.cmd/app {}
    manifest user_all each $config ::stackato::cmd::app::DrainDelete
    return
}

proc ::stackato::cmd::app::DrainDelete {config theapp} {
    debug.cmd/app {}

    set client [$config @client]
    set drain  [$config @drain]

    display "Deleting drain \[[color name $drain]\] ... " false

    if {[$client isv2]} {
	$theapp drain-delete $drain
    } else {
	$client app_drain_delete $theapp $drain
    }

    display [color good OK]
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::drain_list {config} {
    debug.cmd/app {}
    manifest user_all each $config ::stackato::cmd::app::DrainList
    return
}

proc ::stackato::cmd::app::DrainList {config theapp} {
    debug.cmd/app {}
    set client [$config @client]

    if {![$config @json]} {
	if {[$client isv2]} {
	    set appname [$theapp @name]
	} else {
	    set appname $theapp
	}
	display "Drains: [context format-short " -> [color name $appname]"]"
    }

    if {[$client isv2]} {
	set thedrains [$theapp drain-list]
    } else {
	set thedrains [$client app_drain_list $theapp]
    }

    set thedrains [misc sort-aod name $thedrains -dict]

    if {[$config @json]} {
	puts [jmap map {array {dict {json bool}}} $thedrains]
	return
    }

    if {![llength $thedrains]} {
	display [color note "No Drains"]
	return
    }

    # We have drains. Check for existence of status.
    if {[dict exists [lindex $thedrains 0] status]} {
	# Likely 2.11+, with status, show the column

	table::do t {Name Json Url Status} {
	    foreach item $thedrains {
		set n [dict get  $item name]
		set u [dict get  $item uri]
		set j [dict get  $item json]
		set s [dict get $item status]
		$t add $n $j $u $s
	    }
	}
    } else {
	# 2.10- Regular display, no status.

	table::do t {Name Json Url} {
	    foreach item $thedrains {
		set n [dict get  $item name]
		set u [dict get  $item uri]
		set j [dict get  $item json]
		$t add $n $j $u
	    }
	}
    }

    $t show display
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::Upload {config theapp appname} {
    debug.cmd/app {}

    if {[[$config @client] isv2] &&
	[$theapp @docker_image defined?] &&
	([$theapp @docker_image] ne {})} {
	debug.cmd/app {docker image chosen as sources, skip upload}
	display "Uploading Application \[[color name $appname]\] ... Skipped, using docker image \"[color name [DisplayDIR [$theapp @docker_image]]]\""
	return
    }

    set ignores [manifest ignorePatterns]
    debug.cmd/app {ignores      = $ignores}

    upload-files $config $theapp $appname [manifest path] $ignores
    return
}

proc ::stackato::cmd::app::upload-files {config theapp appname path {ignorepatterns {}}} {
    debug.cmd/app {}

    set upload_file {}
    set explode_dir {}

    if {![file exists $path]} {
	return -code error -errorcode {STACKATO CLIENT CLI CLI-ERROR} \
	    "Application $path missing, unable to upload"
    }
    if {0&&![file isdirectory $path]} {
	return -code error -errorcode {STACKATO CLIENT CLI CLI-ERROR} \
	    "Application directory $path not a directory, unable to upload"
    }
    if {![file readable $path]} {
	return -code error -errorcode {STACKATO CLIENT CLI CLI-ERROR} \
	    "Application $path not readable, unable to upload"
    }

    set client      [$config @client]
    set copyunsafe  [$config @copy-unsafe-links]

    try {
	debug.cmd/app {**************************************************************}
	display "Uploading Application \[[color name $appname]\] ... "
	display "  From path $path"

	# Truncate the appname as used in file paths to a sensible
	# length to avoid OS path length restrictions when the user
	# uses a very long application name.

	if {[string length $appname] > 30} {
	    set pappname [string range $appname 0 29]
	} else {
	    set pappname $appname
	}

	set tmpdir      [fileutil::tempdir]
	set upload_file [file normalize "$tmpdir/$pappname.zip"]
	set explode_dir [file normalize "$tmpdir/.stackato_${pappname}_files"]
	set file {}

	file delete -force $upload_file
	file delete -force $explode_dir  # Make sure we didn't have anything left over..

	if {[file isfile $path]} {
	    FileToExplode $explode_dir $path
	} else {
	    set ignorepatterns [TranslateIgnorePatterns $ignorepatterns]

	    cd::indir $path {
		DirToExplode $config $explode_dir $copyunsafe $ignorepatterns
	    }
	}
	
	# The explode_dir (a temp dir) now contains the
	# application's files. We can now check with CC for known
	# resources to reduce the amount of data to upload, etc.,
	# then (re)pack and upload everything.

	debug.cmd/app {explode-dir @ $explode_dir}

	# Send the resource list to the cloudcontroller, the response
	# will tell us what it already has.

	set appcloud_resources [ProcessResources $config $explode_dir]

	# Perform Packing of the upload bits here.

	set ftp [GetFilesToPack $explode_dir]

	# NOTE: Due to the compiled manifest file the zip file
	# always contains at least one entry. I.e. it is never
	# empty.
	display {  Packing application ... } false

	set mcfile [fileutil::tempfile stackato-mc-]
	cfile fix-permissions $mcfile 0644
	manifest currentInfo $mcfile [$client api-version]

	debug.cmd/app {mcfile = $mcfile}

	Pack $explode_dir $ftp $upload_file $mcfile
	file delete $mcfile

	display [color good OK]
	set upload_size [file size $upload_file]

	if {$upload_size > 1024*1024} {
	    set upload_size [expr {round($upload_size/(1024*1024.))}]M
	} elseif {$upload_size >= 512} {
	    set upload_size [expr {round($upload_size/1024.)}]K
	}

	if {[$config @keep-zip set?]} {
	    set keep [$config @keep-zip]
	    display "  Saving zip for inspection, at $keep ... "

	    file mkdir [file dirname $keep]
	    file copy -force $upload_file $keep
	}

	set upload_str "  Uploading ($upload_size) ... "
	display $upload_str false ; # See client.Upload for where
	# this text is used by the upload progress callback.

	if {1||[llength $ftp]} {
	    # original code uses a channel transform to
	    # count bytes read/uploaded, and drive a
	    # percentage progress bar of the upload process.
	    # We drive this directly in the REST client,
	    # with a query-progress callback.

	    set file $upload_file
	} else {
	    set file {}
	}

	debug.cmd/app {**************************************************************}
	debug.cmd/app {R = $appcloud_resources}
	debug.cmd/app {F = $ftp}
	debug.cmd/app {U = $upload_file}
	debug.cmd/app {**************************************************************}

	if {[$client isv2]} {
	    if {[$config @keep-form set?]} {
		$theapp keep-form [$config @keep-form]
	    }

	    $theapp upload! $file $appcloud_resources
	} else {
	    $client upload_app $appname $file $appcloud_resources
	}

	display {Push Status: } false
	display [color good OK]

    } trap {POSIX ENAMETOOLONG} {e o} {
	# Rethrow as client error.

	return -code error -errorcode {STACKATO CLIENT CLI CLI-ERROR} \
	    "The client encountered a file name exceeding system limits, aborting\n$e"

    } finally {
	if {$upload_file ne {}} { catch { file delete -force $upload_file } }
	if {$explode_dir ne {}} { catch { file delete -force $explode_dir } }
    }

    return
}

proc ::stackato::cmd::app::FileToExplode {explode_dir path} {
    debug.cmd/app {}

    # (**) Application is single file ...
    if {[file extension $path] eq ".ear"} {
	display "  Copying .ear file"
	# It is an EAR file, we do not want to unpack it
	file mkdir $explode_dir
	file copy -- $path $explode_dir

    } elseif {[file extension $path] in {.jar .war .zip}} {
	display "  Exploding file"
	# Its an archive, unpack to treat as app directory.
	zipfile::decode::unzipfile $path $explode_dir

    } else {
	# Plain file, just treat it as the single file in an otherwise
	# regular application directory.  We normalize the file to
	# avoid accidentially copying a soft-link as is.
	display "  Copying plain file"

	file mkdir                            $explode_dir
	file copy -- [misc full-normalize $path] $explode_dir
    }
    return
}

proc ::stackato::cmd::app::DirToExplode {config explode_dir copyunsafe ignorepatterns} {
    debug.cmd/app {}

    # (xx) Application is specified through its directory and files
    # therein. If a .ear file is found we do not unpack it as it is
    # hard to pack. If a .war/.jar file is found treat that as the
    # app, and nothing else.  In case of multiple .jar/.war/.ear files
    # one is chosen semi-random.  Don't do something like that. Better
    # specify it as full file, to invoke the treatment at (**) above.

    # Stage the app appropriately and do the appropriate
    # fingerprinting, etc.

    set client [$config @client]

    if {[$config @force-war-unpacking set?]} {
	set special [$config @force-war-unpacking]
    } elseif {[manifest force-war-unpacking] ne {}} {
	set special [manifest force-war-unpacking]
    } else {
	set special [expr {![$client isv2]}]
    }

    debug.cmd/app {special ear/war/jar - by option   = [expr {[$config @force-war-unpacking set?] ? [$config @force-war-unpacking] : "n/a" }]}
    debug.cmd/app {special ear/war/jar - by manifest = [expr {[manifest force-war-unpacking] ne {} ? [manifest force-war-unpacking] : "n/a" }]}
    debug.cmd/app {special ear/war/jar - by API v1   = [expr {![$client isv2]}]}

    if {$special} {
	debug.cmd/app {special ear/war handling}
	# Special handling of ear/war/jar files.

	set warfiles [glob -nocomplain *.war]
	set war_file [lindex $warfiles 0]
	set earfiles [glob -nocomplain *.ear]
	set ear_file [lindex $earfiles 0]
	set jarfiles [glob -nocomplain *.jar]
	set jar_file [lindex $jarfiles 0]

	if {$ear_file ne {}} {
	    display "  Copying .ear file"

	    debug.cmd/app {ear-file found = $ear_file}
	    # It is an EAR file, we do not want to unpack it
	    file mkdir $explode_dir
	    file copy -- $ear_file $explode_dir
	    return
	}

	if {$war_file ne {}} {
	    debug.cmd/app {war-file found = $war_file}
	    # Its an archive, unpack to treat as app directory.
	    if {[file isdirectory $war_file]} {
		display "  Copying .war directory"
		# Actually its a directory, plain copy is good enough.
		cd::indir $war_file {
		    MakeACopy $explode_dir [pwd] {}
		}
	    } else {
		display "  Exploding .war file"
		zipfile::decode::unzipfile $war_file $explode_dir
	    }
	    return
	}

	if {$jar_file ne {}} {
	    debug.cmd/app {jar-file found = $jar_file}
	    # Its an archive, unpack to treat as app directory.
	    if {[file isdirectory $jar_file]} {
		display "  Copying .jar directory"
		# Actually its a directory, plain copy is good enough.
		cd::indir $jar_file {
		    MakeACopy $explode_dir [pwd] {}
		}
	    } else {
		display "  Exploding .jar file"
		zipfile::decode::unzipfile $jar_file $explode_dir
	    }
	    return
	}

	# No ear/war/jar files, fall back to regular operation.
    }

    if {!$copyunsafe} {
	debug.cmd/app {check for unsafe links}
	set outside [GetUnreachableLinks [pwd] $ignorepatterns]

	if {[llength $outside]} {
	    debug.cmd/app {have unsafe links, bail}
	    set msg "Can't deploy application containing the "

	    if {[llength $outside] == 1} {
		append msg "link\n\t'[lindex $outside 0]'\nthat reaches "
	    } else {
		append msg "links\n\t'[join $outside '\n\t']'\nthat reach "
	    }
	    append msg "outside its root directory\n\t'[pwd]'\n"
	    append msg "Use --copy-unsafe-links to force copying the above files or directories."
	    err $msg
	}
    }

    display "  Copying directory"
    debug.cmd/app {safe the app directory for processing}
    MakeACopy $explode_dir [pwd] $ignorepatterns
    return
}

proc ::stackato::cmd::app::ProcessResources {config explode_dir} {
    debug.cmd/app {}

    if {[$config @no-resources]} {
	debug.cmd/app {disabled, upload all ==> 0 ()}
	return {}
    }

    display {  Checking for available resources ... } false

    set fingerprints {} ; # list (dict (size, sha1, fn| */string))
    set total_size   0

    fileutil::traverse T $explode_dir
    T foreach filename {
	if {![file exists      $filename]} continue
	if { [file isdirectory $filename]} continue

	set sz [file size $filename]
	lappend fingerprints [dict create \
				  size $sz \
				  sha1 [sha1::sha1 -hex -file $filename] \
				  fn   $filename]
	incr total_size $sz
	again+ $total_size
    }
    T destroy

    # Check if the resource check is worth the round trip.
    if {$total_size > (64*1024)} {
	# 64k for now
	# Send resource fingerprints to the cloud controller
	again+ "$total_size > 64K, checking with target"

	set client    [$config @client]
	set resources [$client check_resources $fingerprints]
	#@type resources = list (dict (size, sha1, fn| */string))
	again+ {                                           }
	again+ {}
    } else {
	again+ "$total_size < 64K, skip"
	set resources {}
    }

    display " [color good OK]"
    clearlast

    if {![llength $resources]} {
	debug.cmd/app {nothing cached ==> 0 ()}
	display "  Processing resources ... [color good OK]"
	return {}
    }

    display {  Processing resources ... } false
    # We can then delete what we do not need to send.

    set result {}
    foreach resource $resources {
	set fn [dict getit $resource fn]
	file delete -force -- $fn
	# adjust filenames sans the explode_dir prefix
	dict set resource fn [fileutil::stripPath $explode_dir $fn]
	lappend result $resource
    }

    display [color good OK]

    debug.cmd/app {==> [llength $result] ($result)}
    return $result
}


proc ::stackato::cmd::app::application-size {path} {
    debug.cmd/app {}
    # A reduced form of the upload-files below, just computing the size of the application on disk.

    # Use a fixed size if the actual one cannot be determined.
    # Later on the upload will fail and roll the application back.
    if {![file exists   $path] ||
	![file readable $path]} {
	debug.cmd/app {bad path, fixed size ==> 512}
	return 512
    }

    if {[file isfile $path]} {
	# (**) Application is single file ...
	if {[file extension $path] eq ".ear"} {
	    # It is an EAR file, we do not want to unpack it
	    # App size is file size.
	    debug.cmd/app {-- ear file size}
	    return [MB [file size $path]]

	} elseif {[file extension $path] in {.jar .war .zip}} {
	    # Its an archive, unpack to treat as app directory.
	    debug.cmd/app {-- war/jar/zip archive}
	    return [MB [ZipTotal $path]]
	} else {
	    # Plain file, just treat it as the single file in an
	    # otherwise regular application directory.
	    debug.cmd/app {-- plain file size}
	    return [MB [file size $path]]
	}
    }

    # (xx) Application is specified through its directory and files
    # therein. If a .ear file is found we do not unpack it as it is
    # hard to pack. If a .war/.jar file is found treat that as the
    # app, and nothing else.  In case of multiple .war/.ear/.jar files
    # one is chosen semi-random.  Don't do something like that. Better
    # specify it as full file, to invoke the treatment at (**) above.
	    
    cd::indir $path {
	set warfiles [glob -nocomplain *.war]
	set war_file [lindex $warfiles 0]
	set earfiles [glob -nocomplain *.ear]
	set ear_file [lindex $earfiles 0]
	set jarfiles [glob -nocomplain *.jar]
	set jar_file [lindex $jarfiles 0]

	# Stage the app appropriately and do the appropriate
	# fingerprinting, etc.
	if {$ear_file ne {}} {
	    # It is an EAR file, we do not want to unpack it
	    debug.cmd/app {-- ear file size}
	    return [MB [file size $ear_file]]
	} elseif {$war_file ne {}} {
	    # Its an archive, unpack to treat as app directory.
	    if {[file isdirectory $war_file]} {
		# Actually its a directory, plain copy is good enough.
		debug.cmd/app {-- war directory}
		return [MB [Total $war_file]]
	    } else {
		debug.cmd/app {-- war file}
		return [MB [ZipTotal $war_file]]
	    }
	} elseif {$jar_file ne {}} {
	    # Its an archive, unpack to treat as app directory.
	    if {[file isdirectory $jar_file]} {
		# Actually its a directory, plain copy is good enough.
		debug.cmd/app {-- jar directory}
		return [MB [Total $jar_file]]
	    } else {
		debug.cmd/app {-- jar file}
		return [MB [ZipTotal $jar_file]]
	    }
	} else {
	    debug.cmd/app {-- plain directory}
	    return [MB [Total [pwd]]]
	}
    }
}

proc ::stackato::cmd::app::MB {bytes} {
    debug.cmd/app {}
    # Compute MB float from bytes, round up and convert to int.  to
    # prevent the latter from undoing the round-up we add a bit to be
    # over the number to reach.
    set mb [expr {int(ceil($bytes / 1048576.0)+0.1)}]
    debug.cmd/app {==> $mb}
    return $mb
}

proc ::stackato::cmd::app::Total {directory} {
    debug.cmd/app {}

    fileutil::traverse T $directory
    set total 0
    T foreach filename {
	if {![file exists      $filename]} continue
	if { [file isdirectory $filename]} continue

	set sz [file size $filename]
	incr total $sz
    }
    T destroy
    debug.cmd/app {==> $total bytes}
    return $total
}

proc ::stackato::cmd::app::ZipTotal {path} {
    debug.cmd/app {}

    zipfile::decode::open $path
    set zd [zipfile::decode::archive]
    set f  [dict get $zd files]
    zipfile::decode::close

    set total 0
    dict for {_ data} $f {
	set sz [dict get $data ucsize]
	incr total $sz
    }

    debug.cmd/app {==> $total bytes}
    return $total
}

proc ::stackato::cmd::app::GetUnreachableLinks {root ignorepatterns} {
    debug.cmd/app {}
    # Fully normalize the root directory we are checking.
    set root [misc full-normalize $root]

    debug.cmd/app {root = $root}

    # Scan the whole directory hierarchy starting at
    # root. Normalize everything, and anything which is not under
    # the root after that is bad and causes rejection.

    # Anything specified to be ignored however is not checked, as
    # it won't be part of the application's files.

    set iprefix {}

    debug.cmd/app {Scan...}

    set unreachable_paths {}

    display {  Checking for bad links ... } false
    set nfiles 0

    fileutil::traverse T $root \
	-filter    [list ::stackato::cmd::app::IsUsedA $ignorepatterns $root] \
	-prefilter [list ::stackato::cmd::app::IsUsedA $ignorepatterns $root]
    T foreach path {
	again+ [incr nfiles]

	set pathx [fileutil::stripPath $root $path]

	debug.cmd/app {    $pathx}

	set norm  [file dirname [file normalize $path/__]]
	set strip [fileutil::stripPath $root $norm]
	if {$norm ne $strip} continue
	# Path was not stripped, is outside of root.

	# Restrict collection of paths to the actual sym links,
	# and not derived paths (if the sym link is a directory
	# all paths underneath will be found as pointing
	# outside. Naming all of them is redundant.).
	if {[file type $path] ne "link"} continue

	lappend unreachable_paths [fileutil::stripPath $root $path]
    }
    T destroy

    debug.cmd/app {Done}

    if {![llength $unreachable_paths]} {
	#again+ {                  }
	#again+ {}
	display " [color good OK]"
	clearlast
	return
    } else {
	# We have paths outside. Abort.
	clearlast
    }

    return $unreachable_paths
}
proc ::stackato::cmd::app::IsUsedA {ignorepatterns root apath} {
    debug.cmd/app {}
    set rpath [fileutil::stripPath $root $apath]
    return [expr {![IsIgnored $ignorepatterns $root $rpath]}]
}

proc ::stackato::cmd::app::IsIgnored {ignorepatterns root path} {
    debug.cmd/app {}
    # ignorepatterns = list (gitpattern matchdir mode tclpattern ...)
    # path is relative to root.

    if {[file nativename $root/$path] eq [file nativename [info nameofexecutable]]} {
	debug.cmd/app {Ignored, excluded self}
	return 1
    }

    foreach {pattern matchdir mode mpattern} $ignorepatterns {

	if {$matchdir && ![file isdirectory $root/$path]} continue

	switch -exact -- $mode {
	    glob   { set match [string match $mpattern $path] }
	    regexp { set match [regexp --    $mpattern $path] }
	    default { error "Bad pattern mode, must not happen" }
	}

	if {$match} {
	    debug.cmd/app {Ignored}
	    return 1
	}
    }

    debug.cmd/app {Ok}
    return 0
}

proc ::stackato::cmd::app::TranslateIgnorePatterns {ignorepatterns} {
    debug.cmd/app {}
    # ignorepatterns = list (gitpattern)
    set result {}

    foreach pattern $ignorepatterns {
	# The pattern is in .gitignore-style, as per
	# http://www.kernel.org/pub/software/scm/git/docs/gitignore.html
	#
	# (a) foo/ will match a directory foo and paths
	#     underneath it, but will not match a regular
	#     file or a symbolic link foo. For the purpose
	#     of rules (b) and up the / is removed.
	#
	# (b) If the pattern does not contain a slash /,
	#     git treats it as a shell glob pattern and
	#     checks for a match against the pathname
	#     relative to explode-dir.
	#
	# (c) Otherwise, the pattern is a shell glob
	#     suitable for consumption by fnmatch(3) with
	#     the FNM_PATHNAME flag: wildcards in the
	#     pattern will not match a / in the
	#     pathname. For example,
	#     "Documentation/*.html" matches
	#     "Documentation/foo.html" but not
	#     "Documentation/ppc/ppc.html" nor
	#     "tools/perf/Documentation/perf.html".
	#
	# (d) A leading slash matches the beginning of the
	#     pathname. For example, "/*.c" matches
	#     "cat-file.c" but not "mozilla-sha1/sha1.c".

	set opattern $pattern

	# (Ad a)
	set matchdir 0
	if {[string match */ $pattern]} {
	    set matchdir 1
	    set pattern [string range $pattern 0 end-1];#chop/
	}

	if {[string match */* $pattern]} {
	    # (Ad c)
	    set mode regexp

	    set mpattern [string map {
		. \.
		? (.?)
		* ([^/]*)
	    } $pattern]
	    if {[string match /* $mpattern]} {
		set mpattern ^[string range $mpattern 1 end]
	    }

	} else {
	    # (Ad b)
	    set mode glob
	    set mpattern $pattern
	}

	lappend result $opattern $matchdir $mode $mpattern
    }

    return $result
    # list (gitpattern matchdir mode tclpattern ...)
}

proc ::stackato::cmd::app::Filter {files}  {
    #puts PRE-F\t[join $files \nPRE-F\t]
    set result [struct::list filter [lsort -unique $files] [lambda x {
	# Exclude .git repository hierarchies.
	set x [file tail $x]
	#set keep [expr {![string match ..* $x] && ($x ne ".") && ($x ne ".git")}]
	set keep [expr {![string match ..* $x] && ($x ne ".")}]
	#if {!$keep} { puts "DROPPED: $x" }
	return $keep
    }]]
    #puts FILTR\t[join $result \nFILTR\t]
    return $result
}

proc ::stackato::cmd::app::GetFilesToPack {path} {
    debug.cmd/app {}
    return [struct::list map [fileutil::find $path {file exists}] [lambda {p x} {
	fileutil::stripPath $p $x
    } $path]]
}

proc ::stackato::cmd::app::MakeACopy {explode_dir root ignorepatterns} {
    file mkdir $explode_dir
    set files [Filter [glob * .*]]

    debug.cmd/app {STAGE	[join $files \nSTAGE\t]}

    # The files may be symlinks. We have to copy the contents, not
    # the link.

    display "  Copying to temp space ... " false

    Copy 0 $explode_dir $root $ignorepatterns {*}$files

    #again+ {                    }
    #again+ {}
    display " [color good OK]"
    clearlast
}

proc ::stackato::cmd::app::Copy {nfiles dst root ignorepatterns args} {
    # args = relative to pwd = base source directory.

    file mkdir $dst
    foreach f $args {
	if {[file type $f] ni {file directory link}} continue
	if {[IsIgnored $ignorepatterns $root $f]} {
	    debug.cmd/app/ignored {Excluding $f}
	    continue
	}

	if {[file isfile $f]} {
	    again+ [incr nfiles]
	    CopyFile $f $dst
	} elseif {[file isdirectory $f]} {
	    #puts *|$f|\t|$dst|

	    again+ [incr nfiles]
	    file mkdir $dst/$f
	    set nfiles [Copy $nfiles $dst $root $ignorepatterns \
			    {*}[Filter [struct::list map \
					    [glob -nocomplain -tails -directory $f * .*] \
					    [lambda {p x} {
						return $p/$x
					    } $f]]]]
	    #puts @@
	}
    }
    return $nfiles
}

proc ::stackato::cmd::app::CopyFile {src dstdir} {
    if {[file type $src] eq "link"} {
	set actual [file dirname [file normalize $src/XXX]]
    } else {
	set actual $src
    }

    file mkdir [file dirname $dstdir/$src]
    file copy -- $actual $dstdir/$src
    return
}

proc ::stackato::cmd::app::Pack {base files zipfile mcfile} {
    debug.cmd/app {}

    set z [zipfile::encode Z]
    foreach f $files {
	# [Bug 94876] As we are generating our own manifest.yml
	# file for upload we have to keep an existing one out of
	# the zip file, or the decoder will balk below, seeing
	# (and rejecting) the duplicate definition.
	if {$f eq "manifest.yml"} continue

	debug.cmd/app {++ $f}
	$z file: $f 0 $base/$f
    }

    # The compiled manifest has a fixed path in the upload. It is
    # also always present.
    debug.cmd/app {MC $mcfile}

    $z file: manifest.yml 0 $mcfile

    debug.cmd/app {write zip...}
    $z write $zipfile
    $z destroy

    debug.cmd/app {...done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::Context {client} {
    if {[$client isv2]} {
	set context [context format-short]
    } else {
	set context [ctarget get]
	set g [cgroup get]
	if {$g ne {}} { append context { } (@ $g) }
    }
    return $context
}

proc ::stackato::cmd::app::Epoch {epoch} {
    if {$epoch eq "null"} { return N/A }
    clock format [expr {int($epoch)}] -format "%m/%d/%Y %I:%M%p"
}

proc ::stackato::cmd::app::SaveDebuggerInfo {h p} {
    debug.cmd/app {}
    variable dhost $h
    variable dport $p
    return
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::cmd::app {
    variable yes_set {y Y yes YES}

    # Communication between the SaveManifest* procedures.
    variable savemode check
    variable savedst  {}

    # Communication between AppServices and RunDebugger.
    variable dhost {}
    variable dport {}
}

# # ## ### ##### ######## ############# #####################
## Ready

package provide stackato::cmd::app 0
return
