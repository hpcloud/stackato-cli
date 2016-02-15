[comment {--- !doctools ---}]
[comment { DSL :: kettle application :: }]

The [cmd kettle] application is the main interpreter for build
declarations. It can be used directly, or as a shell in the hash-bang
line of build files.

[para] Its general syntax is

[list_begin definitions]
[call [cmd kettle] \
	[opt "[option -f] [arg buildfile]"] \
	[opt [option -trace]] \
	([arg goal]|[option --option] [arg value])...]

In a hash-bang line for a build file the syntax is 'kettle -f', with
the build file becoming the argument to [option -f], and the arguments
to the build file then following, starting with the optional
[option -trace].

[para] Note: The application will look for a build file
[file build.tcl] in the current working, if no build file is
specified.

[para] Configuration options and recipes to run can be mixed on the
commandline, with the options processed first, and then the
recipes. For this to work all the options require a value.

[para] The list of known options, help about them, and their state
after option processing can be queried through the standard recipes
[const list-options], [const help-options], and
[const show-configuraton].

[para] The list of known recipes and help about them can be queried
through the standard recipes [const list-recipes], and
[const help-recipes].

[para] Note that the set of recipes is dynamically constructed based
on the scans of source directory made by kettle at the direction of
the build file. I.e. the options on the command line are processed
first, then the build file is used to scan the sources and initialize
the necessary recipes, at last the recipes on the command line are
run.

[para] The application understands one dot-file for configuration,
[file ~/.kettle/config]. This file is expected to contain
user-specific standard options to use. Its contents are processed as
part of the option processing, before the options found on the command
line.

For all other extensibility the user is reminded that build file are
Tcl files, with the full power of the language behind them. Which
includes the builtin command [cmd source].

[para] If no recipe is specified on the command line a standard recipe
is run. On unix platforms it is "help", whereas on windows "gui" is
used.

[list_end]
