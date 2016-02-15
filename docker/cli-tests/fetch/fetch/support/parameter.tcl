## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## CMDR - Value - Definition of command parameters (for a private).

# @@ Meta Begin
# Package cmdr::parameter 0
# Meta author   {Andreas Kupries}
# Meta location https://core.tcl.tk/akupries/cmdr
# Meta platform tcl
# Meta summary     Internal. Command parameters.
# Meta description Internal. Arguments, options, and other
# Meta description parameters to privates (commands).
# Meta subject {command line}
# Meta require {Tcl 8.5-}
# Meta require debug
# Meta require debug::caller
# Meta require TclOO
# Meta require {oo::util 1.2}    ;# link helper
# Meta require linenoise
# @@ Meta End

## Reference "doc/notes_parameter.txt". The Rnnn and Cnnn tags are
## links into this document.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require debug
package require debug::caller
package require TclOO
package require oo::util 1.2    ;# link helper
package require linenoise

# # ## ### ##### ######## ############# #####################

debug define cmdr/parameter
debug level  cmdr/parameter
debug prefix cmdr/parameter {[string map [::list [self] "([config context fullname])@$myname" my "    @$myname"] [debug caller]] | }
# In the above prefix we massage the object reference into a better
# name for navigation into a command hierarchy.

# # ## ### ##### ######## ############# #####################
## Definition

