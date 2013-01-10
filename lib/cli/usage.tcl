# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5 ; # I want try/catch/finally
package require textutil::adjust
package require stackato::log
package require stackato::color

namespace eval ::stackato::client::cli::usage {
    namespace import ::stackato::log::*
    namespace import ::stackato::color
}

debug level  cli/usage
debug prefix cli/usage {[::debug::snit::call] | }

# # ## ### ##### ######## ############# #####################

proc ::stackato::client::cli::usage::me {} {
    variable me
    if {[info exists me]} { return $me }
    variable wrapped
    if {$wrapped} {
	set base [info nameofexecutable]
    } else {
	global argv0
	set base $argv0
    }

    set me [file tail $base]
    return $me
}

proc ::stackato::client::cli::usage::Display {} {
    Debug.cli/usage {}
    upvar 1 myusage usage myusageerror usageerror

    if {$usage ne {}} {
	if {$usageerror ne {}} {
	    say [wrapl $usageerror]
	}
	say [wrapl "Usage: $usage"]
	return
    }
    say [Command]
    return
}

proc ::stackato::client::cli::usage::Basic {} {
    variable basic
    Debug.cli/usage {}
    return  [wrapl $basic]
}

proc ::stackato::client::cli::usage::Command {} {
    variable basic
    variable command
    Debug.cli/usage {}
    return \n[Basic]\n\n[wrapl [SectionBold $command]]
}

proc ::stackato::client::cli::usage::SectionBold {text} {
    set lines {}
    foreach l [split $text \n] {
	if {[regexp {^  [^ ]} $l]} {
	    set l "  [color bold [string range $l 2 end]]"
	}
	lappend lines $l
    }
    return [join $lines \n]
}

proc ::stackato::client::cli::usage::Format {text} {
    set text [string trimright $text "\n\r\t "]
    set text [string trimleft  $text "\n\r"]
    set text [textutil::adjust::undent $text]
    return [string map [list @ [me]] $text]
}

namespace eval ::stackato::client::cli::usage {
    namespace export Basic Display Command me
    namespace ensemble create

    variable wrapped [expr {[lindex [file system [info script]] 0] ne "native"}]

    variable basic [Format {
	Usage: @ [options] command [<args>] [command_options]
	Try '@ help [command]' or '@ help options' for more information.
    }]

