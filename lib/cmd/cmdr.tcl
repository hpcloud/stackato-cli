# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require cmdr 0.5 ;# defered/immediate + section (help category setup).
package require cmdr::help
package require lambda
package require try
package require tty
package require stackato::color
package require stackato::log
package require stackato::mgr::alias
package require stackato::mgr::exit

debug level  cmdr
debug prefix cmdr {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Global configuration package. This can fail when our current
## working directory was pulled out from under us.

try {
    package require stackato::mgr::cfile

} trap {POSIX ENOENT} {e o} {
    if {[string match {*error getting working directory name*} $e]} {
	if {[tty stdout]} {
	    stackato::color colorize
	}
        stackato::log to stdout
	stackato::log say [stackato::color red {Unable to run client from a deleted directory}]
	::exit 1
    }
    return {*}$o $e
} finally {
    if {[tty stdout]} {
	stackato::color colorize
    }
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

cmdr create stackato-cli stackato {
    description {
	The command line client
    }

    # # ## ### ##### ######## ############# #####################
    ## The error handler interposed command line parsing and execution.
    ## Converts various problems into simple error messages instead
    ## of considering them as internal errors.

    ehandler ::stackato::mgr::exit::attempt

    # # ## ### ##### ######## ############# #####################
    ## The -debug option is provided to and handled by all commands.

    common *all* {
	# Note: By dint of being in *all* this option is declared
	#       before anything else, ensuring that the debug levels
	#       are set before all other parameters too.
	option debug {
	    Activate client internal tracing.
	} {
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
	}
    }

    # # ## ### ##### ######## ############# #####################
    ## Common option for commands allowing interactive input, to
    ## disable this possibility. Made available to all users through
    ## the cmdr framework flag.

    common .prompt {
	# Moved to *all*
    }

    common .verbose {
	option verbose { More verbose operation. } { presence }
    }

    common .v2 {
	state checkv2 {
	    Invisible state argument checking that the chosen target
	    supports the CF v2 API. Use in commands which are v2 only.
	    Note: Requires proper client arguments coming before it.
	} { immediate ; generate [call@mgr client isv2cmd] }
    }
    common .v1 {
	state checkv1 {
	    Invisible state argument checking that the chosen target
	    supports the CF v1 API. Use in commands which are v1 only.
	    Note: Requires proper client arguments coming before it.
	} { immediate ; generate [call@mgr client notv2cmd] }
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
	    validate      [call@vtype path    rfile]
	    generate      [call@mgr   cfile   getc token]
	    when-complete [call@mgr   targets set-path]
	    when-set      [call@mgr   targets set-path]
	}
    }

    common .target {
	option target {
	    The once-off target to use for the current operation.
	} {
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
	    This is a stackato V1 option.
	} {
	    generate      [call@mgr cgroup getc]
	    when-complete [call@mgr cgroup setc]
	    # Priority order (first to last taken):
	    # (1) --group
	    # (2) $STACKATO_GROUP
	    # (3) $HOME/.stackato/client/group
	    # See also mgr/cgroup.tcl: get, Load
	}
	# CF v2 API only. ====================================
	option organization {
	    The once-off organization to use for the current operation.
	    This is a stackato CF v2 option.
	} {
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
	    by name. This is a stackato CF v2 option.
	    Cannot be used together with --space-guid.
	} {
	    when-set      [exclude space-guid --space]
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
	    by guid. This is a stackato CF v2 option.
	    Cannot be used together with --space.
	} {
	    when-set      [exclude space --space-guid]
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
	    validate [call@vtype path rfile]
	    default {}
	    # Using 'generate' here instead of 'default' because the
	    # default value gets validated, whereas the result of
	    # generate is considered valid by definition.
	}
	option path {
	    Path of the directory holding the application files to push.
	    Defaults to the current working directory.
	} {
	    validate [call@vtype path rdir]
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

    common .tail {
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
	} { validate [call@vtype integer0] }

	option appuris {
	    Limit for the number of mapped uris per application.
	} { validate [call@vtype integer0] }

	option services {
	    Limit for the number of services in the group.
	} { validate [call@vtype integer0] }

	option sudo {
	    Applications can use sudo (or not).
	} ;# boolean

	option drains {
	    Limit for the number of drains in the group.
	} { validate [call@vtype integer0] }

	option mem {
	    Amount of memory applications can use.
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
	    # int.rep = v2org entity
	    alias o
	    validate      [call@vtype orgname]
	    generate      [call@mgr corg get-auto]
	    when-complete [call@mgr corg setc]
	    #Note: automatic definition of a current org when not defined.
	}
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
	    validate      [call@vtype spacename]
	    generate      [call@mgr cspace get-auto]
	    when-complete [call@mgr cspace setc]
	    #Note: automatic definition of a current space when not defined.
	}
    }

    # From here on out, implement the command set in the new form.
    # # ## ### ##### ######## ############# #####################
    ## Various debugging helper commands.

    officer debug {
	undocumented
	description {
	    A collection of debugging aids.
	}

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
	    use .prompt
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
	    use .prompt
	    use .manifest
	    input version {
		The version of the target to generate the manifest for.
	    } { validate integer }
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
	} [jump@cmd query trace]

	private map-named-entity {
	    description {
		Map the specified name into a uuid, given the type.
	    }
	    use .prompt
	    use .json
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
		Run a raw rest request against the chosen target
	    }
	    use .login
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
	    use .prompt
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
	    use .prompt
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
	    use .prompt
	    use .dry
	    use .hostfile
	    input ipaddress {
		The IP-address to add.
	    } { validate str } ;# TODO ::stackato::ipaddress
	    input hosts {
		List of hostnames for the ip-address
	    } { list }
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
	    } { list ; optional }
	} [jump@cmd host remove]

	private update {
	    section Administration
	    description {
		Update the entry for the IP address
		with a new set of hostnames.
	    }
	    use .prompt
	    use .dry
	    use .hostfile
	    input ipaddress {
		The IP-address to modify.
	    } { validate str } ;# TODO ::stackato::ipaddress
	    input hosts {
		List of hostnames for the ip-address
	    } { list }
	} [jump@cmd host update]
    }}

    # # ## ### ##### ######## ############# #####################
    ## Current group management

    private group {
	section Administration
	description {
	    Report the current group, or (un)set it.
	}
	use .json
	use .login
	option reset {
	    Reset the current group to nothing.
	    Cannot be used together with name.
	} {
	    presence
	    when-set [exclude name --reset]
	}
	input name {
	    Name of the current group to use from now on.
	    Cannot be used together with --reset.
	} {
	    optional
	    when-set [exclude reset name]
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

    private target {
	section {Getting Started}
	description {
      Set the target API endpoint for the client, or report the current
      target.
	}
	use .prompt
	use .json
	use .verbose
	use .allow-http
	# CF v2 API only. ====================================
	option organization {
	    The organization to set as current for this target.
	    This is a stackato/CFv2 specific option.
	} {
	    alias o
	    #when-set [call@mgr client isv2]
	    #unable to check, no client here.
	    validate str
	    #validate [call@vtype orgname]
	    # We cannot fully validate as the target is not known yet.
	}
	option space {
	    The space to set as current for this target.
	    This is a stackato/CFv2 specific option.
	} {
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
	    }
	    use *introspection*
	    use .v1
	} [jump@cmd query runtimes]

	private services {
	    section Services
	    description {
		List the supported and provisioned services
		of the target.
	    }
	    use *introspection-group*
	} [jump@cmd servicemgr list-instances]

	private stacks {
	    section Administration
	    description {
		List the supported stacks of the target.
	    }
	    use *introspection*
	    use .v2
	} [jump@cmd query stacks]

	private service-plans {
	    section Services
	    description {
		List all available plans of the supported services.
	    }
	    use .login
	    use .v2
	} [jump@cmd servicemgr list-plans]

	private usage {
	    section Administration
	    description {
		Show the current memory allocation and usage
		of the active or specified user/group (CFv1),
		or the specified or current space (CFv2).
	    }
	    use *introspection-group*
	    option all {
		Query information about everything.
		Cannot be used together with userOrGroup.
	    } {
		presence
		when-set [exclude userOrGroup --all]
	    }
	    input userOrGroup {
		For a CFv1 target the name of the group to query the data for.
		For a CFv2 target this names the space to query instead.

		Cannot be used together with --all.

		For a CFv1 target it defaults to the current group if any, or user.
		For a CFv1 target it defaults to the current space.
	    } {
		optional
		when-set [exclude all userOrGroup]
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
	    use *introspection-group*
	} [jump@cmd query applications]

	private context {
	    undocumented
	    description {
		Show the current context (target, organization, and space)
	    }
	} [jump@cmd query context]
    }

    alias frameworks    = introspect frameworks
    alias info          = introspect general
    alias runtimes      = introspect runtimes
    alias services      = introspect services
    alias service-plans = introspect service-plans
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
	    section Administration
	    description {
		Add the named user to the specified group.
	    }
	    use .prompt
	    use .login
	    input group { The name of the group to add the user to. }
	    input user  { The name of the user to add to the group. }
	    # TODO: Validate group/user name (using target, client)
	} [jump@cmd groups add-user]

	private delete-user {
	    section Administration
	    description {
		Remove the named user from the specified group.
	    }
	    use .prompt
	    use .login
	    input group { The name of the group to remove the user from. }
	    input user  { The name of the user to remove from the group. }
	    # TODO: Validate group/user name (using target, client)
	} [jump@cmd groups delete-user]

	private create {
	    section Administration
	    description {
		Create a new group with the specified name.
	    }
	    use .prompt
	    use .login
	    input name { The name of the group to create. }
	    # TODO: Validate group name (using target, client)
	} [jump@cmd groups create]

	private delete {
	    section Administration
	    description {
		Delete the named group.
	    }
	    use .prompt
	    use .login
	    input name { The name of the group to delete. }
	    # TODO: Validate group name (using target, client)
	} [jump@cmd groups delete]

	private limits {
	    section Administration
	    description {
		Show and/or modify the limits applying to applications
		in the named group.
	    }
	    use .json
	    use .login
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
	    section Administration
	    description {
		Show the list of groups known to the target.
	    }
	    use .json
	    use .login
	} [jump@cmd groups show]

	private users {
	    section Administration
	    description {
		Show the list of users in the named group.
	    }
	    use .json
	    use .login
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
	    } { alias passwd ; validate str }
	}

	private add {
	    section Administration {User Management}
	    description {
		Register a new user in the current or specified target.
		This operation requires administrator privileges, except
		 if "allow_registration" is set server-side.
	    }
	    use .prompt
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
		This is a stackato/CFv1 specific option.
	    } {
		when-set [call@mgr client notv2]
		validate str
	    }
	    use .limits
	    # CF v2 API only. ====================================
	    option organization {
		The organization to place the new user into.
		Defaults to the current organization.
		This is a stackato/CFv2 specific option.
	    } {
		alias o
		when-set [call@mgr client isv2]
		validate [call@vtype orgname]
		generate [call@mgr corg get-auto]
	    }
	    # ====================================================
	    input name {
		The name of the user to create.
		(The user's email for a CFv1 target).
	    } {
		optional
		interact "User: "
		validate [call@vtype notusername]
	    }
	    option email {
		The email of the user to create.
		This is a stackato/CFv2 specific option.
	    } {
		validate str ;# future: maybe email regexp.
		when-set [call@mgr client isv2]
		#interact "Email: " - In the action callback itself.
	    }
	    # ====================================================
	} [jump@cmd usermgr add]

	private delete {
	    section Administration {User Management}
	    description {
    Delete the named user, and the user's applications and services from
    the current or specified target.
		This operation requires administrator privileges.
	    }
	    use .prompt
	    use .login-plain
	    input email {
		The name of the user to delete.
	    } {
		validate [call@vtype username]
	    }
	} [jump@cmd usermgr delete]

	private list {
	    section Administration {User Management}
	    description {
		Show the list of users known to the
		current or specified target.
	    }
	    use .json
	    use .login
	} [jump@cmd usermgr list]

	private token {
	    section Administration {User Management}
	    description {
		Interactively set authentication token.
	    }
	    use .token-file
	    use .target
	} [jump@cmd usermgr token]

	private login {
	    section {Getting Started}
	    description {
		Log in to the current or specified target with the named user.
	    }
	    use .prompt
	    use .login-plain
	    use .password
	    # CF v2 API only. ====================================
	    option organization {
		The organization to use.
		This is a stackato/CFv2 specific option.
		If not specified the user is asked interactively
		to choose an organization.
	    } {
		# NOTE: We cannot validate the org name from within
		# NOTE: the dispatcher. To get the proper list we
		# NOTE: we need a login, which is what we do not have
		# NOTE: right now and are working on getting with this
		# NOTE: command. So, defered to the command implementation.
		when-set [call@mgr client isv2]
		validate str
	    }
	    option space {
		The space (in the organization) to use.
		This is a stackato/CFv2 specific option.
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
		when-set [call@mgr client isv2]
		validate str
	    }
	    option ignore-missing {
		Disable errors generated for missing organization and/or space.
	    } { presence }
	    # CF v1 API only. ====================================
	    option group {
		The group to use for the login.
		This is a stackato/CFv1 specific option.
	    } {
		when-set [call@mgr client notv2]
		validate str
	    }
	    # ====================================================
	    input email {
		The name of the user to log in as.
	    } {
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
		when-set [exclude target --all]
	    }
	    input target {
		Name of the target to log out of.
		Defaults to the current target.
		Cannot be used together with --all.
	    } {
		optional
		when-set [exclude all target]
		generate [call@mgr ctarget getc]
	    }
	} [jump@cmd usermgr logout]

	private password {
	    section Administration {User Management}
	    description {
		Change the password of the current user in the
		current or specified target.
	    }
	    use .prompt
	    use .login-plain
	    option password {
		The new password. If not present it will be interactively
		asked for.
	    } { alias passwd ; validate str }
	} [jump@cmd usermgr password]

	private who {
	    section Administration
	    description {
    Show the name of the current user in the current or specified
    target.
	    }
	    use .json
	    use .login-plain
	} [jump@cmd usermgr who]

	private info {
	    section Administration
	    description {
		Shows the information of a user in the current
		or specified target. Defaults to the current user.
		Naming a specific user requires a CFv2 target.
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
	    input token {
		The token string to decode.
	    } { }
	} [jump@cmd usermgr decode-token]

	common .org-roles {
	    section Organizations
	    use .prompt
	    use .login
	    use .v2
	    option developer { Affect the developer role }       { presence }
	    option manager   { Affect the manager role }         { presence }
	    option billing   { Affect the billing manager role } { presence }
	    option auditor   { Affect the auditor role }         { presence }
	    input user {
		Name of the user to modify
	    } {
		validate [call@vtype username]
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
	    use .prompt
	    use .login
	    use .v2
	    option developer { Affect the developer role } { presence }
	    option manager   { Affect the manager role }   { presence }
	    option auditor   { Affect the auditor role }   { presence }
	    input user {
		Name of the user to modify
	    } {
		validate [call@vtype username]
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
		various roles. This is a CFv2 specific command
	    }
	    use .org-roles
	} [jump@cmd usermgr link-org]

	private link-space {
	    description {
		Add the specified user to the named space, in various
		roles. This is a CFv2 specific command
	    }
	    use .space-roles
	} [jump@cmd usermgr link-space]

	private unlink-org {
	    description {
		Remove the specified user from the named organization,
		in various roles. This is a CFv2 specific command
	    }
	    use .org-roles
	} [jump@cmd usermgr unlink-org]

	private unlink-space {
	    description {
		Remove the specified user from the named space, in
		various roles. This is a CFv2 specific command
	    }
	    use .space-roles
	} [jump@cmd usermgr unlink-space]
    }

    alias token       = usermgr token
    alias login       = usermgr login
    alias logout      = usermgr logout
    alias passwd      = usermgr password
    alias user        = usermgr who
    alias add-user    = usermgr add
    alias  add_user
    alias  create_user
    alias  create-user
    alias  register
    alias delete-user = usermgr delete
    alias  delete_user
    alias  unregister
    alias users       = usermgr list
    alias user-info   = usermgr info
    alias debug-token = usermgr decode-token

    alias link-user-org     = usermgr link-org
    alias link-user-space   = usermgr link-space
    alias unlink-user-org   = usermgr unlink-org
    alias unlink-user-space = usermgr unlink-space

    # # ## ### ##### ######## ############# #####################
    ## Administrative tasks

    officer admin {
	description {
	    A set of adminstrative tasks.
	}

	private patch {
	    section Administration
	    description {
		Apply a patch to the current or
		specified target.
	    }
	    use .login
	    input patch {
		Name, path or url referencing the
		patch (file) to apply.
	    }
	} [jump@cmd admin patch]

	private report {
	    section Administration
	    description {
		Retrieve a report containing the logs
		of the current or specified target.
	    }
	    use .login
	    input destination {
		The file to store the report into.
		The default name is derived from the
		target.
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
	    use .prompt
	    use .client
	    input email {
		Name of the user to grant administrator
		privileges to.
	    } {
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
	    use .prompt
	    use .client
	    input email {
		Name of the user to revoke administrator
		privileges from.
	    } {
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

	officer broker {
	    undocumented
	    description {
		Management of service brokers.
	    }
	    # TODO: broker - update (token)
	    # TODO: broker - delete|remove

	    private add {
		section Services Brokers
		description {
		    Make the named service broker known.
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
		option url {
		    Location of the broker.
		} {
		    validate str
		    interact
		}
		option broker-token {
		    Value of the broker's token.
		} {
		    validate str
		    interact "Token: "
		}
	    } [jump@cmd servicebroker add]

	    private list {
		section Services Brokers
		description {
		    Show the list of known service brokers.
		}
		use .login-with-group
		use .v2
		use .json
	    } [jump@cmd servicebroker list]
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
		    validate str
		    interact "Authentication Token: "
		}
	    } [jump@cmd serviceauth create]

	    private update {
		section Services {Authentication Tokens}
		description {
		    Update the specified service authentication token.
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
		    validate str
		    interact "Authentication Token: "
		}
	    } [jump@cmd serviceauth update]

	    private delete {
		section Services {Authentication Tokens}
		description {
		    Delete the specified service authentication token.
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
		}
		use .login-with-group
		use .v2
		use .json
	    } [jump@cmd serviceauth list]
	}

	private bind {
	    section Services Management
	    description {
		Bind the named service to the specified
		application.
	    }
	    use .prompt
	    use .login-with-group
	    use .tail
	    use .manifest
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
	} [jump@cmd servicemgr bind]

	private unbind {
	    section Services Management
	    description {
		Disconnect the named service from the specified
		application.
	    }
	    use .prompt
	    use .login-with-group
	    use .tail
	    use .manifest
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
	} [jump@cmd servicemgr unbind]

	private clone {
	    section Services Management
	    description {
		Copy the service bindings of the source
		application to the destination application.
	    }
	    use .prompt
	    use .login-with-group
	    use .tail
	    input source {
		Name of the application to take the list of services from.
	    } { validate [call@vtype appname] }
	    input application {
		Name of the application to bind the services to.
	    } { validate [call@vtype appname] }
	} [jump@cmd servicemgr clone]

	private create {
	    section Services Management
	    description {
		Create a new provisioned service, and optionally bind it
		to an application.
	    }
	    use .prompt
	    use .login-with-group

	    # ================================================
	    # CF v2 API only. ===============================
	    option provider {
		The service provider. Use this to disambiguate
		between multiple providers of the same vendor/type.
		This is a stackato/CFv2 specific option.
	    } {
		when-set [call@mgr client isv2]
		validate str
		# A filter on 'vendor' (see below).
		# String field in the vendor, no further validation.
	    }
	    option version {
		The service version. Use this to disambiguate
		between multiple versions of the same vendor/type.
		This is a stackato/CFv2 specific option.
	    } {
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
		This is a stackato/CFv2 specific option.
	    } {
		when-set [call@mgr client isv2]
		# Dependency: vendor (validate, generate)
		generate [call@cmd servicemgr select-plan-for-create]
		validate [call@vtype serviceplan]
	    }
	    option credentials {
		The credentials to use.
		Each use of the option declares a single element,
		using the form "key: value" for the argument.
		This is a stackato/CFv2 specific option.
		This is restricted to user-provided services.
	    } {
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
	} [jump@cmd servicemgr create]

	private delete {
	    section Services Management
	    description {
		Delete the named provisioned service.
	    }
	    use .prompt
	    use .login-with-group
	    option all {
		Delete all services.
		Cannot be used together with named service instances.
	    } {
		presence
		when-set [exclude service --all]
	    }
	    option unbind {
		Unbind service from applications before deleting.
		By default bound services are skipped and not deleted.
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
		when-set [exclude all service]
		# We cannot use 'interact' as the interaction is more
		# complex than a simple prompt.  Conditional, and a
		# menu of choices.
		generate [call@cmd servicemgr select-for-delete]
		validate [call@vtype serviceinstance]
	    }
	} [jump@cmd servicemgr delete]

	private show {
	    section Services
	    description {
		Show the information about the named service.
	    }
	    use .prompt
	    use .json
	    use .login-with-group
	    input name {
		The name of the provisioned service to show
		information for.
	    } {
		validate [call@vtype serviceinstance]
	    }
	} [jump@cmd servicemgr show]

	private rename {
	    section Services Management
	    description {
		Rename the specified service instance.
	    }
	    use .prompt
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
	} [jump@cmd servicemgr rename]

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
		default 10000
		validate [call@vtype integer0]
	    }
	    option url {
		Url the tunnel helper application is mapped to and
		listens on. Relevant if and only if the helper has
		to be pushed,i.e. on first use of the tunnel command.
	    } { validate str }
	    state copy-unsafe-links {
		Fake argument for the internal push (tunnel helper).
	    } { default no }
	    state no-resources {
		Fake argument for the internal push (tunnel helper).
	    } { default no }
	    state appname {
		Fake app name argument for use by validation.
	    } { default no }
	} [jump@cmd servicemgr tunnel]
    }
    alias bind-service   = servicemgr bind
    alias  bind_service
    alias unbind-service = servicemgr unbind
    alias  unbind_service
    alias clone-services = servicemgr clone
    alias create-service = servicemgr create
    alias  create_service
    alias rename-service = servicemgr rename
    alias  rename_service
    alias delete-service = servicemgr delete
    alias  delete_service
    alias service        = servicemgr show
    alias tunnel         = servicemgr tunnel

    alias create-service-auth-token = servicemgr auth create
    alias delete-service-auth-token = servicemgr auth delete
    alias update-service-auth-token = servicemgr auth update
    alias service-auth-tokens       = servicemgr auth list

    alias service-brokers    = servicemgr broker list
    alias add-service-broker = servicemgr broker add
    # update, delete?

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

	common .application-core {
	    use .tail
	    use .application-kernel
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
		validate str ; # accept unknown and known apps.
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

	common .application-as-option {
	    use .application-core
	    option application {
		Name of the application to operate on.
	    } {
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
		alias a
		validate [call@vtype appname-api]
		# Dependency on @client (via .application-core)
	    }
	}

	common .dry {
	    option dry {
		Print the low-level ssh command to stdout
		instead of executing it.
	    } { presence ; alias dry-run }
	}

	common .instance {
	    option instance {
		The instance to access with the command.
		Defaults to 0.
	    } {
		validate [call@vtype integer0]
	    }
	}

	common .ssh {
	    use .dry
	    use .instance
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
	    # target version independent ==========================
	    option instance {
		The id of the instance to filter the log stream for,
		or (before 2.3), to retrieve the logs of.
	    } {
		validate [call@vtype integer0]
		when-set [exclude all --instance]
	    }
	    # pre 2.3 only ========================================
	    option all {
		Retrieve the logs from all instances. Before 2.3 only.
	    } {
		presence
		when-set [combine \
		      [call@mgr logstream needslow] \
		      [exclude install all]]
	    }
	    option prefix {
		Put instance information before each line of a
		shown log file. Before 2.3 only.
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
		default 100
		validate [call@vtype integer0]
		when-set [call@mgr logstream needfast]
	    }
	    option source {
		Filter the log stream by origin stage (glob pattern).
		Target version 2.4+ only.
	    } {
		default *
		when-set [call@mgr logstream needfast]
	    }
	    option filename {
		Filter the log stream by origin file (glob pattern).
		Target version 2.4+ only.
	    } {
		default *
		when-set [call@mgr logstream needfast]
	    }
	    option newer {
		Filter the log stream by time, only entries after
		the specified epoch. Target version 2.4+ only.
	    } {
		undocumented ; # internal
		default 0
		validate [call@vtype integer0]
		when-set [call@mgr logstream needfast]
	    }
	    option text {
		Filter the log stream by log entry text (glob pattern).
		Target version 2.4+ only.
	    } {
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
	    } {
		validate str
		when-set [call@mgr client notv2]
		#generate [call@mgr manifest runtime]
	    }
	    option no-framework {
		Create application without any framework.
		Cannot be used together with --framework.
	    } {
		presence
		when-set [combine \
			      [call@mgr client notv2] \
			      [exclude framework --no-framework]]
 	    }
	    option framework {
		Specify the framework to use.
		Cannot be used together with --no-framework.
		Defaults to a heuristically chosen value if
		not specified, and none for --no-framework.
	    } {
		validate str
		when-set [combine \
			      [call@mgr client notv2] \
			      [exclude no-framework --framework]]
	    }
	    # CF v2 API only. ====================================
	    ## Stack, Buildpack ...
	    option stack {
		The OS foundation the application will run on.
	    } {
		when-set [call@mgr client isv2]
		validate [call@vtype stackname]
	    }
	    option buildpack {
		Url of a custom buildpack.
	    } {
		when-set [call@mgr client isv2]
		validate str ; # url
	    }
	    # ====================================================
	    option instances {
		The number of application instances to create.
		Defaults to 1, if not specified by a stackato.yml.
	    } {
		validate [call@vtype integer0]
		#generate [call@mgr manifest instances]
	    }
	    option url {
		The urls to map the application to.
		I.e. can be specified muliple times.
	    } {
		# NOTE: This is a new feature, old-cli supports only a single url.
		validate str
		list
		#generate [call@mgr manifest urls]
	    }
	    option mem {
		The application's per-instance memory allocation.
		Defaults to a framework-specific value if not
		specified by stackato.yml.
	    } {
		validate [call@vtype memspec]
		#generate [call@mgr manifest mem]
	    }
	    option disk {
		The application's per-instance disk allocation.
		Defaults to a framework-specific value if not
		specified by stackato.yml.
	    } {
		validate [call@vtype memspec]
		#generate [call@mgr manifest mem]
	    }
	    option command {
		The application's start command.
		Defaults to a framework-specific value if required
		and not specified by stackato.yml.
	    } {
		validate str
	    }
	    option env {
		Environment variable overrides for declarations in
		the stackato.yml. Ignored without environment variable
		declarations in the manifest.
	    } {
		validate [call@vtype envassign]
		list
	    }
	    option env-mode {
		Environment replacement mode. One of preserve, or replace.
		The default for create and push is "replace", and for
		update it is "preserve". Replace-mode also implies --reset.
	    } {
		# Note: There is also 'append', which is not documented.
		#default preserve - dynamically chosen in the action callback
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
		validate [call@vtype hostport]
	    }
	}

	private info {
	    section Applications
	    description {
		Show the information of the specified application.
	    }
	    section Applications
	    use .prompt
	    use .json
	    use .application-k
	} [jump@cmd query appinfo]

	private events {
	    section Applications Information
	    description {
		Show the application's events as recorded so far.
	    }
	    use .application
	    use .v2
	    use .json
	} [jump@cmd app list-events]

	private rename {
	    section Applications Management
	    description {
		Rename the specified application.
	    }
	    use .application
	    use .v2
	    input name {
		New name of the application.
	    } {
		optional
		interact "Enter new name: "
	    }
	} [jump@cmd app rename]

	private start {
	    section Applications Management
	    description { Start a deployed application. }
	    use .application
	    use .fakelogs
	} [jump@cmd app start]

	private stop {
	    section Applications Management
	    description { Stop a deployed application. }
	    use .application
	} [jump@cmd app stop]

	private restart {
	    section Applications Management
	    description { Stop and restart a deployed application. }
	    use .application
	    use .fakelogs
	} [jump@cmd app restart]

	private map {
	    section Applications Management
	    description {
    Make the application accessible through the specified URL (a route
    consisting of host and domain)
	    }
	    use .prompt
	    use .application
	    input url {
		One or more urls to route to the application.
	    } { }
	} [jump@cmd app map]

	private unmap {
	    section Applications Management
	    description { Unregister the application from a URL. }
	    use .prompt
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
		Update the number of instances, memory and/or
		disk reservation for a deployed application.
	    }
	    use .prompt
	    use .application
	    option disk {
		The new disk reservation to use.
	    } {
		alias d
		validate [call@vtype memspec]
	    }
	    option mem {
		The new memory reservation to use.
	    } {
		alias m
		validate [call@vtype memspec]
	    }
	    option instances {
		Absolute number of instances to scale to, or
		relative change.
	    } {
		alias i
		validate integer
	    }
	} [jump@cmd app scale]

	private files {
	    section Applications Information
	    description {
		Display directory listing or file.
	    }
	    use .mquiet
	    use .prompt
	    option all {
		When present, access all instances for the file or directory.
		Cannot be used together with --instance.
	    } {
		presence
		when-set [exclude instance --all]
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
		when-set [exclude all --instance]
		validate [call@vtype instance]
		generate [call@vtype instance default]
		# Small trick here. Using the VT's default method as
		# generate defers its usage to the 'completion' phase,
		# instead of running it when parsing the spec, which
		# is too early.
	    }
	    use .application-dot
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
	    use .prompt
	    option instance {
		When present the instance to query.
		Cannot be used together with --all.
		Defaults to 0 (except when --all is present).
	    } {
		when-set [exclude all --instance]
		validate [call@vtype instance]
		generate [call@vtype instance default]
		# Small trick here. Using the VT's default method as
		# generate defers its usage to the 'completion' phase,
		# instead of running it when parsing the spec, which
		# is too early.
	    }
	    use .application-dot
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
	    use .prompt
	    use .json
	    use .application
	} [jump@cmd app crashes]

	private crashlogs {
	    section Applications Information
	    description { Display log information for the application. An alias of 'logs'. }
	    use .prompt
	    use .application
	    use .logs
	} [jump@cmd app crashlogs]

	private logs {
	    section Applications Information
	    description { Display log information for the application. }
	    use .prompt
	    use .application
	    use .logs
	} [jump@cmd app logs]

	private create {
	    section Applications Management
	    description {
		Create an empty application with the specified configuration.
	    }
	    use .prompt
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
	    use .prompt
	    use .login-with-group
	    use .tail
	    use .manifest
	    option all {
		Delete all applications.
		Cannot be used together with application names.
	    } {
		presence
		when-set [exclude application --all]
	    }
	    option force {
		Force deletion.
	    } { presence }
	    input application {
		Name of the application(s) to delete.
		Cannot be used together with --all.
	    } {
		optional
		list
		when-set [exclude all application]
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
	    use .prompt
	    use .client-auth+group
	    use .manifest
	    option all {
		Report on all applications in the current space.
		Cannot be used together with application names.
	    } {
		presence
		when-set [exclude application --all]
	    }
	    input application {
		Name of the application(s) to report on.
		Cannot be used together with --all.
	    } {
		optional
		list
		when-set [exclude all application]
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
	}

	private push {
	    section Applications Management
	    description {
		Configure, create, push, map, and start a new application.
	    }
	    use .prompt
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
	    option as {
		The name of the application to push/update the selected application as.
		Possible only if a single application is pushed or updated.
	    } {
		alias name
		validate str
	    }
	} [jump@cmd app push]

	private update {
	    undocumented
	    description {
		Deprecated. Disabled.
		Use push to update an existing application.
	    }
	    use .prompt
	    use .application
	    use .fakelogs
	    use .push-update
	    option env-mode {
		Environment replacement mode. One of preserve, or replace.
		Preserve is default.
	    } {
		# Note: There is also 'append', which is not documented.
		default preserve
		validate [call@vtype envmode]
	    }
	} [jump@cmd app update]

	private dbshell {
	    section Applications Management
	    description { Invoke interactive db shell for a bound service. }
	    use .dry
	    use .application-test
	    input service {
		The name of the service to talk to.
	    } { optional }
	} [jump@cmd app dbshell]

	private open_browser {
	    section Applications Management
	    description {
		Open the application|URL|target (web console) in a browser
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
	    use .prompt
	    use .ssh
	    use .application-as-option
	    input command {
		The command to run.
	    } { list }
	} [jump@cmd app run]

	officer ssh {
	    undocumented
	    description { Secure shell and copy. }

	    private copy {
		section Applications Management
		description {
		    Copy source files and directories to the destination.
		}
		state dry {
		    Fake dry setting
		} { validate integer ; default 0 }
		use .prompt
		use .instance
		use .application-as-option
		input paths {
		    The source paths, and the destination path (last).
		} { list }

	    } [jump@cmd app securecp]

	    private run {
		section Applications Management
		description {
		    SSH to a running instance (or target),
		    or run an arbitrary command.
		}
		use .ssh
		use .application-api
		input command {
		    The command to run.
		} {
		    optional ; list ; test
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

		private receive {
		    undocumented
		    description { Receive multiple files locally. }
		    input dst { Destination directory. }
		} [jump@cmd scp xfer_receive]

		private receive1 {
		    undocumented
		    description { Receive a single file locally. }
		    input dst { Destination file. }
		} [jump@cmd scp xfer_receive1]

		private transmit {
		    undocumented
		    description { Transfer multiple files to remote. }
		    input src {
			Source directories and files.
		    } { list }
		} [jump@cmd scp xfer_transmit]

		private transmit1 {
		    undocumented
		    description { Transfer a single file to remote. }
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
		use .prompt
		use .application
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
		use .prompt
		use .application
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
		use .prompt
		option json {
		    The drain target takes raw json log entries.
		} { presence }
		use .application
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
		use .prompt
		use .application
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
	    } [jump@cmd app drain_list]
	}
    }

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
    alias instances  = application instances
    alias scale      = application scale
    alias logs       = application logs
    alias map        = application map
    alias mem        = application mem
    alias disk       = application disk
    alias open       = application open_browser
    alias push       = application push
    alias restart    = application restart
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
	    }
	    use .prompt
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
	    }
	    use .prompt
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

	private set-quota {
	    section Organizations
	    description {
		Set the quotas for the current or named organization.
	    }
	    use .prompt
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
		Name of the quota definition to use in the organization.
	    } {
		validate [call@vtype quotaname]
	    }
	} [jump@cmd orgs set-quota]

	private switch {
	    section Organizations
	    description {
		Switch the current organization to the named organization.
		This invalidates the current space.
	    }
	    use .prompt
	    use .login
	    use .v2
	    input name {
		Name of the organization to switch to, and make current
	    } {
		optional
		validate [call@vtype orgname]
		generate [call@mgr corg select-for {switch to}]
	    }
	} [jump@cmd orgs switch]

	private show {
	    section Organizations
	    description {
		Show the named organization's information.
	    }
	    use .json
	    use .prompt
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
		generate      [call@mgr corg getc]
		when-complete [call@mgr corg setc]
	    }
	} [jump@cmd orgs show]

	private list {
	    section Organizations
	    description {
		List the available organizations.
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
	    }
	    use .prompt
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

	private create {
	    section Spaces
	    description {
		Create a new space.
	    }
	    use .prompt
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
	    }
	    use .prompt
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
	    }
	    use .prompt
	    use .login
	    use .v2
	    use .autocurrentorg
	    input name {
		Name of the space to switch to, and make current
	    } {
		optional
		validate [call@vtype spacename]
		generate [call@mgr cspace select-for {switch to}]
	    }
	} [jump@cmd spaces switch]

	private show {
	    section Spaces
	    description {
		Show the named space's information.
	    }
	    use .json
	    use .prompt
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
	    }
	    use .json
	    use .login
	    use .v2
	    use .autocurrentorg
	    option full {
		Show more details.
	    } { presence }
	} [jump@cmd spaces list]

	private rename {
	    section Spaces
	    description {
		Rename the named space.
	    }
	    use .prompt
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
    }

    alias create-space = spacemgr create
    alias delete-space = spacemgr delete
    alias space        = spacemgr show
    alias spaces       = spacemgr list
    alias rename-space = spacemgr rename
    alias switch-space = spacemgr switch

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
	    }
	    use .prompt
	    use .login
	    use .v2
	    use .autocurrentspace
	    input name {
		Name of the route to delete.
		This is expected to be host + domain.
	    } {
		validate [call@vtype routename]
	    }
	} [jump@cmd routes delete]

	private list {
	    section Routes
	    description {
		List all available routes.
	    }
	    use .json
	    use .login
	    use .v2
	    #use .autocurrentspace
	    # NOTE: TODO: The cf help is wrong. From the trace
	    # space does not factor here, it shows all routes in the
	    # system.

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
	    }
	    use .prompt
	    use .login
	    use .v2
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
	    }
	    use .prompt
	    use .login
	    use .v2
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

	private list {
	    section Domains
	    description {
		List the available domains in the specified space, or all.
	    }
	    use .login
	    use .v2
	    use .autocurrentorg
	    # Space context for most operations in spaces.
	    option space {
		The name of the space to use as context.

		Defaults to the current space.

		A current space is automatically set if there is none,
		either by taking the one space the user has, or
		asking the user to choose among the possibilities.

		Cannot be used together with --all.
	    } {
		when-set      [exclude all --space]
		validate      [call@vtype spacename]
		generate      [call@mgr cspace get-auto]
		when-complete [call@mgr cspace setc]
		#Note: automatic definition of a current space when not defined.
	    }
	    option all {
		Query information about all domains.
		Cannot be used together with a space.
	    } {
		presence
		when-set [exclude space --all]
	    }
	} [jump@cmd domains list]
    }

    # check how this works with (un)map commands.
    alias map-domain   = domainmgr map
    alias unmap-domain = domainmgr unmap
    alias domains      = domainmgr list

    # # ## ### ##### ######## ############# #####################
    ## CF v2 commands V: Quota definitions

    officer quota {
	description {
	    Management of quota definitions.
	}

	# General quota options.
	# See also common .limits for the CFv1 groups-related limits.
	common .qd {
	    option paid-services-allowed {
		Applications can use non-free services.
	    } ;# boolean

	    option trial-db-allowed {
		Applications can use trial databases.
	    } ;# boolean

	    option services {
		Limit for the number of services in the quota.
	    } { validate [call@vtype integer0] }

	    option mem {
		Amount of memory applications can use.
	    } { validate [call@vtype memspec] }
	}

	private create {
	    section Administration
	    description {
		Create a new quota definition.
	    }
	    use .prompt
	    use .login
	    use .v2
	    use .qd
	    input name {
		Name of the quota definition to create.
		If not specified it will be asked for interactively.
	    } {
		optional
		validate [call@vtype notquotaname]
		interact
	    }
	} [jump@cmd quotas create]

	private configure {
	    section Administration
	    description {
		Reconfigure the named quota definition.
	    }
	    use .prompt
	    use .login
	    use .v2
	    use .qd
	    input name {
		Name of the quota definition to configure.
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
	    section Administration
	    description {
		Delete the named quota definition.
	    }
	    use .prompt
	    use .login
	    use .v2
	    input name {
		Name of the quota definition to delete.
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
	    section Administration
	    description {
		List the available quota definitions.
	    }
	    use .json
	    use .login
	    use .v2
	} [jump@cmd quotas list]

	private rename {
	    section Administration
	    description {
		Rename the named quota definition.
	    }
	    use .prompt
	    use .login
	    use .v2
	    input name {
		Name of the quota definition to rename.
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
		The new name to give to the quota definition.
	    } {
		#optional
		validate [call@vtype notquotaname]
		#interact "Enter new name: "
	    }
	} [jump@cmd quotas rename]

	private show {
	    section Administration
	    description {
		Show the details of the named quota definition.
		If not specified it will be asked for interactively (menu).
	    }
	    use .json
	    use .prompt
	    use .login
	    use .v2
	    input name {
		Name of the quota definition to display.
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

proc jump@cmd {package cmd} {
    lambda {package cmd config args} {
	package require stackato::cmd::$package
	debug.cmdr {[$config dump]}
	::stackato::cmd $package $cmd $config {*}$args
	# Transient settings of the various managers are reset within
	# the ehandler, i.e. ::stackato::mgr::exit::attempt
    } $package $cmd
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

# Another helper to ease handling of parameter exclusion.

proc exclude {locked by} {
    lambda {locked by p args} {
	debug.cmdr {}
	$p config @$locked lock $by
    } $locked $by
}

proc combine {args} {
    lambda {clist args} {
	foreach cmd $clist {
	    {*}$cmd {*}$args
	}
    } $args
}

# # ## ### ##### ######## ############# #####################
## Notes:

# # ## ### ##### ######## ############# #####################
## Ready. Vendor (VMC) version tracked: 0.3.14.

package provide stackato::cmdr 2.0.2
