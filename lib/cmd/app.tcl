# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations.
## Application management commands.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require browse
package require cd
package require cmdr 0.4
package require dictutil
package require exec
package require json
package require lambda
package require sha1 2
package require struct::list
package require struct::set
package require table
package require zipfile::decode
package require zipfile::encode
package require stackato::color
package require stackato::jmap
package require stackato::log
package require stackato::mgr::app
package require stackato::mgr::cfile
package require stackato::mgr::cgroup
package require stackato::mgr::client ;# pulled v2 in also
package require stackato::mgr::context
package require stackato::mgr::cspace
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
package require stackato::term
package require stackato::validate::appname
package require stackato::validate::memspec
package require stackato::validate::routename

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
	list-events
    namespace ensemble create

    namespace import ::stackato::color
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
    namespace import ::stackato::term
    namespace import ::stackato::jmap
    namespace import ::stackato::mgr::app
    namespace import ::stackato::mgr::cfile
    namespace import ::stackato::mgr::cgroup
    namespace import ::stackato::mgr::client
    namespace import ::stackato::mgr::context
    namespace import ::stackato::mgr::cspace
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
    namespace import ::stackato::v2
}

debug level  cmd/app
debug prefix cmd/app {[debug caller] | }
debug level  cmd/app/ignored
debug prefix cmd/app/ignored {[debug caller] | }
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

    manifest currentInfo $mcfile [$config @version]

    set mdata [fileutil::cat $mcfile]
    file delete $mcfile

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

    display "Renaming application \[[$theapp @name]\] to $new ... " false
    $theapp @name set $new
    $theapp commit
    display [color green OK]

    debug.cmd/app {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::app::start {config} {
    debug.cmd/app {}
    manifest user_all each $config ::stackato::cmd::app::start1
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

proc ::stackato::cmd::app::StartV2 {config theapp push} {
    debug.cmd/app {}
    # Note: app existence already verified by validation type.

    set appname [$theapp @name]

    if {[$theapp started?]} {
	display [color yellow "Application '$appname' already started"]
	debug.cmd/app {/done, already started}
	return
    }

    display "Starting Application \[$appname\] ... "

    if {[$config @tail]} {
	# Start logyard streaming before sending the start request, to
	# avoid loss of the first log entries.

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

proc ::stackato::cmd::app::WaitV2 {config theapp push} {
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
    if {[$config @tail] && ![logstream active] && [$theapp have-header x-app-staging-log]} {
	WaitV2Log $theapp [$theapp header x-app-staging-log]
    }

    try {
	set hasstarted no

	while 1 {
	    debug.cmd/app {ping CC}

	    set s [clock clicks -milliseconds]
	    try {
		set imap [$theapp instances]

		if {![logstream active]} {
		    PrintStatusSummary $imap
		}

		if {[OneRunning $imap]} {
		    display [color green OK]
		    return
		}

	    } trap {STACKATO CLIENT V2 STAGING IN-PROGRESS} {e o} {
		debug.cmd/app {staging in progress}
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
		debug.cmd/app {start failed}
		if {$push && [cmdr interactive?]} {
		    display [color red "Application failed to start"]
		    if {[term ask/yn {Should I delete the application ? }]} {
			if {[logstream active]} {
			    logstream stop $config
			}
			app delete $client $theapp false
		    }
		}
		err "Application failed to start"
	    }

	    # Limit waiting to a second, if we have to wait at all.
	    # (wait < 0 => delta was over a second spent on the REST call, don't wait with next query)
	    set wait [expr {1000 - $delta}]
	    if {$wait > 0} { After $wait }

	    # Reset the timeout while the log is active, i.e. new
	    # entries were seen since the last check here.
	    if {[logstream new-entries]} {
		debug.cmd/app {timeout /reset}
		set start_time [clock seconds]
	    }

	    set delta [expr {[clock seconds] - $start_time}]
	    if {$delta > $timeout} {
		debug.cmd/app {timeout /triggered}
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
		err "Application is taking too long to start ($delta seconds), check your logs"
	    }
	} ;# while
    } trap {STACKATO CLIENT V2 STAGING FAILED} {e o} {
	err "Application failed to stage"
    } finally {
	debug.cmd/app {stop log stream}

	if {[logstream active]} {
	    logstream stop $config
	}
    }

    debug.cmd/app {/done}
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

proc ::stackato::cmd::app::AnyFlapping {imap} {
    dict for {n i} $imap {
	if {[$i flapping?]} { return yes }
    }
    return no
}

proc ::stackato::cmd::app::AnyStarting {imap} {
    dict for {n i} $imap {
	if {[$i starting?]} { return yes }
    }
    return no
}

proc ::stackato::cmd::app::NoneActive {imap} {
    # Has (Starting|Running) <=> All (Flapping|Down)
    dict for {n i} $imap {
	if {[$i starting?]} { return no }
	if {[$i running?]}  { return no }
    }
    return yes
}

proc ::stackato::cmd::app::AllRunning {imap} {
    dict for {n i} $imap {
	if {![$i running?]} { return no }
    }
    return yes
}

proc ::stackato::cmd::app::OneRunning {imap} {
    dict for {n i} $imap {
	if {[$i running?]} { return yes }
    }
    return no
}

proc ::stackato::cmd::app::PrintStatusSummary {imap} {
    # Gather: total instances, plus counts of the various states. Make a report.

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

    display "    $ok/$all instances: [join $sum {, }]"
    return
}

proc ::stackato::cmd::app::StateColor {s text} {
    switch -exact -- $s {
	DOWN     { set text [color red   $text] }
	FLAPPING { set text [color red   $text] }
	STARTING { set text [color blue  $text] }
	RUNNING  { set text [color green $text] }
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
	display [color red "Application '$appname' could not be found"]
	return
    }

    if {"STARTED" eq [dict getit $app state]} {
	display [color yellow "Application '$appname' already started"]
	return
    }

    # The regular client messages are disabled if we are displaying
    # the app log stream side-by-side. This stream also includes
    # staging/starting events (among others)

    if {![logstream get-use $client]} {
	set banner "Staging Application \[$appname\] on \[[color blue [Context $client]]\] ... "
	display $banner false
    }

    logstream start $config $appname any ; # The one place where a non-fast log stream is ok.

    debug.cmd/app {REST request STARTED...}
    dict set app state STARTED
    $client update_app $appname $app

    if {![logstream get-use $client]} {
	display [color green OK]
    }

    logstream stop $config slow

    if {![logstream get-use $client]} {
	set banner "Starting Application \[$appname\] on \[[color blue [Context $client]]\] ... "
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
		    display [color red "\nError: Application \[$appname\] failed to start, see log above.\n"]
		} else {
		    display [color red "\nError: Application \[$appname\] failed to start, logs information below.\n"]
		    GrabCrashLogs $config $appname 0 true yes
		}
		if {$push} {
		    display ""
		    if {[cmdr interactive?]} {
			if {[term ask/yn {Should I delete the application ? }]} {
			    app delete $client $appname false
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

	    display [color yellow "\nApplication '$appname' is taking too long to start ($delta seconds), check your logs"]
	    set failed 1
	    break
	}
    } ;# while 1

    if {[logstream active]} {
	logstream stop $config
    }

    if {$failed} {
	exit quit
    }

    if {![logstream get-use $client]} {
	if {[feedback]} {
	    clear
	    display "$banner[color green OK]"
	} else {
	    display [color green OK]
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
	display [color yellow "Application '$appname' already stopped"]
	debug.cmd/app {/done, already stopped}
	return
    }

    # Note: TODO: Wait with full log handling until we know how/if v2
    # has a different log system.

    display "Stopping Application \[$appname\] ... " false
    $theapp stop!
    display [color green OK]

    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::StopV1 {config appname} {
    debug.cmd/app {}

    set client [$config @client]

    set app [$client app_info $appname]
    if {$app eq {}} {
	display [color red "Application '$appname' could not be found"]
	debug.cmd/app {/done, invalid}
	return
    }

    if {"STOPPED" eq [dict getit $app state]} {
	display [color yellow "Application '$appname' already stopped"]
	debug.cmd/app {/done, already stopped}
	return
    }

    if {![logstream get-use $client]} {
	display "Stopping Application \[$appname\] ... " false
    }

    dict set app state STOPPED
    logstream start $config $appname

    $client update_app $appname $app

    logstream stop $config

    if {![logstream get-use $client]} {
	display [color green OK]
    }

    debug.cmd/app {/done, ok}
    return
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

proc ::stackato::cmd::app::check-app-for-restart {config theapp} {
    debug.cmd/app {}

    set client [$config @client]

    # client v1 = theapp is name
    # client v2 = theapp is entity instance

    if {[$client isv2]} {
	if {![$theapp started?]} {
	    display [color green OK]
	    return
	}
    } else {
	set app [$client app_info $theapp]

	if {[dict getit $app state] ne "STARTED"} {
	    display [color green OK]
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

    if {[$config @follow]} {
	# Disable 'Interupted' output for ^C
	exit trap-term-silent

	logstream tail $mconfig
	return
    }

    # Single-shot log retrieval...
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

    #checker -scope line exclude badOption
    set instances_info [dict get' $instances_info_envelope instances {}]
    foreach entry $instances_info {
	#checker -scope line exclude badOption
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
	    display [color red $e]
	} trap {STACKATO CLIENT TARGETERROR} {e o} {
	    if {[string match *retrieving*404* $e]} {
		display [color red "($instance)$path: No such file or directory"]
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
    #checker -scope line exclude badOption
    set instance [dict get' $map $instance $instance]

    foreach path [LogFilePaths $client $appname $instance \
		      /logs /app/logs /app/log] {
	if {$tailed && [string match *staging* $path]} continue

	set content {}
	try {
	    set content [$client app_files $appname $path $instance]
	    DisplayLogfile $prefix $path $content $instance

	} trap {STACKATO CLIENT NOTFOUND} {e o} {
	    display [color red $e]
	} trap {STACKATO CLIENT TARGETERROR} {e o} {
	    if {[string match *retrieving*404* $e]} {
		display [color red "($instance)$path: No such file or directory"]
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
	    display [color red $e]
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
	set prefix [color bold "\[$instance: $path\] -"]
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
		display "No crashed instances for \[$appname\]"
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
	set should_delete [expr {$force || ![cmdr interactive?]}]
	if {!$should_delete} {
	    set msg "Delete ALL Applications from \[[color blue [Context $client]]\] ? "
	    set should_delete [term ask/yn $msg no]
	}
	if {$should_delete} {
	    if {[$client isv2]} {
		set apps [[cspace get] @apps]
		foreach app $apps {
		    app delete $client $app $force
		}
	    } else {
		set apps [$client apps]
		foreach app $apps {
		    app delete $client [dict getit $app name] $force
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
    app delete $client $theapp $force $rollback
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

    display "Application \[$appname\] ... "

    set n [llength [$config @url]]

    foreach url [lsort -dict [$config @url]] {
	set url [string tolower $url]
	debug.cmd/app {+ url = $url}
	dict lappend app uris $url

	display "  Map $url"
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

    display "Application \[[$theapp @name]\] ... "

    set n [llength [$config @url]]

    map-urls $config $theapp [$config @url]

    MapFinal mapped $n
    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::map-urls {config theapp urls {rollback 0} {sync 1}} {
    debug.cmd/app {}

    foreach url [lsort -dict $urls] {
	set url [string tolower $url]
	debug.cmd/app {+ url = $url}

	if {$sync} {
	    display "  Map $url ... " false
	    $theapp @routes add [Url2Route $config $theapp $url $rollback]
	    display [color green OK]
	} else {
	    display "  Map $url ... (Change Ignored)"
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
	    display "  Unmap $url ... " false

	    set r [routename validate [$config @url self] $url]
	    $theapp @routes remove $r
	    display [color green OK]
	} else {
	    display "  Unmap $url ... (Change Ignored)"
	}
    }

    debug.cmd/app {/done}
    return
}

proc ::stackato::cmd::app::kept-urls {theapp urls {sync 1}} {
    debug.cmd/app {}

    foreach u $urls {
	display "  Kept  $u ... "
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
	    if {[llength [v2 domain list-by-name $domain]]} {
		# domain exists, not mapped into the space.
		set msg "Not mapped into the space. [self please map-domain] to add the domain to the space."
	    } else {
		# domains does not exist at all.
		set msg "Does not exist. [self please map-domain] to create the domain and add it to the space."
	    }
	    display "" ; # Force new line.

	    # Force application rollback, per caller's instruction.
	    if {$rollback} {
		Delete 0 1 $config $theapp
	    }

	    err "Unknown domain '$domain': $msg"
	}
    }

    debug.cmd/app {host    = $host}
    debug.cmd/app {domain  = $domain}

    # 2. Find route by host(-name), in all routes, then
    #    filter by domain, locally.

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

    #checker -scope line exclude badOption
    set uris [dict get' $app uris {}]
    debug.cmd/app {uris = [join $uris \n\t]}

    display "Application \[$appname\] ... "

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

    display "Application \[$appname\] ... "

    debug.cmd/app {/regular}
    # Unmap the specified routes from the application.
    set route [$config @url]
    set name [$route name]

    display "  Unmap $name ... " false
    $theapp @routes remove $route
    display [color green OK]

    MapFinal unmapped 1
    return
}

proc ::stackato::cmd::app::MapFinal {action n} {
    display [color green "Successfully $action $n url[expr {$n==1 ? "":"s"}]"]
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
    set stats   [$client app_stats $theapp]
    #@type stats = list (dict (*/string, usage/dict)) /@todo

    debug.cmd/app {= [jmap stats $stats]}

    if {[$config @json]} {
	display [jmap stats $stats]
	return
    }

    if {![llength $stats]} {
	display [color yellow "No running instances for \[$appname\]"]
	return
    }

    display $appname
    [table::do t {Instance {CPU (Cores)} {Memory (limit)} {Disk (limit)} Uptime} {
	foreach entry $stats {
	    set index [dict getit $entry instance]
	    set stat  [dict getit $entry stats]
	    set hp    "[dict getit $stat host]:[dict getit $stat port]"

	    set uptime [uptime [dict getit $stat uptime]]
	    #checker -scope line exclude badOption
	    set usage [dict get' $stat usage {}]
	    if {$usage ne {}} {
		#checker -scope line exclude badOption
		set cpu  [dict getit $usage cpu]
		#checker -scope line exclude badOption
		set mem  [expr {[dict getit $usage mem] * 1024}] ;# mem usage comes in K's
		#checker -scope line exclude badOption
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
	display [color yellow "No running instances for \[$appname\]"]
	return
    }

    display [context format-short " -> $appname"]
    [table::do t {Instance {CPU (Cores)} {Memory (limit)} {Disk (limit)} Started Crashed Uptime} {
	foreach {index data} $stats {
	    set state [dict get $data state]

	    set stats [dict get' $data stats {}]
	    set crashed [dict get' $data since {}]
	    if {$crashed ne {}} {
		set crashed [Epoch $crashed]
	    }

	    if {$stats ne {}} {
		set uptime [uptime [dict get $stats uptime]]
		set mq [psz [dict get $stats mem_quota]]
		set dq [psz [dict get $stats disk_quota]]

		set usage [dict get' $stats usage {}]
		if {$usage ne {}} {
		    set started [dict get $usage time]
		    set m [psz [dict get $usage mem]]
		    set d [psz [dict get $usage disk]]
		} else {
		    set started N/A
		    set m N/A
		    set d N/A
		}
	    } else {
		set started {}
		set uptime N/A
		set m N/A ; set mq N/A
		set d N/A ; set dq N/A
	    }

	    set mem   "$m ($mq)"
	    set disk  "$d ($dq)"

	    $t add $index $state $mem $disk $started $crashed $uptime
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

    set client [$config @client]

    if {[$client isv2]} {
	# @application = list of instances
	[table::do t {Application Health} {
	    foreach app $args {
		$t add [$app @name] [$app health]
	    }
	}] show display
    } else {
	[table::do t {Application Health} {
	    foreach appname $args {
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

    ChangeInstances $config $client $theapp appinfo changes
    ChangeMem       $config $client $theapp appinfo needrestart
    ChangeDisk      $config $client $theapp appinfo needrestart

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
	    display [color green OK]
	}

	if {$needrestart && [AppIsRunning $config $theapp $appinfo]} {
	    debug.cmd/app {restart application}
	    Restart1 $config $theapp
	}

	logstream stop $config
    } else {
	display [color green {No changes}]
    }
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

    if {![$config @instances set?]} return

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
    set relative [string match {[-+]*} $instances]

    debug.cmd/app {relative=$relative}

    set new_instances \
	[expr {
	       $relative
	       ? $current_instances + $instances
	       : $instances}]

    if {$new_instances < 1} {
	err "There must be at least 1 instance."
    }

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

    #checker -scope line exclude badOption
    set instances_info [dict get' $instances_info_envelope instances {}]
    #@type instances_info = list (dict) /@todo determine more.

    # @todo list-util sort on sub-dict key value
    set instances_info [lsort -command [lambda {a b} {
	expr {[dict getit $a index] - [dict getit $b index]}
    }] $instances_info]


    if {[$config @json]} {
	display [jmap instances $instances_info]
	return
    }

    if {![llength $instances_info]} {
	display [color yellow "No running instances for \[$theapp\]"]
	return
    }

    [table::do t {Index State {Start Time}} {
	foreach entry $instances_info {
	    set index [dict getit $entry index]
	    set state [dict getit $entry state]
	    set since [Epoch [dict getit $entry since]]
	    $t add $index $state $since
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

    set instances [dict sort $instances]

    if {[$config @json]} {
	dict for {k v} $instances {
	    dict set instances $k [$v as-json]
	}
	display [jmap v2-instances $instances]
	return
    }

    if {![llength $instances]} {
	display [color yellow "No running instances for \[$theapp\]"]
	return
    }

    display [context format-short " -> [$theapp @name]"]
    [table::do t {Index State {Start Time}} {
	foreach {index i} $instances {
	    set state [$i state]
	    set since [Epoch [$i since]]

	    $t add $index $state $since
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

    display "Current Memory Reservation \[$appname\]: $currfmt"
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

    display "  Updating Memory Reservation \[$appname\] to $memfmt ... "

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
	    [term ask/string/extended "${label}: " \
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

    display "Current Disk Reservation \[$appname\]: $currfmt"
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

    display "  Updating Disk Reservation \[$appname\] to $memfmt ... "

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
	#checker -scope line exclude badOption

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

    } trap {STACKATO CLIENT NOTFOUND} e {
	display [color red $e]
    } trap {STACKATO CLIENT TARGETERROR} {e o} {
	if {[string match *retrieving*404* $e]} {
	    display [color red "($instance)$path: No such file or directory"]
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
		[color bold "====> \[$idx: $path\] <====\n"]

	}  trap {STACKATO CLIENT NOTFOUND} e {
	    display [color red $e]
	} trap {STACKATO CLIENT TARGETERROR} {e o} {
	    if {[string match *retrieving*404* $e]} {
		display [color red "($idx)$path: No such file or directory"]
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

    #checker -scope line exclude badOption
    set instances_info [dict get' $instances_info_envelope instances {}]

    foreach entry $instances_info {
	set idx [dict getit $entry index]
	try {
	    set content [$client app_files $appname $path $idx]
	    DisplayLogfile $prefix $path $content $idx \
		[color bold "====> \[$idx: $path\] <====\n"]

	}  trap {STACKATO CLIENT NOTFOUND} e {
	    display [color red $e]
	} trap {STACKATO CLIENT TARGETERROR} {e o} {
	    if {[string match *retrieving*404* $e]} {
		display [color red "($idx)$path: No such file or directory"]
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

    # framework, runtime - bogus for v2 - TODO fix, replace with actual thing ...

    set instances [AppInstances $config]
    debug.cmd/app {instances     = $instances}

    # Framework/Runtime - Not applicable in V2
    # Detection (which buildpack) is now done serverside.
    # (Buildpack mechanism, asking all known BPs)

    set buildpack [AppBuildpack $config]
    debug.cmd/app {buildpack     = $buildpack}

    set stack [AppStack $config]
    debug.cmd/app {stack         = $stack}

    set command   [AppStartCommand $config {}]
    debug.cmd/app {command      = $command}

    set urls      [AppUrl $config $appname {}] ;# No framework
    debug.cmd/app {urls         = $urls}

    set mem_quota [AppMem $config $starting {} $instances {}] ; # No framework, nor runtime
    debug.cmd/app {mem_quota    = $mem_quota}

    set disk_quota [AppDisk $config $instances $path]
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
    $theapp @total_instances set $instances

    if {$command ne {}} {
	$theapp @command set $command
    }
    if {$stack ne {}} {
	$theapp @stack set $stack
    }
    if {$buildpack ne {}} {
	$theapp @buildpack set $buildpack
    }

    # # ## ### ##### ######## ############# #####################
    ## Write

    set changes 0
    if {$update} {
	set sync [$config @reset]
	set action [expr {$sync ? "Syncing" : "Comparing"}]

	display "$action Application \[$appname\] to \[[context format-short " -> $appname"]\] ... "

	dict for {attr details} [dict sort [$theapp journal]] {
	    lassign $details was old
	    set new [$theapp @$attr]
	    incr changes

	    set label [$theapp @$attr label]
	    if {!$sync} {
		set verb   keeping
		set prefix [color red {Warning, ignoring local change of}]
	    } else {
		set verb   was
		set prefix [color blue Setting]
	    }
	    if {!$was} {
		display "    $prefix $label: $new ($verb <undefined>)"
	    } else {
		display "    $prefix $label: $new ($verb $old)"
	    }
	}
	if {!$sync} {
	    # Undo changes, ignored.
	    $theapp rollback
	    set changes 0
	}
    } else {
	incr changes ; # push forces commit
    }

    # Environment binding.
    AppEnvironment defered $config $theapp \
	[expr { $update ? "preserve" : "replace" }]

    if {$changes} {
	if {$interact} {
	    SaveManifestInitial $config
	}

	if {!$update} {
	    display "Creating Application \[$appname\] as \[[context format-short " -> $appname"]\] ... " false
	} else {
	    display {Committing ... } false
	}
	$theapp commit
	display [color green OK]
    } elseif {$sync} {
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

	    Delete 0 1 $config $theapp
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

    display "Creating Application \[$appname\] in \[[ctarget get]\] ... " false
    set response [$client create_app $appname $manifest]
    display [color green OK]

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

    set disk_quota [AppDisk $config $instances $path]
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
    # Note: defersd set! We have to create services and drains
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
	Delete 0 1 $config $theapp
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
	Delete 0         1        $config $theapp 
	# Rethrow.
	return {*}$o $e
    }

    # Start application after staging, if not suppressed.
    if {$starting} {
	start1 $config $theapp true
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

    display "Updating application '$appname'..."

    if {[$client isv2]} {
	set action [SyncV2 $config $appname $theapp $interact]
    } else {
	set action [SyncV1 $client $config $appname $app $interact]
    }

    RunPPHooks $appname update

    Upload $config $theapp $appname

    switch -exact -- $action {
	start {
	    start1 $config $theapp
	}
	restart {
	    Restart1 $config $theapp
	}
	default {
	    display "Note that \[$appname\] was not automatically started because it was STOPPED before the update."
	    display "You can start it manually [self please "start $appname" using]"
	}
    }

    debug.cmd/app {/done}
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
	display [color red "Unable to run $cmd"]
	display [color red "Host/port information is missing"]
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

    global env
    set saved [array get env]

    set env(STACKATO_APP_NAME)    $appname
    set env(STACKATO_CLIENT)      [self exe]
    set env(STACKATO_HOOK_ACTION) $action

    try {
	foreach cmd [manifest hooks pre-push] {
	    display "[color blue pushing:] -----> $cmd"
	    cd::indir [manifest path] {
		exec::run "[color blue pushing:]       " $::env(SHELL) -c $cmd
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
    display "$cmd application \[$appname\] to \[[ctarget get]\] ... "

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
	    set prefix [color red {Warning, ignoring local change of}]
	} else {
	    set lmod   Not
	    set verb   was
	    set prefix [color blue Setting]
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
	if {!$sync} continue
	incr changes

	dict set app $new
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
	# .../Write
	$client update_app $appname $app
	display [color green OK]
    } else {
	display "    [color green {No changes}]"
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

    } ;# else nothing
    # for there is no manifest (information), and we sync'd from the
    # server, not the other way around

    debug.cmd/app {}

    if {[$theapp started?]} {
	return "restart"
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
    manifest command=   [$theapp @command]
    manifest disk=      [$theapp @disk_quota]
    manifest env=       [$theapp @environment_json]
    manifest instances= [$theapp @total_instances]
    manifest mem=       [$theapp @memory]
    manifest services=  $svc
    manifest url=       [$theapp uris]
    manifest drains=    $drains

    manifest buildpack= [$theapp @buildpack]
    catch {
	manifest stack= [$theapp @stack @name]
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

    if {$interact} {
	# This transforms the collected outmanifest into the main
	# manifest to use. The result may be saved to the application
	# as well.

	if {$sd} {
	    AppServices $config $theapp
	    AppDrains   $config $theapp
	}

	SaveManifestFinal $config
	# Above internally has a manifest reload from the saved
	# interaction.

	# Re-select the application we are working with.
	manifest current= $appname yes

    } else {
	# Bug 93955. Reload manifest. See also file manifest.tcl,
	# proc 'LoadBase'. This is where the collected outmanifest
	# data is merged in during this reload.
	manifest setup \
	    [$config @path] \
	    [$config @manifest] \
	    reset

	# Re-select the application we are working with.
	manifest current= $appname yes

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
	![term ask/yn \
	      "Would you like to save this configuration?" \
	      no]} {
	debug.cmd/app {Not saved}
	variable savemode no
	return
    }

    set dst [$config @manifest]

    # Saving a manifest may happen when there is no manifest present yet.
    if {$dst eq {}} {
	debug.cmd/app {Falling back to @path}
	set dst [$config @path]/stackato.yml
    }

    debug.cmd/app {dst = $dst}

    # FUTURE: TODO - Rewrite the app-dir and other path information in
    # the file to be relative to the destination location, instead of
    # keeping the absolute path it was saved with, to make moving the
    # application in the filesystem easier.

    if {$mode eq "full"} {
	set tmp [fileutil::tempfile stackato_m_]
	manifest save $tmp
	file rename -force $tmp $dst
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
    manifest setup [$config @path] $tmp reset

    if {!$savemode} {
	file delete $tmp
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
    file rename -force $tmp $savedst
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
    if {![cmdr interactive?]}       return
    if {[$config @path set?]} return

    set proceed \
	[term ask/yn \
	     {Would you like to deploy from the current directory ? }]

    if {!$proceed} {
	# TODO: interactive deployment path => custom completion.
	set path [term ask/string {Please enter in the deployment path: }]
    } else {
	set path [pwd]
    }

    set path [file normalize $path]

    CheckDeployDirectory $path

    # May reload manifest structures
    manifest setup $path [$config @manifest]
    return
}

proc ::stackato::cmd::app::AppName {config} {
    debug.cmd/app {}

    set client  [$config @client]

    # (3) May ask the user, use deployment path as default ...

    set appname [manifest askname]

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

    if {$instances < 1} {
	display "Forcing use of minimum instances requirement: 1"
	set instances 1
    }

    manifest instances= $instances
    return $instances
}

proc ::stackato::cmd::app::AppStack {config} {
    debug.cmd/app {}

    # Note: Can pull manifest data only here.
    # During cmdr processing current app is not known.
    if {[$config @stack set?]} {
	set stack [$config @stack]
	debug.cmd/app {option   = $stack}
    } else {
	set stack [manifest stack]
	debug.cmd/app {manifest = $stack}
    }

    manifest stack= $stack
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

    manifest buildpack= $buildpack
    return $buildpack
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
	set runtime [term ask/menu "What runtime?" "Select Runtime: " \
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
	display "Runtime:         [dict get $runtimes $runtime description]"
    } else {
	display "Runtime:         <framework-specific default>"
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
	set command [term ask/string {Start command: }]
	debug.cmd/app {command/interact = ($command)}
	set defined [expr {$command ne {}}]
    }

    if {!$defined} {
	if {$frameobj ne {}} {
	    set basic "The framework \[[$frameobj name]\] needs a non-empty start command."
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
    display "Command:         $command"

    debug.cmd/app {==> ($command)}
    return $command
}

proc ::stackato::cmd::app::AppUrl {config appname frameobj} {
    debug.cmd/app {}

    # Note: Can pull manifest data only here.
    # During cmdr processing current app is not known.
    if {[$config @url set?]} {
	set urls [$config @url]
	debug.cmd/app {options  = [join $urls "\n= "]}
    } else {
	set urls [manifest urls]
	debug.cmd/app {manifest = [join $urls "\n= "]}
    }

    debug.cmd/app {url          = $urls}

    set stock None

    if {![llength $urls]} {
	if {[[$config @client] isv2]} {
	    # For a Stackato 3 target use the domain mapped to the current
	    # space as the base of the default url.

	    set stock_template "\${name}.\${space-base}"
	    set stock [list scalar $stock_template]
	    manifest resolve stock
	    set stock [lindex $stock 1]

	} elseif {($frameobj eq {}) || [$frameobj require_url?]} {
	    # For a Stackato 2 target use the target location as base of
	    # the default url, if required by the framework or framework
	    # unknown.

	    set stock_template "\${name}.\${target-base}"
	    set stock [list scalar $stock_template]
	    manifest resolve stock
	    set stock [lindex $stock 1]
	} else {
	    # No default url available/wanted.
	    set stock None
	}

	debug.cmd/app {default      = $stock}
    }

    if {![llength $urls] &&
	[cmdr interactive?] &&
	(($frameobj eq {}) ||
	 [$frameobj require_url?])} {
	variable yes_set

	set url [term ask/string "Application Deployed URL \[$stock\]: "]
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
	display "Application Url: $u"
    }
    set urls $tmp

    #manifest url= $urls
    return $urls
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
	    [term ask/yn "Detected a [$frameobj description], is this correct ? "]
    }

    # (4) Ask the user.
    if {[cmdr interactive?] &&
	(($frameobj eq {}) ||
	 !$framework_correct)} {
	if {$frameobj eq {}} {
	    display "[color yellow WARNING] Can't determine the Application Type."
	}

	# incorrect, kill object
	if {!$framework_correct} {
	    catch { $frameobj destroy }
	    set frameobj {}
	    set df {}
	} else {
	    set df [$frameobj key]
	}

	set fn [term ask/menu "What framework?" "Select Application Type: " \
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

    display "Framework:       [$frameobj name]"

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
    if {!$starting} {
	set dtotal [expr {$mem * $instances}]
	client check-capacity $client $dtotal push
    }

    manifest mem= $mem
    return $mem
}

proc ::stackato::cmd::app::AppDisk {config instances path} {
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

    set  min [application-size $path]
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
	set have [client server-version $client]
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
		display "  Skipping drain \[$k\], already present, unchanged"
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

	display "  $cmd drain \[$k\] $detail$djson$url " 0
	if {[$client isv2]} {
	    $theapp drain-create $k $url $json
	} else {
	    $client app_drain_create $theapp $k $url $json
	}
	display [color green OK]
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

		set theplan [LocateService $client $sconfig]
		debug.cmd/app {MSI plan = $theplan}

		CreateAndBind $client \
		    $theplan $sname {} $theapp \
		    $known $bound
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
		display "Debugging now enabled on [color red unknown] port."

		# Signal to RunDebugger that we do not have the information it needs.
		SaveDebuggerInfo {} {}
	    } elseif {![dict exists $cred port]} {
		display "Debugging now enabled on [color red unknown] port."
		display [color red "Service failed to transmit its port information"]
		display [color red "Please contact the administrator for \[[ctarget get]\]"]

		# Signal to RunDebugger that we do not have the information it needs.
		SaveDebuggerInfo {} {}
	    } else {
		set port [dict get $cred port]
		set host [dict get $cred host]
		display "[color green {Debugging now enabled}] on host [color cyan $host], port [color cyan $port]"

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

    # All service types.
    set services [v2 service list 1]

    debug.cmd/app {services/all = ($services)}

    # Drop inactive service types
    set services [struct::list filter $services [lambda {s} {
	$s @active
    }]]
    debug.cmd/app {services/act = ($services)}

    # Restrict by label.
    if {[llength $services]} {
	#checker -scope line exclude badOption
	set label [dict get' $spec label [dict get' $spec type [dict get' $spec vendor {}]]]
	debug.cmd/app {select label = ($label)}

	set services [struct::list filter $services [lambda {p s} {
	    string equal $p [$s @label]
	} $label]]
    }

    debug.cmd/app {services/lbl = ($services)}

    # Restrict by version, if specified
    if {[llength $services] && [dict exists $spec version]} {
	set version [dict get $spec version]
	debug.cmd/app {select version = ($version)}

	set services [struct::list filter $services [lambda {p s} {
	    string equal $p [$s @version]
	} $label]]
    }

    debug.cmd/app {services/ver = ($services)}

    # Restrict by provider, default to 'core'.
    if {[llength $services]} {
	#checker -scope line exclude badOption
	set provider [dict get' $spec provider core]

	debug.cmd/app {select provider = ($provider)}

	set services [struct::list filter $services [lambda {p s} {
	    string equal $p [$s @provider]
	} $provider]]
    }

    debug.cmd/app {services/prv = ($services)}

    # Find plans, default to 'free'. (cf difference, cf uses D100).
    set plans {}
    if {[llength $services]} {
	set plan [dict get' $spec plan free]

	debug.cmd/app {select plan = ($plan)}

	foreach s $services {
	    lappend plans {*}[$s @service_plans filter-by @name $plan]
	}
    }

    # Reject specification if ambiguous, or not matching anything.
    set n [llength $plans]
    if {!$n} {
	err "Unable to locate service plan matching [jmap map dict $spec]"
    }
    if {$n > 1} {
	err "Found $n plans matching [jmap map dict $spec], unable to choose."
    }

    # assert: n == 1
    set plan [lindex $plans 0]

    debug.cmd/app {plan = ($plan)}
    return $plan
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
	display [color red "Service failed to transmit its credentials"]
	display [color red "Please contact the administrator for \[[ctarget get]\]"]
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

 	#checker -scope line exclude badOption
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
    foreach service [[cspace get] @service_instances get* {
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
    #checker -scope line exclude badOption
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
	    display "  Preserving Environment Variable \[$k\]"
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
	set item ${k}=$value
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
	set item ${k}=$v
	display "  $cmd Environment Variable \[$item\]"
    }

    # Commit ...
    if {[$client isv2]} {
	set res [AE_WriteV2 $cmode $theapp $appenv]
    } else {
	set res [AE_WriteV1 $cmode $client $theapp $app $appenv]
    }

    debug.cmd/app {/done}
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

    #checker -scope line exclude badOption
    set required [dict get' $vardef required 0]
    #checker -scope line exclude badOption
    set inherit  [dict get' $vardef inherit  0]
    #checker -scope line exclude badOption
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
	#checker -scope line exclude badOption
	set prompt [dict get' $vardef prompt "Enter $varname"]

	# (b) Free form text, or choices from a list.
	if {[dict exists $vardef choices]} {
	    set choices [dict get $vardef choices]
	    set value [term ask/choose $prompt $choices $value]
	} else {
	    while {1} {
		if {$hidden} {
		    set response [term ask/string* "$prompt: "]
		} else {
		    set response [term ask/string "$prompt \[$value\]: "]
		}
		if {$required && ($response eq "") && ($value eq "")} {
		    display [color red "$varname requires a value"]
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
	display [color green OK]
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
	display [color green OK]
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
    }

    set path   [file nativename [file normalize $path]]
    set tmpdir [file nativename [file normalize [fileutil::tempdir]]]
    
    if {$path ne $tmpdir} return

    err "Can't deploy applications from staging directory: \[$tmpdir\]"
}

proc ::stackato::cmd::app::RuntimeMap {runtimes} {
    debug.cmd/app {}
    set map  {}
    set full {}

    # Remember the target names, to keep them unambigous.
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

    # Under v2 vendor eq "" indicates UPSI and details == credentials.
    #          vendor ne "" is MSI, and details is ignored.

    # service = instance name (to be) | requested service, by name

    # known = dict (s-i name -> (s-i name,     minfo)) v1
    #         dict (s-i name -> (s-i instance, minfo)) v2
    # minfo irrelevant here, and ignored.

    # bound = list (s-i name)     v1
    #         list (s-i instance) v2

    # Unknown services are created and bound, known services just bound.

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
	if {$vendor ne {}} {
	    set theservice [service create-with-banner $client $vendor $service 1]
	} else {
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
    err "The application's request for a $need service \"$service\" conflicts with a $have service of the same name${suffix}."
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
	[term ask/yn "Bind existing services to '$appname' ? " no]
    } {
	lappend bound {*}[ChooseExistingServices $client $theapp $user_services]
    }

    # Bind new services, if any provisionable.
    if {
	[llength $services] &&
	[term ask/yn "Create services to bind to '$appname' ? " no]
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
    # chosen depth delivers plans and referenced services.
    foreach plan [v2 service_plan list 1] {
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
    set choices [lsort -dict [dict keys $user_services]]

    #set none "<None of the above>"
    #lappend choices $none

    set bound {}
    while {1} {
	set name [term ask/menu \
		      "Which one ?" "Choose: " \
		      $choices]

	# Convert choice to s-instance and manifest data.
	lassign [dict get $user_services $name] theservice mdetails

	service bind-with-banner $client $theservice $theapp

	# Save for manifest.
	lappend bound $name $mdetails

	if {![term ask/yn "Bind another ? " no]} break
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
		[dict getit $s name] \
		[dict getit $s vendor]
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
	    set name [dict getit $s name]
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
	set choice [term ask/menu \
			"What kind of service ?" "Choose: " \
			$choices]

	# Convert choice into service type or (v2) plan, and
	# information for a manifest.
	lassign [dict get $services $choice] theplan mdetails

	set default_name [service random-name-for $choice]
	set service_name \
	    [term ask/string \
		 "Specify the name of the service \[$default_name\]: " \
		 $default_name]

	CreateAndBind $client $theplan $service_name {} $theapp

	lappend bound $service_name $mdetails

	if {![term ask/yn "Create another ? " no]} break
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
	err "No services are bound to application \[$appname\]"
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
	    err "More than one service found; the name ambigous."
	}
    } else {
	# No service specified, auto-select it.

	# Go through the services and eliminate all which are not
	# supported. The list at (x$x) below must be kept in sync with
	# what is supported by the server side dbshell script.

	# XXX see also c_services.tcl, method tunnel, ProcessService. Refactor and share.
	# Extract the name->vendor map

	set supported {}
	foreach service $services {
	    if {[catch {
		set p [$service @service_plan]
	    }]} continue
	    set vendor [$p @service @label]
	    # (x$x)
	    if {![AcceptDbshell $vendor]} continue
	    lappend supported $service
	}
	set services $supported
	# end XXX

	if {[llength $services] > 1} {
	    err "More than one service found; you must specify the service name.\nWe have: [join $services {, }]"
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
    } else {
	debug.cmd/app {/v1}

	set app [$client app_info $theapp]
	set uri [lindex [dict get $app uris] 0]
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

    set instance [$config @instance]
    set paths    [$config @paths]

    if {[llength $paths] < 2} {
	return -code error -errorcode {STACKATO USAGE} \
	    {Not enough arguments for [scp]}
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

	set item ${k}=$v

	dict set env $k $v

	display "Adding Environment Variable \[$item\] ... " false

	$theapp @environment_json set $env
	$theapp commit

    } else {
	debug.cmd/app {/v1: '$theapp'}
	# CFv1 API...

	set app [$client app_info $theapp]

	#checker -scope line exclude badOption
	set env [dict get' $app env {}]

	set item ${k}=$v

	set     newenv [lsearch -inline -all -not -glob $env ${k}=*]
	lappend newenv $item

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

	display "Deleting Environment Variable \[$varname\] ... " false

	$theapp @environment_json set $env
	$theapp commit

    } else {
	debug.cmd/app {/v1: '$theapp'}
	# CFv1 API...

	set app [$client app_info $theapp]

	#checker -scope line exclude badOption
	set env [dict get' $app env {}]

	set newenv [lsearch -inline -all -not -glob $env ${varname}=*]

	display "Deleting Environment Variable \[$varname\] ... " false

	if {$newenv eq $env} {
	    display [color green OK]
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
	set env [$theapp @environment_json]
	# env is dictionary

    } else {
	debug.cmd/app {/v1: '$theapp'}
	# CFv1 API...

	set app [$client app_info $theapp]

	#checker -scope line exclude badOption
	set env [Env2Dict [dict get' $app env {}]]
    }

    debug.cmd/app {env = ($env)}

    if {[$config @json]} {
	display [jmap env $env]
	return
    }

    if {![dict size $env]} {
	display "No Environment Variables" 
	return
    }

    [table::do t {Variable Value} {
	dict for {k v} $env {
	    $t add $k $v
	}
    }] show display
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

    display "Adding [expr {$json?"json ":""}]drain \[$drain\] ... " false

    if {[$client isv2]} {
	$theapp drain-create $drain $uri $json
    } else {
	$client app_drain_create $theapp $drain $uri $json
    }

    display [color green OK]
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

    display "Deleting drain \[$drain\] ... " false

    if {[$client isv2]} {
	$theapp drain-delete $drain
    } else {
	$client app_drain_delete $theapp $drain
    }

    display [color green OK]
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
    if {[$client isv2]} {
	set json [$theapp drain-list]
    } else {
	set json [$client app_drain_list $theapp]
    }

    if {[$config @json]} {
	puts [jmap map {array {dict {json bool}}} $json]
	return
    }

    if {![llength $json]} {
	display "No Drains"
	return
    }

    # We have drains. Check for existence of status.
    if {[dict exists [lindex $json 0] status]} {
	# Likely 2.11+, with status, show the column

	table::do t {Name Json Url Status} {
	    foreach item $json {
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
	    foreach item $json {
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
	display "Uploading Application \[$appname\] ... "

	set tmpdir      [fileutil::tempdir]
	set upload_file [file normalize "$tmpdir/$appname.zip"]
	set explode_dir [file normalize "$tmpdir/.stackato_${appname}_files"]
	set file {}

	file delete -force $upload_file
	file delete -force $explode_dir  # Make sure we didn't have anything left over..

	set ignorepatterns [TranslateIgnorePatterns $ignorepatterns]

	if {[file isfile $path]} {
	    # (**) Application is single file ...
	    if {[file extension $path] eq ".ear"} {
		# It is an EAR file, we do not want to unpack it
		file mkdir $explode_dir
		file copy $path $explode_dir
	    } elseif {[file extension $path] in {.war .zip}} {
		# Its an archive, unpack to treat as app directory.
		zipfile::decode::unzipfile $path $explode_dir
	    } else {
		# Plain file, just treat it as the single file in
		# an otherwise regular application directory.
		# We normalize the file to avoid accidentially
		# copying a soft-link as is.

		file mkdir                            $explode_dir
		file copy [misc full-normalize $path] $explode_dir
	    }
	} else {
	    # (xx) Application is specified through its directory
	    # and files therein. If a .ear file is found we do not unpack
	    # it as it is hard to pack. If a .war file is found treat
	    # that as the app, and nothing else.  In case of
	    # multiple .war/.ear files one is chosen semi-random.
	    # Don't do something like that. Better specify it as
	    # full file, to invoke the treatment at (**) above.
	    
	    cd::indir $path {
		set warfiles [glob -nocomplain *.war]
		set war_file [lindex $warfiles 0]
		set earfiles [glob -nocomplain *.ear]
		set ear_file [lindex $earfiles 0]

		# Stage the app appropriately and do the appropriate
		# fingerprinting, etc.
		if {$ear_file ne {}} {
		    # It is an EAR file, we do not want to unpack it
		    file mkdir $explode_dir
		    file copy $ear_file  $explode_dir
		} elseif {$war_file ne {}} {
		    # Its an archive, unpack to treat as app directory.
		    if {[file isdirectory $war_file]} {
			# Actually its a directory, plain copy is good enough.
			cd::indir $war_file {
			    MakeACopy $explode_dir [pwd] {}
			}
		    } else {
			zipfile::decode::unzipfile $war_file $explode_dir
		    }
		} else {
		    if {!$copyunsafe} {
			set outside [GetUnreachableLinks [pwd] $ignorepatterns]

			if {[llength $outside]} {
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

		    MakeACopy $explode_dir [pwd] $ignorepatterns
		}
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

	display [color green OK]
	set upload_size [file size $upload_file]

	if {$upload_size > 1024*1024} {
	    set upload_size [expr {round($upload_size/(1024*1024.))}]M
	} elseif {$upload_size >= 512} {
	    set upload_size [expr {round($upload_size/1024.)}]K
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
	    $theapp upload! $file $appcloud_resources
	} else {
	    $client upload_app $appname $file $appcloud_resources
	}

	display {Push Status: } false
	display [color green OK]

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

    display " [color green OK]"
    clearlast

    if {![llength $resources]} {
	debug.cmd/app {nothing cached ==> 0 ()}
	display "  Processing resources ... [color green OK]"
	return {}
    }

    display {  Processing resources ... } false
    # We can then delete what we do not need to send.

    set result {}
    foreach resource $resources {
	set fn [dict getit $resource fn]
	file delete -force $fn
	# adjust filenames sans the explode_dir prefix
	dict set resource fn [fileutil::stripPath $explode_dir $fn]
	lappend result $resource
    }

    display [color green OK]

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

	} elseif {[file extension $path] in {.war .zip}} {
	    # Its an archive, unpack to treat as app directory.
	    debug.cmd/app {-- war file}
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
    # hard to pack. If a .war file is found treat that as the app, and
    # nothing else.  In case of multiple .war/.ear files one is chosen
    # semi-random.  Don't do something like that. Better specify it as
    # full file, to invoke the treatment at (**) above.
	    
    cd::indir $path {
	set warfiles [glob -nocomplain *.war]
	set war_file [lindex $warfiles 0]
	set earfiles [glob -nocomplain *.ear]
	set ear_file [lindex $earfiles 0]

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
	display " [color green OK]"
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

	switch -exact $mode {
	    glob   { set match [string match $mpattern $path] }
	    regexp { set match [regexp --    $mpattern $path] }
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
    display " [color green OK]"
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
    switch [file type $src] {
	link {
	    set actual [file dirname [file normalize $src/XXX]]
	}
	default {
	    set actual $src
	}
    }
    file mkdir [file dirname $dstdir/$src]
    file copy $actual $dstdir/$src
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
