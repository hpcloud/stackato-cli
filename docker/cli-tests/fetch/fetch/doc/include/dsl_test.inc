[comment {--- !doctools ---}]
[comment { DSL :: kettle testsuite :: }]

[comment {- - -- --- ----- -------- ------------- ---------------------}]
[call [cmd {kettle testsuite}] [opt [arg testroot]]]

This command declares the presence of a [package tcltest]-based
testsuite under the directory [arg testroot], which is a path relative
to the source directory.

[para] If not specified [arg testroot] defaults to [file tests].

[para] While this command can be invoked multiple times, only the
first invokation will have an effect. Every invokation after that is
ignored.

The commands [cmd {kettle tcl}] and [cmd {kettle critcl3}]) run this
command implicitly, with the default paths.

This means that if a testsuite is stored in a non-standard location
[cmd {kettle testsuite}] must be run explicitly before them, with the
proper path.

[para] The package testsuite directory is scanned to locate the test
files. They are recognized by containing the marker string

[list_begin itemized]
[item] "[const "tcl.tk//DSL tcltest//EN//"]"
[list_end]

in their first 1024 characters.

[para] When testsuites are found the command will define a recipe to
run them. This recipe will recursively invoke the recipes "debug" (or
"install" if the former does not exist, or fails) before performing
the tests, installing the package under test (and its dependencies) in
a local directory for use by the testsuites. The supporting commands
provided by kettle (see [term {Kettle - Testsuite Support}]) know how
to use this.

[list_begin definitions]
[def [const test]]
[list_end]

[para] The verbosity of testsuite output to the terminal is specified
by the option [option --log-mode].

The ability to save testsuite output to a series of files is specified
by the option [option --log].

The tclsh shell used for running the testsuites is specified by option
[option --with-shell].

[list_begin options]
[include o_logmode.inc]
[include o_log.inc]
[include o_with_shell.inc]
[list_end]

[comment {- - -- --- ----- -------- ------------- ---------------------}]
