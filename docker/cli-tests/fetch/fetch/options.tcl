# -*- tcl -*- Copyright (c) 2012 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## Option handling

# # ## ### ##### ######## ############# #####################
## Export (internals - recipe definitions, other utilities)

namespace eval ::kettle::option {
    namespace export {[a-z]*}
    namespace ensemble create

    namespace import ::kettle::path
    namespace import ::kettle::io
    namespace import ::kettle::status
    namespace import ::kettle::ovalidate
    namespace import ::kettle::strutil
}

# # ## ### ##### ######## ############# #####################
## State

namespace eval ::kettle::option {
    # Dictionaries for option configuration and definition.
    # The first maps option names to values, the other to the
    # definition, including state information about values.
    variable config {}
    variable def    {}

    # Dictionary containing the names of the options (as keys) which
    # will be used in keys into the work database maintained by the
    # 'status' command.
    variable work {}

    # Type of change getting propagated. List to handle nested propagations.
    variable change {}
}

# # ## ### ##### ######## ############# #####################
## API

proc ::kettle::option::define {o description {default {}} {type string}} {
    variable config
    variable def
    variable work

    io trace {DEF'option $o}

    if {[dict exists $config $o]} {
	return -code error "Illegal redefinition of option $o."
    }

    # Validate the default before accepting the definition.
    ovalidate {*}$type check $default

    # Construct the help text. Takes into account both type
    # information and chosen default value.

    ::set desc [strutil reflow $description]
    if {($default ne {}) &&
	![string match {*Default is*} $desc]} {
	append desc \n[strutil reflow [subst {
	    Default is '$default'.
	}]]
    }

    dict set config $o $default     ; # Initial value is default.
    dict set work   $o .            ; # Use as key for work database
    dict set def    $o help   $desc ; # Help text
    dict set def    $o type   $type ; # Validation command.
    dict set def    $o user   0     ; # Flag, this option has been set
    dict set def    $o setter {}    ; # by the user. Plus code to
				      # validate and propagate changes.
    return
}

proc ::kettle::option::onchange {o arguments script args} {
    variable def
    lappend arguments option old new
    dict update def $o o {
	dict lappend o setter \
	    [lambda@ ::kettle::option $arguments $script {*}$args]
    }
    return
}

proc ::kettle::option::no-work-key {o} {
    variable work
    dict unset work $o
    return
}

proc ::kettle::option::exists {o} {
    variable config
    return [dict exists $config $o]
}

proc ::kettle::option::names {{pattern --*}} {
    variable config
    return [dict keys $config $pattern]
}

proc ::kettle::option::help {} {
    global argv0
    variable def
    append prefix $argv0 " "

    foreach option [lsort -dict [names]] {
	::set type [ovalidate {*}[dict get $def $option type] help]
	::set help [dict get $def $option help]

	io puts ""
	io note { io puts "$prefix${option} <$type>" }
	io puts $help
    }
    io puts ""
    return
}

# set value, user choice
proc ::kettle::option::set {o value} {
    variable config
    variable def

    io trace {OPTION SET ($o) = "$value"}

    if {[dict exists $def $o type]} {
	ovalidate {*}[dict get $def $o type] check $value
    }

    if {[dict exists $config $o]} {
	::set has 1
	::set old [dict get $config $o]
    } else {
	::set has 0
	::set old {}
    }  

    dict set config $o $value
    dict set def    $o user 1

    # Propagate choice, if possible
    reportchange user $o $old $value
    return
}

# set value, system choice, new default. ignored if a user has chosen
# a value for the option.
proc ::kettle::option::set-default {o value} {
    variable config
    variable def
    variable change

    if {[lindex $change end] eq "user"} {
	set $o $value
	return
    }

    if {![dict exists $def $o]} {
	return -code error "Unable to set default of undefined option $o."
    }

    io trace {OPTION SET-D ($o) =[dict get $def $o user]= "$value"}

    if {[dict exists $def $o type]} {
	ovalidate {*}[dict get $def $o type] check $value
    }

    if {[dict get $def $o user]} return

    ::set old [dict get $config $o]
    dict set config $o $value
    # Propagate new default.
    reportchange default $o $old $value
    return
}

# set value, override anything, no propagation
proc ::kettle::option::set! {o v} {
    variable config
    #io trace {  SET! $o $v}
    dict set config $o $v
    return
}

proc ::kettle::option::unset {o} {
    variable config
    dict unset config $o
    return
}

proc ::kettle::option::get {o} {
    variable config

    if {![dict exists $config $o]} {
	return -code error "Unable to retrieve unknown option $o."
    }

    return [dict get $config $o]
}

proc ::kettle::option::known {o} {
    variable def
    return [dict exists $def $o]
}

proc ::kettle::option::type {o} {
    variable def

    if {![dict exists $def $o]} {
	return -code error "Unable to retrieve type of unknown option $o."
    }

    return [dict get $def $o type]
}

proc ::kettle::option::userdefined {o} {
    variable def

    if {![dict exists $def $o]} {
	return -code error "Unable to retrieve user-status of unknown option $o."
    }

    return [dict get $def $o user]
}

proc ::kettle::option::reportchange {type o old new} {
    variable def
    if {![dict exists $def $o setter]} return
    ::set setter [dict get $def $o setter]
    if {![llength $setter]} return
    variable change
    lappend  change $type

    foreach s $setter {
	{*}$s $o $old $new
    }

    ::set change [lreplace $change end end]
    return
}

proc ::kettle::option::save {} {
    variable config

    ::set path   [path tmpfile config_]
    ::set serial [dict filter $config key --*]

    dict unset serial --state
    dict unset serial --config

    path write $path $serial
    io trace {options saved to    $path}

    path ensure-cleanup $path
    return $path
}

proc ::kettle::option::load {file} {
    io trace {options loaded from $file}
    variable config

    # Note: See how this bypasses all the setters. The configuration
    # is loaded as is. With setters active the state may change
    # from what we loaded, depending on order of options. Bad.
    ::set config [dict merge $config [path cat $file]]

    # Special handling of --verbose, i.e. activate, as if the setter
    # had been run.
    if {[get --verbose]} { io trace-on }
    return
}

proc ::kettle::option::config {args} {
    variable config
    variable def
    variable work

    # Apply the overrides. We use the regular set command to invoke
    # all relevant setter hooks. Afterward we retrieve the modified
    # configuration (*) and restore the old state.
    #
    # (Ad *) Well, actually just the part needed to key the work
    #        database.

    ::set sconfig $config
    ::set sdef    $def
    foreach {o v} $args { set $o $v }
    ::set serial [dict filter $config script {o v} { dict exists $work $o }]
    ::set sdef   $def
    ::set config $sconfig

    # Now we have the modified configuration a child process will
    # compute for itself given the --config and overrides as options
    # as key part for the work database.

    return [DictSort $serial]
}

proc ::kettle::option::DictSort {dict} {
    array set a $dict
    ::set out [list]
    foreach key [lsort -dict [array names a]] {
	lappend out $key $a($key)
    }
    return $out
}

# # ## ### ##### ######## ############# #####################
## Initialization

apply {{} {
    global tcl_platform

    # - -- --- ----- -------- -------------
    define --exec-prefix {
	Path to the root directory for the installation of binaries.
	Default is $(--prefix).
    } {} directory
    onchange --exec-prefix {} {
	# Implied arguments: option old new
	::set new [path norm $new]
	set!        --exec-prefix $new
	set-default --bin-dir     $new/bin
	set-default --lib-dir     $new/lib
    }

    # - -- --- ----- -------- -------------
    define --bin-dir {
	Path to binary applications.
	Default is the directory of the tclsh running kettle.
	Default is $(--exec-prefix)/bin should --exec-prefix get
	defined by the user.
    } {} directory
    onchange --bin-dir {} { set! --bin-dir [path norm $new] }

    # - -- --- ----- -------- -------------
    define --lib-dir {
	Path to binary libraries.
	Default is [info library] of the tclsh running kettle.
	Default is $(--exec-prefix)/lib should --exec-prefix get
	defined by the user.
    } {} directory
    onchange --lib-dir {} { set! --lib-dir [path norm $new] }

    # - -- --- ----- -------- -------------
    define --prefix {
	Path to the root directory for the installation of any files.
	Default is the twice parent directory of [info library] of the
	tclsh running kettle.
    } {} directory
    onchange --prefix {} {
	# Implied arguments: option old new
	::set new [path norm $new]
	set!        --prefix      $new
	set-default --exec-prefix $new
	set-default --man-dir     $new/man
	set-default --html-dir    $new/html
	set-default --include-dir $new/include
    }

    # - -- --- ----- -------- -------------
    define --man-dir {
	Path to the root directory to install manpages into.
	Default is $(--prefix)/man.
    } {} directory
    onchange --man-dir     {} { set! --man-dir [path norm $new] }

    # - -- --- ----- -------- -------------
    define --html-dir {
	Path to the root directory to install HTML documentation into.
	Default is $(--prefix)/html.
    } {} directory
    onchange --html-dir    {} { set! --html-dir [path norm $new] }

    # - -- --- ----- -------- -------------
    define --include-dir {
	Path to the root directory to install C header files into.
	Default is $(--prefix)/include.
    } {} directory
    onchange --include-dir {} { set! --include-dir [path norm $new] }

    # - -- --- ----- -------- -------------
    set-default --prefix [file dirname [file dirname [info library]]]
    # -> man, html, exec-prefix -> bin, lib
    set-default --bin-dir [file dirname [path norm [info nameofexecutable]]]
    set-default --lib-dir [info library]

    # - -- --- ----- -------- -------------
    define --ignore-glob {
	Tcl list of glob patterns for files to ignore in directory scans.
	Default is a list of patterns matching the special directories
	and files of a matter of source code control systems and
	editor backup files.
    } {
	*~ _FOSSIL_ .fslckout .fos .git .svn CVS .hg RCS SCCS
	*.bak *.bzr *.cdv *.pc _MTN _build _darcs _sgbak blib
	autom4te.cache cover_db ~.dep ~.dot ~.nib ~.plst
    } listsimple
    no-work-key --ignore-glob

    # - -- --- ----- -------- -------------
    # File action. Default on (== dry-run off).

    define --dry {
	Disable file operations during recipe execution, leaving the
	filesystem untouched.
    } off boolean
    no-work-key --dry

    # - -- --- ----- -------- -------------
    # Tracing of internals. Default off.

    define --verbose {
	Activate tracing of kettle's internal operations.
    } off boolean
    no-work-key --verbose
    onchange    --verbose {} {
	if {$new} { io trace-on }
    }

    # - -- --- ----- -------- -------------

    # Disable printing of things for human benefit and interfering
    # with machine communication. Default off.

    define --machine {
	Disable human specific output.
    } off boolean
    no-work-key --machine
    onchange    --machine {} {
	if {$new} { set-default --color off }
    }

    # - -- --- ----- -------- -------------
    # Output colorization. Default platform dependent.

    define --color {
	Colorize the text written to the terminal during execution.
	Default is platform-dependent.
	* Windows: Off
	* Unix && Terminal:     On
	* Unix && not Terminal: Off
    } off boolean
    no-work-key --color
    if {$tcl_platform(platform) eq "windows"} {
	set-default --color off
    } else {
	if {[catch {
	    package require Tclx
	}] || ![fstat stdout tty]} {
	    set-default --color off
	} else {
	    set-default --color on
	}
    }

    # - -- --- ----- -------- -------------
    # State and configuration handling for sub-processes. Default none.

    define --state {
	Path to a file containing shared work state.
	Used for communication between kettle parent and child
	processes.
    } {} readable.file
    no-work-key --state
    onchange    --state {} { status load $new }

    define --config {
	Path to a file overriding the option configuration in full.
	Used for communication between kettle parent and child
	processes.
    } {} readable.file
    no-work-key --config
    onchange    --config {} { load $new }

    # - -- --- ----- -------- -------------
    # Path of the shell to use for Tcl sub-processes, like the
    # execution of testsuites, and benchmarks. Irrelevant to work
    # database keying.

    define --with-shell {
	Path of the shell to run tests, benchmarks, or similar
	Tcl-based sub-processes with.
	Defaults to the tclsh running the kettle build code.
    } [path norm [info nameofexecutable]] readable.file

    no-work-key --with-shell
    onchange    --with-shell {} {
	set! --with-shell [path norm $new]
    }

    # - -- --- ----- -------- -------------
    # Default goals to use when invoked with none.
    # Platform dependent.

    if {$tcl_platform(platform) eq "windows"} {
	set @goals gui
    } else {
	set @goals help
    }

    # - -- --- ----- -------- -------------
} ::kettle::option}

# # ## ### ##### ######## ############# #####################
return
