# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require try            ;# I want try/catch/finally
package require lambda
package require exec
package require TclOO
package require stackato::client::cli::command::ServiceHelp
package require stackato::client::cli::command::MemHelp
package require stackato::client::cli::command::ManifestHelp
package require stackato::client::cli::config
package require stackato::client::cli::framework
package require stackato::log
package require stackato::term
package require stackato::color
package require dictutil
package require fileutil
package require fileutil::traverse
package require cd ; #indir
package require zipfile::decode
package require zipfile::encode
package require sha1 2
package require stackato::jmap
package require browse
package require tar 0.7.1 ; # tar::untar seekorskip stream fix
package require platform

namespace eval ::stackato::client::cli::command::Apps {}

debug level  cli/apps
debug prefix cli/apps {[::debug::snit::call] | }

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::client::cli::command::Apps {
    superclass ::stackato::client::cli::command::ServiceHelp \
	::stackato::client::cli::command::MemHelp \
	::stackato::client::cli::command::ManifestHelp

    # # ## ### ##### ######## #############

    constructor {args} {
	Debug.cli/apps {}

	set SLEEP_TIME  1
	set LINE_LENGTH 80

	# Numerators are in secs
	set TICKER_TICKS  [expr { 25/$SLEEP_TIME}]
	set HEALTH_TICKS  [expr {  5/$SLEEP_TIME}]
	set TAIL_TICKS    [expr { 45/$SLEEP_TIME}]
	set GIVEUP_TICKS  [expr {120/$SLEEP_TIME}]
	set YES_SET {y Y yes YES}

	# Namespace import, sort of.
	namespace path [linsert [namespace path] end \
			    ::stackato ::stackato::log ::stackato::client::cli]
	next {*}$args

	# Make the current group available, if any, ensuring validity
	my confer-group
	return
    }

    destructor {
	Debug.cli/apps {destructor}
    }

    # # ## ### ##### ######## #############
    ## API

    method start {{appname {}}} {
	Debug.cli/apps {}
	manifest 1orall $appname [callback startit]
	return
    }

    method startit {appname {push false}} {
	Debug.cli/apps {}
	set app [[my client] app_info $appname]

	if {$app eq {}} {
	    display [color red "Application '$appname' could not be found"]
	    return
	}
	if {"STARTED" eq [dict getit $app state]} {
	    display [color yellow "Application '$appname' already started"]
	    return
	}

	set banner "Staging Application \[$appname\]: "
	display $banner false

	set fastlog 0
	Debug.cli/apps {tail = [dict get [my options] tail]}
	if {[dict get [my options] tail]} {
	    # Tail the operation of the stager...
	    if {[package vsatisfies [my ServerVersion] 2.3]} {
		set fastlog 1

		# For a fast-log enabled stackato simply use a
		# suitably filtered log --follow as sub-process.

		set newer [my GetLast $appname]
		set pid [exec::bgrun 2>@ stderr >@ stdout \
			     {*}[my appself] logs $appname \
			     --follow --no-timestamps \
			     --newer $newer
			    ]
	    } else {
		# Stackato pre 2.3: Launch a ssh sub-process going
		# through stackato-ssh with special arguments.
		set pid [my run_ssh {} $appname - 1]
	    }

	    Debug.cli/apps {Tail PID = $pid}
	}

	Debug.cli/apps {REST request STARTED...}
	dict set app state STARTED
	[my client] update_app $appname $app

	display [color green OK]

	if {!$fastlog && [dict get [my options] tail] && ($pid ne {})} {
	    Debug.cli/apps {Kill PID = $pid}
	    ::exec::drop $pid
	}

	set banner  "Starting Application \[$appname\]: "
	display $banner false

	set count 0
	set log_lines_displayed 0
	set failed false
	set start_time [clock seconds]

	while {1} {
	    if {!$fastlog && ($count <= $TICKER_TICKS)} { display . false }

	    after [expr {1000 * $SLEEP_TIME}];# @todo ping into the helper thread?

	    try {
		if {[my app_started_properly $appname \
			 [expr {$count > $HEALTH_TICKS}]]} break

		if {[llength [my crashinfo $appname false $start_time]]} {
		    # Check for the existance of crashes
		    if {$fastlog} {
			if {[dict get [my options] tail] && ($pid ne {})} {
			    Debug.cli/apps {Kill PID = $pid}
			    ::exec::drop $pid
			}
			display [color red "\nError: Application \[$appname\] failed to start, see log above.\n"]
		    } else {
			display [color red "\nError: Application \[$appname\] failed to start, logs information below.\n"]
			my grab_crash_logs $appname 0 true yes
		    }
		    if {$push} {
			display ""
			if {[my promptok]} {
			    if {[term ask/yn {Should I delete the application ? }]} {
				my delete_app $appname false
			    }
			}
		    }
		    set failed true
		    break
		} elseif {$count > $TAIL_TICKS} {
		    set log_lines_displayed \
			[my grab_startup_tail $appname $log_lines_displayed]
		}
	    } trap {TERM INTERUPT} {e o} {
		return {*}$o $e

	    } trap {STACKATO CLIENT} {e o} {
		return {*}$o $e

	    } trap {REST HTTP} {e o} {
		return {*}$o $e

	    } on error e {
		# Rethrow as internal error, with a full stack trace.
		return -code error -errorcode {STACKATO CLIENT INTERNAL} \
		    [list $e $::errorInfo $::errorCode]
	    }

	    incr count
	    set delta [expr {[clock seconds] - $start_time}]
	    if {$delta > $GIVEUP_TICKS} {
		# 2 minutes (real time). Counting loop terations here
		# is no good, as the loop itself may take
		# substantially longer than a second, especially when
		# it comes to tailing the startup log and a non-ready
		# container imposes a multi-second wait before timing
		# out.

		display [color yellow "\nApplication '$appname' is taking too long to start ($delta seconds), check your logs"]
		set failed 1
		break
	    }
	} ;# while 1

	if {$fastlog && [dict get [my options] tail] && ($pid ne {})} {
	    Debug.cli/apps {Kill PID = $pid}
	    ::exec::drop $pid
	}

	if {$failed} { exit 1 }
	if {[log feedback]} {
	    clear $LINE_LENGTH
	    display "$banner[color green OK]"
	} else {
	    display [color green OK]
	}
	if {[dict get [my options] tail]} {
	    set targeturl [my target_url]
	    set url [lindex [dict get $app uris] 0]
	    if {$url ne {}} {
		set label http://$url/
	    } else {
		set label $appname
	    }
	    display "$label deployed to Stackato"
	}
	return
    }

    method stop {{appname {}}} {
	Debug.cli/apps {}
	manifest 1orall $appname [callback stopit] 1
	return
    }

    method stopit {appname} {
	Debug.cli/apps {}
	set app [[my client] app_info $appname]

	if {"STOPPED" eq [dict getit $app state]} {
	    display [color yellow "Application '$appname' already stopped"]
	    return
	}

	display "Stopping Application \[$appname\]: " false
	dict set app state STOPPED
	[my client] update_app $appname $app
	display [color green OK]
	return
    }

    method restart {{appname {}}} {
	Debug.cli/apps {}
	manifest rememberapp
	manifest 1orall $appname [callback stopit] 1
	manifest 1orall $appname [callback startit]
	return
    }

    method mem {args} {
	Debug.cli/apps {[llength $args]}

	# args = appname mem  #2
	#      | appname      #1a
	#      | mem          #1b
	#
	# 1a and 1b can be distinguished by looking for the
	# expected syntax of the 'mem' argument.

	switch -exact [llength $args] {
	    0 {
		set appname {}
		set memsize {}
	    }
	    1 {
		set x [lindex $args 0]
		if {[my ismem $x]} {
		    # 1b
		    set appname {}
		    set memsize $x
		} else {
		    # 1a
		    set appname $x
		    set memsize {}
		}
	    }
	    2 {
		lassign $args appname memsize
	    }
	}

	Debug.cli/apps {argument appname = ($appname)}
	Debug.cli/apps {argument memsize = ($memsize)}

	manifest 1app $appname [callback memit $memsize]
	return
    }

    method memit {memsize appname} {
	Debug.cli/apps {resolved appname = ($appname)}

	set app [[my client] app_info $appname]

	Debug.cli/apps {app info = [jmap appinfo $app]}

	set current_mem [my mem_quota_to_choice \
			     [dict getit $app resources memory]]

	Debug.cli/apps {current memory limit = $current_mem}

	set mem $current_mem ; # (*)
	if {$memsize ne {}} {
	    set memsize [my normalize_mem $memsize]
	}

	Debug.cli/apps {normalized requested mem limit = $memsize}

	display "Current Memory Reservation \[$appname\]: $current_mem"

	if {$memsize eq {}} {
	    Debug.cli/apps {unspecified, query user for new limit}

	    # Stop if not allowed to ask user for new settings.
	    if {![my promptok]} return

	    set memsize [my mem_query $current_mem]
	    set memsize [my normalize_mem $memsize]
	}

	# Here: mem == current_mem, per (*)
	set mem         [my mem_choice_to_quota $mem]
	set memsize     [my mem_choice_to_quota $memsize]
	set current_mem [my mem_choice_to_quota $current_mem]

	# Here: mem == current_mem, per (*)
	Debug.cli/apps {current   quota/instance = $mem}
	Debug.cli/apps {requested quota/instance = $memsize}
	Debug.cli/apps {current   quota/instance = $current_mem}

	display "Updating Memory Reservation \[$appname\] to [my mem_quota_to_choice $memsize]: " false

	Debug.cli/apps {instances            = [dict getit $app instances]}
	Debug.cli/apps {quota delta/instance = [expr {($memsize - $mem)}]}
	Debug.cli/apps {quota delta/total    = [expr {($memsize - $mem) * [dict getit $app instances]}]}

	# check memsize here for capacity
	my check_has_capacity_for \
	    [expr {($memsize - $mem) * [dict getit $app instances]}] \
	    mem
	set mem $memsize

	if {$mem != $current_mem} {
	    Debug.cli/apps {reservation/instance changed $current_mem ==> $mem}

	    dict set app resources memory $mem
	    [my client] update_app $appname $app
	    display [color green OK]

	    if {[dict getit $app state] ne "STARTED"} return

	    Debug.cli/apps {restart application}

	    my restart $appname
	} else {
	    Debug.cli/apps {reservation unchanged}

	    display [color green OK]
	}
	return
    }

    method map {args} {
	Debug.cli/apps {}
	# args = ?appname? url
	switch -exact [llength $args] {
	    1 { set appname {} ; set url [lindex $args 0] }
	    2 { lassign $args appname url }
	}
	manifest 1app $appname [callback mapit $url]
	return
    }

    method mapit {url appname} {
	set app [[my client] app_info $appname]
	set url [string tolower $url]

	Debug.cli/apps {+ url = $url}

	dict lappend app uris $url
	[my client] update_app $appname $app
	display "Application \[$appname\]: [color green "Successfully mapped url"]"
	return
    }

    method unmap {args} {
	Debug.cli/apps {}
	# args = ?appname? url
	switch -exact [llength $args] {
	    1 { set appname {} ; set url [lindex $args 0] }
	    2 { lassign $args appname url }
	}
	manifest 1app $appname [callback unmapit $url]
	return
    }

    method unmapit {url appname} {
	Debug.cli/apps {}

	set app [[my client] app_info $appname]
	set url [string tolower $url]

	#checker -scope line exclude badOption
	set uris [dict get' $app uris {}]
	regsub -nocase {^http(s*)://} $url {} url

	Debug.cli/apps {- url = $url}
	Debug.cli/apps {uris = [join $uris \n\t]}

	if {$url ni $uris} {
	    err "Application \[$appname\]: Invalid url $url"
	}
	struct::list delete uris $url
	dict set app uris $uris
	[my client] update_app $appname $app
	display "Application \[$appname\]: [color green "Successfully unmapped url"]"
	return
    }

    method delete {args} {
	Debug.cli/apps {}
	set force [dict get [my options] force]

	# Check for and handle deletion of --all applications.
	if {[dict get [my options] all]} {
	    set should_delete [expr {$force || ![my promptok]}]
	    if {!$should_delete} {
		set should_delete \
		    [term ask/yn {Delete ALL Applications ? }]
	    }
	    if {$should_delete} {
		set apps [[my client] apps]
		foreach app $apps {
		    my delete_app [dict getit $app name] $force
		}
	    }
	    return
	}

	# Handle case of nothing specified. Search the config. Delete
	# only if the app is unambigous. Reject if there are multiple.
	if {![llength $args]} {
	    manifest 1app {} [callback deleteit $force]
	    return
	    lappend args [my QuickName {}]
	}

	# Delete the explicitly specified apps.
	foreach appname $args {
	    if {$appname eq {}} {
		display [color yellow "Ignored invalid appname"]
		continue
	    }
	    my delete_app $appname $force
	}
	return
    }

    method deleteit {force appname} {
	my delete_app $appname $force
	return
    }

    method delete_app {appname force {rollback 0}} {
	Debug.cli/apps {}
	set service_map [my service_map]
	set app [[my client] app_info $appname]
	set services_to_delete {}
	set app_services [dict getit $app services]
	foreach service $app_services {
	    #checker -scope line exclude badOption
	    set multiuse [expr {[llength [dict get' $service_map $service {}]] > 1}]

	    set del_service [expr {!$multiuse && ($force && ![my promptok])}]
	    if                    {!$multiuse && (!$force && [my promptok])} {
		set del_service \
		    [term ask/yn "Provisioned service \[$service\] detected would you like to delete it ?: " no]
	    }

	    if {!$del_service} continue
	    lappend services_to_delete $service
	}

	if {$rollback} {
	    display [color red "Rolling back application \[$appname\]: "] false
	} else {
	    display "Deleting application \[$appname\]: " false
	}

	[my client] delete_app $appname
	display [color green OK]

	foreach s $services_to_delete {
	    display "Deleting service \[$s\]: " false
	    [my client] delete_service $s
	    display [color green OK]
	}
	return
    }

    method all_files {appname path} {
	Debug.cli/apps {}
	set instances_info_envelope [[my client] app_instances $appname]

	# @todo what else can instances_info_envelope be ? Hash map ?
	#      return if instances_info_envelope.is_a?(Array)

	#checker -scope line exclude badOption
	set instances_info [dict get' $instances_info_envelope instances {}]
	foreach entry $instances_info {
	    set idx [dict getit $entry index]
	    try {
		set content [[my client] app_files $appname $path $idx]
		my display_logfile $path $content $idx [color bold "====> \[$idx: $path\] <====\n"]
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

    method files {args} {
	Debug.cli/apps {}
	# args = appname path  #2
	#      | path          #1a
	#      | appname       #1b
	#      |               #0
	#
	# 1a and 1b can be distinguished by checking if the argument
	# is a valid appname.

	switch -exact [llength $args] {
	    0 {
		set appname {}
		set path     {}
	    }
	    1 {
		set x [lindex $args 0]
		if {[my app_exists? $x]} {
		    # 1a
		    set appname $x
		    set path     {}
		} else {
		    # 1b
		    set appname {}
		    set path     $x
		}
	    }
	    2 {
		lassign $args appname path
	    }
	}

	manifest 1app $appname [callback filesit $path]
	return
    }

    method filesit {path appname} {
	try {
	    #checker -scope line exclude badOption
	    set instance [dict get' [my options] instance 0]
	    if {$instance eq {}} { set instance 0 }


	    if {[dict get [my options] all] && !$instance} {
		return [my all_files $appname $path]
	    }

	    set content [[my client] app_files $appname $path $instance]
	    display $content
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

    method scp {args} {
	Debug.cli/apps {}
	# args = appname src... dst
	#      | src... dst

	if {![my app_exists? [lindex $args 0]]} {
	    set appname {}
	} else {
	    set appname [lindex $args 0]
	    set args [lrange $args 1 end]
	}

	if {[llength $args] < 2} {
	    # not enough arguments.
	    return -code error -errorcode {STACKATO USAGE} \
		{Not enough arguments for [scp]}
	}


	manifest 1app $appname [callback do_scp $args]
	return
    }

    method do_scp {args appname} {
	# args = src... dst (at least two).
	Debug.cli/apps {}

	set instance [dict get' [my options] instance 0]
	if {$instance eq {}} { set instance 0 }

	set dst [lindex $args end]
	set src [lrange $args 0 end-1]

	# Classify destination and sources in terms of local and remote.
	# Note that all sources have to have the same classification.

	set dst [my PClass $dst dclass]
	set sclass {}
	foreach s $src {
	    set s [my PClass $s sc]
	    if {($sclass ne {}) && ($sc ne $sclass)} {
		return -code error -errorcode {STACKATO USAGE} \
		    {Illegal mix of local and remote source paths}
	    }
	    set sclass $sc
	    lappend new $s
	}
	set src $new

	# Four possibilities for src/dst classes:
	# (1) local -> local
	# (2) local -> remote
	# (3) remote -> local
	# (4) remote -> remote

	Debug.cli/apps {mode = $sclass/$dclass}
	switch -exact -- $sclass/$dclass {
	    local/local {
		# Copying is purely local.
		# This can be done using the builtin 'file copy'.
		# To match the semantics of unix's 'cp' command we
		# have to fully normalize the paths however, to ensure
		# that files are copied, and not the symlinks.

		set dst [my full_normalize $dst]
		set src [struct::list map $src [callback full_normalize]]
		if {[catch {
		    file copy -force {*}$src $dst
		} e o]} {
		    # Translate into CLI error, not internal.
		    return {*}$o -errorcode {STACKATO CLIENT CLI} $e
		}
	    }
	    local/remote {
		# Stream local to remote, taking destination path type
		# (file, directory, missing) into account.
		my do_scp_lr $appname $instance $src $dst
	    }
	    remote/local {
		# Stream remote to local, taking destination path type
		# (file, directory, missing) into account.
		my do_scp_rl $appname $instance $src $dst
	    }
	    remote/remote {
		# Copying is purely on the remote side. This is done
		# using the unix 'cp' we can expect to exist there.

		my run_ssh [list cp -r {*}$src $dst] $appname $instance
	    }
	}

	return
    }

    method do_scp_lr {appname instance src dst} {
	Debug.cli/apps {}
	# src - all local, dst - remote

	# scp semantics...
	# dst exists ? File or directory ?
	#
	# dst a file?
	# yes: multiple sources?
	#      yes: error (a)
	#      no:  copy file, overwrite existing file (b)
	#
	# dst a directory?
	# yes: copy all sources into the directory (c)
	#
	# now implied => dst missing.
	# multiple sources?
	# yes: error (d)
	# no:  copy file or directory, create destination
	#

	if {[my scp_test_file $dst]} {
	    # destination exists, is a file.
	    # must have single source, must be a file.

	    if {[llength $src] > 1} {
		# (Ad a)
		return -code error -errorcode {STACKATO CLIENT CLI} \
		    "copying multiple files, but last argument `$dst' is not a directory"
	    }

	    set src [lindex $src 0]
	    if {[file isdirectory $src]} {
		return -code error -errorcode {STACKATO CLIENT CLI} \
		    "cannot overwrite non-directory `$dst' with directory `$src'"

	    }

	    # (Ad b)
	    my scp_lr_ff $src $dst
	    return
	}

	if {[my scp_test_dir $dst]} {
	    # (Ad c)
	    my scp_lr_md $src $dst
	    return
	}

	# destination doesn't exist.
	# single source: copy file to file.
	# single source: copy directory to directory.
	# multiple sources: error, can't copy to missing directory.

	if {[llength $src] == 1} {
	    # (Ad e)

	    set src [lindex $src 0]
	    if {[file isdirectory $src]} {
		# single directory to non-existing destination.
		# destination is created as directory, then src
		# contents are streamed.

		cd::indir $src {
		    set paths \
			[struct::list filter \
			     [lsort -unique [glob -nocomplain .* *]] \
			     [lambda {x} {
				 return [expr {($x ne ".") && ($x ne "..")}]
			     }]]
		    my scp_lr_md $paths $dst
		}
	    } else {
		my scp_lr_ff $src $dst
	    }
	    return
	}

	# (Ad d)
	return -code error \
	    -errorcode {STACKATO CLIENT CLI} \
	    "`$dst': specified destination directory does not exist"
	return
    }

    method scp_lr_ff {src dst} {
	# copy file to file (existing or new), streamed via cat on both sides.
	# The double list-quoting for the remote command hides the
	# output redirection from the local exec.

	upvar 1 appname appname instance instance

	Debug.cli/apps {local/remote file/file}

	my run_ssh [list [list cat > $dst]] \
	    $appname $instance 3 \
	    [list {*}[my appself] scp-xfer-transmit1 $src]
	return
    }

    method scp_lr_md {srclist dst} {
	# destination created if not existing, is a directory.
	# copy all sources into that directory.
	# streamed via tar on both sides.

	upvar 1 appname appname instance instance

	Debug.cli/apps {local/remote */dir}

	my run_ssh [list mkdir -p $dst \; cd $dst \; tar xf -] \
	    $appname $instance 3 \
	    [list {*}[my appself] scp-xfer-transmit {*}$srclist]
	return
    }

    method scp_rl_ff {src dst} {
	# copy file to file, streamed via cat on both sides.
	upvar 1 appname appname instance instance

	Debug.cli/apps {remote/local file/file}

	my run_ssh [list cat $src] \
	    $appname $instance 3 \
	    {} [list {*}[my appself] scp-xfer-receive1 $dst]
	return
    }

    method scp_rl_md {srclist dst} {
	# destination exists, is a directory.
	# copy all sources into that directory.
	# streamed via tar on both sides.

	upvar 1 appname appname instance instance

	my run_ssh [list tar cf - {*}$srclist] \
	    $appname $instance 3 \
	    {} [list {*}[my appself] scp-xfer-receive $dst]
	return
    }

    method scp_rl_dd {src dst} {
	# destination exists, is a directory.
	# copy source directory to that directory.
	# streamed via tar on both sides.

	upvar 1 appname appname instance instance

	my run_ssh [list cd $src \; tar cf - .] \
	    $appname $instance 3 \
	    {} [list {*}[my appself] scp-xfer-receive $dst]
	return
    }

    method scp_test_file {path} {
	upvar 1 appname appname instance instance
	# test uses standard unix stati to communicate its result:
	# (0)    == false ==> OK
	# (!= 0) == true  ==> FAIL
	if {![my run_ssh [list test -f $path] $appname $instance 2]} {
	    return 1
	} else {
	    return 0
	}
    }

    method scp_test_dir {path} {
	upvar 1 appname appname instance instance
	# test uses standard unix stati to communicate its result:
	# (0)    == false ==> OK
	# (!= 0) == true  ==> FAIL
	if {![my run_ssh [list test -d $path] $appname $instance 2]} {
	    return 1
	} else {
	    return 0
	}
    }

    method scp_test_exists {path} {
	upvar 1 appname appname instance instance
	# test uses standard unix stati to communicate its result:
	# (0)    == false ==> OK
	# (!= 0) == true  ==> FAIL
	if {![my run_ssh [list test -e $path] $appname $instance 2]} {
	    return 1
	} else {
	    return 0
	}
    }

    method do_scp_rl {appname instance src dst} {
	Debug.cli/apps {}
	# src - all remote, dst - local

	# scp semantics...
	# dst exists ? File or directory ?
	#
	# dst a file?
	# yes: multiple sources?
	#      yes: error (a)
	#      no:  copy file, overwrite existing file (b)
	#
	# dst a directory?
	# yes: copy all sources into the directory (c)
	#
	# now implied => dst missing.
	# multiple sources?
	# yes: error (d)
	# no:  copy file, overwrite existing file (e)
	#

	foreach s $src {
	    if {![my scp_test_exists $s]} {
		return -code error -errorcode {STACKATO CLIENT CLI} \
		    "$s: No such file or directory"
	    }
	}

	if {[file isfile $dst]} {
	    # destination exists, is a file.
	    # must have single source, must be a file.

	    if {[llength $src] > 1} {
		# (Ad a)
		return -code error -errorcode {STACKATO CLIENT CLI} \
		    "copying multiple files, but last argument `$dst' is not a directory"
	    }

	    set src [lindex $src 0]
	    if {[my scp_test_dir $src]} {
		return -code error -errorcode {STACKATO CLIENT CLI} \
		    "cannot overwrite non-directory `$dst' with directory `$src'"

	    }

	    # (Ad b)
	    my scp_rl_ff $src $dst
	    return
	}

	if {[file isdirectory $dst]} {
	    # (Ad c)
	    my scp_rl_md $src $dst
	    return
	}

	# destination doesn't exist.
	# single source: copy file to file.
	# single source: copy directory to directory.
	# multiple sources: error, can't copy to missing directory.

	if {[llength $src] == 1} {
	    # (Ad d)

	    set src [lindex $src 0]
	    if {[my scp_test_dir $src]} {
		# single directory to non-existing destination.
		# destination is created as directory, then src
		# contents are streamed.
		my scp_rl_dd $src $dst
	    } else {
		my scp_rl_ff $src $dst
	    }
	    return
	}

	# (Ad e)
	return -code error \
	    -errorcode {STACKATO CLIENT CLI} \
	    "`$dst': specified destination directory does not exist"
	return
    }

    method scp_xfer_receive {dst} {
	Debug.cli/apps {}

	fconfigure stdin -encoding binary -translation binary
	#file mkdir            $dst
	tar::untar stdin -dir $dst -chan
	return
    }

    method scp_xfer_transmit {args} {
	Debug.cli/apps {}

	fconfigure  stdout -encoding binary -translation binary
	tar::create stdout $args -chan
	close stdout
	return
    }

    method scp_xfer_receive1 {dst} {
	Debug.cli/apps {}

	file mkdir [file dirname $dst]
	set c [open $dst w]

	fconfigure stdin -encoding binary -translation binary
	fconfigure $c    -encoding binary -translation binary

	fcopy stdin $c
	close $c
	close stdin
	return
    }

    method scp_xfer_transmit1 {src} {
	Debug.cli/apps {}

	set c [open $src r]

	fconfigure stdout -encoding binary -translation binary
	fconfigure $c     -encoding binary -translation binary

	fcopy $c stdout
	close $c
	close stdout
	return
    }

    method appself {} {
	variable ::stackato::client::cli::usage::wrapped
	set noe [info nameofexecutable]
	if {$wrapped} {
	    return [list $noe]
	} else {
	    global argv0
	    return [list $noe $argv0]
	}
    }

    method PClass {path cvar} {
	upvar 1 $cvar class
	if {[string match :* $path]} {
	    set class remote
	    set path [string range $path 1 end]
	} else {
	    set class local
	}
	return $path
    }

    method ssh {args} {
	Debug.cli/apps {}
	# args = appname cmd...
	#      | cmd...

	if {[llength $args] && ([lindex $args 0] eq "api")} {
	    my do_ssh_api [lrange $args 1 end]
	    return
	}
	if {![llength $args] || ![my app_exists? [lindex $args 0]]} {
	    set appname {}
	} else {
	    set appname [lindex $args 0]
	    set args [lrange $args 1 end]
	}

	manifest 1app $appname [callback do_ssh $args]
	return
    }

    method do_ssh_api {arguments} {
	Debug.cli/apps {}
	global env

	set target [my target_url]
	regsub ^https?:// $target {} target
	set target [config base_of $target]

	my SSHCommand opts cmd

	# Notes
	# -t : Force pty allocation, to allow the use of
	#      full curses/screen based commands.

	set cmd [list {*}$cmd -t {*}$opts stackato@$target {*}$arguments]

	my InvokeSSH $cmd
	return
    }

    method do_ssh {args appname} {
	Debug.cli/apps {}

	set instance [dict get' [my options] instance 0]
	if {$instance eq {}} { set instance 0 }

	my run_ssh $args $appname $instance
	return
    }

    method run_ssh {args appname instance {bg 0} {eincmd {}} {eocmd {}}} {
	# eincmd = External INput Command.
	Debug.cli/apps {}
	global env

	set target  [my target_url]

	set token   [config auth_token]
	set keyfile [config keyfile $token]
	if {![file exists $keyfile]} {
	    if {$bg == 1} {
		say [color yellow "\nDisabled real-time view of staging, no ssh key available for target \[$target\]"]
		return {}
	    } else {
		err "No ssh key available for target \[$target\]"
	    }
	}

	regsub ^https?:// $target {} target

	my SSHKeyOptions opts
	my SSHCommand    opts cmd

	# Notes
	# -i keyfile            : Non-standard private key.
	# -o IdentitiesOnly=yes : ignore keys offered by ssh-agent
	# -t                    : Force pty allocation, to allow the use of
	#                         full curses/screen based commands.
	#
	# (bg == 3) => no pty, for 8bit clean data transfer (scp)

	lappend cmd -i $keyfile -o IdentitiesOnly=yes
	if {$bg == 3} {
	    # no pty, and handle as plain sync child process.
	    set bg 0
	} else {
	    lappend cmd -t
	}
	lappend cmd {*}$opts stackato@$target stackato-ssh

	if {[my group] ne {}} {
	    lappend cmd -G [my group]
	}

	lappend cmd $token $appname $instance {*}$args

	return [my InvokeSSH $cmd $bg $eincmd $eocmd]
    }

    method SSHKeyOptions {ov} {
	Debug.cli/apps {}
	upvar 1 $ov opts

	# Standard options, common parts.
	lappend opts -o {PasswordAuthentication no}
	lappend opts -o {ChallengeResponseAuthentication no}
	lappend opts -o {PreferredAuthentications publickey}

	return
    }

    method SSHCommand {ov cv} {
	Debug.cli/apps {}
	upvar 1 $ov opts $cv cmd

	lappend opts -2
	lappend opts -q -o StrictHostKeyChecking=no

	set helpsuffix ""
	if {$::tcl_platform(platform) eq "windows"} {
	    # Platform specific standard options
	    lappend opts -o UserKnownHostsFile=NUL:
	    append helpsuffix "\nPrecompiled compatible ssh binaries for Windows can be obtained from:"
	    append helpsuffix "\n   https://sourceforge.net/apps/trac/mingw-w64/wiki/MSYS"
	} else {
	    # Platform specific standard options
	    lappend opts -o UserKnownHostsFile=/dev/null
	}

	set cmd [auto_execok ssh]
	if {![llength $cmd]} {
	    err "Local helper application ssh not found in PATH.$helpsuffix"
	}

	if {[string match macosx* [platform::generic]]} {
	    # On OS X force the use of ipv4 to cut down on delays.
	    lappend opts -4
	}

	if {[info exists env(STACKATO_SSH_OPTS)]} {
	    lappend opts {*}$env(STACKATO_SSH_OPTS)
	}

	return
    }

    method InvokeSSH {cmd {bg 0} {eincmd {}} {eocmd {}}} {
	# eincmd = External INput Command.
	# eocmd = External Output Command.
	Debug.cli/apps {}
	global env

	if {[dict get [my options] dry]} {
	    display [join [my Quote {*}$cmd] { }]
	    return
	}

	if {$bg == 2} {
	    try {
		exec 2>@ stderr >@ stdout <@ stdin {*}$cmd
	    } trap {CHILDSTATUS} {e o} {
		set status [lindex [dict get $o -errorcode] end]

		Debug.cli/apps {status = $status}
		if {$status == 255} {
		    err "Server closed connection."
		} else {
		    return $status
		}
	    }
	    Debug.cli/apps {status = OK}
	    return 0
	}

	if {$bg} {
	    if {$::tcl_platform(platform) eq "windows"} {
		set in NUL:
		set err NUL:
	    } else {
		set in /dev/null
		set err /dev/null
	    }
	    set pid [exec::bgrun 2> $err >@ stdout < $in {*}$cmd]
	    return $pid
	}

	try {
	    if {[llength $eincmd] && [llength $eocmd]} {
		exec 2>@ stderr >@ stdout {*}$eincmd | {*}$cmd | {*}$eocmd
	    } elseif {[llength $eocmd]} {
		exec 2>@ stderr >@ stdout {*}$cmd | {*}$eocmd
	    } elseif {[llength $eincmd]} {
		exec 2>@ stderr >@ stdout {*}$eincmd | {*}$cmd
	    } else {
		exec 2>@ stderr >@ stdout <@ stdin {*}$cmd
	    }
	} trap {CHILDSTATUS} {e o} {
	    set status [lindex [dict get $o -errorcode] end]
	    if {$status == 255} {
		err "Server closed connection."
	    } else {
		exit $status
	    }
	}
	return
    }

    method run {args} {
	Debug.cli/apps {}
	global env
	# args = appname cmd...
	#      | cmd...

	if {![llength $args] || ![my app_exists? [lindex $args 0]]} {
	    set appname {}
	} else {
	    set appname [lindex $args 0]
	    set args    [lrange $args 1 end]
	}

	if {![llength $args]} {
	    err "No command to run"
	}

	manifest 1app $appname [callback runit $args]
	return
    }

    method runit {args appname} {
	# Bug 92171. Dropping support for run-over-http.
	# Always use SSH now. This client will not work with servers
	# pre 0.7.1 anymore. These had only run-over-http.

	my ssh $appname {*}$args
	return
    }

    method Quote {args} {
	Debug.cli/apps {}
	set cmd ""
	foreach w $args {
	    if {
		[string match "*\[ \"'()\$\|\{\}\]*" $w] ||
		[string match "*\]*"                 $w] ||
		[string match "*\[\[\]*"             $w]
	    } {
		set map [list \" \\\"]
		lappend cmd \"[string map $map $w]\"
	    } else {
		lappend cmd $w
	    }
	}
	return $cmd
    }

    method logs {{appname {}}} {
	Debug.cli/apps {}

	if {[package vsatisfies [my ServerVersion] 2.3]} {
	    # Legal options:
	    # --json --follow --num --source --instance
	    # --newer --filename --text
	    my ValidateOptions {
		--json --follow --num --source --instance
		--newer --filename --text --no-timestamps
	    } {
		if {![llength [my CheckOptions {--instance --all}]]} {
		    set res {Are you possibly expecting server version 2.2 or lower?}
		} else {
		    set res {}
		}
	    }
	    manifest 1app $appname [callback fastlogsit]
	} else {
	    # Legal options:
	    # --instance --all
	    my ValidateOptions {--instance --all} {
		if {![llength [my CheckOptions {
		    --json --follow --num --source --instance
		    --newer --filename --text --no-timestamps
		}]]} {
		    set res {Are you possibly expecting server version 2.4 or higher?}
		} else {
		    set res {}
		}
	    }
	    manifest 1app $appname [callback logsit]
	}
	return
    }

    method fastlogsit {appname} {
	Debug.cli/apps {}

	if {[dict get [my options] follow]} {
	    # Disable 'Interupted' output for ^C
	    config smalltrap

	    # Tail the logs, forever...  Data accumulates in the
	    # 'filter' dictionary ensuring that previously seen lines
	    # are not printed multiple times.
	    set filter {}
	    while {1} {
		my ShowLogs $appname 100 1
		after 1000
	    }
	    return
	}

	# Single-shot log retrieval...
	set n [dict get' [my options] numrecords 100]
	my ShowLogs $appname $n
	return
    }

    method GetLast {appname} {
	Debug.cli/apps {}
	set last [[my client] logs $appname 1]
	set last [lindex [split [string trim $last] \n] end]

	Debug.cli/apps {last = $last}

	if {$last eq {}} {
	    Debug.cli/apps { last = everything }
	    return 0
	}

	set last [json::json2dict $last]
	dict with last {} ; # => timestamp, instance, source, text, filename

	Debug.cli/apps { last = $timestamp}
	return $timestamp
    }

    method ShowLogs {appname n {follow 0}} {
	if {$follow} {
	    # We use our calling context for persistence across calls
	    upvar 1 filter filter
	}

	set json [my GenerateJson]

	set sts       [dict get [my options] logtimestamps]
	set pattern   [dict get' [my options] logsrcfilter *]
	set pinstance [dict get' [my options] instance {}]
	set pnewer    [dict get' [my options] lognewer 0]
	set plogfile  [dict get' [my options] logfile *]
	set plogtext  [dict get' [my options] logtext *]

	Debug.cli/apps { Filter Source    |$pattern| }
	Debug.cli/apps { Filter Instance  |$pinstance| }
	Debug.cli/apps { Filter Timestamp |$pnewer| }
	Debug.cli/apps { Filter Filename  |$plogfile| }
	Debug.cli/apps { Filter Text      |$plogtext| }

	foreach line [split [[my client] logs $appname $n] \n] {
	    # Ignore empty lines.
	    if {[string trim $line] eq {}} continue

	    # Filter for tailing, ignore previously seen lines.
	    if {$follow} {
		if {[dict exists $filter $line]} continue
		dict set filter $line .
	    }

	    Debug.cli/apps { $line }

	    # Parse the json...
	    set record [json::json2dict $line]
	    dict with record {} ; # => timestamp, instance, source, text, filename

	    # Filter for time.
	    if {$pnewer >= $timestamp} {
		Debug.cli/apps { Timestamp '$timestamp' rejected by '$pnewer' }
		continue
	    }

	    # Filter for filename
	    if {![string match $plogfile $filename]} {
		Debug.cli/apps { Filename '$filename' rejected by '$plogfile' }
		continue
	    }
	    # Filter for text
	    if {![string match $plogtext $text]} {
		Debug.cli/apps { Text '$text' rejected by '$plogtext' }
		continue
	    }

	    # Filter for instance.
	    if {($pinstance ne {}) && ($instance ne $pinstance)} {
		Debug.cli/apps { Instance '$instance' rejected by '$pinstance' }
		continue
	    }

	    # Filter for log source...
	    if {![string match $pattern $source]} {
		Debug.cli/apps { Source '$source' rejected by '$pattern' }
		continue
	    }

	    # Format for display, and print.

	    if {$json} {
		# Raw JSON as it came from the server.
		display $line
	    } else {
		if {$instance >= 0} { append source .$instance }

		# colors: red green yellow white blue cyan bold
		if {$sts} {
		    set date "[clock format $timestamp -format {%Y-%m-%dT%H:%M:%S%z}] "
		} else {
		    # --no-timestamps
		    set date ""
		}
		set date     [color yellow $date]
		set source   [color blue    $source]
		#set instance [color blue   $instance]
		if {$filename eq "stderr.log"} {
		    set errormark "stderr"
		    set errormark [color red $errormark]
		    display "$date$source $errormark $text"
		} else {
		    display "$date$source $text"
		}
	    }
	}
	return
    }

    method logsit {appname} {
	#checker -scope line exclude badOption
	set instance [dict get' [my options] instance 0]
	if {$instance eq {}} { set instance 0 }

	if {[dict get [my options] all] && !$instance} {
	    return [my grab_all_logs $appname]
	}
	my grab_logs $appname $instance
	return
    }

    method crashes {{appname {}}} {
	Debug.cli/apps {}
	manifest 1app $appname [callback crashesit]
	return
    }

    method crashesit {appname} {
	return [my crashinfo $appname]
    }

    method crashinfo {appname {print_results true} {since 0}} {
	Debug.cli/apps {}
	set crashed [dict getit [[my client] app_crashes $appname] crashes]
	# list (dict (instance since))

	set crashed [struct::list filter $crashed [lambda {since c} {
	    expr { [dict getit $c since] >= $since }
	} $since]]

	set instance_map {}

	#      return display JSON.pretty_generate(apps) if @options[:json]

	set crashed [lsort -command [lambda {a b} {
	    expr {[dict getit $a since] - [dict getit $b since]}
	}] $crashed]

	set counter 0
	table::do t {Name {Instance ID} {Crashed Time}} {
	    foreach crash $crashed {
		incr counter
		set name "$appname-$counter"
		set instance [dict getit $crash instance]

		dict set instance_map $name $instance

		$t add \
		    $name $instance \
		    [clock format [dict getit $crash since] -format {%m/%d/%Y %I:%M%p}]
	    }
	}

	config store_instances $instance_map

	if {$print_results} {
	    if {[my GenerateJson]} {
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

    method crashlogs {{appname {}}} {
	Debug.cli/apps {}

	if {[package vsatisfies [my ServerVersion] 2.3]} {
	    # Legal options:
	    # --json --follow --num --source --instance
	    # --newer --filename --text
	    my ValidateOptions {
		--json --follow --num --source --instance
		--newer --filename --text --no-timestamps
	    }
	} else {
	    # Legal options:
	    # --instance
	    my ValidateOptions {--instance} {
		if {![llength [my CheckOptions {
		    --json --follow --num --source --instance
		    --newer --filename --text
		}]]} {
		    set res {Are you possibly expecting server version 2.4 or higher?}
		} else {
		    set res {}
		}
	    }
	}
	manifest 1app $appname [callback crashlogsit]
	return
    }

    method crashlogsit {appname} {
	#checker -scope line exclude badOption
	set instance [dict get' [my options] instance 0]
	if {$instance eq {}} { set instance 0 }

	my grab_crash_logs $appname $instance
	return
    }

    method open_browser {{appname {}}} {
	Debug.cli/apps {}

	if {$appname eq "api"} {
	    # Special code to open the current target's console.
	    browse url [my target_url]
	} elseif {[regexp {^https?://} $appname]} {
	    # Argument is not an appname, but an url already.
	    # Browse directly to it.
	    browse url $appname
	} else {
	    # Convert appname to url, then browse to it.
	    manifest 1app $appname [callback DoOpenBrowser]
	}
	return
    }

    method DoOpenBrowser {appname} {
	set app [[my client] app_info $appname]
	set uri [config urlcanon [lindex [dict get $app uris] 0]]

	regsub {^https} $uri http uri

	Debug.cli/apps {==> '$uri'}
	browse url $uri
	return
    }

    method instances {args} {
	Debug.cli/apps {}
	# args = appname num  #2
	#      | appname      #1a
	#      | num          #1b
	#
	# 1a and 1b can be distinguished by looking for the expected
	# syntax of the 'num' argument.

	switch -exact [llength $args] {
	    0 {
		set appname {}
		set num     {}
	    }
	    1 {
		set x [lindex $args 0]
		if {[string is int -strict $x]} {
		    # 1b
		    set appname {}
		    set num     $x
		} else {
		    # 1a
		    set appname $x
		    set num     {}
		}
	    }
	    2 {
		lassign $args appname num
	    }
	}

	manifest 1app $appname [callback instancesit $num]
	return
    }

    method instancesit {num appname} {
	if {$num ne {}} {
	    my change_instances $appname $num
	} else {
	    my get_instances $appname
	}
	return
    }

    method stats {{appname {}}} {
	Debug.cli/apps {}
	manifest 1orall $appname [callback statsit]
	return
    }

    method statsit {appname} {
	Debug.cli/apps {}
	display $appname

	set stats   [[my client] app_stats $appname]
	#@type stats = list (dict (*/string, usage/dict)) /@todo

	Debug.cli/apps {= [jmap stats $stats]}

	if {[my GenerateJson]} {
	    display [jmap stats $stats]
	    return
	}

	if {![llength $stats]} {
	    display [color yellow "No running instances for \[$appname\]"]
	} else {
	    table::do t {Instance {CPU (Cores)} {Memory (limit)} {Disk (limit)} Uptime} {
		foreach entry $stats {
		    set index [dict getit $entry instance]
		    set stat  [dict getit $entry stats]
		    set hp    "[dict getit $stat host]:[dict getit $stat port]"

		    set uptime [log uptime [dict getit $stat uptime]]
		    #checker -scope line exclude badOption
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

		    set mem  "[log psz $mem] ([log psz $mem_quota 0])"
		    set disk "[log psz $disk] ([log psz $disk_quota 0])"

		    if {$cpu eq {}} { set cpu NA }
		    set cpu "$cpu% ([dict getit $stat cores])"

		    $t add $index $cpu $mem $disk $uptime
		}
	    }
	    $t show display
	}
    }

    method update {{appname {}}} {
	Debug.cli/apps {}

	# Perform the regular simple update when application is
	# explicitly specified.

	if {$appname ne {}} {
	    if {[dict get [my options] canary]} {
		display [color yellow "\[--canary\] is deprecated and will be removed in a future version"]
	    }

	    manifest current@path
	    my MinVersionChecks
	    my update_core $appname
	    return
	}

	# With no application specified operate on all applications
	# provided by the configuration.

	manifest foreach_app appname {
	    my MinVersionChecks
	    my update_core $appname
	}
	return
    }

    method update_core {appname} {
	Debug.cli/apps {}

	set appname [my AppName $appname 1]
	Debug.cli/apps {appname      = $appname}

	set path [manifest current]
	Debug.cli/apps {path         = $path}
 
	display "Updating application '$appname'..."

	set restart 0
	set app [[my client] app_info $appname]
	if {[dict getit $app state] eq "STARTED"} {
	    my stop $appname
	    set restart 1
	}

	set ignores [manifest ignorePatterns]
	Debug.cli/apps {ignores      = $ignores}

	# Show the urls the application is mapped to.
	#checker -scope line exclude badOption
	foreach url [dict get' $app uris {}] {
	    display "Application Url: $url"
	}

	# Services check, and binding.
	my AppServices $appname

	# Environment bindings.
	my AppEnvironment $appname

	# Get state again, might have changed.
	set app [[my client] app_info $appname]
	my upload_app_bits $appname $path $ignores

	if {$restart} {
	    my start $appname
	    return
	} else {
	    display "Note that \[$appname\] was not automatically started because it was STOPPED before the update."
	    display "You can start it manually using `[usage me] start $appname`"
	}
	return
    }

    method push {{appname {}}} {
	Debug.cli/apps {}
	# Have to be properly logged into the target.
	my CheckLogin

	# Go through the command line, stackato.yml, and user
	# responses to get the whole application setup.

	set options [my options]
	Debug.cli/apps {options      = $options}

	my AppPath

	# Check if the configuration supplies at least one application
	# to push, and push such.

	set have 0
	manifest foreach_app name {
	    my MinVersionChecks
	    incr have
	} 0 ; # don't panic if no applications are found.

	if {$appname ne {} && ($have > 1)} {
	    err "Unable to push $have applications using the same name '$appname'"
	}

	set pushed 0
	manifest foreach_app name {
	    if {$appname ne {}} { set name $appname }
	    if {$name ne {}} {
		display "Pushing application '$name'..."
	    }
	    my pushit $name
	    incr pushed
	} 0 ; # don't panic if no applications are found.

	if {$pushed} return

	# The configuration did not supply anything. Push the
	# deployment directory as is, with proper interaction asking
	# for any missing pieces (if allowed).

	manifest current@path
	my MinVersionChecks
	my pushit $appname 1
	return
    }

    method pushit {appname {interact 0}} {
	Debug.cli/apps {}

        manifest resetout

	set appname [my AppName $appname]
	Debug.cli/apps {appname      = $appname}

	set path [manifest current]
	Debug.cli/apps {path         = $path}

	set instances [my AppInstances]
	Debug.cli/apps {instances    = $instances}

	set frameobj [my AppFramework]
	Debug.cli/apps {framework    = $frameobj}

	set runtime   [my AppRuntime $frameobj]
	Debug.cli/apps {runtime      = $runtime}

	set command   [my AppStartCommand $frameobj]
	Debug.cli/apps {command      = $command}

	set no_start  [dict get [my options] nostart]
	Debug.cli/apps {no-start     = $no_start}

	set exec      [my AppExec $frameobj]
	Debug.cli/apps {exec         = $exec}

	set urls      [my AppUrl $appname $frameobj]
	Debug.cli/apps {urls         = $urls}

	set mem_quota [my AppMem $no_start $frameobj $instances $runtime]
	Debug.cli/apps {mem_quota    = $mem_quota}

	set ignores [manifest ignorePatterns]
	Debug.cli/apps {ignores      = $ignores}

	# Create the manifest and send it to the cloud controller
	display "Creating Application \[$appname\]: " false

	set manifest [dict create \
			  name      $appname \
			  staging   [dict create \
					 framework [$frameobj name] \
					 runtime   $runtime] \
			  uris      $urls \
			  instances $instances  \
			  resources [dict create \
					 memory $mem_quota]]

	if {$command ne {}} {
	    dict set manifest staging command $command
	}

	[my client] create_app $appname $manifest
	display [color green OK]

	# Services check, and binding.
	my AppServices $appname

	# Environment binding.
	my AppEnvironment $appname

	if {$interact} {
	    my SaveManifest
	    # This implies manifest reload from the saved interaction.
	} else {
	    # Bug 93955. Reload manifest. See also file manifest.tcl,
	    # proc 'LoadBase'. This is where the collected outmanifest
	    # data is merged in during this reload.
	    manifest setup [self] [dict get' [my options] path [pwd]] \
		{} reset
	    manifest recurrent
	}

	# Stage and upload the app bits.
	try {
	    #checker -scope line exclude badOption
	    my upload_app_bits $appname $path $ignores
	} on error {e o} {
	    # On upload failure, delete the app (rollback).
	    my delete_app $appname false 1

	    # Rethrow.
	    return {*}$o $e
	}

	# Start application after staging, if not suppressed.
	if {$no_start} return
	my startit $appname true
    }

    method SaveManifest {} {
	Debug.cli/apps {}
	# Move the saved information into the main data
	# structures. Note that we have to ensure the structure is
	# properly transformed.

	# Easiest way of doing this is to save to a file and then
	# re-initalize the system by loading from that. Saving the
	# manifest is then just copying the temp file to the proper
	# place.

	set tmp [fileutil::tempfile stackato_m_]

	manifest save $tmp

	# Reload.
	manifest setup [self] \
	    [dict get' [my options] path [pwd]] \
	    $tmp reset

	manifest current@path

	if {![my promptok] ||
	    ![term ask/yn \
		  "Would you like to save this configuration?" \
		  no]} {
	    file delete $tmp
	    Debug.cli/apps {Not saved}
	    return
	}

    	set dst [dict get' [my options] manifest stackato.yml]
	if {$dst eq {}} {
	    set dst stackato.yml
	}

	file rename -force $tmp $dst
	Debug.cli/apps {Saved}
	return
    }

    method AppPath {} {
	Debug.cli/apps {}

	# Can't ask user, or --path was specified anyway.
	if {![my promptok]}              return
	if {[dict exists [my options] path]} return

	set proceed \
	    [term ask/yn \
		 {Would you like to deploy from the current directory ? }]

	if {!$proceed} {
	    set path [term ask/string {Please enter in the deployment path: }]
	} else {
	    set path [pwd]
	}

	set path [file normalize $path]
	my check_deploy_directory $path

	# May reload manifest structures
	manifest setup [self] $path {}
	return
    }

    method AppInstances {} {
	Debug.cli/apps {}
	# Check user/command line first ...
	if {[dict exists [my options] instances]} {
	    set instances [dict get [my options] instances]
	}

	# ... Next look at the stackato.yml contents ...
	if {$instances eq {}} {
	    set instances [manifest instances]
	}

	manifest instances= $instances
	return $instances
    }

    method AppRuntime {frameobj} {
	Debug.cli/apps {}

	# Check user/command line first ...
	if {[dict exists [my options] runtime]} {
	    set runtime [dict get [my options] runtime]
	    Debug.cli/apps {runtime/options  = ($runtime)}
	}

	# Then the configuration
	if {$runtime eq {}} {
	    set runtime [manifest runtime]
	    Debug.cli/apps {runtime/manifest = ($runtime)}
	}

	set runtimes [my runtimes_info]
	Debug.cli/apps {supported = [join $runtimes "\nsupported = "]}

	# Last, see if we should ask the user for it.
	# (Required by the framework, and user allowed interaction)

	if {
	    ($runtime eq {}) &&
	    [$frameobj prompt_for_runtime?] &&
	    [my promptok]
	} {
   	    set runtime [term ask/menu "What runtime?" "Select Runtime: " \
			[lsort -dict [dict keys $runtimes]] \
			[$frameobj default_runtime [manifest current]]]
	}

	# Lastly, if a runtime was specified, verify that the targeted
	# server actually supports it.

	if {$runtime ne {}} {
	    Debug.cli/apps {runtime/         = ($runtime)}
	    Debug.cli/apps {checking support}

	    set map [my RuntimeMap $runtimes]
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
		Debug.cli/apps {= $runtime}
	    }
	}

	if {$runtime ne {}} {
	    manifest runtime= $runtime
	    display "Runtime:         [dict get $runtimes $runtime description]"
	} else {
	    display "Runtime:         <framework-specific default>"
	}

	return $runtime
    }

    method AppStartCommand {frameobj} {
	Debug.cli/apps {}

	if {![$frameobj require_start_command?]} {
	    return {}
	}

	# Check the configuration
	set command [manifest command]
	Debug.cli/apps {command/manifest = ($command)}
	
	# Query the the user.
	if {($command eq {}) && [my promptok]} {
	    set command [term ask/string {Start command: }]
	}

	if {$command eq {}} {
	    err "Start command required, but not specified"
	}

	manifest command= $command
	display "Command:         $command"
	return $command
    }

    method prefixes {s} {
	Debug.cli/apps {}
	set p {}
	set res {}
	foreach c [split $s {}] {
	    append p $c
	    lappend res $p
	}
	return $res
    }

    method RuntimeMap {runtimes} {
	Debug.cli/apps {}
	set map {}

	foreach {name info} $runtimes {
	    set desc [dict get $info description]

	    foreach p [my prefixes $name] {
		dict lappend map $p                  $name
		dict lappend map [string tolower $p] $name
	    }
	    foreach p [my prefixes $desc] {
		dict lappend map $p                  $name
		dict lappend map [string tolower $p] $name
	    }
	    foreach p [my prefixes [string map {{ } {}} $desc]] {
		dict lappend map $p                  $name
		dict lappend map [string tolower $p] $name
	    }
	}

	# Reduce duplicates
	dict for {k vlist} $map {
	    dict set map $k [lsort -dict -unique $vlist]
	}

	# Map of strings to runtimes they represent.
	return $map
    }

    method AppUrl {appname frameobj} {
	Debug.cli/apps {}

	set url [dict get [my options] url]
	Debug.cli/apps {url/options  = $url}

	if {$url eq {}} {
	    set urls [manifest urls]
	    Debug.cli/apps {url/manifest = [join $urls "\nurl/manifest = "]}
	} else {
	    set urls [list $url]
	}

	if {[$frameobj require_url?]} {
	    set stock_template "\${name}.\${target-base}"
	    set stock [list scalar $stock_template]
	    manifest resolve_lexically stock
	    set stock [lindex $stock 1]
	} else {
	    set stock None
	}

	Debug.cli/apps {url          = $urls}
	Debug.cli/apps {default      = $stock}

	if {![llength $urls] &&
	    [my promptok] &&
	    [$frameobj require_url?]} {
	    set url [term ask/string "Application Deployed URL \[$stock\]: "]
	    # common error case is for prompted users to answer y or Y or yes or YES to this ask() resulting in an
	    # unintended URL of y. Special case this common error
	    if {$url in $YES_SET} {
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

    method AppFramework {} {
	Debug.cli/apps {}
	set supported [my frameworks_info]
	Debug.cli/apps {server supports : [join $supported "\n[::debug::snit::call] | server supports : "]}

	if {[dict get [my options] noframework]} {
	    Debug.cli/apps {no framework /options - empty}
	    # Empty framework if user said to ignore all settings.
	    return [my AppFrameworkComplete \
			[framework create] {} 0]
	}

	# Determine the framework name by checking the command line,
	# the configuration, per auto-detection, or, as last fallback,
	# ask the user.

	# (1) command line option --framework
	set framework [dict get [my options] framework]
	if {$framework ne {}} {
	    Debug.cli/apps {options = $framework}
	    return [my AppFrameworkComplete \
			[framework lookup $framework] \
			$supported]
	}

	# (2) configuration (stackato.yml, manifest.yml)
	set framework [manifest framework]
	if {$framework ne {}} {
	    Debug.cli/apps {manifest = $framework}

	    return [my AppFrameworkComplete \
			[framework create $framework $framework \
			     [manifest framework-info]] \
			$supported]
	}

	# (3) Heuristic detection, confirm result

	Debug.cli/apps {detect by heuristics}
	set framework_correct 0
	set frameobj [framework detect [manifest current] $supported]

	if {($frameobj ne {}) && [my promptok]} {
	    set framework_correct \
		[term ask/yn "Detected a [$frameobj description], is this correct ? "]
	}

	# (4) Ask the user.
	if {[my promptok] && (($frameobj eq {}) || !$framework_correct)} {
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

	return [my AppFrameworkComplete $frameobj $supported]
    }

    method AppFrameworkComplete {frameobj supported {check 1}} {
	Debug.cli/apps {}

	if {$frameobj eq {}} {
	    err "Application Type undetermined for path '[manifest current]'"
	}

	if {$check && ([$frameobj name] ni $supported)} {
	    err "The specified framework \[[$frameobj name]\] is not supported by the target.\nPlease use '[usage me] frameworks' to get the list of supported frameworks."
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

    method AppExec {frameobj} {
	Debug.cli/apps {}
	#checker -scope line exclude badOption

	set exec [dict get' [my options] exec {}]
	if {$exec eq {}} {
	    set exec [manifest exec]
	}
	if {$exec eq {}} {
	    set exec {thin start}
	}

	# Framework override, deprecated
	if {$frameobj ne {}} {
	    set x [$frameobj exec]
	    if {$x ne {}} {
		set exec $x
	    }
	}

	return $exec
    }

    method AppMem {no_start frameobj instances runtime} {
	Debug.cli/apps {}

	set mem [dict get' [my options] mem {}]
	Debug.cli/apps {option default = ($mem)}

	if {$mem eq {}} {
	    set mem [manifest mem]
	    Debug.cli/apps {manifest default = ($mem)}
	}

	if {$mem eq {}} {
	    set mem [$frameobj memory $runtime]
	    Debug.cli/apps {framework default = ($mem)}

	    if {[my promptok]} {
		set mem [my mem_query $mem]
		Debug.cli/apps {user choice = ($mem)}
	    }
	}

	# assert: mem ne {}
	set mem [my normalize_mem $mem]

	# Convert external spec to interna MB.
	set mem_quota [my mem_choice_to_quota $mem]

	if {$mem_quota < [config minmem]} {
	    display "Forcing use of minimum memory requirement: [config minmem]M"
	    set mem_quota [config minmem]
	}

	# Check capacity now, if the app will be started as part of the
	# push.
	if {!$no_start} {
	    my check_has_capacity_for [expr {$mem_quota * $instances}] push
	}

	manifest mem= $mem_quota
	return $mem_quota
    }

    method AppServices {appname} {
	Debug.cli/apps {}
	#checker -scope line exclude badOption

	Debug.cli/apps {options  = [my options]}
	if {[dict get' [my options] noservices 0]} return

	set services [manifest services]
	Debug.cli/apps {services = ($services)}

	if {![llength $services]} {
	    # No configuration data, do the services interactively.
	    if {[my promptok]} {
		my bind_services $appname
	    }
	} else {
	    # Process stackato.yml service information ...

	    set known [struct::list map [[my client] services] [lambda s {
		return [dict getit $s name]
	    }]]

	    set bound [dict get' [[my client] app_info $appname] services {}]

	    # Knowledge leak: We know the structure of $services as
	    # :: dict (servicename -> dict ("type" -> vendor))

	    foreach {sname sconfig} $services {
		set vendor [dict get $sconfig type]
		# Unknown services are created and bound, known services
		# just bound.

		if {$sname ni $known} {
		    # Unknown, create
		    # Similar to create_service_banner

		    display "Creating $vendor service \[$sname\]: " false
		    [my client] create_service $vendor $sname
		    display [color green OK]
		}

		if {$sname ni $bound} {
		    # Similar to bind_service_banner
		    display "Binding service \[$sname\]: " false
		    [my client] bind_service $sname $appname
		    display [color green OK]
		}
	    }
	}

	return
    }

    method AppEnvironment {appname} {
	Debug.cli/apps {}

	set env [manifest env]

	# Inject environment variables for the Komodo debugger into
	# the application.
	if {[dict exists [my options] stackato-debug]} {
	    set hp [dict get [my options] stackato-debug]
	    lassign [split $hp :] host port
	    lappend env STACKATO_DEBUG_PORT_NUMBER $port
	    lappend env STACKATO_DEBUG_HOST        $host
	}

	if {![llength $env]} return

	# Process configured environment information ...

	set appenv {}
	foreach {k v} $env {
	    # inlined method 'environment_add', see this file.
	    set item ${k}=$v

	    #set appenv [lsearch -inline -all -not -glob $appenv ${k}=*]
	    lappend appenv $item

	    display "  Adding Environment Variable \[$item\]"
	}

	display "Updating environment: " 0

	set app [[my client] app_info $appname]
	dict set app env $appenv
	[my client] update_app $appname $app
	display [color green OK]

	return
    }

    method environment {{appname {}}} {
	Debug.cli/apps {}
	manifest 1app $appname [callback envlistit]
	return
    }

    method envlistit {appname} {
	set app [[my client] app_info $appname]
	#checker -scope line exclude badOption
	set env [dict get' $app env {}]

	if {[my GenerateJson]} {
	    display [jmap env $env]
	    return
	}
	if {![llength $env]} {
	    display "No Environment Variables" 
	    return
	}

	table::do t {Variable Value} {
	    foreach e $env {
		# Ensure to not split values should they contain '='
		regexp {^([^=]*)=(.*)$} $e -> k v
		$t add $k $v
	    }
	}
	display "\n"
	$t show display
	return
    }

    method environment_add {args} {
	Debug.cli/apps {}
	# args = appname k v  #3
	#        appname k=v  #2a
	#                k v  #2b
	#                k=v  #1

	switch -exact [llength $args] {
	    1 {
		set appname {}
		regexp {^([^=]*)=(.*)$} [lindex $args 0] -> k v
	    }
	    2 {
		lassign $args a b
		if {[string match *=* $b]} {
		    # 2a
		    set appname $a
		    regexp {^([^=]*)=(.*)$} $b -> k v
		} else {
		    # 2b
		    set appname {}
		    set k $a
		    set v $b
		}
	    }
	    3 {
		lassign $args appname k v
	    }
	}

	manifest 1app $appname [callback envaddit $k $v]
	return
    }

    method envaddit {k v appname} {
	set app [[my client] app_info $appname]
	#checker -scope line exclude badOption
	set env [dict get' $app env {}]

	if {$v eq {}} {
	    regexp {^([^=]*)=(.*)$} $k -> k v
	}

	set item ${k}=$v

	set     newenv [lsearch -inline -all -not -glob $env ${k}=*]
	lappend newenv $item

	display "Adding Environment Variable \[$item\]: " false

	dict set app env $newenv
	[my client] update_app $appname $app
	display [color green OK]

	if {[dict getit $app state] ne "STARTED"} return
	my restart $appname
	return
    }

    method environment_del {args} {
	Debug.cli/apps {}
	# args = ?appname? varname
	switch -exact [llength $args] {
	    1 { set appname {} ; set varname [lindex $args 0] }
	    2 { lassign $args appname varname }
	}

	manifest 1app $appname [callback envdelit $varname]
	return
    }

    method envdelit {varname appname} {
	set app [[my client] app_info $appname]
	#checker -scope line exclude badOption
	set env [dict get' $app env {}]

	set newenv [lsearch -inline -all -not -glob $env ${varname}=*]

	display "Deleting Environment Variable \[$varname\]: " false

	if {$newenv ne $env} {
	    dict set app env $newenv
	    [my client] update_app $appname $app
	    display [color green OK]

	    if {[dict getit $app state] ne "STARTED"} return
	    my restart $appname
	} else {
	    display [color green OK]
	}
    }

    method debug_info {appname} {
	Debug.cli/apps {}
	set app [[my client] app_info $appname]
	display [jmap appinfo $app]
	return
    }

    method debug_manifest {} {
	Debug.cli/apps {}
	upvar #0 ::stackato::client::cli::manifest::manifest M
	if {[info exists M]} {
	    manifest::DumpX $M
	} else {
	    display "No configuration found"
	}
	return
    }

    method service_dbshell {args} {
	Debug.cli/apps {}
	# args = appname servicename  #2
	#      | servicename          #1a
	#      | appname              #1b
	#      |                      #0
	#
	# 1a and 1b can be distinguished by checking if the argument
	# is a valid appname.

	switch -exact [llength $args] {
	    0 {
		set appname     {}
		set servicename {}
	    }
	    1 {
		set x [lindex $args 0]
		if {[my app_exists? $x]} {
		    # 1a
		    set appname     $x
		    set servicename {}
		} else {
		    # 1b
		    set appname     {}
		    set servicename $x
		}
	    }
	    2 {
		lassign $args appname servicename
	    }
	}

	manifest 1app $appname [callback dbshellit $servicename]
	return
    }

    method dbshellit {servicename appname} {
	set app [[my client] app_info $appname]

	Debug.cli/apps {app info = [jmap appinfo $app]}

	set services [dict get $app services]

	Debug.cli/apps {services = [jmap map array $services]}

	# No services. Nothing to convert.
	if {![llength $services]} {
	    err "No services are bound to application \[$appname\]"
	}

	if {$servicename eq {}} {
	    # Go through the services and eliminate all which are not
	    # supported. The list at (x$x) below must be kept in sync
	    # with what is supported by the server side dbshell
	    # script.

	    set ps [[my client] services]
	    Debug.cli/apps {provisioned = [jmap services [dict create provisioned $ps]]}

	    # Extract the name->vendor map
	    set map {}
	    foreach p $ps {
		lappend map [dict get $p name] [dict get $p vendor]
	    }

	    set supported {}
	    foreach service $services {
		set vendor [dict get $map $service]
		# (x$x)
		if {$vendor ni {
		    mysql redis mongodb postgresql
		}} continue
		lappend supported $service
	    }
	    set services $supported

	    if {[llength $services] > 1} {
		err "More than one service found; you must specify the service name.\nWe have: [join $services {, }]"
	    } else {
		# Take first service if its the only one and no name
		# was specified.
		set servicename [lindex $services 0]
	    }
	} else {
	    # Search for service with matching name.

	    if {$servicename ni $services} {
		err "Service \[$servicename\] is not known."
	    }
	}

	my run_ssh [list dbshell $servicename] $appname 0
	return
    }

    # # ## ### ##### ######## #############
    ## Internal commands.

    method check_deploy_directory {path} {
	Debug.cli/apps {}
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

    method full_normalize {path} {
	return [file dirname [file normalize $path/___]]
    }

    method get_unreachable_links {root ignorepatterns} {
	Debug.cli/apps {}
	# Fully normalize the root directory we are checking.
	set root [my full_normalize $root]

	Debug.cli/apps {root = $root}

	# Scan the whole directory hierarchy starting at
	# root. Normalize everything, and anything which is not under
	# the root after that is bad and causes rejection.

	# Anything specified to be ignored however is not checked, as
	# it won't be part of the application's files.

	set iprefix {}

	Debug.cli/apps {Scan...}

	set unreachable_paths {}

	display {  Checking for bad links: } false
	set nfiles 0

	fileutil::traverse T $root \
	    -filter    [callback IsUsedA $ignorepatterns $root] \
	    -prefilter [callback IsUsedA $ignorepatterns $root]
	T foreach path {
	    again+ [incr nfiles]

	    set pathx [fileutil::stripPath $root $path]

	    Debug.cli/apps {    $pathx}

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

	Debug.cli/apps {Done}

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

    method upload_app_bits {appname path {ignorepatterns {}}} {
	Debug.cli/apps {}
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

	set copyunsafe [dict get [my options] copyunsafe]

	try {
	    Debug.cli/apps {**************************************************************}
	    display "Uploading Application \[$appname\]:"

	    set tmpdir      [fileutil::tempdir]
	    set upload_file [file normalize "$tmpdir/$appname.zip"]
	    set explode_dir [file normalize "$tmpdir/.stackato_${appname}_files"]
	    set file {}

	    file delete -force $upload_file
	    file delete -force $explode_dir  # Make sure we didn't have anything left over..

	    set ignorepatterns [my TranslateIgnorePatterns $ignorepatterns]

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

		    file mkdir                          $explode_dir
		    file copy [my full_normalize $path] $explode_dir
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
			zipfile::decode::unzipfile $war_file $explode_dir
		    } else {
			if {!$copyunsafe} {
			    set outside [my get_unreachable_links [pwd] $ignorepatterns]

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

			my MakeACopy $explode_dir [pwd] $ignorepatterns
		    }
		}
	    }
	    
	    # The explode_dir (a temp dir) now contains the
	    # application's files. We can now check with CC for known
	    # resources to reduce the amount of data to upload, etc.,
	    # then (re)pack and upload everything.

	    Debug.cli/apps {explode-dir @ $explode_dir}

	    # Send the resource list to the cloudcontroller, the response
	    # will tell us what it already has.

	    set appcloud_resources {}

	    if {![dict get [my options] noresources]} {
		display {  Checking for available resources: } false

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
		    set appcloud_resources [[my client] check_resources $fingerprints]
		    #@type appcloud_resources = list (dict (size, sha1, fn| */string))
		    again+ {                                           }
		    again+ {}
		}

		display " [color green OK]"
		clearlast

		if {[llength $appcloud_resources]} {
		    display {  Processing resources: } false
		    # We can then delete what we do not need to send.

		    set new {}

		    foreach resource $appcloud_resources {
			set fn [dict getit $resource fn]
			file delete -force $fn
			# adjust filenames sans the explode_dir prefix
			dict set resource fn [fileutil::stripPath $explode_dir $fn]
			lappend new $resource
		    }
		    set appcloud_resources $new
		    display [color green OK]
		}
	    }

	    # Perform Packing of the upload bits here.

	    set ftp [my GetFilesToPack $explode_dir]

	    # NOTE: Due to the compiled manifest file the zip file
	    # always contains at least one entry. I.e. it is never
	    # empty.
	    display {  Packing application: } false

	    set mcfile [fileutil::tempfile stackato-mc-]
	    manifest currentInfo $mcfile

	    Debug.cli/apps {mcfile = $mcfile}

	    my Pack $explode_dir $ftp $upload_file $mcfile
	    file delete $mcfile

	    display [color green OK]
	    set upload_size [file size $upload_file]

	    if {$upload_size > 1024*1024} {
		set upload_size [expr {round($upload_size/(1024*1024.))}]M
	    } elseif {$upload_size >= 512} {
		set upload_size [expr {round($upload_size/1024.)}]K
	    }

	    set upload_str "  Uploading ($upload_size): "
	    display $upload_str false ; # See client.Upload for where
	    # this text is used by the upload progress callback.

	    if {[llength $ftp]} {
		# original code uses a channel transform to
		# count bytes read/uploaded, and drive a
		# percentage progress bar of the upload process.
		# We drive this directly in the REST client,
		# with a query-progress callback.

		set file $upload_file
	    } else {
		set file {}
	    }

	    Debug.cli/apps {**************************************************************}
	    Debug.cli/apps {R = $appcloud_resources}
	    Debug.cli/apps {F = $ftp}
	    Debug.cli/apps {U = $upload_file}
	    Debug.cli/apps {**************************************************************}

	    [my client] upload_app $appname $file $appcloud_resources

	    display {Push Status: } false
	    display [color green OK]

	} trap {POSIX ENAMETOOLONG} {e o} {
	    # Rethrow as client error.

	    return -code error -errorcode {STACKATO CLIENT CLI CLI-ERROR} \
		"Stackato client encountered a file name exceeding system limits, aborting\n$e"

	} finally {
	    if {$upload_file ne {}} { catch { file delete -force $upload_file } }
	    if {$explode_dir ne {}} { catch { file delete -force $explode_dir } }
	}
    }

    method IsUsedA {ignorepatterns root apath} {
	Debug.cli/apps {}
	set rpath [fileutil::stripPath $root $apath]
	return [expr {![my IsIgnored $ignorepatterns $root $rpath]}]
    }

    method IsIgnored {ignorepatterns root path} {
	Debug.cli/apps {}
	# ignorepatterns = list (gitpattern matchdir mode tclpattern ...)
	# path is relative to root.

	if {[file nativename $root/$path] eq [file nativename [info nameofexecutable]]} {
	    Debug.cli/apps {Ignored, excluded self}
	    return 1
	}

	foreach {pattern matchdir mode mpattern} $ignorepatterns {

	    if {$matchdir && ![file isdirectory $root/$path]} continue

	    switch -exact $mode {
		glob   { set match [string match $mpattern $path] }
		regexp { set match [regexp --    $mpattern $path] }
	    }

	    if {$match} {
		Debug.cli/apps {Ignored}
		return 1
	    }
	}

	Debug.cli/apps {Ok}
	return 0
    }

    method TranslateIgnorePatterns {ignorepatterns} {
	Debug.cli/apps {}
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

    method Filter {files}  {
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

    method GetFilesToPack {path} {
	Debug.cli/apps {}
	return [struct::list map [fileutil::find $path [lambda x {
	    set base [file tail $x]
	    foreach pattern {*~ \#*\# *.log} {
		if {[string match $pattern $base]} { return 0 }
	    }
	    return [file exists $x]
	}]] [lambda {p x} {
	    fileutil::stripPath $p $x
	} $path]]
    }

    method MakeACopy {explode_dir root ignorepatterns} {
	file mkdir $explode_dir
	set files [my Filter [glob * .*]]

	Debug.cli/apps {STAGE	[join $files \nSTAGE\t]}

	# The files may be symlinks. We have to copy the contents, not
	# the link.

	display "  Copying to temp space: " false

	my Copy 0 $explode_dir $root $ignorepatterns {*}$files

	#again+ {                    }
	#again+ {}
	display " [color green OK]"
	clearlast
    }

    method Copy {nfiles dst root ignorepatterns args} {
	# args = relative to pwd = base source directory.

	file mkdir $dst
	foreach f $args {
	    if {[file type $f] ni {file directory link}} continue
	    if {[my IsIgnored $ignorepatterns $root $f]} continue

	    if {[file isfile $f]} {
		again+ [incr nfiles]
		my CopyFile $f $dst
	    } elseif {[file isdirectory $f]} {
		#puts *|$f|\t|$dst|

		again+ [incr nfiles]
		file mkdir $dst/$f
		set nfiles [my Copy $nfiles $dst $root $ignorepatterns \
				{*}[my Filter [struct::list map \
					   [glob -nocomplain -tails -directory $f * .*] \
					   [lambda {p x} {
					       return $p/$x
					   } $f]]]]
		#puts @@
	    }
	}
	return $nfiles
    }

    method CopyFile {src dstdir} {
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

    method Pack {base files zipfile mcfile} {
	Debug.cli/apps {}

	set z [zipfile::encode [self namespace]::Z]
	foreach f $files {
	    # [Bug 94876] As we are generating our own manifest.yml
	    # file for upload we have to keep an existing one out of
	    # the zip file, or the decoder will balk below, seeing
	    # (and rejecting) the duplicate definition.
	    if {$f eq "manifest.yml"} continue

	    Debug.cli/apps {++ $f}
	    $z file: $f 0 $base/$f
	}

	# The compiled manifest has a fixed path in the upload. It is
	# also always present.
	Debug.cli/apps {MC $mcfile}

	$z file: manifest.yml 0 $mcfile

	Debug.cli/apps {write zip...}
	$z write $zipfile
	$z destroy

	Debug.cli/apps {...done}
	return
    }

    method choose_existing_services {appname user_services} {
	## Note: Assumed to be called only for [my promptok].
	## Making it unnecessary to perform the same check here, again.

	Debug.cli/apps {}

	foreach s $user_services {
	    lappend choices [dict getit $s name]
	    lappend vmap \
		[dict getit $s name] \
		[dict getit $s vendor]
	}

	#set none "<None of the above>"
	#lappend choices $none

	set bound {}
	while {1} {
	    set name [term ask/menu \
			  "Which one ?" "Choose: " \
			  $choices]

	    display "Binding Service: " false
	    [my client] bind_service $name $appname
	    display [color green OK]

	    # Save for manifest.
	    lappend bound $name [dict get $vmap $name]

	    if {![term ask/yn "Bind another ? " no]} break
	}

	return $bound
    }

    method choose_new_services {appname services} {
	## Note: Assumed to be called only for [my promptok].
	## Making it unnecessary to perform the same check here, again.
	Debug.cli/apps {}

	foreach {service_type value} $services {
	    foreach {vendor version} $value {
		lappend service_choices $vendor
	    }
	}

	set service_choices [lsort -dict $service_choices]
	#set none "<None of the above>"
	#lappend service_choices $none

	set bound {}
	while {1} {
	    set vendor [term ask/menu \
			    "What kind of service ?" "Choose: " \
			    $service_choices]

	    set default_name [my random_service_name $vendor]
	    set service_name \
		[term ask/string \
		     "Specify the name of the service \[$default_name\]: " \
		     $default_name]

	    my create_service_banner $vendor $service_name
	    my bind_service_banner   $service_name $appname

	    lappend bound $service_name $vendor

	    if {![term ask/yn "Create another ? " no]} break
	}

	return $bound
    }

    method bind_services {appname} {
	## Note: Assumed to be called only for [my promptok].
	## Making it unnecessary to perform the same check here, again.

	Debug.cli/apps {}
	set user_services [[my client] services]
	set services      [[my client] services_info]

	Debug.cli/apps {existing      = $user_services}
	Debug.cli/apps {provisionable = $services}

	set bound {}

	# Bind existing services, if any.
	if {
	    [llength $user_services] &&
	    [term ask/yn "Bind existing services to '$appname' ? " no]
	} {
	    lappend bound {*}[my choose_existing_services $appname $user_services]
	}

	# Bind new services, if any provisionable.
	if {
	    [llength $services] &&
	    [term ask/yn "Create services to bind to '$appname' ? " no]
	} {
	    lappend bound {*}[my choose_new_services $appname $services]
	}

	if {[llength $bound]} {
	    manifest services= $bound
	}
	return
    }

    method check_app_limit {} {
	Debug.cli/apps {}

	#checker -scope local exclude badOption
	set ci [my client_info]
	set usage  [dict get' $ci usage  {}]
	set limits [dict get' $ci limits {}]

	if {($usage  eq {}) ||
	    ($limits eq {}) ||
	    ([dict get' $limits apps {}] eq {})
	} return

	set tapps [dict get' $limits apps 0]
	set apps  [dict get' $usage  apps 0]

	if {$apps < $tapps} return

        err "Not enough capacity for operation.\nCurrent Usage: ($apps of $tapps total apps already in use)"
    }

    method check_has_capacity_for {mem_wanted context} {
	#checker -scope local exclude badOption
	Debug.cli/apps {}

	set ci [my client_info]
	set usage  [dict get' $ci usage  {}]
	set limits [dict get' $ci limits {}]

	Debug.cli/apps {client info usage = [jmap map dict $usage]}
	Debug.cli/apps {client info limits = [jmap map dict $limits]}

	if {($usage  eq {}) ||
	    ($limits eq {})
	} {
	    Debug.cli/apps {no usage, or no limits -- no checking}
	    return
	}

	set tmem [dict getit $limits memory]
	set mem  [dict getit $usage  memory]

	set available [expr {$tmem - $mem}]

	Debug.cli/apps {MB Total limit = $tmem}
	Debug.cli/apps {MB Total used  = $mem}
	Debug.cli/apps {MB Available   = $available}
	Debug.cli/apps {MB Requested   = $mem_wanted}

	if {$mem_wanted <= $available} return
	# More requested than the system can give.

        set tmem      [log psz [expr {$tmem * 1024 * 1024}]]
	set mem       [log psz [expr {$mem * 1024 * 1024}]]
        set available [log psz [expr {$available * 1024 * 1024}]]
	set wanted    [log psz [expr {$mem_wanted * 1024 * 1024}]]

	switch -- $context {
	    mem {
		if {$available <= 0} {
		    set available none
		}
		set    message "Not enough capacity ($wanted requested) for operation."
		append message "\nCurrent Usage: $mem of $tmem total, $available available for use"
	    }
	    push {
		set message "Unable to push. "
		if {$available < 0} {
		    append message "The total memory usage of $mem exceeds the allowed limit of ${tmem}."
		} else {
		    append message "Not enough capacity available ($available, but $wanted requested)."
		}
	    }
	    default {
		error "bad context $context for memory error"
	    }
	}

	display ""
	err $message
    }

    method mem_query {mem {label {}}} {
	Debug.cli/apps {}

	if {$label eq {}} {
	    set label "Enter Memory Reservation \[$mem\]"
	}

	while {1} {
	    set mem_user [term ask/string "${label}: "]

	    # Plain <Enter> ==> default.
	    if {$mem_user == {}} {
		set mem_user $mem
	    }

	    Debug.cli/apps {  user = $mem_user}

	    if {![catch {
		my mem_choice_to_quota $mem_user;#syntax check
	    } msg]} break

	    display "Expected memory (<int>, <int>M, <float>G), got \"$mem_user\": $msg"
	}
	return $mem_user
    }

    method mem_choices {} {
	Debug.cli/apps {}

	set default {64M 128M 256M 512M 1G 2G}

	set ci [my client_info]
	if {$ci eq {}} {
	    return $default
	}

	#checker -scope local exclude badOption
	set usage  [dict get' $ci usage  {}]
	set limits [dict get' $ci limits {}]

	if {($usage  eq {}) ||
	    ($limits eq {})} {
	    return $default
	}

	set available_for_use [dict getit $limits memory]

	#@todo checks that this ok for
	set max [llength $default];incr max -1
	for {
	    set counter 0
	    set n 128
	} {$counter < $max} {
	    incr counter
	    incr n $n
	} {
	    if {$available_for_use < $n} {
		return [lrange $default 0 $counter]
	    }
	}
	return $default
    }

    method ismem {mem} {
	Debug.cli/apps {}
	return [expr {
		      [regexp -nocase {^\d+M$} $mem] ||
		      [regexp -nocase {^\d+G$} $mem] ||
		      [regexp -nocase {^\d+$}  $mem]
		  }]
    }

    method normalize_mem {mem} {
	Debug.cli/apps {}
	if {[regexp -nocase {[KGM]$} $mem]} { return $mem }
	return ${mem}M
    }

    method mem_quota_to_choice {mem} {
	Debug.cli/apps {}
	if {$mem < 1024} { return ${mem}M }
	return [format %.1f [expr {$mem/1024.}]]G
    }

    method get_instances {appname} {
	Debug.cli/apps {}
	set instances_info_envelope [[my client] app_instances $appname]

	# @todo what else can instances_info_envelope be ? Hash map ?
	# if instances_info_envelope.is_a?(Array)      return

	#checker -scope line exclude badOption
	set instances_info [dict get' $instances_info_envelope instances {}]
	#@type instances_info = list (dict) /@todo determine more.

	# @todo list-util sort on sub-dict key value
	set instances_info [lsort -command [lambda {a b} {
	    expr {[dict getit $a index] - [dict getit $b index]}
	}] $instances_info]

	if {[my GenerateJson]} {
	    display [jmap instances $instances_info]
	    return
	}

	if {![llength $instances_info]} {
	    display [color yellow "No running instances for \[$appname\]"]
	    return
	}

	table::do t {Index State {Start Time}} {
	    foreach entry $instances_info {
		$t add \
		    [dict getit $entry index] \
		    [dict getit $entry state] \
		    [clock format [dict getit $entry since] -format "%m/%d/%Y %I:%M%p"]
	    }
	}
	display ""
	$t show display
    }

    method change_instances {appname instances} {
	Debug.cli/apps {}
	# instances = +/-num, or num
	# 1st is a relative spec, 2nd is absolute.

	set app [[my client] app_info $appname]
	if {![string is int $instances]} {
	    err "Invalid number of instances '$instances'" 
	}

	set current_instances [dict getit $app instances]

	set new_instances \
	    [expr {
		   [string match {[-+]*} $instances]
		   ? $current_instances + $instances
		   : $instances}]

	if {$new_instances < 1} {
	    err "There must be at least 1 instance."
	}

	if {$current_instances == $new_instances} {
	    if {$new_instances > 1} {
		display [color yellow "Application \[$appname\] is already running $new_instances instances."]
	    } else {
		display [color yellow "Application \[$appname\] is already running $new_instances instance."]
	    }
	    return
	}

	set up_or_down [expr {$new_instances > $current_instances
			      ? "up"
			      : "down"}]

	display "Scaling Application instances $up_or_down to $new_instances: " false
	dict set app instances $new_instances

	[my client] update_app $appname $app
	display [color green OK]
    }

    method app_started_properly {appname error_on_health} {
	Debug.cli/apps {}
	set app [[my client] app_info $appname]
	set health [my health $app]
	switch -- $health {
	    N/A {
		# Health manager not running.
		if {$error_on_health} {
		    err "Application '$appname's state is undetermined, not enough information available." 
		}
		return 0
	    }
	    RUNNING { return 1 }
	    STOPPED { return 0 }
	    default {
		if {$health > 0} {
		    return 1
		}
		return 0
	    }
	}
    }

    method display_logfile {path content {instance 0} {banner {}}} {
	Debug.cli/apps {}
	if {$banner eq {}} { set banner  "====> $path <====" }
	if {$content eq {}} return
     
        display $banner
	if {[dict get [my options] prefixlogs]} {
	    set prefix [color bold "\[$instance: $path\] -"]
	    foreach line [split [string trimright $content] \n] {
		display "$prefix $line"
	    }
	} else {
	    display [string trimright $content]
	}
        display {}      
    }

    method log_file_paths {appname instance args} {
	Debug.cli/apps {}
	set res {}
	foreach path $args {
	    catch {
		set content [[my client] app_files $appname $path $instance]
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

    method grab_all_logs {appname} {
	Debug.cli/apps {}
	set instances_info_envelope [[my client] app_instances $appname]

	# @todo what else can instances_info_envelope be ? Hash map ?
	# if instances_info_envelope.is_a?(Array)      return

	#checker -scope line exclude badOption
	set instances_info [dict get' $instances_info_envelope instances {}]
	foreach entry $instances_info {
	    my grab_logs $appname [dict getit $entry index]
	}
    }

    method grab_logs {appname instance} {
	Debug.cli/apps {}
	foreach path [my log_file_paths $appname $instance \
			  /logs] {
	    set content {}
	    try {
		set content [[my client] app_files $appname $path $instance]
		my display_logfile $path $content $instance
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

    method grab_crash_logs {appname instance {was_staged false} {tailed no}} {
	Debug.cli/apps {}
	# stage crash info
	if {!$was_staged} {
	    my crashinfo $appname false
	}

	if {[package vsatisfies [my ServerVersion] 2.3]} {
	    # Like s logs...
	    my fastlogsit $appname
	    return
	}

	if {$instance eq {}} { set instance 0 }

	set map [config instances]
	#checker -scope line exclude badOption
	set instance [dict get' $map $instance $instance]

	foreach path [my log_file_paths $appname $instance \
			  /logs /app/logs /app/log] {
	    if {$tailed && [string match *staging* $path]} continue
	    set content {}
	    try {
		set content [[my client] app_files $appname $path $instance]
		my display_logfile $path $content $instance
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

    method grab_startup_tail {appname {since 0}} {
	Debug.cli/apps {}

	try {
	    set new_lines 0
	    set path "logs/stderr.log"
	    set content [[my client] app_files $appname $path]

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

    method check_app_for_restart {appname} {
	Debug.cli/apps {}
	set app [[my client] app_info $appname]
	if {[dict getit $app state] ne "STARTED"} return
	my restart $appname
	return
    }

    # # ## ### ##### ######## #############
    ## State

    variable \
	SLEEP_TIME \
	LINE_LENGTH \
	TICKER_TICKS \
	HEALTH_TICKS \
	TAIL_TICKS \
	GIVEUP_TICKS \
	YES_SET

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::client::cli::command::Apps 0
