[comment {--- !doctools ---}]
[comment { DSL :: kettle tcl :: }]

[comment {- - -- --- ----- -------- ------------- ---------------------}]
[call [cmd {kettle tcl}]]

This command declares the presence of one or more Tcl packages in the
package source directory.

[para] The package source directory is scanned to locate
them. Packages are detected by finding a marker (Tcl command) of the
form

[example {
    package provide NAME VERSION
}]

in a file, where both [var NAME] and [var VERSION] must be literal
strings, not commands, nor variable references. It is best recognized
when found alone on its line.

Note that files containing an [emph anti-marker] of the form

[example {
    package require critcl
}]

are rejected as Tcl packages. Use the command [cmd {kettle critcl3}]
to detect such packages, mixing Tcl and C.

In each accepted package file the command further looks for and
recognizes embedded pragmas of the form

[example {# @owns: PATH}]

which provides kettle with information about files belonging to the
same package without directly providing it. This can be data files, or
other Tcl files sourced by the main package file.

[para] For each detected package [var P] two recipes are defined, to
install and uninstall this package, namely:

[list_begin definitions]
[def [const install-package-[var P]]]
[def [const uninstall-package-[var P]]]
[list_end]

[para] The command further extends the recipes
[list_begin definitions]
[def [const install-tcl-packages]]
[def [const install-packages]]
[def [const install]]
[def [const uninstall-tcl-packages]]
[def [const uninstall-packages]]
[def [const uninstall]]
[list_end]

generating a recipe tree matching

[example {
  install
  -> install-packages
     -> install-tcl-packages
        -> install-app-$path

  uninstall
  -> uninstall-packages
     -> uninstall-tcl-packages
        -> uninstall-app-$path
}]

[para] The extended recipes may be created by this process. As other
declarations create similar trees these get merged together, enabling
a user to install parts of the sources at various levels of specifity,
from just a specific package up to all and sundry.

[para] Tcl packages are installed into the directory specified by
option [option --lib-dir] despite technically not being binary files.

[list_begin options]
[include o_libdir.inc]
[list_end]

[para] To simplify usage the command heuristically detects
documentation and testsuites by means of internally calling the
commands [cmd {kettle doc}] and [cmd {kettle testsuite}] with default
path arguments ([file doc] and [file tests] respectively).

[para] If documentation and/or testsuite are placed in non-standard
locations these commands have to be run before [cmd {kettle tcl}],
with the proper paths.

[para] If dependencies have been specified, via
[cmd {kettle depends-on}], the package specific install and debug
recipes will recusively invoke install or debug on them before
building the package itself.

[comment {- - -- --- ----- -------- ------------- ---------------------}]
