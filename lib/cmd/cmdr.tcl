# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require cmdr 1 ;# defered/immediate + section (help category setup) + *in-shell* marker + no-promotion.
package require cmdr::help
package require cmdr::history
package require lambda
package require try
package require cmdr::tty
package require cmdr::color
package require cmdr::parameter 1.4   ;# disallow, touch, multiple when-set
package require cmdr::private   1.3.1 ;# *config* - active config instance.
package require stackato::log
package require stackato::mgr::alias
package require stackato::mgr::exit
package require stackato::mgr::self
package require stackato::mgr::cfile

debug level  cmdr
debug prefix cmdr {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Global configuration package. This can fail when our current
## working directory was pulled out from under us.

try {
    package require stackato::mgr::cfile

} trap {POSIX ENOENT} {e o} {
    if {[string match {*error getting working directory name*} $e]} {
        stackato::log to stdout
	stackato::log say [cmdr color error {Unable to run client from a deleted directory}]
	::exit 1
    }
    return {*}$o $e
} finally {
    stackato::log to stdout
}

# # ## ### ##### ######## ############# #####################
# Handle ^C and other signals.
stackato::mgr exit trap-term

# Handle signal trap diverted into bgerror path.
proc bgerror {msg} {
    global errorCode errorInfo

    if {$errorCode eq "SIGTERM"} {
	::stackato::log::say! "\n$msg (BG)\n"
	::exec::clear
	exit 1
    }

    # Regular bgerror output. And make clear where we are.
    set prefix {Background error: }
    ::stackato::log::say! $prefix$msg
    ::stackato::log::say! $prefix[join [split $errorInfo \n] \n$prefix]
    exit 1
}

# # ## ### ##### ######## ############# #####################
## Command declarations and dispatch.

#cmdr::config interactive 1
cmdr history initial-limit 20
cmdr history save-to       [stackato::mgr cfile get history]

cmdr create stackato-cli [::stackato::mgr::self::me] {
    description {
	The command line client
    }

    shandler ::cmdr::history::attach

    # # ## ### ##### ######## ############# #####################
    ## The error handler interposing around command line parsing and
    ## execution. Converts various problems into simple error messages
    ## instead of considering them as internal errors.

    ehandler ::stackato::mgr::exit::attempt

    # # ## ### ##### ######## ############# #####################
    ## Global options and state shared with all commands.

    option colormode {
	Set color mode (always|auto|never) of the client.
	Default is auto, which activates color when in a proper terminal.
    } {
	argument mode
	label color
	validate  [call@vtype colormode]
	# React early to user settings.
	when-set [lambda {p x} {
	    switch -exact -- $x {
		auto   {
		    # Nothing to do, system default, already in place.
		}
		always { cmdr color activate 1 }
		never  { cmdr color activate 0 }
	    }
	}]
    }

    option version {
	Print the version number of the client, and stop.
    } {
	alias v ; alias V ; presence
	when-set [lambda {p x} {
	    [$p config context root] do version
	    stackato::mgr::exit quit
	}]
    }

    option help {
	Show the help of the client (main or current command), and stop.
    } {
	alias h ; alias ? ; presence
	when-set [lambda {p x} {
	    set root [$p config context root]
	    if {[$root exists *prefix*]} {
		$root do help {*}[$root get *prefix*]
	    } else {
		$root do help
	    }
	    stackato::mgr::exit quit
	}]
    }

    state motd {
	Check version of the client for being a devbuild and note
	that in a warning message. Exception is under @json existing
	and set.
    } {
	immediate
	generate [lambda p {
	    ::stackato-cli set (cc) [$p config]

	    # Block multiple calls from within the process
	    # (=> recursion through cmdr (f.e: aliases))
	    # Using an app-specific "common" block "(motd)" as signal.
	    if {[::stackato-cli exists (motd)]} return
	    ::stackato-cli set (motd) {}

	    # Block message when command explicitly denies it.
	    if {[$p config has @nomotd]} return
	    # Block message to prevent interference with --json output
	    if {[$p config has @json] && [$p config @json]} return

	    # Block message for released builds (not alpha, nor beta)
	    set v [package present stackato::cmdr]
	    if {![string match {*[ab]*} $v]} return
	    puts "*** DEV BUILD VERSION $v, FOR TESTING ONLY ***"
	}]
    }

    # Note: As a global option debug levels can be set before all other parameters.
    option debug {
	Activate client internal tracing.
    } {
	argument tag
	undocumented
	list
	validate [call@vtype debug]
	when-complete [lambda {p tags} {
	    foreach t $tags { debug on $t }
	}]
    }

    option no-prompt {
	Disable interactive queries.
    } {
	presence
	alias n
	alias non-interactive
	alias noprompt
	# Note: Global disabling of all interactivity. Use first
	# to affect all other input. Also the reason for when-set
	# instead of when-complete. Must be handled early to cut off
	# interactive entry in cmdr::private, where possible.
	when-set [lambda {p x} {
	    cmdr interactive [expr {!$x}]
	}]
    }

    option show-stacktrace {
	Show stack traces of internal errors on stdout.
    } {
	undocumented
	presence
	when-set [call@mgr exit dump-stderr]
    }

    option debug-http-log {
	Activate tracing inside of the http package itself.
    } {
	undocumented
	presence
	when-set [lambda {p x} {
	    package require s-http
	    global shpre
	    set    shpre [http::Now]
	    proc ::http::Log {args} {
		global shpre
		set n [Now]
		set d [expr {$n - $shpre}]
		set prefix "[cmdr color trace HTTP:] [format %10d $d] [format %15d $n] "
		set text $prefix[join [split [join $args] \n] "\n$prefix"]
		puts $text
		set shpre [Now]
	    }
	}]
    }

    option debug-http-data {
	Activate tracing of wire data inside of the http package itself.
    } {
	undocumented
	presence
	when-set [lambda {p x} {
	    package require s-http
	    global shpre shdsep
	    set    shpre [http::Now]
	    set shdsep "---- | [string repeat --- 16] |[string repeat - 16]|"
	    proc ::http::LogData {args} {
		global shpre shdsep
		set n [Now]
		set d [expr {$n - $shpre}]
		set prefix "[cmdr color trace HTTP:] [format %10d $d] [format %15d $n] "
		puts "$prefix$shdsep"
		puts -nonewline [Hexl $prefix [join $args]]
		puts "$prefix$shdsep"
		set shpre [Now]
	    }
	}]
    }

    option debug-http-token {
	Track all state changes of http token arrays
    } {
	undocumented
	presence
	when-set [lambda {p x} {
	    package require s-http
	    proc ::http::LogToken {token} {
		set local [string map {:: _} $token]
		upvar #0 $token $local
		set text [Parray $local]
		set prefix "[cmdr color trace HTTP:] "
		set text $prefix[join [split $text \n] "\n$prefix"]
		puts $text

		trace add variable $token {write unset} [lambda {var local index op} {
		    upvar 1 $local here
		    if {$index ni {{} body meta}} {
			set v $here($index)
		    } else {
			set v {}
		    }
		    puts "[cmdr color trace "TOK: "] $var $op ($index) @ ($v)"
		    if {($index eq "state") && ($op eq "unset")} {
			::error STATE-UNSET
		    }
		} $token]
	    }
	}]
    }

    # # ## ### ##### ######## ############# #####################
    ## Still global options, security-related

    option cafile {
	Path to a file containing the CA certificates to use for validation.
    } {
	validate rfile
	when-set      [lambda {p path} { REST::cafile $path }]
	when-complete [lambda {p path} { REST::cafile $path }]
	generate      [lambda p {
	    package require stackato::mgr::self
	    return [file join [stackato::mgr::self topdir] config ca-certificates.pem]
	}]
    }

    option skip-ssl-validation {
	Disable SSL certificate validation warnings.
    } {
	validate boolean
	when-set      [lambda {p x} { if {$x} REST::tlsskipverify }]
	when-complete [lambda {p x} { if {$x} REST::tlsskipverify }]
	generate      [lambda p {
	    global env

	    # p = inherited, global parameter
	    # The 'p config' is the definition config, containing only the other globals.
	    # To access the parameters of the active private we have to get the active context.
	    # This information is present starting with cmdr::private 1.3.1

	    set active [[$p config context root] get *config*]

	    # Force skip when manifest reporting is suppressed for the
	    # whole command.
	    if {[$active has @manifest/quiet]} {
		return yes
	    }

	    # 0. Use option (not coming here if it is (un)set explicitly).
	    # 1. Check the environment - STACKATO_SKIP_SSL_VALIDATION.
	    # 2. Check the config of the current target (sticky setting)
	    #    See cmd/target.tcl, 'Set' (Ok/Save branch) for where
	    #    the information was set (target command).
	    # 3. Hardwired last line - No skip.

	    if {[info exists env(STACKATO_SKIP_SSL_VALIDATION)] &&
		[string is boolean -strict $env(STACKATO_SKIP_SSL_VALIDATION)]
	    } {
		return $env(STACKATO_SKIP_SSL_VALIDATION)
	    }

	    package require stackato::mgr::ctarget
	    package require stackato::mgr::tadjunct

	    set target [stackato::mgr::ctarget get]
	    set skip   [stackato::mgr::tadjunct get' $target \
			    skip-ssl-validation {}]
	    if {[string is boolean -strict $skip]} {
		return $skip
	    }

	    return no
	}]
    }

    option debug-tls-handshake {
	Activate tracing of the TLS handshake
    } {
	undocumented
	presence
	when-set [lambda {p x} { REST::tlsdebug }]
    }

    # # ## ### ##### ######## ############# #####################

    common .nomotd {
	state nomotd {
	    This parameter is a pure marker whose presence in a command's
	    configuration will prevent the generation of the MotD message.
	    This is used by internal commands which should not show MotD,
	    or where MotD may interfere with operation.
	} { default 0 }
    }

    # DEV AID - Insert 'use .show-parameters' at the end of the
    # specification for a private P to see the full set of parameters
    # (and their state) of P, when using P. This aborts P before it
    # reaches the execution stage.
    common .show-parameters {
	state show-parameters {
	} {
	    immediate
	    generate [lambda {p} {
		$p set {} ;# prevent infinite recursive entry through itself when display below asks for its value.
		puts [$p config dump]
		::exit
	    }]
	}
    }

    # # ## ### ##### ######## ############# #####################
    ## Bespoke category ordering for help
    ## Values are priorities. Final order is by decreasing priority.
    ## I.e. Highest priority is printed first, at the top, beginning.

    common *category-order* {
	{Getting Started} 100
	Services          -50
	Routes           -600
	Domains          -700
	Administration   -800
	Convenience      -900
    }

    # # ## ### ##### ######## ############# #####################
    ## Common --json interpretation as request for machine-readable output.

    common .json {
	option json {
	    Print raw json as output, not human-formatted data.
	} {
	    presence
	    # Prevent manifest from printing messages destroying the
	    # json-ness of the requested output.
	    when-set [call@mgr manifest quiet]
	    when-set [touch @skip-ssl-validation yes]
	}
    }

    common .recursive {
	option recursive {
	    Remove all sub-ordinate parts, and relations.
	} {
	    alias r
	    presence
	}
    }

    common .mquiet {
	state manifest/quiet {
	    Include this state variable to quiet manifest location reporting early on.
	} {
	    immediate
	    # Prevent manifest from printing messages destroying the
	    # json-ness of the requested output.
	    when-complete [call@mgr manifest quiet]
	    when-complete [touch @skip-ssl-validation yes]
	}
    }

    # # ## ### ##### ######## ############# #####################
    ## Common options for groups of commands.

    common .dry {
	option dry {
	    Print the low-level ssh command to stdout
	    instead of executing it.
	} { presence ; alias dry-run }
    }

    common .verbose {
	option verbose { More verbose operation. } { presence }
    }

    common .v2 {
	state checkv2 {
	    Invisible state argument checking that the chosen target
	    supports CF API v2. Use in commands which are v2 only.
	    Note: Requires proper client arguments coming before it.
	} { immediate ; generate [call@mgr client isv2cmd] }
    }
    common .v1 {
	state checkv1 {
	    Invisible state argument checking that the chosen target
	    supports CF API v1. Use in commands which are v1 only.
	    Note: Requires proper client arguments coming before it.
	} { immediate ; generate [call@mgr client notv2cmd] }
    }
    common .hasdrains {
	state checkdrains {
	    Invisible state argument checking that the chosen target
	    supports the Stackato drain API.
	    Note: Requires proper client arguments coming before it.
	} { immediate ; generate [call@mgr client hasdrains] }
    }
    common .isstackato {
	state checkstackato {
	    Invisible state argument checking that the chosen target
	    is a stackato target.
	    Note: Requires proper client arguments coming before it.
	} { immediate ; generate [call@mgr client is-stackato] }
    }
    common .pre31 {
	state checkpre31 {
	    Invisible state argument checking that the chosen target
	    is before version 3.1
	    Note: Requires proper client arguments coming before it.
	} { immediate ; generate [call@mgr client max-version 3.0] }
    }
    # The post checks are for release points.
    common .post30 {
	# Release 3.0 (Holophonor) was followed by 3.1dev/3.2 (Iggy)
	state checkpost30 {
	    Invisible state argument checking that the chosen target
	    is after version 3.0
	    Note: Requires proper client arguments coming before it.
	} { immediate ; generate [call@mgr client min-version 3.1] }
    }
    common .post32 {
	# Release 3.2 (Iggy) was followed by 3.3dev/3.4 (JukeBox)
	state checkpost32 {
	    Invisible state argument checking that the chosen target
	    is after version 3.2
	    Note: Requires proper client arguments coming before it.
	} { immediate ; generate [call@mgr client min-version 3.3] }
    }
    common .post34 {
	# Release 3.4/3.4.1 (both Jukebox) was followed by 3.4.2 (Kraftwerk)
	state checkpost34 {
	    Invisible state argument checking that the chosen target
	    is after version 3.4/3.4.1
	    Note: Requires proper client arguments coming before it.
	} { immediate ; generate [call@mgr client min-version 3.4.2] }
    }
    common .post342 {
	# Release 3.4.2 (Kraftwerk) was followed by 3.6 (Lennon)
	state checkpost34 {
	    Invisible state argument checking that the chosen target
	    is after version 3.4.2
	    Note: Requires proper client arguments coming before it.
	} { immediate ; generate [call@mgr client min-version 3.5] }
    }

    # # ## ### ##### ######## ############# #####################
    ## Common options to specify various things transiently for
    ## the current command, instead of using the standard settings
    ## from the config files.

    common .token-file {
	option token-file {
	    Path to an existing and readable file containing
	    the targets and authorization tokens.
	} {
	    argument path
	    validate      [call@vtype path    rwfile]
	    generate      [call@mgr   cfile   getc token]
	    when-complete [call@mgr   targets set-path]
	    when-set      [call@mgr   targets set-path]
	}
    }

    common .target {
	option target {
	    The once-off target to use for the current operation.
	} {
	    argument target-url
	    validate      [call@vtype target]
	    generate      [call@mgr ctarget getc]
	    when-complete [call@mgr ctarget setc]
	    when-set      [call@mgr ctarget setc]

	    # Priority order (first to last taken):
	    # (1) --target
	    # (2) $STACKATO_TARGET
	    # (3) $HOME/.stackato/client/target
	    # See also mgr/ctarget.tcl: get, Load
	}
    }

    common .group {
	# (L) Note: generate callbacks depends on --target, --token-file
	# CF v1 API only. ====================================
	option group {
	    The once-off group to use for the current operation.
	    This is a Stackato 2 option.
	} {
	    argument name
	    generate [call@mgr cgroup getc]
	    when-set [call@mgr cgroup setc]
	    # NOTE: when-set to be early, before target, token, etc, generating the client.
	    # Priority order (first to last taken):
	    # (1) --group
	    # (2) $STACKATO_GROUP
	    # (3) $HOME/.stackato/client/group
	    # See also mgr/cgroup.tcl: get, Load
	}
	use .groupv2
    }
    common .groupv2 {
	# CF v2 API only. ====================================
	option organization {
	    The once-off organization to use for the current operation.
	    This is a Stackato 3 option.
	} {
	    argument name
	    # int.rep = v2org entity
	    alias o
	    validate      [call@vtype orgname]
	    generate      [call@mgr corg getc]
	    when-complete [call@mgr corg setc]
	    # Priority order (first to last taken):
	    # (1) --organization, -o
	    # (2) $STACKATO_ORG
	    # (3) $HOME/.stackato/client/token2
	    # See also mgr/corg.tcl
	}
	option space {
	    The once-off space to use for the current operation, specified
	    by name. This is a Stackato 3 option.
	    Cannot be used together with --space-guid.
	} {
	    argument name
	    when-set      [disallow @space-guid]
	    validate      [call@vtype spacename]
	    generate      [call@mgr cspace getc]
	    when-complete [call@mgr cspace setc]
	    # Priority order (first to last taken):
	    # (1) --group
	    # (2a) $STACKATO_SPACE_GUID
	    # (2b) $STACKATO_SPACE
	    # (3) $HOME/.stackato/client/token2
	    # See also mgr/cspace.tcl
	}
	option space-guid {
	    The once-off space to use for the current operation, specified
	    by guid. This is a Stackato 3 option.
	    Cannot be used together with --space.
	} {
	    when-set      [disallow @space]
	    validate      [call@vtype spaceuuid]
	    generate      [call@mgr cspace getc]
	    when-complete [call@mgr cspace setc]
	    # Priority order (first to last taken):
	    # (1) --group
	    # (2a) $STACKATO_SPACE_GUID
	    # (2b) $STACKATO_SPACE
	    # (3) $HOME/.stackato/client/token2
	    # See also mgr/cspace.tcl
	}
	# ====================================================
    }

    common .token {
	# (L) Note: generate callback depends on --target, --token-file
	option token {
	    The once-off authentication token to use for the
	    current operation.
	} {
	    generate      [call@mgr auth getc]
	    when-complete [call@mgr auth setc]
	    when-set      [call@mgr auth setc]
	}
    }

    # # ## ### ##### ######## ############# #####################
    ## Parameter to hold the client/target connection, several
    ## variants, depending on needs (no login required, login
    ## required, group setting effective, ...)

    # Use this in conjunction with all uses of 'state client'.
    # Specify after the 'client'! so that we can auto-set the
    # information into it with when-complete. See below, .client*

    # Effectively disabled. System now saves a REST trace unconditionally.
    common .trace {
	option trace {
	    Activate tracing of the issued REST requests and responses.
	    This option is a no-op now. Tracing is always active. See
	    the 'trace' command to print the saved trace to stdout.
	} {
	    undocumented
	    alias t
	    default no
	    if 0 { disabled -- when-set [call@mgr client trace=] }
	}
    }

    common .client-auth {
	state client {
	    The client instance providing the connection
	    to the chosen target.
	} { immediate ; generate [call@mgr client authenticatedc] }
	use .trace
    }

    common .client-auth+group {
	state client {
	    The client instance providing the connection
	    to the chosen target, configured for the group.
	} { immediate ; generate [call@mgr client auth+group] }
	use .trace
    }

    common .client+group {
	state client {
	    The client instance providing the connection
	    to the chosen target, configured for the group.
	} { immediate ; generate [call@mgr client plainc] }
	use .trace
    }

    common .client {
	state client {
	    The client instance providing the connection
	    to the chosen target.
	} { immediate ; generate [call@mgr client plainc] }
	use .trace
    }

    common .rawclient {
	state client {
	    The client instance providing the connection
	    to the chosen target. Raw: v1 only, no login
	    check, no API check, no url redirection.

	} { immediate ; generate [call@mgr client rawc] }
	use .trace
    }

    # # ## ### ##### ######## ############# #####################
    ## Multiple blocks of options and state for the client/target
    ## connection of a command.

    # Note the order of declarations, see (L) above.
    common .login {
	use .token-file
	use .target
	use .token
	use .client-auth
    }

    # Note the order of declarations, see (L) above.
    common .login-with-group {
	use .token-file
	use .target
	use .token
	use .group
	use .client-auth+group
    }

    common .login-with-group2 {
	use .token-file
	use .target
	use .token
	use .groupv2
	use .client-auth+group
    }

    # Note the order of declarations, see (L) above.
    common .login-plain-with-group {
	use .token-file
	use .target
	use .token
	use .group
	use .client+group
    }

    # Note the order of declarations, see (L) above.
    common .login-plain {
	use .token-file
	use .target
	use .token
	use .client
    }

    # # ## ### ##### ######## ############# #####################
    ## Manifest processing related options and state.
    ## Dependency: client.

    common .manifest {
	option manifest {
	    Path of the manifest file to use.
	    If not specified a search is done.
	} {
	    argument path
	    validate [call@vtype path rfile]
	    default {}
	    # Using 'generate' here instead of 'default' because the
	    # default value gets validated, whereas the result of
	    # generate is considered valid by definition.
	}
	option path {
	    Path of the directory or file holding the application files to push.
	    Defaults to the current working directory.
	} {
	    validate rpath
	    default  [pwd]
	}
	state manifest/config {
	    Internal state. Place config information into the manifest processor.
	} {
	    immediate
	    when-complete [call@mgr manifest config=]
	}
	state manifest/setup {
	    Internal state to initalize manifest processing
	    properly, where needed. On-demand.
	} {
	    when-complete [call@mgr manifest setup-from-config]
	}
    }

    # # ## ### ##### ######## ############# #####################

    common .no-ws {
	option ws {
	    Use the websocket log interface, instead of
	    polling on the older /stackato_logs endpoint.
	} {
	    undocumented
	    validate boolean
	    generate [lambda p {
		# Sticky per-target
		package require stackato::mgr::ctarget
		package require stackato::mgr::tadjunct

		set target [stackato::mgr::ctarget get]
		set ws   [stackato::mgr::tadjunct get' $target ws {}]

		if {[string is boolean -strict $ws]} {
		    return $ws
		}

		return yes
	    }]
	}
    }

    common .tail {
	use .no-ws
	option tail {
	    Request target to stream the log.
	} {
	    validate boolean
	    # Dependency: @client
	    when-complete [call@mgr logstream set-use-c]
	    generate      [call@mgr logstream get-use-c]
	}
    }

    # # ## ### ##### ######## ############# #####################

    # Two users: groups limits, usermgr add
    common .limits {
	option apps {
	    Limit for the number of applications in the group.
	} {
	    argument num
	    validate [call@vtype integer0]
	}

	option appuris {
	    Limit for the number of mapped uris per application.
	} {
	    argument num
	    validate [call@vtype integer0]
	}

	option services {
	    Limit for the number of services in the group.
	} {
	    argument num
	    validate [call@vtype integer0]
	}

	option sudo {
	    Applications can use sudo (or not).
	} ;# boolean

	option drains {
	    Limit for the number of drains in the group.
	} {
	    argument num
	    validate [call@vtype integer0]
	}

	option mem {
	    Amount of memory applications can use.

	    Use the suffices 'M' and 'G' for the convenient specification
	    of mega- and gigabytes. Without a unit-suffix mega-bytes are
	    assumed. As the base-unit megabytes must specified as integers.
	    Gigabytes can be specified as fractions.
	} { validate [call@vtype memspec] }
    }

    common .allow-http {
	option allow-http {
	    Required to prevent the client from rejecting http urls.
	} { presence }
    }

    # # ## ### ##### ######## ############# #####################

    common .autocurrentorg {
	# Organizational context for most operations on spaces
	option organization {
	    The name of the parent organization to use as context.

	    Defaults to the current organization.

	    A current organization is automatically set if there is none,
	    either by taking the one organization the user belongs to, or
	    asking the user to choose among the possibilities.
	} {
	    argument name
	    # int.rep = v2org entity
	    alias o
	    validate      [call@vtype orgname]
	    generate      [call@mgr corg get-auto]
	    when-complete [call@mgr corg setc]
	    #Note: automatic definition of a current org when not defined.
	}
	state org_auto {
	    State queried by get-auto to discern if the automatic is temporarily disabled.
	} { validate boolean ; default true }
    }

    common .autocurrentspace {
	# Space context for most operations in spaces.
	use .autocurrentorg
	option space {
	    The name of the space to use as context.

	    Defaults to the current space.

	    A current space is automatically set if there is none,
	    either by taking the one space the user has, or
	    asking the user to choose among the possibilities.
	} {
	    argument name
	    validate      [call@vtype spacename]
	    generate      [call@mgr cspace get-auto]
	    when-complete [call@mgr cspace setc]
	    #Note: automatic definition of a current space when not defined.
	}
	state space_auto {
	    State queried by get-auto to discern if the automatic is temporarily disabled.
	} {
	    validate boolean ; default true
	    when-set [touch @org_auto off]
	}
    }

    common .htime {
	option health-timeout {
	    The time the health manager waits for an application to start
	    before sending problem reports. The default is target-specific.

	    Use the suffixes 'm', 'h', and 'd' for the convenient
	    specification of minutes, hours, and days. The optional
	    suffix 's' stands for seconds.
	} {
	    argument interval
	    default {}
	    validate [call@vtype interval]
	}
    }
    common .start {
	use .tail
	use .timeout
    }
    common .timeout {
	option timeout {
	    The time the client waits for an application to
	    start before giving up and returning, in seconds.
	    Note that this is measured from the last entry
	    seen in the log stream. While there is activity
	    in the log the timeout is reset.

	    The default is 2 minutes.

	    Use the suffixes 'm', 'h', and 'd' for the convenient
	    specification of minutes, hours, and days. The optional
	    suffix 's' stands for seconds.
	} {
	    argument interval
	    validate [call@vtype interval]
	    generate [lambda p {
		# Sticky per-target
		package require stackato::mgr::ctarget
		package require stackato::mgr::tadjunct
		package require stackato::validate::interval

		set target  [stackato::mgr::ctarget get]
		set timeout [stackato::mgr::tadjunct get' $target push-timeout 120]

		# Validate user-supplied data, might be edited
		try {
		    set timeout [stackato::validate::interval validate $p $timeout]
		} trap {STACKATO INTERVAL} {e o} {
		    set timeout 120
		}
		return $timeout
	    }]
	}
    }

    # From here on out, implement the command set in the new form.
    # # ## ### ##### ######## ############# #####################
    ## color management

    officer color {
	description {Management of terminal colors}
	private list {
	    section Administration Colors
	    description {
		Show the current color settings.
	    }
	} [jump@cmd color listing]
	private test {
	    section Administration Colors
	    description {
		Test a color specification.
	    }
	    input specification {
		The color specification. The accepted forms are
		'%r,g,b', '=othername', 'eX(,X)...', and any raw
		string.
	    } {	validate str }
	    input string {
		The string to apply the color specification to.
	    } {
		optional ; validate str ; default 0123456789
	    }
	} [jump@cmd color test]
	private set {
	    section Administration Colors
	    description {
		(Re)define a color.
	    }
	    input color {
		The name of the color to work on.
	    } {
		#validate color name
	    }
	    input specification {
		The color specification. The accepted forms are
		'%r,g,b', '=othername', 'eX(,X)...', and any raw
		string.
	    } {	validate str }
	} [jump@cmd color def]
	private unset {
	    section Administration Colors
	    description {
		Remove a color redefinition.
	    }
	    input color {
		The name of the color to work on.
	    } {
		#validate color name
		list
	    }
	} [jump@cmd color undef]
    }
    alias colors = color list

    # # ## ### ##### ######## ############# #####################
    ## Various debugging helper commands.

    officer debug {
	undocumented
	description {
	    A collection of debugging aids.
	}

	private diref {
	    undocumented
	    description {Test the regexp for password concealment in docker image refs}
	    input ref {The image ref to test}
	} [jump@cmd app debug-dir]

	private stdout {
	    undocumented
	    description {
		Print the Tcl configuration of the stdout channel.
	    }
	} [jump@cmd misc chan-config stdout]

	private stderr {
	    undocumented
	    description {
		Print the Tcl configuration of the stderr channel.
	    }
	} [jump@cmd misc chan-config stderr]

	private stdin {
	    undocumented
	    description {
		Print the Tcl configuration of the stdin channel.
	    }
	} [jump@cmd misc chan-config stdin]

	private columns {
	    undocumented
	    description {
		Print the terminal width in characters.
	    }
	} [jump@cmd misc columns]

	private home {
	    undocumented
	    description {
		Print various environment variables related to
		the user's home directory.
	    }
	} [jump@cmd misc home]

	private revision {
	    undocumented
	    description {
		Print the exact revision of the client.
	    }
	} [jump@cmd misc revision]

	private manifest {
	    undocumented
	    description {
		Show the internal representation for the
		application's manifest.
	    }
	    use .login-with-group
	    use .manifest
	} [jump@cmd query manifest]

	private upload-manifest {
	    undocumented
	    description {
		Show the internal representation for the
		application's manifest as it would be
		generated and uploaded to a target on push.
	    }
	    use .manifest
	    input tversion {
		The version of the target to generate the manifest for.
	    } {
		label version
		validate integer
	    }
	    input application {
		The name of the application to generate the manifest for.
	    } { validate str }
	} [jump@cmd app the-upload-manifest]

	private target {
	    undocumented
	    description {
		Return the API version of the chosen target.
	    }
	    use .target
	} [jump@cmd query target-version]

	private trace {
	    description {
		Print the saved REST trace for the last client
		command to stdout.
	    }
	    option short {
		When present, show only the short list of requests,
		without details like headers and responses.
	    } { presence }
	} [jump@cmd query trace]

	private map-named-entity {
	    description {
		Map the specified name into a uuid, given the type.
		This is a Stackato 3 specific command.
	    }
	    use .json
	    use .target
	    use .client
	    use .v2
	    input type {
		The type of the object to convert.
	    } {
		validate [call@vtype entity]
	    }
	    input name {
		The name to return the uuid for.
	    } {
		optional
		interact
	    }
	} [jump@cmd query map-named-entity]

	private named-entities {
	    description {
		List the entity types usable for 'guid'.
		I.e. the types of the named entities known to the client.
	    }
	    use .json
	} [jump@cmd query named-entities]

	private raw-rest {
	    description {
		Run a raw rest request against the chosen target.
	    }
	    use .nomotd
	    # inlined .login, but using rawclient instead.
	    use .token-file
	    use .target
	    use .token
	    use .rawclient
	    option show-extended {
		Show additional information about the request, i.e.
		response headers and the like.
	    } { presence }
	    option data {
		Payload to use for PUT and POST.
		Cannot be used with neither GET nor DELETE.
		A value of "-" or "stdin" causes the client to read the data from stdin.
	    } {
		alias d
		validate str
	    }
	    option output {
		Path to the file to write the returned payload to.
		A value of "-" or "stdin" causes the client to write
		the data to stdout.
	    } {
		argument path
		alias o
		alias O
		validate str
		default stdout
	    }
	    option form {
		Zero or more form fields to be added to the base url.
		Data is in the form of "key: value".
	    } {
		argument key:value
		list
		validate [call@vtype http-header]
	    }
	    option web-socket {
		Switch to WebSocket mode for GET.
		Cannot be used with any other operation.
	    } {
		alias ws
		alias W
		presence
	    }
	    option reconnect {
		Automatically reconnect when the websocket server
		closes the connection. Only relevant to websocket
		operation.
	    } { presence }
	    option port {
		The port to use for the request.
		Only relevant to websocket operation.
	    } {
		argument num
		default {}
		validate [call@vtype integer0]
	    }
	    input operation {
		The operation to perform (get, put, ...)
	    } {
		validate [call@vtype http-operation]
	    }
	    input path {
		The path, i.e. rest endpoint to use.
	    } {
		# maybe set vtype - urlpath or some such, which would
		# handle the normalization (prepend a missing leading /).
		# currently done in the action.
	    }
	    input header {
		Zero or more additional http headers in the form of "key: value".
	    } {
		optional
		list
		validate [call@vtype http-header]
	    }
	} [jump@cmd query raw-rest]

	private packages {
	    undocumented
	    description {
		Show the packages used the client, and their versions.
	    }
	    use .json
	    option all { Show load commands } { presence }
	} [jump@cmd query list-packages]

	private option-help {
	    undocumented
	    description {
		Show the packages used the client, and their versions.
	    }
	    use .json
	} [jump@cmd query list-options]
    }

    alias guid                  = debug map-named-entity
    alias named-entities        = debug named-entities
    alias curl                  = debug raw-rest
    alias trace                 = debug trace
    alias debug-columns         = debug columns
    alias debug-home            = debug home
    alias debug-revision        = debug revision
    alias debug-manifest        = debug manifest
    alias debug-upload-manifest = debug upload-manifest
    alias debug-target          = debug target
    alias debug-packages        = debug packages
    alias debug-stdout          = debug stdout
    alias debug-stderr          = debug stderr
    alias debug-stdin           = debug stdin
    alias debug-options         = debug option-help
    alias debug-diref           = debug diref

    # # ## ### ##### ######## ############# #####################

    private version {
	section Administration
	description {
	    Print the version number of the client.
	}
    } [jump@cmd misc version]

    # # ## ### ##### ######## ############# #####################
    ## Alias management

    officer aliasmgr {
	undocumented
	description {
	    A collection of commands to manage
	    user-specific shortcuts for command
	    entry
	}

	private add {
	    section Convenience
	    description {
		Create a shortcut for a command (prefix).
	    }
	    input name {
		The name of the new shortcut.
	    } {
		validate [call@vtype notclicmd]
	    }
	    input command {
		The command (prefix) the name will map to.
	    } { list }
	} [jump@cmd alias alias]

	private remove {
	    section Convenience
	    description {
		Remove a shortcut by name.
	    }
	    input name {
		The name of the shortcut to remove.
	    } { validate [call@vtype alias] }
	} [jump@cmd alias unalias]

	private list {
	    section Convenience
	    description {
		List the known aliases (shortcuts).
	    }
	    use .json
	} [jump@cmd alias aliases]
    }
    alias alias   = aliasmgr add
    alias unalias = aliasmgr remove
    alias aliases = aliasmgr list

    # # ## ### ##### ######## ############# #####################
    ##

    officer flagmgr {
	undocumented
	description {
	    Management of feature flags
	}

	private list {
	    section {Feature Flags}
	    description {
		Show all known feature flags and their status.
		This is a Stackato 3.4.2 command.
	    }
	    use .login
	    use .post34
	    use .json
	} [jump@cmd features list]

	private show {
	    section {Feature Flags}
	    description {
		Show the details of the specified feature flag.
		This is a Stackato 3.4.2 command.
	    }
	    use .login
	    use .post34
	    use .json
	    input name {
		The name of the feature flag to show.
	    } { validate [call@vtype featureflag] }
	} [jump@cmd features show]

	common .mod {
	    input name {
		The name of the feature flag to modify
	    } { validate [call@vtype featureflag] }
	}

	private enable {
	    section {Feature Flags}
	    description {
		Activate the specified feature.
		This is a Stackato 3.4.2 command.
	    }
	    use .login
	    use .post34
	    use .mod
	} [jump@cmd features enable]

	private disable {
	    section {Feature Flags}
	    description {
		Deactivate the specified feature.
		This is a Stackato 3.4.2 command.
	    }
	    use .login
	    use .post34
	    use .mod
	} [jump@cmd features disable]
    }
    alias feature-flags        = flagmgr list
    alias feature-flag         = flagmgr show
    alias enable-feature-flag  = flagmgr enable
    alias disable-feature-flag = flagmgr disable

    # # ## ### ##### ######## ############# #####################
    ## security groups

    officer secgroupmgr {
	undocumented
	description {
	    Management of security groups, i.e. in-system firewalling.
	}
	common .rules {
	    input rules {
		Path to the file holding the security rules, json formatted.
	    } { validate [call@vtype path rfile] }
	}
	common .staging-or-running {
	    option staging {
		Switch operation to work on the security groups for staging applications.
	    } {
		presence
		when-set [disallow @running]
		when-set [touch? @space_auto off]
	    }
	    option running {
		Switch operation to work on the security groups for running applications.
	    } {
		presence
		when-set [disallow @staging]
		when-set [touch? @space_auto off]
	    }
	}
	private show {
	    section {Security Groups}
	    description {
		Show the details of the named security group.
		This is a Stackato 3.4.2 command.
	    }
	    use .login
	    use .post34
	    use .json
	    input security_group {
		The name of the security group to show.
		This is a Stackato 3.4.2 command.
	    } { validate [call@vtype securitygroup] }
	} [jump@cmd secgroups show]

	private list {
	    section {Security Groups}
	    description {
		Show the known security groups, either
		all, or just those assigned to the running
		and staging phases.
		This is a Stackato 3.4.2 command.
	    }
	    use .login
	    use .post34
	    use .json
	    use .staging-or-running
	} [jump@cmd secgroups list]

	private create {
	    section {Security Groups}
	    description {
		Create a new security group.
		This is a Stackato 3.4.2 command.
	    }
	    use .login
	    use .post34
	    input security_group {
		The name of the new security group.
	    } { validate [call@vtype notsecuritygroup] }
	    use .rules
	} [jump@cmd secgroups create]

	private update {
	    section {Security Groups}
	    description {
		Modify the named security group. I.e.
		replace the set of rules with a new set.
		This is a Stackato 3.4.2 command.
	    }
	    use .login
	    use .post34
	    input security_group {
		The name of the security group to modify.
	    } { validate [call@vtype securitygroup] }
	    use .rules
	} [jump@cmd secgroups update]

	private delete {
	    section {Security Groups}
	    description {
		Delete the named security group.
		This is a Stackato 3.4.2 command.
	    }
	    use .login
	    use .post34
	    input security_group {
		The name of the security group to delete.
	    } { validate [call@vtype securitygroup] }
	} [jump@cmd secgroups delete]

	private bind {
	    section {Security Groups}
	    description {
		Bind the named security group to either the
		current or specified space, or the running
		and staging phases.
		This is a Stackato 3.4.2 command.
	    }
	    use .login
	    use .post34
	    use .autocurrentspace
	    use .staging-or-running
	    input security_group {
		The name of the security group to bind.
	    } { validate [call@vtype securitygroup] }
	} [jump@cmd secgroups bind]

	private unbind {
	    section {Security Groups}
	    description {
		Drop the named security group from either the
		current or specified space, or the running
		and staging phases.
		This is a Stackato 3.4.2 command.
	    }
	    use .login
	    use .post34
	    use .autocurrentspace
	    use .staging-or-running
	    input security_group {
		The name of the security group to unbind.
	    } { validate [call@vtype securitygroup] }
	} [jump@cmd secgroups unbind]
    }
    alias security-group        = secgroupmgr show
    alias security-groups       = secgroupmgr list
    alias create-security-group = secgroupmgr create
    alias update-security-group = secgroupmgr update
    alias delete-security-group = secgroupmgr delete
    alias bind-security-group   = secgroupmgr bind
    alias unbind-security-group = secgroupmgr unbind

    # # ## ### ##### ######## ############# #####################
    ## environment variable groups

    officer envgroupmgr {
	undocumented
	description {
	    Management of environment variable groups (running, staging).
	}
	common .staging-or-running {
	    option staging {
		Switch operation to work on the environment variable group for staging applications.
	    } {
		presence
		when-set [disallow @running]
		when-set [touch? @envg staging]
	    }
	    option running {
		Switch operation to work on the environment variable group for running applications.
	    } {
		presence
		when-set [disallow @staging]
		when-set [touch? @envg running]
	    }
	    state envg {
		State holding the ev-group to operate on.
	    } {
		generate [lambda {p} {
		    stackato::log::err "No group specified"
		}]
	    }
	}

	private show {
	    section {Environment Variable Groups}
	    description {
		Show the details of the specified environment variable group.
		This is a Stackato 3.6 command.
	    }
	    use .login
	    use .post342
	    use .json
	    use .staging-or-running
	} [jump@cmd envgroups show]

	private assign {
	    section {Environment Variable Groups}
	    description {
		Set the contents of the specified environment variable group.
		This is a Stackato 3.6 command.
	    }
	    use .login
	    use .post342
	    use .staging-or-running
	    option env {
		Environment variable settings.
	    } {
		argument key=value
		validate [call@vtype envassign]
		list
	    }
	} [jump@cmd envgroups assign]
    }
    alias environment-variable-group     = envgroupmgr show
    alias set-environment-variable-group = envgroupmgr assign

    # # ## ### ##### ######## ############# #####################
    ## /etc/host management

    if 0 {officer host {
	common .dry {
	    option dry-run {
		Show what would be done without
		actually making the changes.
	    }
	}
	common .hostfile {
	    option hostfile {
		The host file to manipulate.
		The defaults are platform specific.
	    } {
		argument path
		undocumented
		validate [call@vtype path rfile]
		generate [call@cmd   host default-hostfile]
	    }
	}

	private add {
	    section Administration
	    description {
		Add an IP address with its host
		names to the system's host file.
	    }
	    use .dry
	    use .hostfile
	    input ipaddress {
		The IP-address to add.
	    } { validate str } ;# TODO ::stackato::ipaddress
	    input hosts {
		List of hostnames for the ip-address
	    } { no-promotion ; list }
	} [jump@cmd host add]

	private list {
	    section Administration
	    description {
		Show the contents of the system's host file.
	    }
	    use .hostfile
	} [jump@cmd host list]

	private remove {
	    section Administration
	    description {
		Remove entries from the system's host file,
		specified by IP address or hostname
	    }
	    use .dry
	    use .hostfile
	    input hostsOrIPs {
		List of ip-addresses and host names to remove.
	    } { no-promotion ; list ; optional }
	} [jump@cmd host remove]

	private update {
	    section Administration
	    description {
		Update the entry for the IP address
		with a new set of hostnames.
	    }
	    use .dry
	    use .hostfile
	    input ipaddress {
		The IP-address to modify.
	    } { validate str } ;# TODO ::stackato::ipaddress
	    input hosts {
		List of hostnames for the ip-address
	    } { no-promotion ; list }
	} [jump@cmd host update]
    }}

    # # ## ### ##### ######## ############# #####################
    ## Current group management

    private group {
	section Administration "Groups (Stackato 2)"
	description {
	    Report the current group, or (un)set it.
	    This is a Stackato 2 specific command.
	}
	use .json
	use .login
	use .v1
	option reset {
	    Reset the current group to nothing.
	    Cannot be used together with name.
	} {
	    presence
	    when-set [disallow @name]
	}
	input name {
	    Name of the current group to use from now on.
	    Cannot be used together with --reset.
	} {
	    optional
	    when-set [disallow @reset]
	}
    } [jump@cmd cgroup getorset]

    # # ## ### ##### ######## ############# #####################
    ## Target management

    private targets {
	section Administration
	description {
	    List the available targets, and their
	    authorization tokens, if any.
	}
	use .json
	use .token-file
    } [jump@cmd target list]
    alias tokens

    private show-token {
	section Administration
	description {
	    Print the current target's token.
	}
	use .nomotd
	use .token-file
    } [jump@cmd target show-token]

    private target {
	section {Getting Started}
	description {
	    Set the target API endpoint for the client,
	    or report the current target.
	}
	use .json
	use .verbose
	use .allow-http
	# Allow stickyness ====================================
	option ws {
	    Use of websocket log interface, do not
	    poll on the older /stackato_logs endpoint.
	} { undocumented ; validate boolean ; default yes }
	option timeout {
	    Set a sticky timeout for push to the chosen target.
	    Values of "default", "none" or "" unstick the timeout,
	    i.e. reactivate the system default.
	} { undocumented
	    validate [call@vtype intervalornone]
	    default none
	}
	# CF v2 API only. ====================================
	option organization {
	    The organization to set as current for this target.
	    This is a Stackato 3 specific option.
	} {
	    argument name
	    alias o
	    #when-set [call@mgr client isv2]
	    #unable to check, no client here.
	    validate str
	    #validate [call@vtype orgname]
	    # We cannot fully validate as the target is not known yet.
	}
	option space {
	    The space to set as current for this target.
	    This is a Stackato 3 specific option.
	} {
	    argument name
	    alias s
	    #when-set [call@mgr client isv2]
	    #unable to check, no client here.
	    validate str
	    #validate [call@vtype spacename]
	    # We cannot fully validate as the target is not known yet.
	}
	state client {
	    Slot to place client information into when we have it, for
	    other parts of the system (org/space name validation). Not
	    set by the command line processor, but the backend.
	} {
	    immediate
	    when-set [call@mgr client isv2]
	    validate str
	}
	# ====================================================
	input url {
	    The url of the target to talk to.
	} { optional }
    } [jump@cmd target getorset]

    # # ## ### ##### ######## ############# #####################
    # Queries, introspection of the target.

    officer introspect {
	undocumented
	description {
	    A collection of commands to query the current target
	    for various pieces of information.
	}

	common *introspection* {
	    use .json
	    use .login
	}
	common *introspection-group* {
	    use .json
	    use .login-with-group
	}
	common *introspection-group-plain* {
	    use .json
	    use .login-plain-with-group
	}

	private frameworks {
	    section Administration
	    description {
		List the supported frameworks of the target.
		This is a Stackato 2 specific command.
	    }
	    use *introspection*
	    use .v1
	} [jump@cmd query frameworks]

	private general {
	    section Administration
	    description {
		Show the basic system and account information.
	    }
	    use *introspection-group-plain*
	} [jump@cmd query general]

	private runtimes {
	    section Administration
	    description {
		List the supported runtimes of the target.
		This is a Stackato 2 specific command.
	    }
	    use *introspection*
	    use .v1
	} [jump@cmd query runtimes]

	private stacks {
	    section Administration
	    description {
		List the supported stacks of the target.
		This is a Stackato 3 specific command.
	    }
	    use *introspection*
	    use .v2
	} [jump@cmd query stacks]

	private usage {
	    section Administration
	    description {
		Show the current memory allocation and usage
		of the active or specified user/group (Stackato 2),
		or the specified or current space (Stackato 3).
	    }
	    use *introspection-group*
	    option all {
		Query information about everything.
		Cannot be used together with userOrGroup.
	    } {
		presence
		when-set [disallow @userOrGroup]
	    }
	    input userOrGroup {
		For a Stackato 2 target the name of the group to query the data for.
		For a Stackato 3 target this names the space to query instead.

		Cannot be used together with --all.

		For a Stackato 2 target it defaults to the current group if any, or user.
		For a Stackato 3 target it defaults to the current space.
	    } {
		optional
		when-set [disallow @all]
	    }
	} [jump@cmd query usage]

	private applications {
	    section Applications
	    description {
		List the applications deployed to the target.
	    }
	    option all {
		Show all applications instead of just those
		associated with the current space.
	    } { presence }
	    option full {
		Show complete information normally left out
		(restart flag, and drains).
	    } { presence }
	    use *introspection-group*
	} [jump@cmd query applications]

	private context {
	    undocumented
	    description {
		Show the current context (target, organization, and space)
		This is a Stackato 3 specific command.
	    }
	} [jump@cmd query context]
    }

    alias frameworks    = introspect frameworks
    alias info          = introspect general
    alias runtimes      = introspect runtimes
    alias usage         = introspect usage
    alias apps          = introspect applications
    alias list          = introspect applications
    #alias where         = introspect context
    alias stacks        = introspect stacks

    # # ## ### ##### ######## ############# #####################
    ## Group management

    officer groups {
	description {
	    A collection of commands to manage groups and the
	    users in them.
	}

	private add-user {
	    section Administration "Groups (Stackato 2)"
	    description {
		Add the named user to the specified group.
		This is a Stackato 2 specific command.
	    }
	    use .login
	    use .v1
	    input group { The name of the group to add the user to. }
	    input user  { The name of the user to add to the group. }
	    # TODO: Validate group/user name (using target, client)
	} [jump@cmd groups add-user]

	private delete-user {
	    section Administration "Groups (Stackato 2)"
	    description {
		Remove the named user from the specified group.
		This is a Stackato 2 specific command.
	    }
	    use .login
	    use .v1
	    input group { The name of the group to remove the user from. }
	    input user  { The name of the user to remove from the group. }
	    # TODO: Validate group/user name (using target, client)
	} [jump@cmd groups delete-user]

	private create {
	    section Administration "Groups (Stackato 2)"
	    description {
		Create a new group with the specified name.
		This is a Stackato 2 specific command.
	    }
	    use .login
	    use .v1
	    input name { The name of the group to create. }
	    # TODO: Validate group name (using target, client)
	} [jump@cmd groups create]

	private delete {
	    section Administration "Groups (Stackato 2)"
	    description {
		Delete the named group.
		This is a Stackato 2 specific command.
	    }
	    use .login
	    use .v1
	    input name { The name of the group to delete. }
	    # TODO: Validate group name (using target, client)
	} [jump@cmd groups delete]

	private limits {
	    section Administration "Groups (Stackato 2)"
	    description {
		Show and/or modify the limits applying to applications
		in the named group.
		This is a Stackato 2 specific command.
	    }
	    use .json
	    use .login
	    use .v1
	    use .limits
	    input group {
		The name of the group (including users) to show and/or
		modify the limits for.
		Defaults to the current group.
	    } {
		optional
		generate      [call@mgr cgroup getc]
		when-complete [call@mgr cgroup setc]
		# TODO: Validate group name (using target, client)
	    }
	} [jump@cmd groups limits]

	private show {
	    section Administration "Groups (Stackato 2)"
	    description {
		Show the list of groups known to the target.
		This is a Stackato 2 specific command.
	    }
	    use .json
	    use .login
	    use .v1
	} [jump@cmd groups show]

	private users {
	    section Administration "Groups (Stackato 2)"
	    description {
		Show the list of users in the named group.
		This is a Stackato 2 specific command.
	    }
	    use .json
	    use .login
	    use .v1
	    input group {
		The name of the group to list the users for.
		Defaults to the current group.
	    } {
		optional
		generate      [call@mgr cgroup getc]
		when-complete [call@mgr cgroup setc]
		# TODO: Validate group name (using target, client)
	    }
	} [jump@cmd groups users]

	default show
    }
    alias limits = groups limits

    # # ## ### ##### ######## ############# #####################
    ## User management

    officer usermgr {
	undocumented
	description {
	    A collection of commands to manage users.
	}

	common .password {
	    option password {
		The password to use.
	    } {
		argument text
		alias passwd
		validate str
	    }
	}

	common .add {
	    section Administration {User Management}
	    description {
		Register a new user in the current or specified target.
		This operation requires administrator privileges, except
		if "allow_registration" is set server-side. This exception
		is specific to Stackato 2.
	    }
	    # ====================================================
	    use .login-plain
	    # NOTE: Plain login because on inital setup it is possible
	    # to create the first new user without having to be
	    # logged into the target. After that the target will reject
	    # if not logged in.
	    use .password
	    option admin {
		Give the newly created user administrator privileges.
	    } { presence }
	    # CF v1 API only. ====================================
	    option group {
		The group to put the new user into.
		This is a Stackato 2 specific option.
	    } {
		argument name
		when-set [call@mgr client notv2]
		validate str
	    }
	    use .limits
	    # CF v2 API only. ====================================
	    option organization {
		The organization to place the new user into.
		Defaults to the current organization.
		This is a Stackato 3 specific option.
		Cannot be used together with --no-organization.
	    } {
		argument name
		alias o
		when-set [call@mgr client isv2]
		when-set [disallow @no-organization]
		validate [call@vtype orgname]
		generate [call@mgr corg get-auto]
	    }
	    option no-organization {
		Flag to indicate that the new user should not be placed into any organization.
		This is a Stackato 3 specific option.
		Cannot be used together with --organization.
		When used any --manager and --auditor flags are ignored.
	    } {
		presence
		when-set [disallow @organization]
	    }

	    option manager {
		Add the new user to the organization, as manager.
		By request
	    } { default no }

	    option auditor {
		Add the new user to the organization, as auditor.
		By request.
	    } { default no }

	    # ====================================================
	    input name {
		The name of the user to create.
		(The user's email for a Stackato 2 target).
	    } {
		optional
		interact "User: "
		validate [call@vtype notusername]
	    }
	    option email {
		The email of the user to create.
		This is a Stackato 3 specific option.
	    } {
		validate str ;# future: maybe email regexp.
		when-set [call@mgr client isv2]
		#interact "Email: " - In the action callback itself.
	    }
	    option given {
		The given name of the user. Left empty if not specified.
		This is a Stackato 3 specific option.
	    } {
		argument name
		validate str
		when-set [call@mgr client isv2]
	    }
	    option family {
		The family name of the user. Left empty if not specified.
		This is a Stackato 3 specific option.
	    } {
		argument name
		validate str
		when-set [call@mgr client isv2]
	    }
	    # ====================================================
	}
	private add {
	    use .add
	} [jump@cmd usermgr add]

	# variant of add for the aliases based on _ in the name.
	# we do not want these in the help.
	private add_ {
	    undocumented
	    use .add
	} [jump@cmd usermgr add]

	common .delete {
	    section Administration {User Management}
	    description {
		Delete the named user, and the user's applications
		and services from the current or specified target.
		This operation requires administrator privileges.
	    }
	    use .login-plain
	    input email {
		The name of the user to delete.
	    } {
		validate [call@vtype username]
	    }
	}

	private delete {
	    use .delete
	} [jump@cmd usermgr delete]

	private delete-by-uuid {
	    undocumented
	    use .login-plain
	    input uuid {
		Uuid of the user to delete, in CC and/or AOK.
	    } { validate str }
	} [jump@cmd usermgr delete-by-uuid]

	# variant of delete for the aliases based on _ in the name.
	# we do not want these in the help.
	private delete_ {
	    undocumented
	    use .delete
	} [jump@cmd usermgr delete]

	private list {
	    section Administration {User Management}
	    description {
		Show the list of users known to the
		current or specified target.
	    }
	    use .json
	    use .login
	    option mode {
		Select the details to show
		("name" information (default), "related" entities, and "all").
	    } {
		validate [call@vtype ulmode]
	    }
	    option crosscheck {
		Show users known to AOK but not CC as well.
	    } { undocumented ; presence }
	} [jump@cmd usermgr list]

	private token {
	    section Administration {User Management}
	    description {
		Interactively set authentication token.
	    }
	    use .token-file
	    use .target
	} [jump@cmd usermgr token]

	private login-fields {
	    section Administration {User Management}
	    description {
		Show the names of the credential fields needed for a login.
		This is a Stackato 3 specific command.
	    }
	    use .login-plain
	    use .v2
	    use .json
	} [jump@cmd usermgr login-fields]

	private login {
	    section {Getting Started}
	    description {
		Log in to the current or specified target with the named user.
	    }
	    use .login-plain
	    # General ....... ====================================
	    option password {
		The password to use. 
		For Stackato 3 this is a shorthand
		for --credentials 'password: ...'.
	    } { argument text ; alias passwd ; validate str }
	    # CF v2 API only. ====================================
	    option credentials {
		The credentials to use.
		Each use of the option declares a single element,
		using the form "key: value" for the argument.
		This is a Stackato 3 specific option.
	    } {
		argument key:value
		list
		when-set [call@mgr client isv2]
		validate [call@vtype http-header]
	    }
	    option organization {
		The organization to use.
		This is a Stackato 3 specific option.
		If not specified the user is asked interactively
		to choose an organization.
	    } {
		# NOTE: We cannot validate the org name from within
		# NOTE: the dispatcher. To get the proper list we
		# NOTE: we need a login, which is what we do not have
		# NOTE: right now and are working on getting with this
		# NOTE: command. So, defered to the command implementation.
		argument name
		when-set [call@mgr client isv2]
		validate str
	    }
	    option space {
		The space (in the organization) to use.
		This is a Stackato 3 specific option.
		If not specified the user is asked interactively
		to choose among the possible spaces in
		either the chosen organization, or all
		organizations it belongs to.
	    } {
		# NOTE: We cannot validate the space name from within
		# NOTE: the dispatcher. To get the proper list we
		# NOTE: we need a login, which is what we do not have
		# NOTE: right now and are working on getting with this
		# NOTE: command. So, defered to the command implementation.
		argument name
		when-set [call@mgr client isv2]
		validate str
	    }
	    option ignore-missing {
		Disable errors generated for missing organization and/or space.
	    } { presence }
	    # CF v1 API only. ====================================
	    option group {
		The group to use for the login.
		This is a Stackato 2 specific option.
	    } {
		argument name
		when-set [call@mgr client notv2]
		validate str
	    }
	    # ====================================================
	    input email {
		The user to log in as.
		For Stackato 2 this is an email address.
		For Stackato 3 this is a user name, and a shorthand
		for --credentials 'username: ...'.
	    } {
		label name
		optional

		# We cannot set user name validation here because that
		# requires UAA access (uuid <-> name mapping and
		# list), and that is not something we can expect to
		# have before we are properly logged in!
		#validate [call@vtype username]

		# The interaction for an undefined 'email' is
		# performed explicitly in the command implementation
	    }
	} [jump@cmd usermgr login]

	private logout {
	    section {Getting Started}
	    description {
		Log out of the current, specified, or all targets.
	    }
	    use .token-file
	    use .client
	    option all {
		When present, log out of all targets we know.
		Cannot be used together with a target.
	    } {
		presence
		when-set [disallow @target]
	    }
	    input target {
		Name of the target to log out of.
		Defaults to the current target.
		Cannot be used together with --all.
	    } {
		optional
		when-set [disallow @all]
		generate [call@mgr ctarget getc]
	    }
	} [jump@cmd usermgr logout]

	private password {
	    section Administration {User Management}
	    description {
		Change the password of the current user in the
		current or specified target.
	    }
	    use .login-plain
	    option password {
		The new password. If not present it will be interactively
		asked for.
	    } { argument text ; alias passwd ; validate str }
	} [jump@cmd usermgr password]

	private who {
	    section Administration
	    description {
		Show the name of the current user in the current or
		specified target.
	    }
	    use .json
	    use .login-plain
	} [jump@cmd usermgr who]

	private info {
	    section Administration
	    description {
		Shows the information of a user in the current
		or specified target. Defaults to the current user.
		Naming a specific user requires a Stackato 3 target.
	    }
	    use .json
	    use .login-plain
	    input name {
		Name of the user to show information for.
		Defaults to the current user.
	    } {
		optional
		when-set [call@mgr client isv2]
		generate [lambda p {
		    [$p config @client] current_user
		}]
	    }
	} [jump@cmd usermgr info]

	private decode-token {
	    undocumented
	    description {
		Decode a CF token and print the contents.
	    }
	    use .nomotd
	    input token {
		The token string to decode.
	    } { }
	} [jump@cmd usermgr decode-token]

	common .org-roles {
	    section Organizations
	    use .login
	    use .v2
	    state developer  { Affect the developer role }       { default no }
	    option manager   { Affect the manager role }         { presence }
	    option billing   { Affect the billing manager role } { presence }
	    option auditor   { Affect the auditor role }         { presence }
	    input user {
		Name of the user to modify
	    } {
		validate [call@vtype username-org]
	    }
	    input org {
		Name of the org to modify
	    } {
		optional
		validate      [call@vtype orgname]
		generate      [call@mgr corg get-auto]
		when-complete [call@mgr corg setc]
	    }
	}

	common .space-roles {
	    section Spaces
	    use .login
	    use .v2
	    option developer { Affect the developer role } { presence }
	    option manager   { Affect the manager role }   { presence }
	    option auditor   { Affect the auditor role }   { presence }
	    input user {
		Name of the user to modify
	    } {
		validate [call@vtype username-space]
	    }
	    use .autocurrentorg
	    input space {
		Name of the space to modify
	    } {
		optional
		validate      [call@vtype spacename]
		generate      [call@mgr cspace get-auto]
		when-complete [call@mgr cspace setc]
	    }
	}

	private link-org {
	    description {
		Add the specified user to the named organization, in
		various roles. This is a Stackato 3 specific
		command.
	    }
	    use .org-roles
	} [jump@cmd usermgr link-org]

	private link-space {
	    description {
		Add the specified user to the named space, in various
		roles. This is a Stackato 3 specific command.
	    }
	    use .space-roles
	} [jump@cmd usermgr link-space]

	private unlink-org {
	    description {
		Remove the specified user from the named organization,
		in various roles. This is a Stackato 3
		specific command.
	    }
	    use .org-roles
	} [jump@cmd usermgr unlink-org]

	private unlink-space {
	    description {
		Remove the specified user from the named space, in
		various roles. This is a Stackato 3
		specific command.
	    }
	    use .space-roles
	} [jump@cmd usermgr unlink-space]

	private org-list {
	    section Organizations
	    description {
		Show the users for the organization, by role.
	    }
	    use .json
	    use .login
	    use .v2
	    input org {
		Name of the org to query.
		Defaults to the current org.
	    } {
		optional
		validate      [call@vtype orgname]
		generate      [call@mgr corg get-auto]
		when-complete [call@mgr corg setc]
	    }
	} [jump@cmd usermgr org-list]

	private space-list {
	    section Spaces
	    description {
		Show the users for the space, by role.
	    }
	    use .json
	    use .login
	    use .v2
	    use .autocurrentorg
	    input space {
		Name of the space to query.
		Defaults to the current space.
	    } {
		optional
		validate      [call@vtype spacename]
		generate      [call@mgr cspace get-auto]
		when-complete [call@mgr cspace setc]
	    }

	} [jump@cmd usermgr space-list]
    }

    alias token       = usermgr token
    alias login       = usermgr login
    alias logout      = usermgr logout
    alias passwd      = usermgr password
    alias user        = usermgr who
    alias add-user    = usermgr add
    alias  register
    alias  add_user   = usermgr add_
    alias  create_user
    alias  create-user
    alias delete-user = usermgr delete
    alias  unregister
    alias  delete_user = usermgr delete_

    # Hidden, helper
    alias delete-user-id = usermgr delete-by-uuid

    alias users        = usermgr list
    alias user-info    = usermgr info
    alias debug-token  = usermgr decode-token
    alias login-fields = usermgr login-fields

    alias link-user-org     = usermgr link-org
    alias link-user-space   = usermgr link-space
    alias unlink-user-org   = usermgr unlink-org
    alias unlink-user-space = usermgr unlink-space

    alias org-users   = usermgr org-list
    alias space-users = usermgr space-list

    # # ## ### ##### ######## ############# #####################
    ## Administrative tasks

    officer admin {
	description {
	    A set of adminstrative tasks.
	}

	private report {
	    section Administration
	    description {
		Retrieve a report containing the logs of the current or specified target.
		This is a stackato-specific command.
	    }
	    use .login
	    use .isstackato
	    input destination {
		The file to store the report into.
		The default name is derived from the target.
	    } {
		optional
		generate [call@cmd admin default-report]
	    }
	} [jump@cmd admin report]

	private grant {
	    section Administration
	    description {
		Grant the named user administrator
		privileges for the current or specified
		target.
	    }
	    use .client
	    input email {
		Name of the user to grant administrator
		privileges to.
	    } {
		label user
		validate [call@vtype username]
	    }
	} [jump@cmd admin grant]

	private revoke {
	    section Administration
	    description {
		Revoke administrator privileges for
		the named user at the current or specified
		target.
	    }
	    use .client
	    input email {
		Name of the user to revoke administrator
		privileges from.
	    } {
		label user
		validate [call@vtype username]
	    }
	} [jump@cmd admin revoke]

	private list {
	    section Administration
	    description {
		Show a list of the administrators for
		the current or specified target.
	    }
	    use .json
	    use .login
	} [jump@cmd admin list]
    }

    # # ## ### ##### ######## ############# #####################
    ## Service management

    officer servicemgr {
	undocumented
	description {
	    Set of commands to manage services.
	}

	common .type-filter {
	    option provider {
		The service provider. Use this to disambiguate
		between multiple providers of the same vendor/type.
	    } {
		argument name
		when-set [call@mgr client isv2]
		validate str
		# A filter on 'vendor' (see below).
		# String field in the vendor, no further validation.
	    }
	    option sversion {
		The service version. Use this to disambiguate
		between multiple versions of the same vendor/type.
	    } {
		label version
		when-set [call@mgr client isv2]
		validate str
		# A general filter on 'vendor' (see below).
		# String field in the vendor, no further validation.
	    }
	}

	officer type {
	    private purge {
		section Services
		description {
		    Purge all offerings of the service type from the system.
		    Danger. Do this only for services we know to have their
		    brokers killed, leaving behind orphans.
		    This is a Stackato 3.4+ specific command.
		}
		use .login
		use .post32
		use .type-filter
		input service {
		    The service type to purge.
		} {
		    validate [call@vtype servicetype]
		}
	    } [jump@cmd servicemgr purge-service-type]
	}

	officer plan {
	    common .plan-filter {
		section Services Plans
		use .login
		use .v2
		use .type-filter
		option vendor {
		    Name of the service type the specified plan belongs to.
		} {
		    argument name
		    validate [call@vtype servicetype]
		    interact
		}
	    }

	    common .plan-visibility {
		use .plan-filter
		input name {
		    Name of the service-plan to modify
		} {
		    validate [call@vtype serviceplan]
		}
		input organization {
		    Name of the organization to modify.
		    Defaults to the current organization.
		} {
		    optional
		    validate      [call@vtype orgname]
		    generate      [call@mgr corg get-auto]
		    when-complete [call@mgr corg setc]
		}
	    }

	    private show {
		description {
		    Show the details of the specified service plan.
		    This is a Stackato 3 specific command.
		}
		use .plan-filter
		use .json
		input name {
		    Name of the service-plan to show the details of.
		} {
		    validate [call@vtype serviceplan]
		}
	    } [jump@cmd servicemgr show-plan]

	    private link-org {
		description {
		    Make the specified service-plan visible to the named organization.
		    This is a Stackato 3 specific command.
		}
		use .plan-visibility
	    } [jump@cmd servicemgr link-plan-org]

	    private unlink-org {
		description {
		    Hide the specified service-plan from the named organization.
		    This is a Stackato 3 specific command.
		}
		use .plan-visibility
	    } [jump@cmd servicemgr unlink-plan-org]

	    private update {
		description {
		    Update the target's knowledge of the named service plan.
		    This is a Stackato 3 specific command.
		}
		use .plan-filter
		input name {
		    Name of the plan to update.
		} {
		    optional
		    validate [call@vtype serviceplan]
		    interact
		}
		option free {
		    Mark the plan as free.
		} {}
		option public {
		    Mark the plan as globally public.
		} {}
		option description {
		    Change the plan's description.
		} {
		    argument text
		    validate str
		}
		input newname {
		    The new name of the service plan
		} {
		    optional
		    validate [call@vtype notserviceplan]
		}
	    } [jump@cmd servicemgr update-plan]

	    private list {
		section Services Plans
		description {
		    List all available plans of the supported services.
		    This is a Stackato 3 specific command.
		}
		use .login
		use .v2
		use .json
	    } [jump@cmd servicemgr list-plans]

	    private market {
		section Services
		description {
		    List the supported service plans of the target, for the current or specified space.
		    This is a Stackato 3.4+ specific command.
		}
		use .json
		use .post32
		use .login-with-group
	    } [jump@cmd servicemgr market]
	}

	officer broker {
	    undocumented
	    description {
		Management of service brokers.
	    }

	    private add {
		section Services Brokers
		description {
		    Make the named service broker known.
		    This is a Stackato 3 specific command.
		}
		use .login-with-group
		use .v2
		input name {
		    Name of the new broker.
		} {
		    optional
		    validate [call@vtype notservicebroker]
		    interact
		}
		option broker-token {
		    Value of the broker's token.
		    Note: This option is specific to Stackato 3.0.
		} {
		    argument text
		    immediate
		    when-set [call@mgr client max-version-opt 3.0]
		    validate str
		}
		option url {
		    Location of the broker.
		} {
		    argument location
		    validate str
		    interact
		}
		option username {
		    Name of the user to use for access to the broker.
		} {
		    argument name
		    validate str
		    interact
		}
		option password {
		    The password to use for access to the broker.
		} {
		    argument text
		    validate str
		    interact
		}
		option public {
		    Make the plans of the newly registered broker
		    immediately public.
		} { presence }
	    } [jump@cmd servicebroker add]

	    private list {
		section Services Brokers
		description {
		    Show the list of known service brokers.
		    This is a Stackato 3 specific command.
		}
		use .login-with-group
		use .v2
		use .json
	    } [jump@cmd servicebroker list]

	    private update {
		section Services Brokers
		description {
		    Update the target's knowledge of the named service broker.
		    This is a Stackato 3 specific command.
		}
		use .login-with-group
		use .v2
		input name {
		    Name of the broker to update.
		} {
		    optional
		    validate [call@vtype servicebroker]
		    interact
		}
		option broker-token {
		    Value of the broker's token.
		    Note: This option is specific to Stackato 3.0.
		} {
		    argument text
		    immediate
		    when-set [call@mgr client max-version-opt 3.0]
		    validate str
		}
		option url {
		    New location of the broker.
		} {
		    argument location
		    validate str
		}
		option username {
		    Name of the user to use for access to the broker.
		} {
		    argument name
		    validate str
		}
		option password {
		    The password to use for access to the broker.
		} {
		    argument text
		    validate str
		}
		input newname {
		    The new name of the service broker.
		} {
		    optional
		    validate [call@vtype notservicebroker]
		}
	    } [jump@cmd servicebroker update]

	    private remove {
		section Services Brokers
		description {
		    Remove the named service broker from the target.
		    This is a Stackato 3 specific command.
		}
		use .login-with-group
		use .v2
		input name {
		    Name of the broker to remove.
		} {
		    optional
		    validate [call@vtype servicebroker]
		    interact
		}
	    } [jump@cmd servicebroker remove]

	    private show {
		section Services Brokers
		description {
		    Show the information of the named service broker from the target.
		    This is a Stackato 3 specific command.
		}
		use .login-with-group
		use .v2
		input name {
		    Name of the broker to show.
		} {
		    optional
		    validate [call@vtype servicebroker]
		    interact
		}
	    } [jump@cmd servicebroker show]
	}

	officer auth {
	    undocumented
	    description {
		Management of service authentication tokens.
	    }

	    private create {
		section Services {Authentication Tokens}
		description {
		    Create a new service authentication token.
		    This is a Stackato 3 specific command.
		}
		use .login-with-group
		use .v2
		input label {
		    Identifying label of the new service authentication token.
		} {
		    optional
		    validate [call@vtype notserviceauthtoken]
		    interact
		}
		input provider {
		    Name of the token provider.
		} {
		    optional
		    validate str
		    default core
		}
		option auth-token {
		    Value of the new token.
		} {
		    argument text
		    validate str
		    interact "Authentication Token: "
		}
	    } [jump@cmd serviceauth create]

	    private update {
		section Services {Authentication Tokens}
		description {
		    Update the specified service authentication token.
		    This is a Stackato 3 specific command.
		}
		use .login-with-group
		use .v2
		input label {
		    Label identifying the service authentication token to update.
		} {
		    optional
		    validate [call@vtype serviceauthtoken]
		    generate [call@cmd serviceauth select-for update]
		}
		option auth-token {
		    New value of the specified token.
		} {
		    argument text
		    validate str
		    interact "Authentication Token: "
		}
	    } [jump@cmd serviceauth update]

	    private delete {
		section Services {Authentication Tokens}
		description {
		    Delete the specified service authentication token.
		    This is a Stackato 3 specific command.
		}
		use .login-with-group
		use .v2
		input label {
		    Label identifying the service authentication token to delete.
		} {
		    optional
		    validate [call@vtype serviceauthtoken]
		    generate [call@cmd serviceauth select-for delete]
		}
	    } [jump@cmd serviceauth delete]

	    private list {
		section Services {Authentication Tokens}
		description {
		    Show all service authentication tokens knowns to the target.
		    This is a Stackato 3 specific command.
		}
		use .login-with-group
		use .v2
		use .json
	    } [jump@cmd serviceauth list]
	}

	common .bind {
	    section Services Management
	    description {
		Bind the named service to the specified
		application.
	    }
	    use .login-with-group
	    use .manifest
	    use .start
	    input service {
		Name of the provisioned service to bind.
	    } {
		optional
		generate [call@cmd servicemgr select-for-change bind]
		validate [call@vtype serviceinstance]
	    }
	    input application {
		Name of the application to bind to.
	    } {
		optional
		validate [call@vtype appname]
	    }
	}

	private bind {
	    use .bind
	} [jump@cmd servicemgr bind]

	private bind_ {
	    undocumented
	    use .bind
	} [jump@cmd servicemgr bind]

	common .unbind {
	    section Services Management
	    description {
		Disconnect the named service from the specified
		application.
	    }
	    use .login-with-group
	    use .manifest
	    use .start
	    input service {
		Name of the provisioned service to disconnect.
	    } {
		optional
		generate [call@cmd servicemgr select-for-change unbind]
		validate [call@vtype serviceinstance]
	    }
	    input application {
		Name of the application to disconnect from.
	    } {
		optional
		validate [call@vtype appname]
	    }
	}

	private unbind {
	    use .unbind
	} [jump@cmd servicemgr unbind]

	private unbind_ {
	    undocumented
	    use .unbind
	} [jump@cmd servicemgr unbind]

	private clone {
	    section Services Management
	    description {
		Copy the service bindings of the source
		application to the destination application.
	    }
	    use .login-with-group
	    use .start
	    input source {
		Name of the application to take the list of services from.
	    } { validate [call@vtype appname] }
	    input application {
		Name of the application to bind the services to.
	    } { validate [call@vtype appname] }
	} [jump@cmd servicemgr clone]

	common .create {
	    section Services Management
	    description {
		Create a new provisioned service, and optionally bind it
		to an application.
	    }
	    use .login-with-group
	    use .start

	    # ================================================
	    # CF v2 API only. ===============================
	    option provider {
		The service provider. Use this to disambiguate
		between multiple providers of the same vendor/type.
		This is a Stackato 3 specific option.
	    } {
		argument name
		when-set [call@mgr client isv2]
		validate str
		# A filter on 'vendor' (see below).
		# String field in the vendor, no further validation.
	    }
	    option sversion {
		The service version. Use this to disambiguate
		between multiple versions of the same vendor/type.
		This is a Stackato 3 specific option.
	    } {
		label version
		when-set [call@mgr client isv2]
		validate str
		# A general filter on 'vendor' (see below).
		# String field in the vendor, no further validation.
	    }
	    # ================================================
	    input vendor {
		The type/vendor of the service to provision.
	    } {
		optional
		# We cannot use 'interact' as the interaction is more
		# complex than a simple prompt.  TODO FUTURE: Allow
		# more type of prompting. Here: menu of fixed set of
		# choices.
		# Dependency: client, no-prompt
		generate [call@cmd servicemgr select-for-create]
		validate [call@vtype servicetype]
	    }
	    # ================================================
	    # CF v2 API only. ===============================
	    option plan {
		The service plan to use.
		This is a Stackato 3 specific option.
	    } {
		argument name
		when-set [call@mgr client isv2]
		# Dependency: vendor (validate, generate)
		generate [call@cmd servicemgr select-plan-for-create]
		validate [call@vtype serviceplan]
	    }
	    option credentials {
		The credentials to use.
		Each use of the option declares a single element,
		using the form "key: value" for the argument.
		This is a Stackato 3 specific option.
		This is restricted to user-provided services.
	    } {
		argument key:value
		list
		when-set [call@mgr client isv2]
		validate [call@vtype http-header]
	    }
	    # ================================================
	    input name {
		The name of the new service.
		Defaults to a randomly generated name
		based on the type/vendor.
	    } {
		optional
		# Dependency: vendor
		generate [call@mgr service random-name]
	    }
	    input application {
		The name of the application to bind the new
		service to, if any.
	    } {
		optional
		validate [call@vtype appname]
	    }
	}

	private create {
	    use .create
	} [jump@cmd servicemgr create]

	private create_ {
	    undocumented
	    use .create
	} [jump@cmd servicemgr create]

	common .delete {
	    section Services Management
	    description {
		Delete the named provisioned service.
	    }
	    use .login-with-group
	    option all {
		Delete all services.
		Cannot be used together with named service instances.
	    } {
		presence
		when-set [disallow @service]
	    }
	    option unbind {
		Unbind service from applications before deleting.
		By default bound services are skipped and not deleted.
		This is a Stackato 3 specific option.
	    } {
		when-set [call@mgr client isv2]
		presence
	    }
	    input service {
		List of the service instances to delete.
		Cannot be used together with --all.
	    } {
		optional
		list
		when-set [disallow @all]
		# We cannot use 'interact' as the interaction is more
		# complex than a simple prompt.  Conditional, and a
		# menu of choices.
		generate [call@cmd servicemgr select-for-delete]
		validate [call@vtype serviceinstance]
	    }
	}

	private delete {
	    use .delete
	} [jump@cmd servicemgr delete]

	private delete_ {
	    undocumented
	    use .delete
	} [jump@cmd servicemgr delete]

	common .uupsi {
	    section Services Management
	    description {
		Update the credentials of a user provided service.
		This is a Stackato 3 specific command.
	    }
	    use .login
	    use .start
	    use .v2
	    option credentials {
		The new credentials to use.
		Their entirety replaces the old credentials.
		Each use of the option declares a single element,
		using the form "key: value" for the argument.
	    } {
		argument key:value
		list
		when-set [call@mgr client isv2]
		validate [call@vtype http-header]
	    }
	    input service {
		Name of the service instance to update.
		Must be a user-provided service.
	    } {
		validate [call@vtype serviceinstance]
	    }
	}

	private u-upsi {
	    use .uupsi
	} [jump@cmd servicemgr update-upsi]

	private show {
	    section Services
	    description {
		Show the information about the named service.
	    }
	    use .json
	    use .login-with-group
	    input name {
		The name of the provisioned service to show
		information for.
	    } {
		validate [call@vtype serviceinstance]
	    }
	} [jump@cmd servicemgr show]

	common .rename {
	    section Services Management
	    description {
		Rename the specified service instance.
		This is a Stackato 3 specific command.
	    }
	    use .v2
	    use .login-with-group
	    input service {
		The name of the service instance to rename.
	    } {
		validate [call@vtype serviceinstance]
	    }
	    input name {
		The new name of the service instance.
	    } {
		optional
		interact "Enter new name: "
		validate [call@vtype notserviceinstance]
	    }
	}

	private rename {
	    use .rename
	} [jump@cmd servicemgr rename]

	private rename_ {
	    undocumented
	    use .rename
	} [jump@cmd servicemgr rename]

	private list {
	    section Services
	    description {
		List the supported and provisioned services
		of the target.
	    }
	    use .json
	    use .login-with-group
	} [jump@cmd servicemgr list-instances]

	private tunnel {
	    section Services Management
	    description {
		Create a local tunnel to a service,
		optionally start a local client as well.
	    }
	    use .allow-http
	    use .login-with-group
	    use .tail
	    input service {
		The name of the service to tunnel to.
	    } { optional }
	    input tunnelclient {
		The name of the local client to connect to the
		tunnel. Defaults to a service-specific client.
	    } { optional }
	    option port {
		Port used for the tunnel.
	    } {
		argument num
		default 10000
		validate [call@vtype integer0]
	    }
	    option url {
		Url the tunnel helper application is mapped to and
		listens on. Relevant if and only if the helper has
		to be pushed,i.e. on first use of the tunnel command.
	    } { validate str }

	    # See also common .push-update, command 'push'.
	    option keep-zip {
		Path to a file to keep the upload zip under after upload, for inspection.
	    } {
		argument path
		undocumented
		validate [call@vtype path rwfile]
		default {}
	    }
	    # See also create-buildpack
	    option keep-form {
		Path to a file to keep the whole uploaded multipart/formdata
		under after upload, for inspection.
	    } {
		argument path
		undocumented
		validate [call@vtype path rwfile]
		default {}
	    }
	    state copy-unsafe-links {
		Fake argument for the internal push (tunnel helper).
	    } { default no }
	    state no-resources {
		Fake argument for the internal push (tunnel helper).
	    } { default no }
	    state appname {
		Fake app name argument for use by validation.
	    } { default no }
	    state timeout {
		Fake timeout for start of tunnel helper.
		Standard 2min default.
	    } { default 120 }
	    state health-timeout {
		Fake timeout for health manager for start of tunnel helper.
		Standard target default.
	    } { default {} }
	    state force-war-unpacking {
		Fake .war option, disable special unpacking. Irrelevant to tunnel.
	    } { default no }
	} [jump@cmd servicemgr tunnel]
    }
    alias bind-service   = servicemgr bind
    alias  bind_service   = servicemgr bind_
    alias unbind-service = servicemgr unbind
    alias  unbind_service = servicemgr unbind_
    alias clone-services = servicemgr clone
    alias create-service = servicemgr create
    alias  create_service = servicemgr create_
    alias rename-service = servicemgr rename
    alias  rename_service = servicemgr rename_
    alias delete-service = servicemgr delete
    alias  delete_service = servicemgr delete_
    alias service        = servicemgr show
    alias tunnel         = servicemgr tunnel

    alias update-user-provided-service = servicemgr u-upsi

    alias marketplace   = servicemgr plan market
    alias services      = servicemgr list
    alias service-plans = servicemgr plan list
    alias service-plan  = servicemgr plan show

    alias update-service-plan = servicemgr plan update
    alias show-service-plan   = servicemgr plan link-org
    alias hide-service-plan   = servicemgr plan unlink-org

    alias create-service-auth-token = servicemgr auth create
    alias update-service-auth-token = servicemgr auth update 
    alias delete-service-auth-token = servicemgr auth delete
    alias service-auth-tokens       = servicemgr auth list

    alias service-brokers       = servicemgr broker list
    alias add-service-broker    = servicemgr broker add
    alias create-service-broker = servicemgr broker add
    alias remove-service-broker = servicemgr broker remove
    alias update-service-broker = servicemgr broker update
    alias delete-service-broker = servicemgr broker remove
    alias show-service-broker   = servicemgr broker show

    alias purge-service-offerings = servicemgr type purge

    # # ## ### ##### ######## ############# #####################
    ## Application control

    officer application {
	undocumented
	description {
	    Collection of commands to manage and control applications.
	}

	# application ref
	common .application-kernel {
	    use .login-with-group
	    use .manifest
	}

	common .application2-kernel {
	    use .login-with-group2
	    use .manifest
	}

	common .application-core {
	    #use .tail -- Most app commands do _not_ do logyard tailing. Only those which 'start'.
	    use .application-kernel
	}

	common .application2-core {
	    use .application2-kernel
	}

	common .application-k {
	    use .application-kernel
	    input application {
		Name of the application to operate on.
	    } {
		optional
		validate [call@vtype appname]
		# Dependency on @client (via .application-core)
	    }
	}

	common .application {
	    use .application-core
	    input application {
		Name of the application to operate on.
	    } {
		optional
		validate [call@vtype appname]
		# Dependency on @client (via .application-core)
	    }
	}

	common .application-test {
	    use .application-core
	    input application {
		Name of the application to operate on.
	    } {
		optional ; test
		validate [call@vtype appname]
		# Dependency on @client (via .application-core)
	    }
	}

	common .application-push {
	    use .application-core
	    input application {
		Name of the application to operate on.
	    } {
		optional
		validate [call@vtype appname-lex] ; # lexical validation only, accept unknown and known apps.
		# Dependency on @client (via .application-core)
	    }
	}

	common .application-dot {
	    use .application-core
	    input application {
		Name of the application to operate on.
		Or "." to take the name from the manifest.
	    } {
		validate [call@vtype appname-dot]
		# Dependency on @client (via .application-core)
	    }
	}

	common .application2-dot {
	    use .application2-core
	    input application {
		Name of the application to operate on.
		Or "." to take the name from the manifest.
	    } {
		validate [call@vtype appname-dot]
		# Dependency on @client (via .application-core)
	    }
	}

	common .application-dot-optional {
	    use .application-core
	    input application {
		Name of the application to operate on.
		Or "." to take the name from the manifest.
	    } {
		optional
		validate [call@vtype appname-dot]
		# Dependency on @client (via .application-core)
	    }
	}

	common .application-as-option {
	    use .application-core
	    option application {
		Name of the application to operate on.
	    } {
		argument name
		alias a
		validate [call@vtype appname]
		# Dependency on @client (via .application-core)
	    }
	}

	common .application-api {
	    use .application-core
	    option application {
		Name of the application to operate on, or
		"api" to talk to the cloud controller node.
	    } {
		argument name
		alias a
		validate [call@vtype appname-api]
		# Dependency on @client (via .application-core)
	    }
	}

	common .instance {
	    option instance {
		The instance to access with the command.
		Defaults to 0.
	    } {
		argument num
		validate [call@vtype instance]
		generate [call@vtype instance default]
	    }
	}

	common .instance-all {
	    option instance {
		The instance to access with the command.
		Defaults to 0.
		Cannot be used together with --all.
	    } {
		argument num
		validate [call@vtype instance]
		generate [call@vtype instance default]
		when-set [disallow @all]
	    }
	}

	common .ssh {
	    use .nomotd
	    use .dry
	    use .instance-all
	    option all {
		Run the command on all instances.
		Cannot be used together with --instance.
	    } {
		presence
		when-set [disallow @instance]
	    }
	    option banner {
		Show the leading and trailing banner to separate
		instance data. Applies only when --all is used.
		Defaults to on.
	    } { default 1 }
	}

	# The log options as state parameters, with fixed values, for
	# commands dipping into log display as part of their function:
	# start, restart, push, update.
	common .fakelogs {
	    state instance       {} { default 0   }
	    state all            {} { default no  }
	    state prefix         {} { default no  }
	    state follow         {} { default no  }
	    state json           {} { default no  }
	    state num            {} { default 100 }
	    state source         {} { default *   }
	    state filename       {} { default *   }
	    state newer          {} { default 0   }
	    state text           {} { default *   }
	    state non-timestamps {} { default yes }
	}

	# log options. conditional on server version -> dependency @client.
	common .logs {
	    use .no-ws
	    # target version independent ==========================
	    option instance {
		The id of the instance to filter the log stream for,
		or (before 2.3), to retrieve the logs of.
	    } {
		argument num
		validate [call@vtype integer0]
		when-set [disallow @all]
	    }
	    # pre 2.3 only ========================================
	    option all {
		Retrieve the logs from all instances. Before 2.3 only.
	    } {
		presence
		when-set [call@mgr logstream needslow]
		when-set [disallow @install]
	    }
	    option prefix {
		Put instance information before each line of a
		shown log file. Before Stackato 2.3 only.
	    } {
		alias prefixlogs
		alias prefix-logs
		presence
		when-set [call@mgr logstream needslow]
	    }
	    # 2.3+ only ===========================================
	    option follow {
		Tail -f the log stream. Target version 2.4+ only.
	    } {
		presence
		when-set [call@mgr logstream needfast]
		alias tail
		alias f
	    }
	    option json {
		Print the raw json log stream, not human-formatted data.
	    } {
		presence
		when-set [call@mgr logstream needfast]
	    }
	    option num {
		Show the last num entries of the log stream.
		Target version 2.4+ only.
	    } {
		generate [lambda {p} {
		    # Dynamic default, smaller when --follow is active.
		    if {[$p config @follow]} { return 10 }
		    return 100
		}]
		validate [call@vtype integer0]
		when-set [call@mgr logstream needfast]
	    }
	    option source {
		Filter the log stream by origin stage (glob pattern).
		Target version 2.4+ only.
	    } {
		argument glob-pattern
		default *
		when-set [call@mgr logstream needfast]
	    }
	    option filename {
		Filter the log stream by origin file (glob pattern).
		Target version 2.4+ only.
	    } {
		argument glob-pattern
		default *
		when-set [call@mgr logstream needfast]
	    }
	    option newer {
		Filter the log stream by time, only entries after
		the specified epoch. Target version 2.4+ only.
	    } {
		argument epoch
		undocumented ; # internal
		default 0
		validate [call@vtype integer0]
		when-set [call@mgr logstream needfast]
	    }
	    option text {
		Filter the log stream by log entry text (glob pattern).
		Target version 2.4+ only.
	    } {
		argument glob-pattern
		default *
		when-set [call@mgr logstream needfast]
	    }
	    option no-timestamps {
		Disable the printing of timestamps before the log entries.
		Target version 2.4+ only.
	    } {
		undocumented ; # internal
		presence
		when-set [call@mgr logstream needfast]
	    }
	}

	common .app-config {
	    # CF v1 API only. ====================================
	    option runtime {
		The name of the runtime to use.
		Default is framework specific, if not specified
		by a stackato.yml.
		This is a Stackato 2 specific option.
	    } {
		argument name
		validate str
		when-set [call@mgr client notv2]
		#generate [call@mgr manifest runtime]
	    }
	    option no-framework {
		Create application without any framework.
		Cannot be used together with --framework.
		This is a Stackato 2 specific option.
	    } {
		presence
		when-set [call@mgr client notv2]
		when-set [disallow @framework]
 	    }
	    option framework {
		Specify the framework to use.
		Cannot be used together with --no-framework.
		Defaults to a heuristically chosen value if
		not specified, and none for --no-framework.
		This is a Stackato 2 specific option.
	    } {
		argument name
		validate str
		when-set [call@mgr client notv2]
		when-set [disallow @no-framework]
	    }
	    # CF v2 API only. ====================================
	    ## Stack, Buildpack ...
	    option docker-image {
		Name of the docker image to use as source of the application.
		When specified the docker image is taken to contain the
		application, ready to run. No other sources are considered
		anymore in that case.
		This is a Stackato 3.6 specific option.
	    } {
		argument name
		when-set [call@mgr client isv2]
		validate str
	    }
	    option stack {
		The OS foundation the application will run on.
		This is a Stackato 3 specific option.
	    } {
		argument name
		when-set [call@mgr client isv2]
		validate [call@vtype stackname]
	    }
	    option buildpack {
		Url of a custom buildpack.
		This is a Stackato 3 specific option.
	    } {
		argument url
		when-set [call@mgr client isv2]
		validate str ; # url
	    }
	    option placement-zone {
		The placement zone associated with the application.
		This is a Stackato 3.2 specific option.
	    } {
		argument name
		alias zone
		alias placementzone
		when-set [call@mgr client isv2]
		validate [call@vtype zonename]
	    }
	    # Auto-scale support. See also 'private scale' for reconfiguration.
	    option min-instances {
		Auto-scale support.
		The minimal number of instances for the application.
		This is a Stackato 3.2 specific option.
	    } {
		argument num
		default 1
		validate [call@vtype integer1]
		when-set [call@mgr client isv2]
		when-set [call@mgr client is-stackato-opt]
	    }
	    option max-instances {
		Auto-scale support.
		The maximal number of instances for the application.
		This is a Stackato 3.2 specific option.
	    } {
		argument num
		default {} ;# <=> nil, no max
		validate [call@vtype integer1]
		when-set [call@mgr client isv2]
		when-set [call@mgr client is-stackato-opt]
	    }
	    option min-cpu {
		Auto-scale support.
		Scale down when the average CPU usage dropped below this
		threshold for the previous minute and --min-instances has
		not been reached yet.
		This is a Stackato 3.2 specific option.
	    } {
		argument num
		default 0
		validate [call@vtype percent-int]
		when-set [call@mgr client isv2]
		when-set [call@mgr client is-stackato-opt]
	    }
	    option max-cpu {
		Auto-scale support.
		Scale up when the average CPU usage exceeds this threshold
		for the previous minute and --max-instances has not been
		reached yet.
		This is a Stackato 3.2 specific option.
	    } {
		argument num
		default 100
		validate [call@vtype percent-int]
		when-set [call@mgr client isv2]
		when-set [call@mgr client is-stackato-opt]
	    }
	    option autoscale {
		Autoscaling support.
		Declare (non)usage of auto-scaling.
		Defaults to off.
		This is a Stackato 3.2 specific option.
	    } {
		validate boolean
		when-set [call@mgr client isv2]
		when-set [call@mgr client is-stackato-opt]
	    }
	    option description {
		The description associated with the application.
		This is a Stackato 3.2 specific option.
	    } {
		argument text
		when-set [call@mgr client isv2]
		validate str
	    }
	    option sso-enabled {
		A boolean flag associated with the application
		determining whether it requests single-sign-on or not.
		This is a Stackato 3.2 specific option.
	    } {
		when-set [call@mgr client isv2]
		validate boolean
	    }
	    use .htime
	    # ====================================================
	    option instances {
		The number of application instances to create.
		Defaults to 1, if not specified by a stackato.yml.
	    } {
		argument num
		validate [call@vtype integer0]
		#generate [call@mgr manifest instances]
	    }
	    option url {
		The urls to map the application to.
		I.e. can be specified multiple times.
	    } {
		# NOTE: This is a new feature, old-cli supports only a single url.
		validate str
		list
		#generate [call@mgr manifest urls]
	    }
	    option domain {
		The default domain to use for the url of the application.
		This information is only used if no urls are specified by
		neither command line nor manifest.
	    } {
		argument name
		validate str
	    }
	    option mem {
		The application's per-instance memory allocation.
		Defaults to a framework-specific value if not
		specified by stackato.yml.

		Use the suffices 'M' and 'G' for the convenient specification
		of mega- and gigabytes. Without a unit-suffix mega-bytes are
		assumed. As the base-unit megabytes must specified as integers.
		Gigabytes can be specified as fractions.
	    } {
		validate [call@vtype memspec]
		#generate [call@mgr manifest mem]
	    }
	    option disk {
		The application's per-instance disk allocation.
		Defaults to a framework-specific value if not
		specified by stackato.yml.

		Use the suffices 'M' and 'G' for the convenient specification
		of mega- and gigabytes. Without a unit-suffix mega-bytes are
		assumed. As the base-unit megabytes must specified as integers.
		Gigabytes can be specified as fractions.
	    } {
		validate [call@vtype memspec]
		#generate [call@mgr manifest mem]
	    }
	    option command {
		The application's start command.
		Defaults to a framework-specific value if required
		and not specified by stackato.yml.
	    } {
		argument text
		validate str
	    }
	    option env {
		Environment variable overrides. These are always applied
		regardless of --env-mode. The mode is restricted to the
		variable declarations found in the manifest.
	    } {
		argument key=value
		validate [call@vtype envassign]
		list
	    }
	    option env-mode {
		Environment replacement mode. One of preserve, or replace.
		The default is "preserve". Using mode "replace" implies
		--reset as well, for push. Note that new variables are always
		set. Preserve only prevents update of existing variables.
		This setting applies only to the variable declarations found
		in the manifest.  Overrides made with --env are always applied.
	    } {
		# Note: There is also 'append', which is not documented.
		#default preserve - dynamically chosen in the action callback
		argument mode
		validate [call@vtype envmode]
		when-set [lambda {p x} {
		    if {$x ne "replace"} return
		    $p config @reset set yes
		    return
		}]
	    }
	    option reset {
		Analogue of --env-mode, for the regular settings.
	    } {
		presence
	    }
	    option d {
		Set up debugging through an application-specific
		harbor (port) service. Target version 2.8+ only.
	    } {
		presence
		when-set [call@mgr app hasharbor]
		# dependencies: @client (implied @target)
	    }
	    option stackato-debug {
		host:port of the Komodo debugger listener to inject
		into the application as environment variables.
	    } {
		argument host:port
		validate [call@vtype hostport]
	    }
	}

	private versions {
	    section Applications
	    description {
		Show the list of versions for the specified application.
		This is a Stackato 3.4 specific command.
	    }
	    section Applications
	    use .json
	    use .application-k	
	    use .v2
	    use .post32
	} [jump@cmd query app-versions]

	private info {
	    section Applications
	    description {
		Show the information of the specified application.
	    }
	    section Applications
	    use .json
	    use .application-k
	} [jump@cmd query appinfo]

	private events {
	    section Applications Information
	    description {
		Show recorded application events, for application or space.
		Without an application given the current or specified space
		is used, otherwise that application.
		This is a Stackato 3 specific command.
	    }
	    use .application-dot-optional
	    use .v2
	    use .json
	} [jump@cmd app list-events]

	private rename {
	    section Applications Management
	    description {
		Rename the specified application.
		This is a Stackato 3 specific command.
	    }
	    use .application
	    use .v2
	    input name {
		New name of the application.
	    } {
		optional
		interact "Enter new name: "
		validate [call@vtype notappname]
	    }
	} [jump@cmd app rename]

	private activate {
	    section Applications Management
	    description {
		Switch to a different version of the application.
		This is a Stackato 3.4 specific command.
	    }
	    use .application
	    use .v2
	    use .post32
	    input appversion {
		The application version to switch to and activate.
	    } {
		label version
		validate [call@vtype appversion]
	    }
	    option code-only {
		When specified the rollback reactivates only the old
		droplet of the specified version while retaining the
		current configuration.
	    } { presence }
	} [jump@cmd app activate]

	private start {
	    section Applications Management
	    description { Start a deployed application. }
	    use .application
	    use .fakelogs
	    use .start
	} [jump@cmd app start]

	private stop {
	    section Applications Management
	    description { Stop a deployed application. }
	    use .application
	    use .no-ws
	} [jump@cmd app stop]

	private restart {
	    section Applications Management
	    description { Stop and restart a deployed application. }
	    use .application
	    use .start
	    use .fakelogs
	} [jump@cmd app restart]

	private restart-instance {
	    section Applications Management
	    description {
		Stop and restart a specific instance of a deployed application.
		This is a Stackato 3.4.2 command.
	    }
	    use .application2-dot
	    use .post34
	    use .timeout
	    use .fakelogs
	    use .no-ws ;# Do not place into .fakelogs, would conflict with .start
	    input theinstance {
		The index of the instance to restart.
	    } {
		label instance
		validate [call@vtype instance]
	    }
	} [jump@cmd app restart-instance]

	private restage {
	    section Applications Control
	    description {
		Restage an application, regenerate its droplet.
		This is a Stackato 3.4.2 command.
	    }
	    use .application
	    use .post34
	    use .start
	    use .fakelogs
	} [jump@cmd app restage]

	private migrate {
	    section Applications Control
	    description {
		Move the application to a different space.
		This is a Stackato 3.4.2 command.
	    }
	    use .application-dot
	    use .post34
	    option destination-organization {
		The organization of the destination space, if not the current org.
	    } {
		alias D
		alias dest-org
		argument name
		# int.rep = v2org entity
		validate      [call@vtype orgname]
		generate      [call@mgr corg getc]
	    }
	    input destination {
		Name of the space to migrate the application to.
	    } {
		validate [call@vtype otherspacename @destination-organization]
	    }
	} [jump@cmd app migrate]

	private map {
	    section Applications Management
	    description {
		Make the application accessible through the
		specified URL (a route consisting of host and domain)
	    }
	    use .application
	    input url {
		One or more urls to route to the application.
	    } { }
	} [jump@cmd app map]

	private unmap {
	    section Applications Management
	    description { Unregister the application from a URL. }
	    use .application
	    input url {
		The url to remove from the application routing.
	    } {
		validate [call@vtype approute]
	    }
	} [jump@cmd app unmap]

	private stats {
	    section Applications Information
	    description {
		Display the resource usage for a deployed application.
	    }
	    use .json
	    use .application
	} [jump@cmd app stats]

	private instances {
	    section Applications Information
	    description {
		List application instances for a deployed application.
	    }
	    use .json
	    use .application
	} [jump@cmd app instances]

	private mem {
	    section Applications Information
	    description {
		Show the memory reservation for a deployed application.
	    }
	    use .application
	} [jump@cmd app mem]

	private disk {
	    section Applications Information
	    description {
		Show the disk reservation for a deployed application.
	    }
	    use .application
	} [jump@cmd app disk]

	private scale {
	    section Applications Management
	    description {
		Update the number of instances, memory,
		disk reservation and/or autoscaling settings
		for a deployed application.
	    }
	    use .application
	    use .start

	    option disk {
		The new disk reservation to use.

		Use the suffices 'M' and 'G' for the convenient specification
		of mega- and gigabytes. Without a unit-suffix mega-bytes are
		assumed. As the base-unit megabytes must specified as integers.
		Gigabytes can be specified as fractions.
	    } {
		alias d
		validate [call@vtype memspec]
	    }
	    option mem {
		The new memory reservation to use.

		Use the suffices 'M' and 'G' for the convenient specification
		of mega- and gigabytes. Without a unit-suffix mega-bytes are
		assumed. As the base-unit megabytes must specified as integers.
		Gigabytes can be specified as fractions.
	    } {
		alias m
		validate [call@vtype memspec]
	    }
	    option instances {
		Absolute number of instances to scale to, or
		relative change.
	    } {
		argument num
		alias i
		validate integer
	    }
	    # Auto scaling support in 'scale'. See also .app-config for push/create.
	    option min-instances {
		Auto-scale support.
		The minimal number of instances for the application.
		This is a Stackato 3.2 specific option.
	    } {
		argument num
		default 1
		validate [call@vtype integer1]
		when-set [call@mgr client isv2]
		when-set [call@mgr client is-stackato-opt]
	    }
	    option max-instances {
		Auto-scale support.
		The maximal number of instances for the application.
		This is a Stackato 3.2 specific option.
	    } {
		argument num
		default {} ;# <=> nil, no max
		validate [call@vtype integer1]
		when-set [call@mgr client isv2]
		when-set [call@mgr client is-stackato-opt]
	    }
	    option min-cpu {
		Auto-scale support.
		Scale down when the average CPU usage dropped below this
		threshold for the previous minute and --min-instances has
		not been reached yet.
		This is a Stackato 3.2 specific option.
	    } {
		argument num
		default 0
		validate [call@vtype percent-int]
		when-set [call@mgr client isv2]
		when-set [call@mgr client is-stackato-opt]
	    }
	    option max-cpu {
		Auto-scale support.
		Scale up when the average CPU usage exceeds this threshold
		for the previous minute and --max-instances has not been
		reached yet.
		This is a Stackato 3.2 specific option.
	    } {
		argument num
		default 100
		validate [call@vtype percent-int]
		when-set [call@mgr client isv2]
		when-set [call@mgr client is-stackato-opt]
	    }
	    option autoscale {
		Autoscaling support.
		Declare (non)usage of auto-scaling. The default is determined
		from the (use of the) other autoscaling options and --instances.
		This is a Stackato 3.2 specific option.
	    } {
		validate boolean
		when-set [call@mgr client isv2]
		when-set [call@mgr client is-stackato-opt]
	    }
	} [jump@cmd app scale]

	private files {
	    section Applications Information
	    description {
		Display directory listing or file.
		Relative paths are interpreted relative to $STACKATO_APP_ROOT on the target.
		Without path it defaults to $STACKATO_APP_ROOT on the target.
	    }
	    use .mquiet
	    use .application-dot
	    option all {
		When present, access all instances for the file or directory.
		Cannot be used together with --instance.
	    } {
		presence
		when-set [disallow @instance]
	    }
	    option prefix {
		Put instance information before each line of a
		shown file or directory listing. Effective only
		for --all.
	    } {
		alias prefixlogs
		alias prefix-logs
		presence
	    }
	    option instance {
		When present the instance to query.
		Cannot be used together with --all.
		Defaults to 0 (except when --all is present).
	    } {
		argument num
		when-set [disallow @all]
		validate [call@vtype instance]
		generate [call@vtype instance default]
		# Small trick here. Using the VT's default method as
		# generate defers its usage to the 'completion' phase,
		# instead of running it when parsing the spec, which
		# is too early.
	    }
	    input apath {
		The path to list or download.
	    } {
		label path
		optional
	    }
	} [jump@cmd app files]

	private tail {
	    section Applications Information
	    description {
		Monitor file for changes and stream them.
	    }
	    use .mquiet
	    use .application-dot
	    option instance {
		When present the instance to query.
		Cannot be used together with --all.
		Defaults to 0 (except when --all is present).
	    } {
		argument num
		when-set [disallow @all]
		validate [call@vtype instance]
		generate [call@vtype instance default]
		# Small trick here. Using the VT's default method as
		# generate defers its usage to the 'completion' phase,
		# instead of running it when parsing the spec, which
		# is too early.
	    }
	    input apath {
		The path to list or download.
	    } {
		label path
	    }
	    state all {
		Fake parameter to allow reuse in the backend.
	    } { default 0 }
	} [jump@cmd app tail]

	private crashes {
	    section Applications Information
	    description { List recent application crashes. }
	    use .json
	    use .application
	} [jump@cmd app crashes]

	private crashlogs {
	    section Applications Information
	    description { Display log information for the application. An alias of 'logs'. }
	    use .application
	    use .logs
	} [jump@cmd app crashlogs]

	private logs {
	    section Applications Information
	    description { Display the application log stream. }
	    use .application
	    use .logs
	} [jump@cmd app logs]

	private create {
	    section Applications Management
	    description {
		Create an empty application with the specified configuration.
	    }
	    use .json
	    use .application-core
	    input application {
		The name of the application to create.
	    } {
		optional
		# NOTE: vtype is currently v1-only, compare vtype appname.
		validate [call@vtype notappname]
	    }
	    use .app-config
	} [jump@cmd app create]

	private delete {
	    section Applications Management
	    description {
		Delete the specified application(s).
	    }
	    use .login-with-group
	    use .manifest
	    option all {
		Delete all applications (in the current/specified space).
		Cannot be used together with application names.
	    } {
		presence
		when-set [disallow @application]
	    }
	    option force {
		Force deletion.
	    } { presence }

	    option routes {
		Delete exclusive routes with the application.
		Done by default.
	    } { default on }
	    input application {
		Name of the application(s) to delete.
		Cannot be used together with --all.
	    } {
		optional
		list
		when-set [disallow @all]
		validate [call@vtype appname]
	    }
	    #
	    # TODO: v2 --routes               Delete routes also
	    # TODO: v2: -o, --delete-orphaned Delete orphaned services
	    #
	} [jump@cmd app delete]

	private health {
	    section Applications Information
	    description {
		Report the health of the specified application(s).
	    }
	    use .login-with-group
	    use .manifest
	    option all {
		Report on all applications in the current space.
		Cannot be used together with application names.
	    } {
		presence
		when-set [disallow @application]
	    }
	    input application {
		Name of the application(s) to report on.
		Cannot be used together with --all.
	    } {
		optional
		list
		when-set [disallow @all]
		validate [call@vtype appname]
	    }
	} [jump@cmd app health]

	common .push-update {
	    option copy-unsafe-links {
		Links pointing outside of the application directory
		are copied into the application.
	    } {
		presence
	    }
	    option no-resources {
		Do not optimize upload by checking for existing file resources.
	    } {
		alias noresources
		presence
	    }
	    # See also command 'tunnel'
	    option keep-zip {
		Path to a file to keep the upload zip under after upload, for inspection.
	    } {
		argument path
		undocumented
		validate [call@vtype path rwfile]
		default {}
	    }
	    option keep-form {
		Path to a file to keep the whole uploaded multipart/formdata
		under after upload, for inspection.
	    } {
		argument path
		undocumented
		validate [call@vtype path rwfile]
		default {}
	    }
	    option force-war-unpacking {
		When true, unpack .war and .jar files and upload contents as
		application root. Defaults to true for Stackato 2.x targets.
		Defaults to false for Stackato 3.x targets. 
	    } {	validate boolean }
	}

	private push {
	    section Applications Management
	    description {
		Configure, create, push, map, and start a new application.
	    }
	    use .application-push
	    use .fakelogs
	    option no-start {
		Push, but do not start the application.
	    } {
		alias nostart ; presence
	    }
	    option force-start {
		Push, and start the application, even when stopped.
	    } {
		presence
	    }
	    use .app-config
	    # TODO: check order of option use in 'push'
	    # Note: manifest use contra-indicated for defaults.
	    # Note: We do not know the current app, and it may
	    # Note: be multiple anyway.
	    use .push-update
	    use .start
	    option as {
		The name of the application to push/update the selected application as.
		Possible only if a single application is pushed or updated.
	    } {
		argument name
		validate [call@vtype appname-lex]
	    }
	    option no-create {
		TODO: check when/where it was removed and why.
	    } { undocumented ; presence }
	} [jump@cmd app push]

	private update {
	    undocumented
	    description {
		Deprecated. Disabled.
		Use push to update an existing application.
	    }
	    use .application
	    use .fakelogs
	    use .push-update
	    option env-mode {
		Environment replacement mode. One of preserve, or replace.
		Preserve is default.
	    } {
		argument mode
		# Note: There is also 'append', which is not documented.
		default preserve
		validate [call@vtype envmode]
	    }
	} [jump@cmd app update]

	private dbshell {
	    section Applications Management
	    description {
		Invoke interactive db shell for a bound service.
	    }
	    use .dry
	    use .application-test
	    input service {
		The name of the service to talk to.
	    } { optional }
	} [jump@cmd app dbshell]

	private open_browser {
	    section Applications Management
	    description {
		Open the url of the specified application in the default
		web browser. If 'api' is specified as the app name, the
		Management Console is opened. With no arguments, the
		'name' value from the stackato.yml/manifest.yml in the
		current directory is used (if present).
	    }
	    use .application-kernel
	    input application {
		The name of the application to open the
		browser for, or "api" to talk to the
		target's web console, or any regular
		url a browser may understand.
	    } {
		optional
		# Note: No validation as appname here, because of the
		# special forms, i.e. "api" and _any_ url.
	    }
	} [jump@cmd app open_browser]

	private run {
	    # Essentially 'ssh' without interactive mode, nor "api".
	    section Applications Management
	    description {
		Run an arbitrary command on a running instance.
	    }
	    use .mquiet
	    use .application-as-option
	    use .ssh
	    input command {
		The command to run.
	    } { no-promotion ; list }
	} [jump@cmd app run]

	officer ssh {
	    undocumented
	    description { Secure shell and copy. }

	    private copy {
		section Applications Management
		description {
		    Copy files and directories to and from application containers.
		    The colon ":" character preceding a specified source or destination
		    indicates a remote file or path. Sources and destinations can be
		    file names, directory names, or full paths.
		}
		use .mquiet
		state dry {
		    Fake dry setting
		} { validate integer ; default 0 }
		use .application-as-option
		use .instance
		input paths {
		    The source paths, and the destination path (last).
		    The colon ":" character preceding a specified source
		    or destination indicates a remote file or path.
		    Sources and destinations can be file names, directory
		    names, or full paths.
		} { list }

	    } [jump@cmd app securecp]

	    private run {
		section Applications Management
		description {
		    SSH to a running instance (or target),
		    or run an arbitrary command.
		}
		use .mquiet
		use .application-api
		use .ssh
		input command {
		    The command to run.
		} {
		    optional ; no-promotion ; list ; test
		    # test is used to fully disable out of order
		    # option processing. Thresholding for 'optional'
		    # would still try to process the -l of, for
		    # example 'ls -l'. As validation type is 'str'
		    # everything passes the test, so no other effect.
		}
	    } [jump@cmd app securesh]

	    officer xfer {
		undocumented
		description { Internal scp support commands. }

		# Note: As internal commands they explicitly deny
		# printing of the MotD warning.

		private receive {
		    undocumented
		    description { Receive multiple files locally. }
		    use .nomotd
		    input dst { Destination directory. }
		    input n { Expected number of files } {
			optional ; default -1
		    }
		} [jump@cmd scp xfer_receive]

		private receive1 {
		    undocumented
		    description { Receive a single file locally. }
		    use .nomotd
		    input dst { Destination file. }
		} [jump@cmd scp xfer_receive1]

		private transmit {
		    undocumented
		    description { Transfer multiple files to remote. }
		    use .nomotd
		    input src {
			Source directories and files.
		    } { list }
		} [jump@cmd scp xfer_transmit]

		private transmit1 {
		    undocumented
		    description { Transfer a single file to remote. }
		    use .nomotd
		    input src { Source file. }
		} [jump@cmd scp xfer_transmit1]
	    }
	}

	officer env {
	    undocumented
	    description { Application environment }

	    private list {
		section Applications Information
		description {
		    List the application's environment variables.
		}
		use .json
		use .application
	    } [jump@cmd app env_list]

	    private add {
		section Applications Management
		description {
		    Add the specified environment variable to the
		    named application.
		}
		use .application
		use .start
		input varname {
		    The name of the new environment variable.
		}
		input value {
		    The value to set the new environment variable to.
		}
	    } [jump@cmd app env_add]

	    private delete {
		section Applications Management
		description {
		    Remove the specified environment variable from the
		    named application.
		}
		use .application
		use .start
		input varname {
		    The name of the environment variable to remove.
		}
	    } [jump@cmd app env_delete]
	}

	officer drains {
	    description {
		Commands for the management of drains attached
		to applications.
	    }

	    private add {
		section Applications Management
		description {
		    Attach a new named drain to the application.
		}
		option json {
		    The drain target takes raw json log entries.
		} { presence }
		use .application
		use .hasdrains
		input drain {
		    The name of the new drain.
		}
		input uri {
		    The target of the drain, the url of the service
		    it will deliver log data to.
		}
	    } [jump@cmd app drain_add]

	    private delete {
		section Applications Management
		description {
		    Remove the named drain from the application.
		}
		use .application
		use .hasdrains
		input drain {
		    The name of the drain to remove.
		}
	    } [jump@cmd app drain_delete]

	    private list {
		section Applications Information
		description {
		    Show the list of drains attached
		    to the application.
		}
		use .json
		use .application
		use .hasdrains
	    } [jump@cmd app drain_list]
	}

	officer zones {
	    undocumented
	    description {
		Manage the placement zone of applications.
	    }

	    private set {
		section Applications Placement
		description {
		    Associate the application with a specific
		    placement zone.
		    This is a Stackato 3.2+ specific command.
		}
		use .application
		use .post30
		use .start
		input zone {
		    The name of the placement zone to associate
		    with the application.
		} {
		    validate [call@vtype zonename]
		}
	    } [jump@cmd zones set]

	    private unset {
		section Applications Placement
		description {
		    Remove the association between application and its
		    current placement zone.
		    This is a Stackato 3.2+ specific command.
		}
		use .application
		use .post30
		use .start
	    } [jump@cmd zones unset]

	    private list {
		section Applications Placement
		description {
		    Show the available placement zones.
		    This is a Stackato 3.2+ specific command.
		}
		use .login
		use .json
		use .post30
	    } [jump@cmd zones list]

	    private show {
		section Applications Placement
		description {
		    Show the list of DEAs associated with the specified
		    placement zone.
		    This is a Stackato 3.2+ specific command.
		}
		use .login
		use .post30
		use .json
		input zone {
		    The name of the placement zone to associate
		    with the application.
		} {
		    optional
		    validate [call@vtype zonename]
		    generate [call@cmd zones select-for show]
		}
	    } [jump@cmd zones show]
	}
    }

    alias set-placement-zone   = application zones set
    alias unset-placement-zone = application zones unset
    alias placement-zones      = application zones list
    alias placement-zone       = application zones show

    alias crashes    = application crashes
    alias crashlogs  = application crashlogs
    alias create-app = application create
    alias dbshell    = application dbshell
    alias delete     = application delete
    alias files      = application files
    alias  file
    alias tail       = application tail
    alias app        = application info
    alias events     = application events

    alias versions       = application versions
    alias releases       = application versions
    alias rollback       = application activate
    alias switch-version = application activate

    alias instances  = application instances
    alias scale      = application scale
    alias logs       = application logs
    alias map        = application map
    alias mem        = application mem
    alias disk       = application disk
    alias open       = application open_browser
    alias push       = application push
    alias restart    = application restart
    alias restart-instance    = application restart-instance
    alias restage    = application restage
    alias migrate    = application migrate
    alias run        = application run
    alias rename     = application rename
    alias start      = application start
    alias stats      = application stats
    alias health     = application health
    alias stop       = application stop
    alias unmap      = application unmap
    alias update     = application update

    alias env        = application env list
    alias env-add    = application env add
    alias env-del    = application env delete

    alias set-env    = application env add
    alias unset-env  = application env delete

    alias scp        = application ssh copy
    alias ssh        = application ssh run

    alias scp-xfer-receive   = application ssh xfer receive
    alias scp-xfer-receive1  = application ssh xfer receive1
    alias scp-xfer-transmit  = application ssh xfer transmit
    alias scp-xfer-transmit1 = application ssh xfer transmit1

    alias drain  = application drains
    alias drains = application drains list

    # # ## ### ##### ######## ############# #####################
    ## CF v2 commands I: Organizations

    officer orgmgr {
	undocumented
	description {
	    Management of organizations.
	}

	private create {
	    section Organizations
	    description {
		Create a new organization.
		This is a Stackato 3 specific command.
	    }
	    use .login
	    use .v2
	    option add-self {
		Add yourself to the new organization, as developer.
		Done by default.
	    } { default yes }
	    option activate {
		Switch the current organization to the newly created one.
		Done by default.
	    } { default yes }
	    # activate is our equivalent of cf create-org --target.
	    # we can't use --target, because that is already in use as
	    # common option to use a once-off CC target.

	    option default {
		Make the organization the default for users without explicit organization.
		The previous default organization is automatically reset.
	    } { presence }

	    option quota {
		The named quota of the new organization.
		Default is the target's choice.
	    } {
		argument name
		validate [call@vtype quotaname]
	    }
	    input name {
		Name of the organization to create.
		If not specified it will be asked for interactively.
	    } {
		optional
		validate [call@vtype notorgname]
		interact
	    }
	} [jump@cmd orgs create]

	private delete {
	    section Organizations
	    description {
		Delete the named organization.
		This is a Stackato 3 specific command.
	    }
	    use .login
	    use .v2
	    use .recursive
	    #
	    # TODO: orgmgr delete
	    # TODO --warn bool,          default ??  - Show warning when the last org is deleted
	    #
	    input name {
		Name of the organization to delete.
		If not specified it will be asked for interactively (menu).
	    } {
		# int.rep = v2org entity
		optional
		validate [call@vtype orgname]
		generate [call@mgr corg select-for delete]
		# Interaction in generate, interact not complex
		# enough for menu.
	    }
	} [jump@cmd orgs delete]

	private update {
	    section Organizations
	    description {
		Change one or more attributes of an organization in a single call.
	    }
	    use .login
	    use .v2
	    option quota {
		Name of the quota plan to use in the organization.
	    } {
		argument name
		validate [call@vtype quotaname]
	    }
	    option default {
		Make the organization the default for users without explicit organization.
		The previous default organization is automatically reset.
	    } { }

	    option newname {
		A new name to give to the organization.
	    } {
		argument name
		validate [call@vtype notorgname]
	    }
	    input name {
		Name of the organization to update.
		If not specified the user is asked interactively (menu).
	    } {
		optional
		validate [call@vtype orgname]
		generate [call@mgr corg select-for update]
	    }
	}  [jump@cmd orgs update]

	private set-quota {
	    section Organizations
	    description {
		Set the quotas for the current or named organization.
		This is a Stackato 3 specific command.
	    }
	    use .login
	    use .v2
	    input name {
		Name of the organization to set the quota for.
		If not specified the user is asked interactively (menu).
	    } {
		optional
		validate [call@vtype orgname]
		generate [call@mgr corg select-for {link to the quota}]
	    }
	    input quota {
		Name of the quota plan to use in the organization.
	    } {
		validate [call@vtype quotaname]
	    }
	} [jump@cmd orgs set-quota]

	private switch {
	    section Organizations
	    description {
		Switch the current organization to the named organization.
		This invalidates the current space.
		This is a Stackato 3 specific command.
	    }
	    use .login
	    use .v2
	    input name {
		Name of the organization to switch to, and make current
	    } {
		defered ;# backend intercepts validation failure for bespoke message
		optional
		validate [call@vtype orgname]
		generate [call@mgr corg select-for {switch to}]
	    }
	    state space {
		Fake. Slot for backend to handle space setup.
	    } {}
	} [jump@cmd orgs switch]

	private show {
	    section Organizations
	    description {
		Show the named organization's information.
		This is a Stackato 3 specific command.
	    }
	    use .json
	    use .login
	    use .v2
	    option full {
		Show more details.
	    } { presence }
	    input name {
		Name of the organization to display.
		Defaults to the current organization if not specified.
		Fails if there is no current organization.
	    } {
		# int.rep = v2org entity
		optional
		validate      [call@vtype orgname]
		generate      [call@mgr corg get-auto]
		when-complete [call@mgr corg setc]
	    }
	} [jump@cmd orgs show]

	private list {
	    section Organizations
	    description {
		List the available organizations.
		This is a Stackato 3 specific command.
	    }
	    use .json
	    use .login
	    use .v2
	    option full {
		Show more details.
	    } { presence }
	} [jump@cmd orgs list]

	private rename {
	    section Organizations
	    description {
		Rename the named organization.
		This is a Stackato 3 specific command.
	    }
	    use .login
	    use .v2
	    input name {
		Name of the organization to rename.
	    } {
		# int.rep = v2org entity
		optional
		validate [call@vtype orgname]
		generate [call@mgr corg select-for rename]
		# Interaction in generate, interact not complex
		# enough for menu.
	    }
	    input newname {
		The new name to give to the organization.
	    } {
		optional
		validate [call@vtype notorgname]
		interact "Enter new name: "
	    }
	} [jump@cmd orgs rename]
    }

    alias create-org = orgmgr create
    alias delete-org = orgmgr delete
    alias org        = orgmgr show
    alias orgs       = orgmgr list
    alias rename-org = orgmgr rename
    alias switch-org = orgmgr switch
    alias quota-org  = orgmgr set-quota
    alias update-org = orgmgr update

    # # ## ### ##### ######## ############# #####################
    ## CF v2 commands II: Spaces
    #
    ## Spaces are entities wholly within organizations, i.e. a means
    ## to structure an organization.
    #
    ## Names are only unique within the organization. To fully
    ## identify a space the containing organization has to be known
    ## also.
    #
    ## The commands in this section usually use either the specfied or
    ## the current organization as context for resolving space
    ## names. If no current org is known one is set, by either taking
    ## the one org the user is part of, or asking the user to choose
    ## the org to use.

    officer spacemgr {
	undocumented
	description {
	    Management of spaces.
	}

	officer quota {
	    undocumented
	    description { Management of the space quotas }

	    # General space quota options.
	    common .sqd {
		option paid-services-allowed {
		    Applications can use non-free services.
		} { default true } ;# boolean

		option services {
		    Limit for the number of services in the quota.
		} {
		    alias s
		    argument num
		    default 100
		    validate [call@vtype integer0]
		}

		option routes {
		    Limit for the number of routes in the quota.
		} {
		    alias r
		    argument num
		    default 1000
		    validate [call@vtype integer0]
		}

		option mem {
		    Amount of memory applications can use.

		    Use the suffices 'M' and 'G' for the convenient specification
		    of mega- and gigabytes. Without a unit-suffix mega-bytes are
		    assumed. As the base-unit megabytes must specified as integers.
		    Gigabytes can be specified as fractions.

		    Also accepts -1 and "unlimited" for unlimited memory.
		} {
		    alias m
		    default 2048
		    validate [call@vtype memspecplus]
		}

		option instance-mem {
		    Amount of memory application instances can use.

		    Use the suffices 'M' and 'G' for the convenient specification
		    of mega- and gigabytes. Without a unit-suffix mega-bytes are
		    assumed. As the base-unit megabytes must specified as integers.
		    Gigabytes can be specified as fractions.

		    Also accepts -1 and "unlimited" for unlimited memory.
		} {
		    alias i
		    default 2048
		    validate [call@vtype memspecplus]
		}
	    }

	    private list {
		section Administration {Space Quotas}
		description {
		    List the space quotas owned by the current or
		    specified organization, or all.
		    This is a Stackato 3.4.2 command.
		}
		use .login
		use .post34
		use .json
		use .autocurrentorg
		option all {
		    Show all space quotas instead
		} {
		    presence
		    # combine - exclude --organisation
		    when-set [touch? @space_auto off]
		}
		option full {
		    Show all information about the space-quota.
		} { presence }
	    } [jump@cmd spacequotas list]

	    private show {
		section Administration {Space Quotas}
		description {
		    Show the details of the named space quota.
		    If not specified it will be asked for interactively (menu).
		    This is a Stackato 3.4.2 command.
		}
		use .login
		use .post34
		use .json
		input name {
		    Name of the quota plan to display.
		} {
		    # int.rep = v2/space_quota_definition entity
		    optional
		    validate      [call@vtype spacequota]
		    generate      [call@cmd spacequotas select-for display]
		}
	    } [jump@cmd spacequotas show]

	    private create {
		section Administration {Space Quotas}
		description {
		    Create a new space quota. It will be owned by
		    the current or specified organization.
		    This is a Stackato 3.4.2 command.
		}
		use .login
		use .post34
		use .autocurrentorg
		use .sqd
		input name {
		    The name of the new space quota.
		    If not specified it will be asked for interactively.
		} {
		    optional
		    validate [call@vtype notspacequota]
		    interact
		}
	    } [jump@cmd spacequotas create]

	    private update {
		section Administration {Space Quotas}
		description {
		    Modify the named space quota.
		    This is a Stackato 3.4.2 command.
		}
		use .login
		use .post34
		use .sqd
		input name {
		    The name of the space quota to modify
		    If not specified it will be asked for interactively (menu).
		} {
		    optional
		    validate [call@vtype spacequota]
		    generate [call@cmd spacequotas select-for update]
		    # Interaction in generate, interact not complex
		    # enough for menu.
		}
	    } [jump@cmd spacequotas update]

	    private delete {
		section Administration {Space Quotas}
		description {
		    Delete the named space quota.
		    This is a Stackato 3.4.2 command.
		}
		use .login
		use .post34
		input name {
		    Name of the space quota to delete.
		    If not specified it will be asked for interactively (menu).
		} {
		    # int.rep = v2/space_quota_definition entity
		    optional
		    validate [call@vtype spacequota]
		    generate [call@cmd spacequotas select-for delete]
		    # Interaction in generate, interact not complex
		    # enough for menu.
		}
	    } [jump@cmd spacequotas delete]

	    private rename {
		section Administration {Space Quotas}
		description {
		    Rename the named space quota.
		    This is a Stackato 3.4.2 command.
		}
		use .login
		use .post34
		input name {
		    Name of the space quota to rename.
		    If not specified it will be asked for interactively (menu).
		} {
		    # int.rep = v2/space_quota_definition entity
		    optional
		    validate [call@vtype spacequota]
		    generate [call@cmd spacequotas select-for rename]
		    # Interaction in generate, interact not complex
		    # enough for menu.
		}
		input newname {
		    The new name to give to the space quota.
		} {
		    #optional
		    validate [call@vtype notspacequota]
		    #interact "Enter new name: "
		}
	    } [jump@cmd spacequotas rename]

	    private setq {
		section Administration {Space Quotas}
		description {
		    Assign the specified space quota to the current or
		    specified space. This is a Stackato 3.4.2 command.
		}
		use .login
		use .post34
		use .autocurrentspace
		input name {
		    Name of the space quota to assign to the space.
		} {
		    optional
		    validate [call@vtype spacequota]
		    generate [call@cmd spacequotas select-for add]
		}
	    } [jump@cmd spacequotas setq]

	    private unsetq {
		section Administration {Space Quotas}
		description {
		    Drop the space quota from the current or specified space.
		    This is a Stackato 3.4.2 command.
		}
		use .login
		use .post34
		use .autocurrentspace
	    } [jump@cmd spacequotas unsetq]
	}

	private create {
	    section Spaces
	    description {
		Create a new space.
		This is a Stackato 3 specific command.
	    }
	    use .login
	    use .v2
	    use .autocurrentorg
	    option developer {
		Add yourself to the new space, as developer.
		Done by default.
	    } { default yes }

	    option manager {
		Add yourself to the new space, as manager.
		Done by default.
	    } { default yes }

	    option auditor {
		Add yourself to the new space, as auditor.
		By request.
	    } { default no }

	    option activate {
		Switch the current space to the newly created one.
		Done by default.
	    } { default yes }

	    # activate is our equivalent of cf create-space --target.
	    # we can't use --target, because that is already in use as
	    # common option to use a once-off CC target.

	    option default {
		Make the space the default for users without explicit space.
		The previous default space is automatically reset.
		The spaces' organization is implicitly made the default as well.
	    } { presence }

	    input name {
		Name of the space to create.
	    } {
		optional
		validate [call@vtype notspacename]
		interact
	    }
	} [jump@cmd spaces create]

	private delete {
	    section Spaces
	    description {
		Delete the named space.
		This is a Stackato 3 specific command.
	    }
	    use .login
	    use .v2
	    use .autocurrentorg
	    use .recursive
	    #
	    # TODO: spacemgr delete
	    # TODO --warn bool,          default ??  - Show warning when the last space is deleted
	    #
	    input name {
		Name of the space to delete.
	    } {
		optional
		validate [call@vtype spacename]
		generate [call@mgr cspace select-for delete]
		# Interaction in generate, interact not complex
		# enough for menu.
	    }
	} [jump@cmd spaces delete]

	private switch {
	    section Spaces
	    description {
		Switch from the current space to the named space.
		This may switch the organization as well.
		This is a Stackato 3 specific command.
	    }
	    use .login
	    use .v2
	    use .autocurrentorg
	    input name {
		Name of the space to switch to, and make current
	    } {
		defered ;# backend intercepts validation failure for bespoke message
		optional
		validate [call@vtype spacename]
		generate [call@mgr cspace select-for {switch to}]
	    }
	} [jump@cmd spaces switch]

	private show {
	    section Spaces
	    description {
		Show the named space's information.
		This is a Stackato 3 specific command.
	    }
	    use .json
	    use .login
	    use .v2
	    use .autocurrentorg
	    option full {
		Show more details.
	    } { presence }
	    input name {
		Name of the space to display.
	    } {
		optional
		validate      [call@vtype spacename]
		generate      [call@mgr cspace get-auto]
		when-complete [call@mgr cspace setc]
	    }
	} [jump@cmd spaces show]

	private list {
	    section Spaces
	    description {
		List the available spaces in the specified organization.
		See --organization for details
		This is a Stackato 3 specific command.
	    }
	    use .json
	    use .login
	    use .v2
	    # # ## ### ##### ######## inlined .autocurrentorg - slightly changed help, spec
	    option organization {
		The name of the organization to use as context.

		Defaults to the current organization.

		A current organization is automatically set if there is none,
		either by taking the one organization the user has, or
		asking the user to choose among the possibilities.

		Cannot be used together with --all.
	    } {
		argument name
		alias o
		when-set      [disallow @all]
		validate      [call@vtype orgname]
		generate      [call@mgr corg get-auto]
		when-complete [call@mgr corg setc]
		#Note: automatic definition of a current org when not defined.
	    }
	    state org_auto {
		State queried by get-auto to discern if the automatic is temporarily disabled.
	    } { validate boolean ; default true }
	    # # ## ### ##### ########
	    option full {
		Show more details.
	    } { presence }
	    option all {
		Show all spaces across all organizations.
	    } {
		presence
		when-set [disallow @organization]
		when-set [touch @org_auto off]
	    }
	} [jump@cmd spaces list]

	private rename {
	    section Spaces
	    description {
		Rename the named space.
		This is a Stackato 3 specific command.
	    }
	    use .login
	    use .v2
	    use .autocurrentorg
	    input name {
		Name of the space to rename.
	    } {
		optional
		validate [call@vtype spacename]
		generate [call@mgr cspace select-for rename]
		# Interaction in generate, interact not complex
		# enough for menu.
	    }
	    input newname {
		The new name to give to the space.
	    } {
		optional
		validate [call@vtype notspacename]
		interact "Enter new name: "
	    }
	} [jump@cmd spaces rename]

	private update {
	    section Spaces
	    description {
		Change one or more attributes of a space in a single call.
	    }
	    use .login
	    use .v2
	    use .autocurrentorg

	    option default {
		Make the space the default for users without explicit space.
		The previous default space is automatically reset.
		The spaces' organization is implicitly made the default as well.
	    } { }

	    option newname {
		A new name to give to the space.
	    } {
		argument name
		validate [call@vtype notspacename]
	    }
	    input name {
		Name of the space to update.
		If not specified the user is asked interactively (menu).
	    } {
		optional
		validate [call@vtype spacename]
		generate [call@mgr cspace select-for update]
	    }
	}  [jump@cmd spaces update]
    }

    alias create-space = spacemgr create
    alias delete-space = spacemgr delete
    alias space        = spacemgr show
    alias spaces       = spacemgr list
    alias rename-space = spacemgr rename
    alias switch-space = spacemgr switch
    alias update-space = spacemgr update

    alias space-quotas       = spacemgr quota list
    alias space-quota        = spacemgr quota show
    alias create-space-quota = spacemgr quota create
    alias rename-space-quota = spacemgr quota rename
    alias update-space-quota = spacemgr quota update
    alias delete-space-quota = spacemgr quota delete
    alias set-space-quota    = spacemgr quota setq
    alias unset-space-quota  = spacemgr quota unsetq

    # # ## ### ##### ######## ############# #####################
    ## CF v2 commands III: Routes
    #
    ## Routes, and Domains specify the urls an application is mapped to.
    ## Routes are a component of spaces, associated with applications,
    ## similar to service-bindings.

    officer routemgr {
	undocumented
	description {
	    Management of routes.
	}

	private delete {
	    section Routes
	    description {
		Delete the named route.
		This is a Stackato 3 specific command.
	    }
	    use .login
	    use .v2
	    use .autocurrentspace
	    input name {
		Name of the route to delete.
		This is expected to be host + domain.
		Cannot be used together with --unused, nor --all.
	    } {
		list ; optional
		validate [call@vtype routename]
		when-set [disallow @unused]
		when-set [disallow @all]
	    }
	    option unused {
		Delete all routes which are not used by any application.
		Cannot be used together with named routes.
	    } {
		presence
		when-set [disallow @name]
	    }
	    option all {
		Operate --unused across all domains.
		Cannot be used together with named routes.
	    } {
		presence
		when-set [disallow @name]
		when-set [touch @space_auto off]
	    }
	} [jump@cmd routes delete]

	private list {
	    section Routes
	    description {
		List all available routes in the specified space, or all.
		This is a Stackato 3 specific command.
	    }
	    use .json
	    use .login
	    use .v2
	    # # ## ### ##### ######## inlined .autocurrentorg - slightly changed help.
	    option organization {
		The name of the organization to use as context.
		Defaults to the current organization.

		A current organization is automatically set if there is none,
		either by taking the one organization the user has, or
		asking the user to choose among the possibilities.

		Cannot be used together with --all.
	    } {
		argument name
		alias o
		when-set      [disallow @all]
		validate      [call@vtype orgname]
		generate      [call@mgr corg get-auto]
		when-complete [call@mgr corg setc]
		#Note: automatic definition of a current org when not defined.
	    }
	    state org_auto {
		State queried by get-auto to discern if the automatic is temporarily disabled.
	    } { validate boolean ; default true }
	    # # ## ### ##### ######## inlined .autocurrentspace - slightly changed help.
	    # Space context (s 3.0)
	    option space {
		The name of the space to use as context.
		Defaults to the current space.

		A current space is automatically set if there is none,
		either by taking the one space the user has, or
		asking the user to choose among the possibilities.

		Cannot be used together with --all.
	    } {
		argument name
		when-set      [disallow @all]
		validate      [call@vtype spacename]
		generate      [call@mgr cspace get-auto]
		when-complete [call@mgr cspace setc]
		#Note: automatic definition of a current space when not defined.
	    }
	    state space_auto {
		State queried by get-auto to discern if the automatic is temporarily disabled.
	    } {
		validate boolean ; default true
		when-set [touch @org_auto off]
	    }
	    # # ## ### ##### ######## end inlines
	    option all {
		Query information about all domains.
		Cannot be used together with a space.
	    } {
		presence
		when-set [disallow @space]
		when-set [disallow @organization]
		when-set [touch @space_auto off]
	    }
	    option unused {
		Filter output to show only the routes which are not used by any application.
	    } {	presence }
	} [jump@cmd routes list]
    }

    alias delete-route = routemgr delete
    alias routes       = routemgr list

    # # ## ### ##### ######## ############# #####################
    ## CF v2 commands IV: Domains
    #
    ## Routes, and Domains specify the urls an application is mapped to.
    ## Domains are a top-level entity which can be associated with many
    ## spaces and applications, through routes.

    officer domainmgr {
	undocumented
	description {
	    Management of domains.
	}

	private map {
	    section Domains
	    description {
		Add the named domain to an organization or space.
		This is a Stackato 3 specific command.
		This command is not supported by Stackato 3.2 or higher.
	    }
	    use .login
	    use .v2
	    use .pre31
	    use .autocurrentspace
	    input name {
		Name of the domain to add
	    } {
		#validate [call@vtype notdomainname]
		#generate [call@mgr cdomain select-for map]
		# Interaction in generate, interact not complex
		# enough for menu.
	    }
	} [jump@cmd domains map]

	private unmap {
	    section Domains
	    description {
		Remove the named domain from an organization or space.
		This is a Stackato 3 specific command.
		This command is not supported by Stackato 3.2 or higher.
	    }
	    use .login
	    use .v2
	    use .pre31
	    use .autocurrentspace
	    input name {
		Name of the domain to remove
	    } {
		#validate [call@vtype domainname]
		#generate [call@mgr croute select-for delete]
		# Interaction in generate, interact not complex
		# enough for menu.
	    }
	} [jump@cmd domains unmap]

	private create {
	    section Domains
	    description {
		Create a new domain.
		This is a Stackato 3.2+ specific command.
	    }
	    use .login
	    use .v2
	    use .post30
	    use .autocurrentorg
	    option shared {
		Mark the new domain as shared by all organizations.
		If not present the new domain will be owned by and
		private to the current or specified organization.
	    } { presence }
	    input name {
		Name of the domain to create
	    } {
		#validate [call@vtype notdomainname]
	    }
	} [jump@cmd domains create]

	private delete {
	    section Domains
	    description {
		Delete the named domain.
		This is a Stackato 3.2+ specific command.
	    }
	    use .login
	    use .v2
	    use .post30
	    input name {
		Name of the domain to delete
	    } {
		#validate [call@vtype domainname]
		#generate [call@cmd domains select-for delete]
		# Interaction in generate, interact not complex
		# enough for menu.
	    }
	} [jump@cmd domains delete]

	private list {
	    section Domains
	    description {
		List the available domains in the specified space, or all.
		This is a Stackato 3 specific command.
	    }
	    use .login
	    use .v2
	    use .json
	    # # ## ### ##### ######## inlined .autocurrentorg - slightly changed help, spec
	    option organization {
		The name of the organization to use as context.
		Defaults to the current organization.
		Note: This is specific to Stackato 3.2 and higher.

		A current organization is automatically set if there is none,
		either by taking the one organization the user has, or
		asking the user to choose among the possibilities.

		Cannot be used together with --all.
	    } {
		argument name
		alias o
		when-set      [disallow @all]
		validate      [call@vtype orgname]
		generate      [call@mgr corg get-auto]
		when-complete [call@mgr corg setc]
		#Note: automatic definition of a current org when not defined.
	    }
	    state org_auto {
		State queried by get-auto to discern if the automatic is temporarily disabled.
	    } { validate boolean ; default true }
	    # # ## ### ##### ######## inlined .autocurrentspace - slightly changed help.
	    # Space context (s 3.0)
	    option space {
		The name of the space to use as context.
		Defaults to the current space.
		Note: This is specific to Stackato 3.0

		A current space is automatically set if there is none,
		either by taking the one space the user has, or
		asking the user to choose among the possibilities.

		Cannot be used together with --all.
	    } {
		argument name
		when-set      [disallow @all]
		validate      [call@vtype spacename]
		generate      [call@mgr cspace get-auto-s30]
		when-complete [call@mgr cspace setc]
		#Note: automatic definition of a current space when not defined.
	    }
	    state space_auto {
		State queried by get-auto to discern if the automatic is temporarily disabled.
	    } {
		validate boolean ; default true
		when-set [touch @org_auto off]
	    }
	    # # ## ### ##### ######## end inlines
	    option all {
		Query information about all domains.
		Cannot be used together with a space.
	    } {
		presence
		when-set [disallow @space]
		when-set [disallow @organization]
		when-set [touch @space_auto off]
	    }
	} [jump@cmd domains list]
    }

    # check how this works with (un)map commands.
    alias create-domain = domainmgr create
    alias delete-domain = domainmgr delete
    alias map-domain    = domainmgr map
    alias unmap-domain  = domainmgr unmap
    alias domains       = domainmgr list

    # # ## ### ##### ######## ############# #####################
    ## CF v2 commands V: Quota plans

    officer quota {
	description {
	    Management of quota plans.
	}

	# General quota options.
	# See also common .limits for the CFv1 groups-related limits.
	common .qd {
	    option paid-services-allowed {
		Applications can use non-free services.
	    } { default true } ;# boolean

	    option trial-db-allowed {
		Applications can use trial databases.
		Before Stackato 3.4 only.
	    } {
		when-set [call@mgr client max-version-opt 3.2]
		;# boolean
	    }

	    option services {
		Limit for the number of services in the quota.
	    } {
		argument num
		default 100
		validate [call@vtype integer0]
	    }

	    option routes {
		Limit for the number of routes in the quota.
		This is a Stackato 3.2+ specific setting.
	    } {
		argument num
		default 1000
		validate [call@vtype integer0]
	    }

	    option mem {
		Amount of memory applications can use.

		Use the suffices 'M' and 'G' for the convenient specification
		of mega- and gigabytes. Without a unit-suffix mega-bytes are
		assumed. As the base-unit megabytes must specified as integers.
		Gigabytes can be specified as fractions.
	    } {
		default 2048
		validate [call@vtype memspec]
	    }

	    option allow-sudo {
		Applications can use sudo in their container.
	    } ;# boolean

	    option droplets {
		Limit for the number of droplets per application
		that are stored (older droplets that exceed this
		quota are removed and their associated versions
		can no longer be restored).
		This is a Stackato 3.4+ specific setting.
	    } {
		argument num
		validate [call@vtype integer0]
	    }
	}

	private create {
	    section Administration Quotas
	    description {
		Create a new quota plan.
		This is a Stackato 3 specific command.
	    }
	    use .login
	    use .v2
	    use .qd
	    input name {
		Name of the quota plan to create.
		If not specified it will be asked for interactively.
	    } {
		optional
		validate [call@vtype notquotaname]
		interact
	    }
	} [jump@cmd quotas create]

	private configure {
	    section Administration Quotas
	    description {
		Reconfigure the named quota plan.
		This is a Stackato 3 specific command.
	    }
	    use .login
	    use .v2
	    use .qd
	    input name {
		Name of the quota plan to configure.
		If not specified it will be asked for interactively (menu).
	    } {
		optional
		validate [call@vtype quotaname]
		generate [call@cmd quotas select-for configure]
		# Interaction in generate, interact not complex
		# enough for menu.
	    }
	} [jump@cmd quotas configure]

	private delete {
	    section Administration Quotas
	    description {
		Delete the named quota plan.
		This is a Stackato 3 specific command.
	    }
	    use .login
	    use .v2
	    input name {
		Name of the quota plan to delete.
		If not specified it will be asked for interactively (menu).
	    } {
		# int.rep = v2quota_definition entity
		optional
		validate [call@vtype quotaname]
		generate [call@cmd quotas select-for delete]
		# Interaction in generate, interact not complex
		# enough for menu.
	    }
	} [jump@cmd quotas delete]

	private list {
	    section Administration Quotas
	    description {
		List the available quota plans.
		This is a Stackato 3 specific command.
	    }
	    use .json
	    use .login
	    use .v2
	} [jump@cmd quotas list]

	private rename {
	    section Administration Quotas
	    description {
		Rename the named quota plan.
		This is a Stackato 3 specific command.
	    }
	    use .login
	    use .v2
	    input name {
		Name of the quota plan to rename.
		If not specified it will be asked for interactively (menu).
	    } {
		# int.rep = v2quota_definition entity
		optional
		validate [call@vtype quotaname]
		generate [call@cmd quotas select-for rename]
		# Interaction in generate, interact not complex
		# enough for menu.
	    }
	    input newname {
		The new name to give to the quota plan.
	    } {
		#optional
		validate [call@vtype notquotaname]
		#interact "Enter new name: "
	    }
	} [jump@cmd quotas rename]

	private show {
	    section Administration Quotas
	    description {
		Show the details of the named quota plan.
		If not specified it will be asked for interactively (menu).
		This is a Stackato 3 specific command.
	    }
	    use .json
	    use .login
	    use .v2
	    input name {
		Name of the quota plan to display.
	    } {
		# int.rep = v2quota_definition entity
		optional
		validate      [call@vtype quotaname]
		generate      [call@cmd quotas select-for display]
	    }
	} [jump@cmd quotas show]
    }

    #alias create-quota = quota create
    #alias delete-quota = quota delete
    #alias quota        = quota show
    alias quotas       = quota list
    #alias rename-quota = quota rename

    officer buildpack {
	undocumented
	description {
	    Management of admin buildpacks.
	}

	common .bp {
	    use .login
	    use .v2
	    use .post32
	    section Administration Buildpacks
	}

	common .bpconfig {
	    option position {
		Location of the buildpack in the sequence used
		to check them during auto-detection.
	    } {
		alias P
		validate [call@vtype integer0]
		default -1
	    }

	    # Series of presence options to match 'cf' cli. Use drives
	    # the hidden state below as the known API, and merging the
	    # information.
	    option lock {
		Lock the buildpack against modification.
	    } { presence
		when-set [disallow @unlock]
		when-set [touch @locked yes]
	    }
	    option unlock {
		Unlock the buildpack, allow changes again.
	    } { presence
		when-set [disallow @lock]
		when-set [touch @locked no]
	    }
	    option enable {
		Enable use of the buildpack.
	    } { presence
		when-set [disallow @disable]
		when-set [touch @enabled yes]
	    }
	    option disable {
		Disable the buildpack, prevent its use.
	    } { presence
		when-set [disallow @enable]
		when-set [touch @enabled no]
	    }

	    # API to the backend, driven by the presence options above.
	    state enabled {
		Whether the buildpack will be used for staging or not.
	    } { validate boolean }
	    state locked {
		Whether the buildpack can be modified or not.
	    } { validate boolean }

	    option keep-form {
		Path to a file to keep the whole uploaded multipart/formdata
		under after upload, for inspection.
	    } {
		argument path
		undocumented
		validate [call@vtype path rwfile]
		default {}
	    }
	    option keep-zip {
		Path to a file to keep the whole uploaded zip file
		under after upload, for inspection.
	    } {
		argument path
		undocumented
		validate [call@vtype path rwfile]
		default {}
	    }
	}

	private list {
	    description {
		Show all buildpacks known to the target, in the
		order they are checked in during auto-detection.
	    }
	    use .bp
	    use .json
	} [jump@cmd buildpacks list]

	private create {
	    description {
		Add a buildpack to the target.
	    }
	    use .bp
	    use .bpconfig
	    input name {
		Name of the new buildpack.
	    } {
		validate [call@vtype notbuildpack]
	    }
	    input zip {
		Path or url of the zip file containing the implementation of the buildpack.
		Accepts the path to a local directory as well, which will become the zip file to upload.
	    } {
		label zip|url|dir
		#validate [call@vtype path rfile];# validation in backend.
	    }
	} [jump@cmd buildpacks create]

	private lock {
	    description {
		Lock the specified buildpack against changes.
	    }
	    use .bp
	    input name {
		Name of the buildpack to lock against changes.
	    } {
		optional
		validate [call@vtype buildpack]
		generate [call@cmd buildpacks select-for lock]
	    }
	    
	} [jump@cmd buildpacks lock]

	private unlock {
	    description {
		Allow changes of the specified buildpack.
	    }
	    use .bp
	    input name {
		Name of the buildpack to allow changes for.
	    } {
		optional
		validate [call@vtype buildpack]
		generate [call@cmd buildpacks select-for lock]
	    }
	    
	} [jump@cmd buildpacks unlock]

	private rename {
	    description {
		Change the name of the specified buildpack.
	    }
	    use .bp
	    input name {
		Name of the buildpack to rename.
	    } {
		optional
		validate [call@vtype buildpack]
		generate [call@cmd buildpacks select-for rename]
	    }
	    input newname {
		New name of the buildpack.
	    } {
		optional
		validate [call@vtype notbuildpack]
		interact "Enter new name: "
	    }
	} [jump@cmd buildpacks rename]

	private update {
	    description {
		Change the information known about the specified buildpack.
	    }
	    use .bp
	    use .bpconfig
	    option zip {
		Path or url of the new zip file containing the implementation of the buildpack.
		Accepts the path to a local directory as well, which will become the zip file to upload.
	    } {
		argument zip|url|dir
		validate str
		#validate [call@vtype path rfile];# validation in backend.
	    }
	    input name {
		Name of the buildpack to update.
	    } {
		optional
		validate [call@vtype buildpack]
		generate [call@cmd buildpacks select-for update]
	    }
	} [jump@cmd buildpacks update]

	private delete {
	    description {
		Remove the specified buildpack from the target.
	    }
	    use .bp
	    input name {
		Name of the buildpack to remove.
	    } {
		optional
		validate [call@vtype buildpack]
		generate [call@cmd buildpacks select-for delete]
	    }
	} [jump@cmd buildpacks delete]
    }

    alias buildpacks       = buildpack list
    alias create-buildpack = buildpack create
    alias rename-buildpack = buildpack rename
    alias update-buildpack = buildpack update
    alias delete-buildpack = buildpack delete
    
    # # ## ### ##### ######## ############# #####################
    ## New feature. Script execution by the client.

    private do {
	undocumented
	description {
	    Execute the Tcl script with embedded client commands.
	}
	use .verbose
	option trusted {
	    By default the script is run in a safe interpreter.
	    When specifying this option an unrestricted interpreter
	    will be used instead.
	} { presence }
	input script {
	    The path to the script file to run.
	} { validate [call@vtype path rfile] }
    } [jump@cmd do it]

    # # ## ### ##### ######## ############# #####################
    ## Help :: Automatic by cmdr
    # # ## ### ##### ######## ############# #####################
}

# # ## ### ##### ######## ############# #####################
## Dynamically create commands for the aliases which map them to
## their resolved command prefixes.

## TODO: mgr::alias should prevent user from overriding existing commands.
## TODO: Alternative: Create mechanism allowing override and chaining.
## TODO: Recognize and catch alias loops.

proc mapalias {cmd} {
    lambda {cmd config} {
	# Modify the command line and feed it back to the main
	# dispatcher. Note: The definition of the @args parameter (see
	# (#alias) below) prevented any processing on it, defering all the
	# checks to the mapped command.

	# Clear prefix information, we are starting a new command here.
	$config context unset-all *prefix*
	stackato-cli do {*}$cmd {*}[$config @args]
    } $cmd
}

apply {{} {
    dict for {name cmd} [stackato::mgr alias known] {
	stackato-cli learn [subst -nocommand -nobackslashes {
	    private {$name} {
		description { Alias for "$cmd". }
		# (#alias)
		input args {
		    Additional arguments for the mapped command.
		} {
		    list ; optional ; test
		    # Note: Using test mode here prevents any
		    # (out-of-order) option processing. This is
		    # defered to the command the alias maps to.
		}
	    } [::mapalias {$cmd}]
	}]
    }
}}

# # ## ### ##### ######## ############# #####################
## Helper commands. Redirection into command packages and classes.

# Shortcuts for creating command callbacks.

proc run {body args} {
    lambda config $body {*}$args
}

proc jump@cmd {package args} {
    lambda {package cmd config args} {
	package require stackato::cmd::$package
	debug.cmdr {[$config dump]}
	::stackato::cmd $package {*}$cmd $config {*}$args
	# Transient settings of the various managers are reset within
	# the ehandler, i.e. ::stackato::mgr::exit::attempt
    } $package $args
}

# These helpers are for callbacks, i.e. generate, validate, when-complete, and when-set.

proc call@cmd   {package args} { jump@ stackato::cmd::$package      $args }
proc call@mgr   {package args} { jump@ stackato::mgr::$package      $args }
proc call@vtype {package args} { jump@ stackato::validate::$package $args }

proc jump@ {package cmd} {
    lambda {package cmd args} {
	package require $package
	${package} {*}$cmd {*}$args
    } $package $cmd
}

# # ## ### ##### ######## ############# #####################
## Notes:

# # ## ### ##### ######## ############# #####################
## Ready. Vendor (VMC) version tracked: 0.3.14.
package provide stackato::cmdr 3.2.3