    variable command [Format {
	Currently available @ commands are:

	  Getting Started
	    target [url] [--allow-http]
		Report the current target or set a new target

	    login  [email] [--email, --passwd]
		Log into the current target.

	    login  [email] [--email, --passwd] --group GROUP
		Log into the current target, and persistently set the current group.
		(All the applicaton and services commands use the option for current
		 group also, but only for that one operation, i.e. transient).

	    info
		System and account information

	    usage [--all] [user|group]
		Shows the current memory allocation and usage of the active or
		specified user/group.

	  Applications
	    apps
		List deployed applications

	  Application Creation
	    push [appname]
		Create, push, map, and start a new application

	    push [appname] --path
		Push application from specified path

	    push [appname] --url
		Set the url for the application

	    push [appname] --instances <N>
		Set the expected number <N> of instances

	    push [appname] --mem M
		Set the memory reservation for the application

	    push [appname] --runtime RUNTIME
		Set the runtime to use for the application

	    push [appname] --framework FRAMEWORK
		Set the framework to use for the application

	    push [appname] --no-start
		Do not auto-start the application

	    push --no-prompt
		No input. Take settings from stackato.yml

	    push [appname] --copy-unsafe-links
		Copy links to outside of the application
		into it, instead of rejecting them with
		an error.

	  Application Operations
	    start [appname]
		Start the application

	    stop  [appname]
		Stop the application

	    restart [appname]
		Restart the application

	    delete [appname...]
		Delete the named applications

	  Application Updates
	    update [appname] [--path]
		Update the application bits

	    mem [appname] [memsize]
		Update the memory reservation for an application

	    map [appname] <url>
		Register the application to the url

	    unmap [appname] <url>
		Unregister the application from the url

	    instances [appname] <num|delta>
		Scale the application instances up or down

	  Application Information
	    crashes [appname]
		List recent application crashes

	    crashlogs [appname] [options...]
	    logs      [appname] [options...]
		Display log information for the application

	    (crash)logs --follow
		Tail the stream of log entries...

	    (crash)logs --num N
		Show the last N log entries. Default: 100.
		N == 0 ==> Show the whole log.

	    (crash)logs --source S
		Show only log entries coming from source S (glob pattern).

	    (crash)logs --instance N
		Show only log entries coming from instance N.

	    (crash)logs --filename F
		Show only log entries coming from file F (glob pattern).

	    (crash)logs --text T
		Show only log entries matching the glob pattern T.

	    drain add [appname] <drain> <uri>
		Add a named log drain to the application.
		<uri> specifies the log destination.

	    drain delete [appname] <drain>
		Delete the named log drain from the application.

	    drain list [appname]
		List all log drains defined for the application.

	    files [appname] [path] [--all]
		Display directory listing or file download for [path]

	    run [--instance N] [appname] <cmd>...
		Run an arbitrary command on a running instance

	    ssh [--instance N] [appname] [cmd...]
		 Run interactive ssh to a running instance

	    ssh api [command...]
		Opens an ``ssh`` session to the Stackato VM (Cloud Controller)
		as the 'stackato' system user. Available to Admin users only.
		Prompts for the 'stackato' user password.

	    scp [--instance N] [appname] [:]source... [:]destination
		Copy files and directories to and from application containers.
		The colon ":" character preceding a specified source or
		destination indicates a remote file or path. Sources and
		destinations can be file names, directory names, or full paths.

	    stats [appname]
		Display resource usage for the application

	    instances [appname]
		List application instances

	    open [appname]
		Open primary application url in a browser

	    open <url>
		Open any url in a browser

	    open api
		Open target web console in a browser

	  Application Environment
	    env [appname]
		List application environment variables

	    env-add [appname] <variable[=]value>
		Add an environment variable to an application

	    env-del [appname] <variable>
		Delete an environment variable to an application

	  Services
	    services
		Lists of services available and provisioned

	    create-service <service> [--name,--bind]
		Create a provisioned service

	    create-service <service> <name>
		Create a provisioned service and assign it <name>

	    create-service <service> <name> <app>
		Create a provisioned service and assign it <name>, and bind to <app>

	    delete-service [--all] [servicename...]
		Delete provisioned services

	    bind-service <servicename> [appname]
		Bind a service to an application

	    unbind-service <servicename> [appname]
		Unbind service from the application

	    clone-services <src-app> <dest-app>
		Clone service bindings from <src-app> application to <dest-app>

	    dbshell [appname] [servicename]
		Invoke interactive db shell for a bound service.

	    tunnel [servicename] [--port port] [--allow-http]
		Create a local tunnel to a service.

	    tunnel [servicename] [clientcmd] [--allow-http]
		As above, and start a local client.

	  Administration
	    user
		Display user account information

	    passwd
		Change the password for the current user

	    logout
		Logs current user out of the current target system

	    logout target
		Logs current user out of the specified target system

	    logout --all
		Logs current user out of all known targets

	    add-user [--email, --passwd]
		Register a new user (requires admin privileges)

	    delete-user <user>
		Delete a user and all apps and services (requires admin privileges)

	    users
		List all users and associated applications.

	    admin report [destinationfile]
		Retrieve compressed tarball of server logs for diagnosis.
		Default output file is stackato-report.tgz in the current
		working directory.

	    admin patch patchfile|name|url
		Upload and execute patchfile (via ssh) to modify the server.
		Will ask for the stackato password.

	  System
	    runtimes
		Display the supported runtimes of the target system

	    frameworks
		Display the recognized frameworks of the target system

	  Misc
	    aliases
		List aliases

	    alias <alias[=]command>
		Create an alias for a command

	    unalias <alias>
		Remove an alias

	    targets
		List known targets and associated authorization tokens

	    group
		Show the current group. May be none.

	    group <name>
		Make the named group the current group to use.

	    group --reset
		Unset the current group.

	    groups create <groupname>
		Create a new named group

	    groups delete <groupname>
		Remove the named group

	    groups
		List the known groups, and the users belonging to them

	    groups add-user <groupname> <username>
		Add the specified user to the named group

	    groups delete-user <groupname> <username>
		Remove the specified user from the named group

	    groups users [groupname]
		List users belonging to the named group
		Without group, list for the current group

	    limits [groupname|username] [--mem MEM] [--apps N] [--appuris N] [--services N] [--sudo BOOL]
		Set or retrieve limits for a group or user.
		Without group/user use current group.
		Without current group use current user.

	    host add    [--dry-run] <ip-address> <host>...
	    host update [--dry-run] <ip-address> <host>...
	    host remove [--dry-run] (<ip-address>|<host>)...
	    host list
		Manipulate the hosts file. Add mappings,
		replace, remove, and show them.

	  Help
	    help [command]
		Get general help or help on a specific command

	    help options
		Get help on available options
    }]
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::client::cli::usage 0
