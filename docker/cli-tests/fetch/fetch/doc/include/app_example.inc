[comment {--- !doctools ---}]
[comment { DSL :: kettle application :: example :: }]

A simple example of a build.tcl script is that for kettle itself.

[para] Stripping out the special code taking care of the fact that it
cannot assume to have kettle installed already this reduces to the
code below, and of that only the last two lines are relevant in terms
of build declarations. The first three are the (bourne) shell magic to
find and run the kettle application in the [var PATH] environment
variable. (The actual code assumes that [cmd kettle] is found the
working directory, again it cannot assume to be installed already).

[para][example_begin]
#!/bin/sh
# -*- tcl -*- \
exec kettle -f "$0" "${1+$@}"
kettle tcl
kettle tclapp kettle
[example_end]

[para] The code asks the system to search for and handle all Tcl
script packages to be found in the directory of the [file build.tcl]
file, and declares that we have a script application named
[syscmd kettle] in the same directory.

As the documentation files and figures are in the standard locations,
[cmd {kettle tcl}] is allowed to handle them implicitly.

[para] Done.
