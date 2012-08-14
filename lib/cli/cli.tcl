# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require try                           ;# I want try/catch/finally
package require Tclx                          ;# Signal handling.
package require stackato::client::cli::config ;# Global configuration.
package require stackato::client::cli::usage  ;# Global usage texts
package require stackato::color
package require stackato::log
package require stackato::term
package require stackato::readline
package require struct::list
package require lambda
package require exec

namespace eval ::stackato::client::cli {}

debug level  cli
debug prefix cli {[::debug::snit::call] | }

# # ## ### ##### ######## ############# #####################

oo::class create ::stackato::client::cli {
    # # ## ### ##### ######## #############

    constructor {argv} {
	global env
	Debug.cli {}

	set myargs       $argv
	set myexitstatus 1 ; # ok (not unix convention)
	set myhelponly   0
	set myusage      {}
	set myusageerror {}
	set mynamespace  {}
	set myaction     {}
	#set myoptions(path) [pwd] - initially not defined.
	# limit-* options - initially not defined.
	# mem   - initially undefined
	# group - initially undefined
	# stackato-debug - initially undefined
	# reset - initially undefined
	array set myoptions {
	    copyunsafe 0
	    email {}
	    password {}
	    name {}
	    bind {}
	    instances {}
	    instance {}
	    url {}
	    manifest {}
	    nostart 0
	    force 0
	    all 0
	    dry 0
	    trace {}
	    quiet 0
	    nozip 0
	    noresources 0
	    colorize 1
	    verbose 0
	    noprompts 0
	    prefixlogs 0
	    json 0
	    print 0
	    allow-http 0
	    runtime {}
	    exec {}
	    noframework 0
	    framework {}
	    canary 0
	}

	set myoptions(tail) [expr {$::tcl_platform(platform) ne "windows"}]

	if {[info exists env(STACKATO_TARGET)]} {
	    set myoptions(target) $env(STACKATO_TARGET)
	}
	if {[info exists env(STACKATO_GROUP)]} {
	    set myoptions(group) $env(STACKATO_GROUP)
	}

	# Leaving out 'port', for proper defaulting on non-existence.

	# Namespace import, sort of.
	namespace path [linsert [namespace path] end \
			    ::stackato ::stackato::log ::stackato::client::cli]
    }

    destructor {
	Debug.cli {}
    }

    # # ## ### ##### ######## #############
    ## API

    method run {} {
	Debug.cli {}
	global tcl_platform
	try {
	    if {$tcl_platform(platform) eq "windows"} {
		signal trap {TERM INT} {
		    ::stackato::log::say! "\nInterrupted\n"
		    ::exec::clear
		    exit 1
		}
	    } else {
		signal -restart trap {TERM INT} {
		    ::stackato::log::say! "\nInterrupted\n"
		    ::exec::clear
		    exit 1
		}
	    }

	    my ParseOptions

	    if {![stackato::readline tty]} {
		set myoptions(colorize) 0
	    }

	    color colorize    $myoptions(colorize)	; unset myoptions(colorize)
	    config nozip      $myoptions(nozip)		; unset myoptions(nozip)
	    config trace      $myoptions(trace)		; unset myoptions(trace)
	    config allow-http $myoptions(allow-http)	; unset myoptions(allow-http)

	    if {!$myoptions(quiet) && ![log defined]} {
		log to stdout
	    }

	    my ConvertOptions
	    my ProcessAliases
	    my ParseCommand

	    if {($mynamespace ne {}) && ($myaction ne {})} {
		Debug.cli {Dispatch ($mynamespace, $myaction)}

		set cmdclass "stackato::client::cli::command::[textutil::string::cap [string tolower $mynamespace]]"
		set cmd      FAKE

		Debug.cli {Command class = $cmdclass}

		package require $cmdclass

		set cmd [$cmdclass new {*}[array get myoptions]]
		$cmd $myaction {*}$myargs ; # HERE the main action happens.
		$cmd destroy

	    } elseif {$myhelponly || ($myusage ne {})} {
		Debug.cli {Help requested, or syntax error}
		usage::Display
		exit [expr {!$myhelponly}]
	    } else {
		Debug.cli {Full Help}
		display [usage::Basic]
		exit 1
	    }

	    # Done with main actions, below is the error capture
	} trap {TERM INTERUPT} {e o} {
	    say! "\nInterrupted\n"
	    exit 1

 	} trap {OPTION INVALID} {e} - trap {OPTION AMBIGOUS} {e} {

	    say! [color red "$e"]\n[usage::Basic]
	    set myexitstatus false

	} trap {STACKATO SERVER DATA ERROR} {e} {

	    say! [color red "Bad server response; $e"]
	    set myexitstatus false

	} trap {STACKATO CLIENT AUTHERROR} {e} {

	    if {[config auth_token] eq {}} {
		say! [color red "Login Required"]
		say! "Please use '[usage me] login'"
	    } else {
		say! [color red "Not Authorized"]
		say! "You are using an expired or deleted login"
		say! "Please use '[usage me] login'"
	    }
	    set myexitstatus false

	} trap {STACKATO CLIENT TARGETERROR} {e} - trap {STACKATO CLIENT NOTFOUND} {e} - trap {STACKATO CLIENT BADTARGET} {e} {

	    say! [color red "$e"]

	    Debug.cli {$e}
	    Debug.cli {$::errorCode}
	    Debug.cli {$::errorInfo}

	    #my ProcessInternalError $e $::errorCode $::errorInfo
	    set myexitstatus false

	} trap {@todo@ http exception} e {

	    say! [color red "$e"]
	    set myexitstatus false

	} trap {STACKATO CLIENT CLI GRACEFUL-EXIT} e {
	    # Redirected commands end up generating this exception (kind of goto)
 	} trap {STACKATO CLIENT CLI} e - trap {BROWSE FAIL} e {

	    say! [color red "$e"]
	    set myexitstatus false

 	} trap {REST HTTP} {e o} {

	    say [color red "$e"]
	    set myexitstatus false

 	} trap {STACKATO CLIENT INTERNAL} {e o} {
	    lassign $e msg trace code

	    Debug.cli {$e}
	    Debug.cli {$o}
	    Debug.cli {$code}
	    Debug.cli {$trace}

	    my ProcessInternalError $msg $code $trace
	    set myexitstatus false

	} trap {POSIX EPIPE} {e o} {
	    # Ignore (stdout was piped and aborted before we wrote all our output).
	    Debug.cli {$e}
	    Debug.cli {$o}
	    Debug.cli {$::errorCode}
	    Debug.cli {$::errorInfo}

	} trap {@todo@ system exit} e {
	    set myexitstatus e.success?

 	} trap {@todo@ syntax error} e {

	    say! [color red "$e"]\n$::errorInfo
	    set myexitstatus false

	} on error {e o} {
	    Debug.cli {$e}
	    Debug.cli {$o}
	    Debug.cli {$::errorCode}
	    Debug.cli {$::errorInfo}

	    if {[string match {*wrong \# args*} $e] &&
		[string match *${cmd}* $e]} {
		usage::Display
	    } else {
		my ProcessInternalError $e $::errorCode $::errorInfo
	    }
	    set myexitstatus false

	} finally {
	    Debug.cli {/finally}
	    #say ""

	    if {$myexitstatus eq {}} {
		set myexitstatus 1
	    }
	    if {$myoptions(verbose)} {
		if {$myexitstatus} {
		    puts [color green "\[$mynamespace:$myaction\] SUCCEEDED"]
		} else {
		    puts [color red   "\[$mynamespace:$myaction\] FAILED"]
		}
		say ""
	    }
	}

	# Clean up any child processes whose regular cleanup location
	# was not reached, likely due to an error being thrown and
	# reported, whether internal or server side.
	::exec::clear

	# ruby exitstatus - true/false = ok/fail. Map to regular unix 0/1.

	exit [expr {!$myexitstatus}]
	return
    }

    # # ## ### ##### ######## #############
    ## Internal commands.

    method ProcessInternalError {msg code trace} {
	Debug.cli {}

	# Bug 90845.
	if {[string match {*stdin isn't a terminal*} $msg]} {
	    say! "Error: [color red $msg]"
	    say! "Try with --noprompt to suppress all user interaction requiring a proper terminal"
	    return
	}

	say! [color red "Stackato client has encountered an internal error."]
	say! "Error: [color red $msg]"

	set f [fileutil::tempfile stackato-]
	fileutil::writeFile $f $msg\n$code\n$trace\n

	say! "Full traceback stored at: [file nativename $f]"

	#say! "Please report this bug to ActiveState by attaching the above file at,"
	#say! "\thttp://bugs.activestate.com/"
	say! "Please report this bug to ActiveState by emailing the above file to"
	say! "stackato-support@activestate.com with a short description of what you"
	say! "were trying to do."
	return
    }

    method ParseOptions {} {
	Debug.cli {}

	set instances [my CheckInstancesDelta]

	# regular cmdline processing...

	set arguments {}
	set noo  0 ; # number of non-option arguments seen.
	set stop 0 ; # stop at next non-option argument.

	set theoptions [my JustOptions]


	while {[llength $myargs]} {
	    # Skip non-options at head, and in between.

	    set o [lindex $myargs 0]

	    Debug.cli {noo($noo)stop($stop)| ($o) <-- [llength $myargs]:($myargs)}

	    if {![string match -* $o]} {
		Debug.cli {    Save regular word}

		struct::list shift myargs
		lappend arguments $o

		if {$stop} {
		    Debug.cli {    Stop!}
		    # Push all remaining words into the list of
		    # arguments for the command, options or not.
		    lappend arguments {*}$myargs
		    set myargs {}
		    break
		}

		# When we see a 'run' or 'ssh' command the next
		# non-option is the command which will be run, and the
		# remainder will be its arguments, not
		# stackato's. Prepare to stop processing the arguments
		# when that happens.
		incr noo
		if {($noo == 1) && (($o eq "run") || ($o eq "ssh"))} {
		    Debug.cli {    Stop on next non-option}
		    incr stop
		}
		continue
	    }

	    # Check option for validity.
	    # @todo@ Extend option processing to report ambigous option names.
	    set what [cmdline::getopt myargs $theoptions o v]

	    Debug.cli {    Process: $what ($o) => ($v)}

	    switch -exact -- $what {
		-1 {
		    # Have to know which errorcodes to set.
		    return -code error -errorcode {OPTION INVALID} $v
		}
		0 break
		1 {
		    switch -exact -- $o {
			-copy-unsafe-links { set myoptions(copyunsafe) 1 }
			-email     -
			-user      { set myoptions(email) $v }
			-passwd    -
			-pass      -
			-password  { set myoptions(password) $v }
			-app       -
			-name      { set myoptions(name) $v }
			-bind      { set myoptions(bind) $v }
			-instance  { set myoptions(instance) $v }
			-instances { set myoptions(instances) $v }
			-url       { set myoptions(url) $v }
			-mem       { set myoptions(mem) $v }
			-apps      { set myoptions(limit-apps) $v }
			-appuris   { set myoptions(limit-appuris) $v }
			-services  { set myoptions(limit-services) $v }
			-sudo      { set myoptions(limit-sudo) $v }
			-path      { set myoptions(path) $v }
			m          -
			-manifest  { set myoptions(manifest) $v }
			-no-start  -
			-nostart   { set myoptions(nostart) 1 }
			-force     { set myoptions(force) 1 }
			-all       { set myoptions(all) 1 }
			-dry-run   { set myoptions(dry) 1 }
			-reset     { set myoptions(reset) 1 }
			-timeout   { set myoptions(timeout) $v }
			-target    { set myoptions(target) $v }
			-group     { set myoptions(group) $v }
			-debug-group { set myoptions(debug-group) 1 }
			-stackato-debug { set myoptions(stackato-debug) $v }
			-token-file {
			    set myoptions(token_file) $v
			}
			t          -
			-trace     {
			    if {![llength $myargs] || [string match -* [lindex $myargs 0]]} {
				# Next is option, argument not present
				set v 1
			    } else {
				# Optional argument is present, process.
				set v [struct::list shift myargs]
			    }
			    set myoptions(trace) $v
			}
			-tail {
			    set myoptions(tail) 1
			}
			-no-tail -
			-notail {
			    set myoptions(tail) 0
			}
			q             -
			-quiet        { set myoptions(quiet) 1 }
			-nozip        -
			-no-zip       { set myoptions(nozip) 1 }
			-no-resources -
			-noresources  { set myoptions(noresources) 1 }
			-no-color     { set myoptions(colorize) 0 }
			-verbose      { set myoptions(verbose) 1 }
			n                -
			-no-prompt       -
			-noprompt        -
			-non-interactive { set myoptions(noprompts) 1 }
			-prefix          -
			-prefix-logs     -
			-prefixlogs      { set myoptions(prefixlogs) 1 }
			-json            { set myoptions(json) 1 }
			-print           { set myoptions(print) 1 }
			-allow-http      { set myoptions(allow-http) 1 }
			v                -
			-version         {
			    my SetCommand misc version
			}
			h                -
			-help            {
			    puts [usage::Command]
			    exit
			}
			-runtime         { set myoptions(runtime) $v }
			-exec            { set myoptions(exec) $v }
			-noframework     {
			    set myoptions(noframework) 1
			    set myoptions(framework) {}
			}
			f                -
			-framework       {
			    set myoptions(framework) $v
			    set myoptions(noframework) 0
			}
			-port            { set myoptions(port) $v }
			-canary          { set myoptions(canary) 1 }
			u                { set myoptions(proxy) $v }
			-options {
			    puts [cmdline::usage [my Options]]
			    exit 0
			}
			-debug {
			    debug on $v
			}
			default {
			    return -code error -errorcode {STACKATO CLIENT CLI INVALID OPTION} \
				"Unknown option \"$o\""
			}
		    }
		}
		default {
		    return -code error {Internal error, bad cmdline return}
		}
	    }
	    # Handle tail --options ... ?
	}

	Debug.cli {words     = ($arguments)}
	Debug.cli {instances = ($instances)}

	set     myargs $arguments
	lappend myargs {*}$instances
	return
    }

    method CheckInstancesDelta {} {
	Debug.cli {}
	if {![llength $myargs]} { return {} }

	# @todo RFE struct::list -- split (2 results, filter, and !filter)

	# Extract the instance references
	set instances [struct::list filter $myargs [lambda x {
	    regexp -- {^-\d+$} $x
	}]]

	# ... and, conversely, strip them from the regular arguments.
	set myargs [struct::list filter $myargs [lambda x {
	    expr {![regexp -- {^-\d+$} $x]}
	}]]

	return $instances
    }

    method ConvertOptions {} {
	Debug.cli {}
	# make sure certain options are valid and in correct form.
	if {![string is int $myoptions(instances)]} {
	    return -code error -errorcode {STACKATO CLIENT CLI INSTANCES BAD} "Bad instances \[$myoptions(instances)\]"
	}
	if {![string is int $myoptions(instance)]} {
	    return -code error -errorcode {STACKATO CLIENT CLI INSTANCE BAD} "Bad instance \[$myoptions(instance)\]"
	}
	return
    }

    method ProcessAliases {} {
	Debug.cli {}
	if {![llength $myargs]} return

	set cmd [lindex $myargs 0]
	set aliases [config aliases]

	if {[dict exists $aliases $cmd]} {
	    set newcmd [dict get $aliases $cmd]

	    if {$myoptions(verbose)} {
		display "\[$cmd\] aliased to $newcmd"
	    }

	    set myargs \
		[lreplace $myargs 0 0 \
		     $newcmd]
	}
	return
    }

    method ParseCommand {} {
	Debug.cli {}
	# just return if already set, this happens with -v, -h
	if {($mynamespace ne {}) && ($myaction ne {})} return

	set verb [struct::list shift myargs]
	Debug.cli {verb = ($verb)}

	switch -exact -- $verb {
	    debug-columns {
		my Usage {debug-columns}
		my SetNamedCommand misc columns debug-columns 0
	    }
	    debug-user {
		my Usage {debug-user}
		my SetNamedCommand user allinfo debug-user 0
	    }
	    debug-app-info {
		my Usage {debug-app-info <appname>}
		my SetNamedCommand apps debug_info debug-app-info 1
	    }
	    debug-manifest {
		my Usage {debug-manifest}
		my SetNamedCommand apps debug_manifest debug-manifest
	    }
	    debug-home {
		my Usage {debug-home}
		my SetNamedCommand misc debug_home debug-home
	    }
	    version {
		my Usage {version} \
		    {Report client application version}
		my SetCommand misc version
	    }
	    target {
		my Usage {target [url] [--url] [--allow-http]} \
		    {Reports current target or sets a new target}
		if {[llength $myargs] == 1} {
		    my SetNamedCommand misc set_target target 1
		} else {
		    my SetCommand misc target
		}
	    }
	    targets {
		my Usage {targets} \
		    {List known targets and associated authorization tokens}
		my SetCommand misc targets
	    }
	    group {
		my Usage {group [--reset] [name]} \
		    {Set/unset current group, show current group}
		if {[llength $myargs] == 1} {
		    my SetNamedCommand misc group_set group 1
		} else {
		    my SetNamedCommand misc group_show group
		}
	    }
	    groups {
		lappend cmds groups
		lappend cmds {groups create <name>}
		lappend cmds {groups delete <name>}
		lappend cmds {groups add-user <group> <user>}
		lappend cmds {groups delete-user <group> <user>}
		lappend cmds {groups users <group>}
		lappend cmds {groups limits [group|user] [--mem SIZE] [--services N] [--apps N] [--appuris N] [--sudo BOOL]}
		my Usage [join $cmds "\n\t "] {Manage groups}

		if {[llength $myargs] == 0} {
		    my SetNamedCommand misc groups_show groups 0
		} else {
		    # Switch per sub-method
		    switch -exact -- [set sub [lindex $myargs 0]] {
			create      { my SetNamedCommand       misc group_create      {groups create} 2 }
			delete      { my SetNamedCommand       misc group_delete      {groups delete} 2 }
			add-user    { my SetNamedCommand       misc group_add_user    {groups add-user} 3 }
			delete-user { my SetNamedCommand       misc group_remove_user {groups delete-user} 3 }
			users       { my SetNamedCommandMinMax misc group_users       {groups users} 1 2 }
			limits      { my SetNamedCommandMinMax misc group_limits      {groups limits} 1 2 }
			default {
			    my UsageError "Unknown groups command \[$sub\]"
			}
		    }
		}
	    }
	    limits {
		my Usage {limits [group|user] [--mem SIZE] [--services N] [--apps N] [--appuris N] [--sudo BOOL]} \
		    {Show and modify user/group limits}
		my SetNamedCommandMinMax misc group_limits1 limits 0 1
	    }
	    admin {
		lappend cmds {admin report <destinationfile>}
		lappend cmds {admin patch  <patchfile>|<name>|<url>}
		my Usage [join $cmds "\n\t "] {Administrative operations}
		# Switch per sub-method
		switch -exact -- [set sub [lindex $myargs 0]] {
		    report  { my SetNamedCommandMinMax admin admin_report {admin report} 1 2 }
		    patch   { my SetNamedCommand       admin admin_patch  {admin patch} 2 }
		    default {
			my UsageError "Unknown admin command \[$sub\]"
		    }
		}
	    }
	    tunnel {
		my Usage {tunnel [servicename] [clientcmd] [--port port] [--url URL] [--passwd PASS] [--allow-http]} \
		    {Create a local tunnel to a service, possibly start a local client as well}
		set n [llength $myargs]
		switch -exact -- $n {
		    0 - 1 - 2 { my SetCommand services tunnel $n }
		    default   { my SetCommand services tunnel 0 }
		}
	    }
	    tokens {
		my Usage {tokens} \
		    {List known targets and associated authorization tokens}
		my SetCommand misc tokens
	    }
	    info {
		my Usage {info} \
		    {System and account information}
		my SetCommand misc info
	    }
	    usage {
		my Usage {usage [--all] [user|group]} \
		    {System usage information}
		my SetCommandMinMax misc usage 0 1
	    }
	    runtimes {
		my Usage {runtimes} \
		    {Display the supported runtimes of the target system}
		my SetCommand misc runtimes
	    }
	    frameworks {
		my Usage {frameworks} \
		    {Display the recognized frameworks of the target system}
		my SetCommand misc frameworks
	    }
	    user {
		my Usage {user} \
		    {Display user account information}
		my SetNamedCommand user info user
	    }
	    login {
		my Usage {login [email] [--passwd PASS] [--token-file TOKENFILE] [--group GROUP]} \
		    {Log into the current target}
		if {[llength $myargs] == 1} {
		    my SetCommand user login 1
		} else {
		    my SetCommand user login
		}
	    }
	    logout {
		my Usage {logout [--all] [target]} \
		    {Logs current user out of the current, all, or specified target system}
		if {[llength $myargs] == 1} {
		    my SetCommand user logout 1
		} else {
		    my SetCommand user logout
		}

	    }
	    passwd {
		my Usage {passwd} \
		    {Change the password for the current user}
		if {[llength $myargs] == 1} {
		    my SetNamedCommand user change_password passwd 1
		} else {
		    my SetNamedCommand user change_password passwd
		}

	    }
	    add-user - add_user - create_user - create-user - register {
		my Usage {add-user [email] [--passwd PASS]} \
		    {Register a new user (requires admin privileges)}
		if {[llength $myargs] == 1} {
		    my SetNamedCommand admin add_user $verb 1
		} else {
		    my SetNamedCommand admin add_user $verb
		}

	    }
	    delete-user - delete_user - unregister {
		my Usage {delete-user <user>} \
		    {Delete a user and all apps and services (requires admin privileges)}
		my SetNamedCommand admin delete_user $verb 1
	    }
	    users {
		my Usage {users} \
		    {List all users and associated applications.}
		my SetNamedCommand admin list_users users
	    }
	    list - apps {
		my Usage $verb \
		    {List deployed applications}
		my SetCommand misc apps
	    }
	    open {
		my Usage {open [appname|url|"api"]} \
		    {Open the application|url|target in a browser}
		my SetNamedCommandMinMax apps open_browser open 0 1
	    }
	    start {
		my Usage {start [appname]} \
		    {Start the application}
		my SetCommandMinMax apps start 0 1
	    }
	    stop {
		my Usage {stop [appname]} \
		    {Stop the application}
		my SetCommandMinMax apps stop 0 1
	    }
	    restart {
		my Usage {restart [appname]} \
		    {Restart the application}
		my SetCommandMinMax apps restart 0 1
	    }
	    mem {
		my Usage {mem [appname] [memsize]} \
		    {Show or update the memory reservation for an application}
		my SetCommandMinMax apps mem 0 2
	    }
	    stats {
		my Usage {stats [appname]} \
		    {Display resource usage for the application}
		my SetCommandMinMax apps stats 0 1
	    }
	    map {
		my Usage {map [appname] <url>} \
		    {Register the application to the url}
		my SetCommandMinMax apps map 1 2
	    }
	    unmap {
		my Usage {unmap [appname] <url>} \
		    {Unregister the application from the url}
		my SetCommandMinMax apps unmap 1 2
	    }
	    delete {
		my Usage {delete [appname...]} \
		    {Delete the named applications}
		if {$myoptions(all) && ![llength $myargs]} {
		    my SetCommand apps delete 0
		} else {
		    set n [llength $myargs]
		    my SetCommand apps delete $n
		}
	    }
	    files {
		my Usage {files [appname] [path] [--instance N] [--all] [--prefix]} \
		    {Display directory listing or file download for [path]}
		my SetCommandMinMax apps files 0 2
	    }
	    run {
		my Usage {run [--instance N] [appname] <cmd>...} \
		    {Run an arbitrary command on a running instance}
		if {[set n [llength $myargs]] > 1} {
		    my SetCommand apps run $n
		} else {
		    my SetCommand apps run 1
		}
	    }
	    ssh {
		my Usage {ssh [--instance N] [appname|"api"] [cmd...]} \
		    {ssh to a running instance (or target), or run an arbitrary command.}
		my SetCommand apps ssh [llength $myargs]
	    }
	    logs {
		my Usage {logs <appname> [--instance N] [--all] [--prefix]} \
		    {Display log information for the application}
		my SetCommandMinMax apps logs 0 1
	    }
	    instances - scale {
		my Usage {instances [appname] [num|delta]} \
		    {List application instances, and scale up or down}
		my SetNamedCommandMinMax apps instances $verb 0 2
	    }
	    crashes {
		my Usage {crashes [appname]} \
		    {List recent application crashes}
		my SetCommandMinMax apps crashes 0 1
	    }
	    crashlogs {
		my Usage {crashlogs [appname]} \
		    {Display log information for crashed applications}
		my SetCommandMinMax apps crashlogs 0 1
	    }
	    push {
		my Usage {push [appname] [--path PATH] [--url URL] [--instances N] [--mem SIZE] [--runtime RUNTIME] [--framework|-f FRAMEWORK] [--no-start] [--copy-unsafe-links]} \
		    "Configure, create, push, map, and start a new application.\nThe application inherits the following properties from stackato.yml:\n  name\n  instances\n  framework runtime\n  framework type\n  mem\n  ignores\n  env\n  services"
		if {[llength $myargs] == 1} {
		    my SetCommand apps push 1
		} else {
		    my SetCommand apps push 0
		}
	    }
	    update {
		my Usage {update [appname] [--path PATH]} \
		    "Update the application bits.\nThe application inherits the following properties from stackato.yml:\n  ignores\n  env\n  services"
		if {[llength $myargs] == 1} {
		    my SetCommand apps update 1
		} else {
		    my SetCommand apps update 0
		}
	    }
	    services {
		my Usage {services} \
		    {Lists of services available and provisioned}
		my SetCommand misc services
	    }
	    dbshell {
		my Usage {dbshell [appname] [servicename]} \
		    {Invoke interactive db shell for a bound service.}
		my SetNamedCommandMinMax apps service_dbshell dbshell 0 2
	    }
	    env {
		my Usage {env [appname]} \
		    {List application environment variables}
		my SetNamedCommandMinMax apps environment env 0 1
	    }
	    env-add {
		my Usage {env-add [appname] <variable[=]value>} \
		    {Add an environment variable to an application}
		my SetNamedCommandMinMax apps environment_add env-add 1 3
	    }
	    env-del {
		my Usage {env-del [appname] <variable>} \
		    {Delete an environment variable to an application}
		my SetNamedCommandMinMax apps environment_del env-del 1 2
	    }
	    create-service - create_service {
		my Usage {create-service [service] [servicename] [appname] [--name servicename] [--bind appname]} \
		    {Create a provisioned service and assign it <servicename>, and bind to <appname>}
		switch -exact -- [set n [llength $myargs]] {
		    0 - 1 - 2 - 3 {
			my SetNamedCommand services create_service $verb $n
		    } default {
			my SetNamedCommand services create_service $verb
		    }
		}
	    }
	    delete-service - delete_service {
		my Usage {delete-service [--all] [service...]} \
		    {Delete provisioned services}
		my SetNamedCommand services delete_service $verb [llength $myargs]
	    }
	    bind-service - bind_service {
		my Usage {bind-service <servicename> [appname]} \
		    {Bind a service to an application}
		my SetNamedCommandMinMax services bind_service $verb 1 2
	    }
	    unbind-service - unbind_service {
		my Usage {unbind-service <servicename> [appname]} \
		    {Unbind service from the application}
		my SetNamedCommandMinMax services unbind_service $verb 1 2
	    }
	    clone-services {
		my Usage {clone-services <src-app> <dest-app>} \
		    {Clone service bindings from <src-app> application to <dest-app>}
		my SetNamedCommand services clone_services clone-services 2
	    }
	    aliases {
		my Usage {aliases} \
		    {List aliases}
		my SetCommand misc aliases
	    }
	    alias {
		my Usage {alias <alias[=]command>} \
		    {Create an alias for a command}
		switch -exact -- [set n [llength $myargs]] {
		    1 - 2 {
			my SetCommand misc alias $n
		    } default {
			my SetCommand misc alias 1
		    }
		}
	    }
	    unalias {
		my Usage {unalias <alias>} \
		    {Remove an alias}
		my SetCommand misc unalias 1
	    }
	    host {
		lappend cmds {host add    [--dry-run] <ip-address> <host>...}
		lappend cmds {host update [--dry-run] <ip-address> <host>...}
		lappend cmds {host remove [--dry-run] (<ip-address>|<host>)...}
		lappend cmds {host list}
		my Usage [join $cmds "\n\t "] {Manage the HOSTS file}

		# Switch per sub-method
		set n [llength $myargs]
		switch -exact -- [set sub [lindex $myargs 0]] {
		    add    { my SetNamedCommandMinMax misc host_add    {host add}    3 $n }
		    update { my SetNamedCommandMinMax misc host_update {host update} 3 $n }
		    remove { my SetNamedCommandMinMax misc host_remove {host remove} 2 $n }
		    list   { my SetNamedCommand       misc host_list   {host list}   1 }
		    default {
			my UsageError "Unknown host command \[$sub\]"
		    }
		}
	    }
	    help {
		if {![llength $myargs]} {
		    my DisplayHelp
		}
		set myhelponly 1

		# Next argument is the actual verb for which the help
		# was requested. Simply recurse to fill in data.
		Debug.cli {Recurse to fill help information}
		my ParseCommand
		Debug.cli {Recurse done}
	    }
	    usage {
		display [usage::Basic]
		exit 0
	    }
	    options {
		# Simulate --options
		set myargs [linsert $myargs 0 --options]
		my ParseOptions
	    }
	    default {
		if {$verb ne {}} {
		    display "[usage::me]: Unknown command \[$verb\]"
		    display [usage::Basic]
		    exit 1
		}
	    }
	}
	return
    }

    method Usage {msg {synop {}}} {
	Debug.cli {}
	set cmd [usage::me]
	if {$synop ne {}} { append synop \n }
	set    myusage "$cmd $msg\n$synop"
	append myusage "Please use '$cmd help options' to see the general "
	append myusage "options, and shorthands."
	return
    }

    method UsageError {msg} {
	Debug.cli {}
	set myusageerror $msg
	return
    }

    method SetCommandMinMax {namespace action min max} {
	my SetNamedCommandMinMax $namespace $action $action $min $max
    }

    method SetCommand {namespace action {range 0}} {
	my SetNamedCommand $namespace $action $action $range
    }

    method SetNamedCommandMinMax {namespace action label min max} {
	Debug.cli {}
	set n [llength $myargs]
	if {($min <= $n ) && ($n <= $max)} {
	    my SetNamedCommand $namespace $action $label $n
	} else {
	    my SetNamedCommand $namespace $action $label $min
	}
    }

    method SetNamedCommand {namespace action label {range 0}} {
	Debug.cli {}
	if {$myhelponly} return

	# NOTE: not handling actual ranges from the original ruby.
	# A check of the code showed that this wasn't used by callers.

	if {($range eq "*") || ($range == [llength $myargs])} {
	    set mynamespace $namespace
	    set myaction    $action
	} else {
	    set myexit_status 0

	    if {[llength $myargs] > $range} {
		my UsageError "Too many arguments for \[$label\]: '[join [lrange $myargs $range end] {', '}]'"
	    } else {
		my UsageError "Not enough arguments for \[$label\]"
	    }
	}
	return
    }

    method DisplayHelp {} {
	Debug.cli {}
	puts [usage::Command]
	exit 0
    }

    method JustOptions {} {
	Debug.cli {}
	return [struct::list map [my Options] [lambda x {
	    lindex $x 0
	}]]
    }

    method Options {} {
	Debug.cli {}
	return {
	    {-copy-unsafe-links {For push, links pointing outside are copied into the application.}}
            {-email.arg       {no default} {User name, identified by email address}}
	    {-user.arg        {no default} {Alias of --email}}
	    {-passwd.arg      {no default} {Password for the account}}
	    {-pass.arg        {no default} {Alias of --passwd}}
	    {-password.arg    {no default} {Alias of --passwd}}
	    {-app.arg         {no default} {Application name}}
	    {-name.arg        {no default} {Alias of --app}}
	    {-bind.arg        {no default} {Name of application to bind a new service to}}
	    {-instance.arg    {no default} {Id of the instance to talk to}}
	    {-instances.arg   {no default} {Number of instances to run the application with}}
	    {-url.arg         {Default derived from application name} {Primary application url to map to}}
	    {-mem.arg         {Default is framework dependent} {Memory requirement of pushed application}}
	    {-path.arg        {Default is working directory} {directory the application files to push are in}}
	    {-manifest.arg    {Default is stackato.yml/manifest.yml in --path directory} {Location of the manifest file to use}}
	    {-no-start        {If specified do not start the pushed application}}
	    {-nostart         {Alias of --no-start}}
	    {-force           {Force deletion}}
	    {-all             {Operation is for all applications, files, or logs}}
	    {t                {Activate tracing of http requests and responses. OPTIONAL argument!}}
	    {-trace           {Alias of -t}}
	    {-token-file.arg  {~/.stackato/client/tokens} {File with login tokens to use}}
	    {-timeout.arg     {No timeout} {Timeout in seconds for the 'run' command.}}
	    {-target.arg      {Configuration files} {Target server to use for this command, instead of configured default.}}
	    {-group.arg       {} {Group to use for this command, instead of default.}}
	    {-debug-group     {Internal use. Intentionally not documented}}
	    {-tail            {Activate tailing of stager operation (push, update, start, restart)}}
	    {-notail          {Deactivate tailing of stager operation (push, update, start, restart)}}
	    {-no-tail         {Alias of --notail}}
	    {q                {Alias of --quiet}}
	    {-quiet           {Quiet operation}}
	    {-nozip           {IGNORED! Do not use native external (un)zip applications}}
	    {-no-zip          {IGNORED! Alias of --nozip}}
	    {-no-resources    {Do not upload resources when pushing}}
	    {-noresources     {Alias of --no-resources}}
	    {-no-color        {Do not colorize output}}
	    {-verbose         {More verbose operation}}
	    {n                {Alias of --no-prompt}}
	    {-no-prompt       {Disable interactive queries}}
	    {-noprompt        {Alias of --no-prompt}}
	    {-non-interactive {Alias of --no-prompt}}
	    {-prefix          {Put instance information before each line of a shown logfile}}
	    {-prefix-logs     {Alias of --prefix}}
	    {-prefixlogs      {Alias of --prefix}}
	    {-json            {Print raw json as output, not human-formatted data}}
	    {-print           {Print dbshell connection command}}
	    {v                {Print client version}}
	    {-version         {Alias of -v}}
	    {h                {Print command help}}
	    {-help            {Alias of -h}}
	    {-runtime.arg     {no default} {Name of runtime to use}}
	    {-exec.arg        {Default framework specific} {Execution/start mode}}
	    {-noframework     {Application getting pushed has no framework}}
	    {-framework.arg   {Default is auto-detected} {Framework to use for the application}}
	    {f.arg            {Default is auto-detected} {Alias of --framework}}
	    {-canary          {DEPRECATED}}
	    {u.arg            {no default} {User for which we are doing the operation}}
	    {-options         {Print the help on options}}
	    {-port.arg        10000 {Port for tunneling}}
	    {-allow-http      {Required to prevent rejection of http urls}}
	    {-dry-run         {Do run launch internal command, but display it.}}
	    {-debug.arg       {no default} {Activate tracing of specific client internals}}
	    {-apps.arg        {target dependent} {Limit for number of applicatons in group}}
	    {-appuris.arg     {target dependent} {Limit for number of mapped uris per app}}
	    {-services.arg    {target dependent} {Limit for number of services in group}}
	    {-sudo.arg        {target dependent} {Applications can use sudo}}
	    {-stackato-debug.arg {no defaults} {Host:Port for debugging the user app}}
	    {-reset           {Reset current group}}
	}
    }

    method options {} {
	Debug.cli {}
	return [array get myoptions]
    }

    # # ## ### ##### ######## #############
    ## State

    variable \
	myargs \
	myoptions \
	myexitstatus \
	mynamespace \
	myaction \
	myusage \
	myusageerror \
	myhelponly

    export ParseOptions

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
## Ready. Vendor (VMC) version tracked: 0.3.14.

package provide stackato::client::cli 1.4.4
