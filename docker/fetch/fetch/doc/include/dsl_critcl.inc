[comment {--- !doctools ---}]
[comment { DSL :: kettle critcl3 :: }]

[comment {- - -- --- ----- -------- ------------- ---------------------}]
[call [cmd {kettle critcl3}]]

This command declares the presence of one or more critcl-based Tcl
packages in the package source directory, mixing C and Tcl.

[para] The package source directory is scanned to locate
them. Packages are detected by finding two markers (Tcl commands) in
the file. These markers are of the form

[example {
    package provide NAME VERSION
}]
and

[example {
    package require critcl
}]

Both [var NAME] and [var VERSION] must be literal strings, not
commands, nor variable references. They are best recognized when found
alone on their respective lines.

[para] For each detected package [var P] three recipes are defined, to
install and uninstall this package. Installation comes in two
variants, regular and debug:

[list_begin definitions]
[def [const install-package-[var P]]]
[def [const debug-package-[var P]]]
[def [const uninstall-package-[var P]]]
[list_end]

[para] The command further extends the recipes
[list_begin definitions]
[def [const install-binary-packages]]
[def [const install-packages]]
[def [const install]]
[def [const debug-binary-packages]]
[def [const debug-packages]]
[def [const debug]]
[def [const uninstall-binary-packages]]
[def [const uninstall-packages]]
[def [const uninstall]]
[list_end]

generating a recipe tree matching

[example {
  install
  -> install-packages
     -> install-binary-packages
        -> install-app-$path

  debug
  -> debug-packages
     -> debug-binary-packages
        -> debug-app-$path

  uninstall
  -> uninstall-packages
     -> uninstall-binary-packages
        -> uninstall-app-$path
}]

[para] The extended recipes may be created by this process. As other
declarations create similar trees these get merged together, enabling
a user to install parts of the sources at various levels of specifity,
from just a specific package up to all and sundry.

[para] Critcl-based packages are installed into the directory
specified by option [option --lib-dir].

Critcl's choice of the target configuration to build for can be
overrriden via option [option --target].

Kettle's choice of which critcl application to use cane overriden by
option [option --with-critcl3], except if kettle found a
[package critcl] package and runs everything itself instead of
invoking critcl child processes.

[list_begin options]
[include o_libdir.inc]
[include o_target.inc]
[include o_with_critcl3.inc]
[list_end]

[para] To simplify usage the command heuristically detects
documentation and testsuites by means of internally calling the
commands [cmd {kettle doc}] and [cmd {kettle testsuite}] with default
path arguments ([file doc] and [file tests] respectively).

[para] If documentation and/or testsuite are placed in non-standard
locations these commands have to be run before [cmd {kettle critcl3}],
with the proper paths.

[para] If dependencies have been specified, via
[cmd {kettle depends-on}], the package specific install and debug
recipes will recusively invoke install or debug on them before
building the package itself.

[comment {- - -- --- ----- -------- ------------- ---------------------}]