oo::class create ::cmdr::parameter {
    # # ## ### ##### ######## #############
    ## Lifecycle.

    constructor {theconfig order cmdline required defered name desc valuespec} {
	set myname  $name		; # [R1]
	set mylabel $name

	# Import the whole collection of parameters this one is a part
	# of into our namespace, as the fixed command "config", for
	# use by the various command prefixes (generate, validate,
	# when-complete), all of which will be run in our namespace
	# context.

	interp alias {} [self namespace]::config {} $theconfig

	# Note ordering!
	# We set up the pieces required by the narrator first, above.

	debug.cmdr/parameter {}

	# The valuespec is parsed immediately.  In contrast to actors,
	# which defer until they are required.  As arguments are
	# required when the using private is required further delay is
	# nonsense.

	set mydescription $desc		; # [R2]

	set myisordered   $order	; # [R3,4,5,6]
	set myiscmdline   $cmdline	; # [R3,4,5,6]
	set myisrequired  $required	; # [R7,8,9,10]
	set myisdefered   $defered      ; # [R ???]
	set mynopromote   no

	my C1_StateIsUnordered
	my C2_OptionIsOptional
	my C3_StateIsRequired

	set mystopinteraction no ;# specified interaction is not suppressed.
	set myislist       no ;# scalar vs list parameter
	set myisdocumented yes
	set myonlypresence no ;# options only, no argument when true.
	set myhasdefault   no ;# flag for default existence
	set mydefault      {} ;# default value - raw
	set mygenerate     {} ;# generator command
	set myinteractive  no ;# no interactive query of value
	set myprompt       "Enter ${name}: " ;# standard prompt for interaction

	set myvalidate     {} ;# validation command
	set mywhencomplete {} ;# action-on-int-rep-creation command.
	set mywhenset      {} ;# action-on-set(-from-parse) command.

	set mythreshold    {} ;# threshold for optional arguments
	#                     ;# empty: Undefined
	#                     ;#    -1: No threshold, peek and validate for choice.
	#                     ;#  else: #required arguments after this one.

	my ExecuteSpecification $valuespec

	# Start with a proper runtime state. See also method 'reset'
	# for an exported variant with cleanup, for use by cmdr::config.
	set myhasstring no
	set mystring    {}
	set myhasvalue  no
	set myisundefined no
	set myvalue     {}
	set mylocker    {}

	return
    }

    # # ## ### ##### ######## #############
    ## API: Property accessors...

    # Make the container accessible, and through it also all other
    # parameters of a private.
    method config {args} {
	debug.cmdr/parameter {}
	if {![llength $args]} {
	    return [config self]
	}
	config {*}$args
    }

    # Make self accessible.
    method self {} { self }

    method code {} {
	# code in {
	#     +		<=> required
	#     ?		<=> optional
	#     +*	<=> required splat
	#     ?* 	<=> optional splat
	# }
	my Assert {$myiscmdline} {State parameter "@" has no help (coding)}
	append code [expr {$myisrequired ? "+" : "?"}]
	append code [expr {$myislist     ? "*" : ""}]
	return $code
    }

    method is {type} {
	string equal $type [my type]
    }

    method type {} {
	if {$myisordered} { return "input" }
	if {$myiscmdline} { return "option" }
	return "state"
    }

    # Identification and help. Add context name into it?
    method name        {} { return $myname }
    method label       {} { return $mylabel }
    method description {{detail {}}} {
	if {($detail ne {}) && [dict exists $myflags $detail]} {
	    switch -exact -- [dict get $myflags $detail] {
		primary  {}
		alias    { return "Alias of [my Option $myname]." }
		inverted { return "Complementary alias of [my Option $myname]." }
	    }
	}
	return $mydescription
    }

    method primary {option} {
	return [expr {[dict get $myflags $option] eq "primary"}]
    }

    method flag {} {
	my Option $mylabel
    }

    # Core classification properties
    method ordered      {} { return $myisordered }
    method cmdline      {} { return $myiscmdline }
    method required     {} { return $myisrequired }
    method defered      {} { return $myisdefered }
    method nopromote    {} { return $mynopromote }

    method list         {} { return $myislist }
    method presence     {} { return $myonlypresence }
    method documented   {} { return $myisdocumented }
    method isbool       {} { return [expr {$myvalidate eq "::cmdr::validate::boolean"}] }
    method locker       {} { return $mylocker }

    # Alternate sources for the parameter value.
    method hasdefault   {} { return $myhasdefault }
    method default      {} { return $mydefault }
    method generator    {} { return $mygenerate }
    method interactive  {} { return $myinteractive }
    method prompt       {} { return $myprompt }

    # Hooks for validation and side-effects at various stages.
    method validator     {} { return $myvalidate }
    method when-complete {} { return $mywhencomplete }
    method when-set      {} { return $mywhenset }

    # - test mode of optional arguments (not options)
    method threshold   {} { return $mythreshold }
    method threshold: {n} {
	# Ignore when parameter is required, or already set to mode peek+test
	if {$myisrequired || ($mythreshold ne {})} return
	debug.cmdr/parameter {}
	set mythreshold $n
	return
    }


    method help {} {
	# Generate a dictionary describing the parameter configuration.
	if {[catch {
	    my code
	} thecode]} {
	    set thecode {}
	}
	# mynopromote - Irrelevant to help
	return [dict create \
		    cmdline     $myiscmdline    \
		    code        $thecode        \
		    default     $mydefault      \
		    defered     $myisdefered    \
		    description $mydescription  \
		    documented  $myisdocumented \
		    flags       $myflags        \
		    generator   $mygenerate     \
		    interactive $myinteractive  \
		    isbool      [my isbool]     \
		    label       $mylabel        \
		    list        $myislist       \
		    ordered     $myisordered    \
		    presence    $myonlypresence \
		    prompt      $myprompt       \
		    required    $myisrequired   \
		    threshold   $mythreshold    \
		    type        [my type]       \
		    validator   $myvalidate     \
		]
    }

    # One shot disabling of interaction, if any.
    method dontinteract {} {
	set mystopinteraction yes
	return
    }

    # # ## ### ##### ######## #############
    ## Internal: Parameter DSL implementation + support.

    method ExecuteSpecification {valuespec} {
	debug.cmdr/parameter {}
	# Dictionary of flags to recognize for an option.
	# The value indicates if the flag is primary or alias, or
	# inverted alias. This is used by 'description' to return
	# generated text as description of the aliases.

	set myflags {}

	# Import the DSL commands to translate the specification.
	link \
	    {alias         Alias} \
	    {default       Default} \
	    {defered       Defered} \
	    {generate      Generate} \
	    {immediate     Immediate} \
	    {interact      Interact} \
	    {label         Label} \
	    {list          List} \
	    {no-promotion  NoPromote} \
	    {optional      Optional} \
	    {presence      Presence} \
	    {test          Test} \
	    {undocumented  Undocumented} \
	    {validate      Validate} \
	    {when-complete WhenComplete} \
	    {when-set      WhenSet}
	eval $valuespec

	# Postprocessing ... Fill in validation and other defaults

	my FillMissingValidation
	my FillMissingDefault
	my DefineStandardFlags

	# Validate all constraints.

	my C1_StateIsUnordered
	my C2_OptionIsOptional
	my C3_StateIsRequired
	my C5_OptionalHasAlternateInput
	my C5_StateHasAlternateInput
	my C6_RequiredArgumentForbiddenDefault
	my C6_RequiredArgumentForbiddenGenerator
	my C6_RequiredArgumentForbiddenInteract
	my C7_DefaultGeneratorConflict

	return
    }

    # # ## ### ##### ######## #############
    ## Internal: Parameter DSL commands.

    method Label {name} {
	set mylabel $name
	return
    }

    method List {} {
	set myislist yes
	return
    }

    method Presence {} {
	my C8_PresenceOption
	my C9_ForbiddenPresence
	# Implied type and default
	my Validate boolean
	my Default  no
	set myonlypresence yes
	return
    }

    method Undocumented {} {
	set myisdocumented no
	return
    }

    method Alias {name} {
	my Alias_Option
	dict set myflags [my Option $name] alias
	return
    }

    method Optional {} {
	# Arguments only. Options are already optional, and state
	# parameters must not be.
	my Optional_State  ; # Order of tests is important, enabling us
	my Optional_Option ; # to simplify the guard conditions inside.
	set myisrequired no
	return
    }

    method Interact {{prompt {}}} {
	# Check relevant constraint(s) after making the change. That
	# is easier than re-casting the expressions for the proposed
	# change.
	set myinteractive yes
	my C6_RequiredArgumentForbiddenInteract
	if {$prompt eq {}} return ; # keep standard prompt
	set myprompt $prompt
	return
    }

    method Defered {} {
	# Consider adding checks against current state, prevent use
	# of calls not making an actual change.
	set myisdefered yes
	return
    }

    method Immediate {} {
	# Consider adding checks against current state, prevent use
	# of calls not making an actual change.
	set myisdefered no
	return
    }

    method NoPromote {} {
	# Arguments only. Options cannot take unknown option as value,
	# nor can hidden state.
	my Promote_InputOnly
	# Consider adding checks against current state, prevent use
	# of calls not making an actual change.
	set mynopromote yes
	return
    }

    method Default {value} {
	my C9_PresenceDefaultConflict
	# Check most of the relevant constraint(s) after making the
	# change. That is easier than re-casting the expressions for
	# the proposed change.
	set myhasdefault yes
	set mydefault    $value
	my C6_RequiredArgumentForbiddenDefault
	my C7_DefaultGeneratorConflict
	return
    }

    method Generate {cmd} {
	my C9_PresenceGeneratorConflict
	# Check most of the relevant constraint(s) after making the
	# change. That is easier than re-casting the expressions for
	# the proposed change.
	set mygenerate $cmd
	my C6_RequiredArgumentForbiddenGenerator
	my C7_DefaultGeneratorConflict
	return
    }

    method Validate {cmdprefix} {
	my C9_PresenceValidateConflict

	# Extract primary command.
	set cmd [lindex $cmdprefix 0]

	# Allow FOO shorthand for cmdr::validate::FOO
	if {![llength [info commands $cmd]] &&
	    [llength [info commands ::cmdr::validate::$cmd]]} {
	    set cmdprefix [lreplace $cmdprefix 0 0 ::cmdr::validate::$cmd]
	}

	set myvalidate $cmdprefix
	return
    }

    method WhenComplete {cmd} {
	set mywhencomplete $cmd
	return
    }

    method WhenSet {cmd} {
	set mywhenset $cmd
	return
    }

    method Test {} {
	my Test_NotState    ; # Order of tests is important, enabling us
	my Test_NotOption   ; # to simplify the guard conditions inside.
	my Test_NotRequired ; #
	# Switch the mode of the optional argument from testing by
	# argument counting to peeking at the queue and validating.
	set mythreshold -1
	return
    }

    # # ## ### ##### ######## #############
    ## Internal: DSL support.

    # # ## ### ##### ######## #############
    ## Internal: DSL support. Constraints.

    forward C1_StateIsUnordered \
	my Assert {$myiscmdline || !$myisordered} \
	{State parameter "@" must be unordered}

    forward C2_OptionIsOptional \
	my Assert {!$myisrequired || !$myiscmdline || $myisordered} \
	{Option argument "@" must be optional}

    forward C3_StateIsRequired \
	my Assert {$myiscmdline || $myisrequired} \
	{State parameter "@" must be required}

    forward C5_OptionalHasAlternateInput \
	my Assert {$myisrequired||$myhasdefault||[llength $mygenerate]||$myinteractive} \
	{Optional parameter "@" must have default value, generator command, or interaction}

    forward C5_StateHasAlternateInput \
	my Assert {$myiscmdline||$myhasdefault||[llength $mygenerate]||$myinteractive} \
	{State parameter "@" must have default value, generator command, or interaction}

    forward C6_RequiredArgumentForbiddenDefault \
	my Assert {!$myhasdefault || !$myisrequired || !$myiscmdline} \
	{Required argument "@" must not have default value}

    forward C6_RequiredArgumentForbiddenGenerator \
	my Assert {![llength $mygenerate] || !$myisrequired || !$myiscmdline} \
	{Required argument "@" must not have generator command}

    forward C6_RequiredArgumentForbiddenInteract \
	my Assert {!$myinteractive || !$myisrequired || !$myiscmdline} \
	{Required argument "@" must not have user interaction}

    forward C7_DefaultGeneratorConflict \
	my Assert {!$myhasdefault || ![llength $mygenerate]} \
	{Default value and generator command for parameter "@" are in conflict}

    forward C8_PresenceOption \
	my Assert {$myiscmdline && !$myisordered} \
	{Non-option parameter "@" cannot have presence-only}

    forward C9_ForbiddenPresence \
	my Assert {(!$myhasdefault && ![llength $mygenerate] && ![llength $myvalidate]) || !$myonlypresence} \
	{Customized option cannot be presence-only}

    forward C9_PresenceDefaultConflict \
	my Assert {!$myonlypresence} \
	{Presence-only option cannot have custom default value}

    forward C9_PresenceGeneratorConflict \
	my Assert {!$myonlypresence} \
	{Presence-only option cannot have custom generator command}

    forward C9_PresenceValidateConflict \
	my Assert {!$myonlypresence} \
	{Presence-only option cannot have custom validation type}

    # # ## ### ##### ######## #############
    ## Internal: DSL support. Syntax constraints.

    forward Alias_Option \
	my Assert {$myiscmdline && !$myisordered} \
	{Non-option parameter "@" cannot have alias}

    forward Optional_Option \
	my Assert {$myisordered} \
	{Option "@" is already optional}

    forward Optional_State \
	my Assert {$myiscmdline} \
	{State parameter "@" cannot be optional}

    forward Test_NotState \
	my Assert {$myiscmdline} \
	{State parameter "@" has no test-mode}

    forward Test_NotOption \
	my Assert {$myisordered} \
	{Option "@" has no test-mode}

    forward Test_NotRequired \
	my Assert {!$myisrequired} \
	{Required argument "@" has no test-mode}

    forward Promote_InputOnly \
	my Assert {$myisordered && $myiscmdline} \
	{Non-input parameter "@" does not handle promotion}

    # # ## ### ##### ######## #############
    ## Internal: DSL support. General helpers.

    method Assert {expr msg} {
	# Note: list is a local command, we want the builtin
	if {[uplevel 1 [::list expr $expr]]} return
	return -code error \
	    -errorcode {CMDR PARAMETER CONSTRAINT VIOLATION} \
	    [string map [::list @ $myname] $msg]
    }

    method FillMissingValidation {} {
	debug.cmdr/parameter {}
	# Ignore when the user specified a validation type
	# Note: 'presence' has set 'boolean'.
	if {[llength $myvalidate]} return

	# The parameter has no user-specified validation type. Deduce
	# a validation type from the default value, if there is
	# any. If there is not, go with "boolean". Exception: Go with
	# "identity" when a generator command is specified. Note that
	# the constraints ensured that we have no default value in
	# that case.

	if {[llength $mygenerate]} {
	    set myvalidate ::cmdr::validate::identity
	} elseif {!$myhasdefault} {
	    # Without a default value base the validation type on the
	    # kind of parameter we have here:
	    # - input, state: identity
	    # - option:       boolean
	    if {$myiscmdline && !$myisordered} {
		set myvalidate ::cmdr::validate::boolean
	    } else {
		set myvalidate ::cmdr::validate::identity
	    }
	} elseif {[string is boolean -strict $mydefault]} {
	    set myvalidate ::cmdr::validate::boolean
	} elseif {[string is integer -strict $mydefault]} {
	    set myvalidate ::cmdr::validate::integer
	} else {
	    set myvalidate ::cmdr::validate::identity
	}
	return
    }

    method FillMissingDefault {} {
	debug.cmdr/parameter {}
	# Ignore when the user specified a default value.
	# Ditto when the user specified a generator command.
	# Ditto if the parameter is a required argument.
	# Note: 'presence' has set 'no' (together ith type 'boolean').
	if {$myhasdefault ||
	    [llength $mygenerate] ||
	    ($myiscmdline && $myisordered && $myisrequired)
	} return

	if {$myislist} {
	    # For a list parameter the default is the empty list,
	    # regardless of the validation type.
	    my Default {}
	} else {
	    # For a scalar parameter ask the chosen validation type
	    # for a default value.
	    my Default [{*}$myvalidate default [self]]
	}
	return
    }

    method DefineStandardFlags {} {
	debug.cmdr/parameter {}
	# Only options have flags, arguments and state don't.
	# NOTE: Arguments may change in the future (--ask-FOO)
	if {!$myiscmdline || $myisordered} return

	# Flag derived from option name.
	dict set myflags [my Option $mylabel] primary
	# Special flags for boolean options
	# XXX Consider pushing this into the validators.
	if {$myvalidate ne "::cmdr::validate::boolean"} return

	# A boolean option triggered on presence does not have a
	# complementary alias. There is no reverse setting.
	if {$myonlypresence} return

	if {[string match no-* $myname]} {
	    # The primary option has prefix 'no-', create an alias without it.
	    set alternate [string range $myname 3 end]
	} else {
	    # The primary option is not inverted, make an alias which is.
	    set alternate no-$myname
	}

	dict set myflags [my Option $alternate] inverted
	return
    }

    method Option {name} {
	# Short options (single character) get a single-dash '-'.
	# Long options use a double-dash '--'.
	if {[string length $name] == 1} {
	    return "-$name"
	}
	return "--$name"
    }

    # # ## ### ##### ######## #############
    ## API. Support for runtime command line parsing.
    ## See "cmdr::config" for the main controller.

    method lock {reason} {
	debug.cmdr/parameter {}
	set mylocker $reason
	return
    }

    method reset {{cleanup 1}} {
	debug.cmdr/parameter {}
	# Runtime configuration, force initial state. See also the
	# constructor for an inlined variant without cleanup.

	my forget

	set mylocker    {}
	set myhasstring no
	set mystring    {}
	return
    }

    method forget {} {
	debug.cmdr/parameter {}
	# Clear a cached value.

	if {$myhasvalue} {
	    my ValueRelease $myvalue
	}
	set myisundefined no
	set myhasvalue  no
	set myvalue     {}
	return
    }

    method options {} { 
	return [lsort -dict [dict keys $myflags]]
    }

    method complete-words {parse} {
	debug.cmdr/parameter {} 10
	# Entrypoint for completion, called by
	# cmdr::config (complete-words|complete-repl).
	# See cmdr::actor/parse-line for structure definition.
	dict with parse {}
	# -> words, at (ignored: ok, nwords, line, doexit)

	# We need just the text of the current word.
	set current [lindex $words $at end]

	# Actual completion is delegated to the validation type of the
	# parameter.
	return [{*}$myvalidate complete [self] $current]
    }

    method setq {queue} {
	debug.cmdr/parameter {}
	my Locked
	if {$myislist} {
	    # Bug 99702. The 'get' method of queues is variable-type.
	    # Retrieve 2 or more elements => get a list.
	    # Retrieve one element => get that element (NOT a list of one element).
	    # So, if our splat argument consists of just one element we have to
	    # undo 'get's stripping of list-ness, mystring must always be a list.

	    set n [$queue size]
	    set mystring [$queue get $n]

	    if {$n == 1} {
		set mystring [::list $mystring]
	    }
	} else {
	    set mystring [$queue get]
	}
	set myhasstring yes

	my forget

	if {[llength $mywhenset]} {
	    {*}$mywhenset [self] $mystring
	}
	return
    }

    method set {value} {
	debug.cmdr/parameter {}
	my Locked
	if {$myislist} {
	    lappend mystring $value
	} else {
	    set mystring $value
	}
	set myhasstring yes

	my forget

	if {[llength $mywhenset]} {
	    {*}$mywhenset [self] $mystring
	}
	return
    }

    method accept {x} {
	debug.cmdr/parameter {}
	try {
	    my ValueRelease [{*}$myvalidate validate [self] $x]
	    # If that was ok it has to be released also!
	    # XXX Or should we maybe immediately cache it for 'value'?
	} trap {CMDR VALIDATE} {e o} {
	    #puts "$myname (type mismatch, pass, $e)"
	    # Type mismatch, pass.
	    return 0
	} ; # internal errors bubble further
	return 1
    }

    method Locked {} {
	if {$mylocker eq {}} return
	debug.cmdr/parameter {}
	return -code error \
	    -errorcode {CMDR PARAMETER LOCKED} \
	    "You cannot use \"[my name]\" together with \"$mylocker\"."
    }

    method process {detail queue} {
	debug.cmdr/parameter {}
	# detail = actual flag (option)
	#        = parameter name (argument)

	my Assert {$myiscmdline} "Illegal command line input for state parameter \"$myname\""

	if {$myisordered} {
	    my ProcessArgument $queue
	    return
	}

	# Option parameters.
	my ProcessOption $detail $queue
	return
    }

    method ProcessArgument {queue} {
	debug.cmdr/parameter {}
	# Arguments.

	if {$myisrequired} {
	    # Required. Unconditionally retrieve its parameter
	    # value. Must have a value.
	    if {![$queue size]} { config notEnough }
	} elseif {![my Take $queue]} return

	# Optional. Conditionally retrieve the parameter value based
	# on argument count and threshold or validation of the
	# value. For the count+threshold method to work we have to
	# process (i.e. remove) all the options first.

	# Note also the possibility of the argument being a list.

	my setq $queue
	return
    }

    method ProcessOption {flag queue} {
	debug.cmdr/parameter {}
	if {$myonlypresence} {
	    # See also cmdr::config/dispatch
	    # Option has only presence.
	    # Validation type is 'boolean'.
	    # Default value is 'no', presence therefore 'yes'.
	    my set yes
	    return
	}

	if {[my isbool]} {
	    # XXX Consider a way of pushing this into the validator classes.

	    # Look for and process boolean special forms.

	    # Insert implied boolean flag value.
	    #
	    # --foo    non-boolean-value ==> --foo YES non-boolean-value
	    # --no-foo non-boolean-value ==> --foo NO  non-boolean-value

	    # Invert meaning of option.
	    # --no-foo YES ==> --foo NO
	    # --no-foo NO  ==> --foo YES

	    # Take implied or explicit value.
	    if {![$queue size] || ![string is boolean -strict [$queue peek]]} {
		set value yes
	    } else {
		# queue size && boolean
		set value [$queue get]
	    }

	    # Invert meaning, if so requested.
	    if {[string match --no-* $flag]} {
		set value [expr {!$value}]
	    }
	} else {
	    # Everything else has no special forms. The option's value
	    # is required here.
	    if {![$queue size]} { config missingOptionValue $flag }
	    set value [$queue get]
	}

	my set $value
	return
    }

    method Take {queue} {
	debug.cmdr/parameter {threshold $mythreshold}

	if {$mythreshold >= 0} {
	    # Choose by checking argument count against a threshold.

	    # For this to work correctly we now have to process all
	    # the remaining options first. Except for list
	    # arguments. These are last, and thus will always
	    # take whatever where is. Ok, we pass on an empty
	    # queue.

	    if {$myislist} {
		if {[$queue size]} {
		    debug.cmdr/parameter {list, taken}
		    return 1
		} else {
		    debug.cmdr/parameter {list, empty, pass}
		    return 0
		}
	    }

	    config parse-options

	    if {[$queue size] <= $mythreshold} {
		debug.cmdr/parameter {Q[$queue size] <= T$mythreshold: pass}
		# Not enough values left, pass.
		return 0
	    }
	    debug.cmdr/parameter {Q[$queue size] >  T$mythreshold: taken}
	    return 1
	} elseif {[$queue size]} {
	    debug.cmdr/parameter {validate ([$queue peek])}
	    # Choose by peeking at and validating the front value.
	    # Note: We may not have a front value!
	    set take [my accept [$queue peek]]
	    debug.cmdr/parameter {= [expr {$take ? "taken" : "pass"}]}
	    return $take
	} else {
	    # peek+test mode, nothing to peek at, pass.
	    debug.cmdr/parameter {no argument, pass}
	    return 0
	}
	debug.cmdr/parameter {should not be reached}
	return -code error -errorcode {CMDR PARAMETER INTERNAL} \
	    "Should not be reached"
    }

    # # ## ### ##### ######## #############
    ## APIs for use in the actual command called by the private
    ## containing the cmdr::config holding this value.
    #
    # - retrieve user string
    # - retrieve validated value, internal representation.
    # - query if a value is defined.

    method string {} {
	if {!$myhasstring} {
	    my undefined!
	}
	return $mystring
    }

    method set? {} {
	return $myhasstring
    }

    method value {} {
	debug.cmdr/parameter {}

	# Pull interaction suppression into the scope, and reset for
	# future calls. Suppression is a one-shot thing.
	set stopinteraction $mystopinteraction
	set mystopinteraction no

	# compute argument value if any, cache result.

	# Calculate value, from most prefered to least
	#
	# (0) Cache valid ?
	#     => Return
	#
	# (1) User entered value ?
	#     => Is string rep. Validate and transform to int. rep.
	#
	# (2) Generation command ?
	#     => Run, result is the int. rep. No validation, nor transform.
	#
	# (3) Default value ?
	#     => Take. It is int. rep. No validation, nor transform.
	#
	# (4) Interactive entry possible ? (general config, plus per value)
	#     Enter (string rep): validate and transform
	#     - mini shell - ^C abort
	#     - completion => Validator API
	#
	# (5) Optional ?
	#     => It is ok to not have the value. Return empty string.
	#     This should not be possible actually, because of [R12],
	#     [C5], and [C6].
	#
	#
	# (6) FAIL. 

	if {$myhasvalue} {
	    debug.cmdr/parameter {/cached ==> ($myvalue)}
	    return $myvalue
	}

	# Do not run the whole value generation a second time, when
	# the first already failed.
	if {$myisundefined} {
	    my undefined!
	}

	# Note that myvalidate and mygenerate are executed in this
	# scope, which implies the parameter instance namespace, which
	# implies access to the 'config' command, and thus the other
	# parameters. IOW, parameter generation and/or validation can
	# use the value of other parameters for their work. Catching
	# infinite loops so created are outside the scope of this
	# code.

	if {$myhasstring} {
	    debug.cmdr/parameter {/user}
	    # Specified on command line, string rep. Validate and
	    # transform to the int. rep.
	    #
	    # See "FillMissingValidation" on why we always have a
	    # validator command.

	    if {$myislist} {
		# Treat user-specified value as list and validate each
		# element.
		set myvalue {}
		foreach v $mystring {
		    lappend myvalue [{*}$myvalidate validate [self] $v]
		}
	    } else {
		set myvalue [{*}$myvalidate validate [self] $mystring]
	    }

	    debug.cmdr/parameter {/user ==> ($myvalue)}
	    my Value: $myvalue
	}

	if {!$stopinteraction && $myinteractive && [cmdr interactive?]} {
	    # Interaction.
	    debug.cmdr/parameter {/interact begin}
	    my interact

	    debug.cmdr/parameter {/interact ==> ($myvalue)}
	    return $myvalue
	}

	if {[llength $mygenerate]} {
	    # Generation callback. Result is int. rep.
	    debug.cmdr/parameter {/generate begin}
	    set v [{*}$mygenerate [self]]
	    debug.cmdr/parameter {/generate ==> ($v)}
	    my Value: $v
	}

	if {$myhasdefault} {
	    debug.cmdr/parameter {/default ==> ($mydefault)}
	    # A declared default value is the int. rep. No validation,
	    # no transform. Set it directly.
	    my Value: $mydefault
	}

	if {!$myisrequired} {
	    debug.cmdr/parameter {/optional, empty}
	    # Hardwired default int. rep if all else failed.
	    my Value: {}
	}

	debug.cmdr/parameter {undefined!}
	my undefined!
    }

    method interact {{prompt {}}} {
	debug.cmdr/parameter {}
	# Note: ^C for prompt aborts system.
	#       ^C for list aborts loop, but not system.
	# Details below.

	if {$prompt eq {}} {
	    set prompt $myprompt
	}

	if {$myislist} {
	    debug.cmdr/parameter {/list}
	    # Prompt for a list of values. We loop until the user
	    # aborted. The latter aborts just the loop. Completion
	    # is done through the chosen validation type. Invalid
	    # values are reported and ignored.
	    set continue 1

	    set thestringlist {}
	    set thevaluelist {}

	    puts $prompt
	    flush stdout

	    while {$continue} {
		debug.cmdr/parameter {/enter}
		#set continue 0
		try {
		    set thestring [linenoise prompt \
				       -prompt "  Item [llength $thevaluelist]> " \
				       -complete [::list {*}$myvalidate complete [self]]]
		} on error {e o} {
		    debug.cmdr/parameter {trapped $e}
		    debug.cmdr/parameter {options $o}

		    if {$e eq "aborted"} {
			set continue 0
		    } else {
			return {*}$o $e
		    }
		}
		if {!$continue} {
		    debug.cmdr/parameter {/break on ^C}
		    break
		}

		if {$thestring eq {}} {
		    debug.cmdr/parameter {/break on empty input}
		    # Plain enter. Nothing entered. Treat as abort.
		    break
		}

		set take 1
		try {
		    set thevalue [{*}$myvalidate validate [self] $thestring]
		} trap {CMDR VALIDATE} {e o} {
		    set take 0
		    puts "$e, ignored"
		}
		if {$take} {
		    debug.cmdr/parameter {/keep $thevalue}
		    lappend thestringlist $thestring
		    lappend thevaluelist  $thevalue
		}
	    }

	    # Inlined 'set' and 'Value:'. Modified to suit.
	    set     myhasstring yes
	    lappend mystring    {*}$thestringlist
	    set     myhasvalue  yes
	    lappend myvalue     {*}$thevaluelist

	} else {
	    debug.cmdr/parameter {/single}
	    # Prompt for a single value. We loop until a valid
	    # value was entered, or the user aborted. The latter
	    # aborts the whole operation. Completion is done through
	    # the chosen validation type.
	    set continue 1
	    while {$continue} {
		set abort 0
		set continue 0
		try {
		    set thestring [linenoise prompt \
				       -prompt $prompt \
				       -complete [::list {*}$myvalidate complete [self]]]
		} on error {e o} {
		    debug.cmdr/parameter {trapped $e}
		    debug.cmdr/parameter {options $o}

		    if {$e eq "aborted"} {
			debug.cmdr/parameter {/abort}
			# prevent system from taking which does not exist
			set abort 1
		    } else {
			# rethrow any other error
			return {*}$o $e
		    }
		}

		if {$abort} {
		    debug.cmdr/parameter {/break on ^C}
		    my undefined!
		}

		try {
		    set thevalue [{*}$myvalidate validate [self] $thestring]
		} trap {CMDR VALIDATE} {e o} {
		    debug.cmdr/parameter {trap $e}
		    puts "$e, ignored"
		    set continue 1
		}
	    }

	    # Inlined 'set'. Modified to suit. No locking, nor lock
	    # check, nor forgetting, except release of a previous value.

	    set myhasstring yes
	    set mystring    $thestring
	    if {$myhasvalue} { my ValueRelease $myvalue }
	    my Value: $thevalue
	}
	return
    }

    # # ## ### ##### ######## #############

    method undefined! {} {
	set myisundefined yes
	debug.cmdr/parameter {}
	return -code error \
	    -errorcode {CMDR PARAMETER UNDEFINED} \
	    "Undefined: $myname"
    }

    method Value: {v} {
	debug.cmdr/parameter {}
	if {[llength $mywhencomplete]} {
	    {*}$mywhencomplete [self] $v
	}
	set myvalue $v
	set myhasvalue yes

	# Return value, abort caller!
	return -code return $myvalue
    }

    method ValueRelease {value} {
	debug.cmdr/parameter {}
	# The validation type knows how to fully clean up the
	# value it returned during validation (See methods
	# 'value' and 'Take' (mode peek+test)).

	if {$myislist} {
	    foreach v $myvalue {
		{*}$myvalidate release [self] $v
	    }
	} else {
	    {*}$myvalidate release [self] $myvalue
	}
	return
    }

    # # ## ### ##### ######## #############

    variable myname mylabel mydescription \
	myisordered myiscmdline myislist myisrequired \
	myinteractive myprompt mydefault myhasdefault \
	mywhencomplete mywhenset mygenerate myvalidate \
	myflags mythreshold myhasstring mystring \
	myhasvalue myvalue mylocker mystopinteraction \
	myisdocumented myonlypresence myisdefered \
	myisundefined mynopromote

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide cmdr::parameter 1.0
