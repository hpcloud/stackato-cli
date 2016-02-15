[comment {--- !doctools ---}]
[comment { application :: recipes :: standard }]

The following recipes are understood by [cmd kettle] regardless of
build definitions. They are its [term standard] recipes.

[list_begin definitions]
[def [const gui]]
	Opens a standard graphical interface.

	This is the standard recipe run on windows if no recipe was
	specified on the command line.

[def [const help-options]]
	Print the help for all known options.

[def [const help-recipes]]
	Print the help for all defined recipes.

[def [const help]]
	The combination of the previous two recipes.

	This is the standard recipe run on unix if no recipe was
	specified on the command line.

[def [const list-options]]
	Print a list of all known options.

[def [const list-recipes]]
	Print a list of all defined recipes.

[def [const list]]
	The combination of the previous two recipes.

[def [const null]]
	This recipe does nothing.

	It is generally only useful for kettle developers, in
	combination with option [option -trace].

[def [const show-configuration]]
	Print the state of the option database after processing the
	dot-file and command line settings.

[def [const show-state]]
	Print the state of various internal global settings
	after processing the dot-file and command line settings.

[list_end]
