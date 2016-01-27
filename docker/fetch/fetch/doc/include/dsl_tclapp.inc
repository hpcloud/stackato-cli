[comment {--- !doctools ---}]
[comment { DSL :: kettle tclapp :: }]

[comment {- - -- --- ----- -------- ------------- ---------------------}]
[call [cmd {kettle tclapp}] [arg path]]

This command declares the presence of a Tcl script application found 
at the [arg path] under the package source directory.

[para] If the specified application is found the command will define
two recipes to install and uninstall this application, namely:

[list_begin definitions]
[def [const install-app-[arg path]]]
[def [const uninstall-app-[arg path]]]
[list_end]

[para] It will further extend the recipes
[list_begin definitions]
[def [const install-tcl-applications]]
[def [const install-applications]]
[def [const install]]
[def [const uninstall-tcl-applications]]
[def [const uninstall-applications]]
[def [const uninstall]]
[list_end]

generating a recipe tree matching

[example {
  install
  -> install-applications
     -> install-tcl-applications
        -> install-app-$path

  uninstall
  -> uninstall-applications
     -> uninstall-tcl-applications
        -> uninstall-app-$path
}]

[para] The extended recipes may be created by this process. As other
declarations create similar trees these get merged together, enabling
a user to install parts of the sources at various levels of specifity,
from just a specific application up to all and sundry.

[para] Script applications are installed into the directory specified
by option [option --bin-dir] despite technically not being binary
files.

[list_begin options]
[include o_bindir.inc]
[list_end]

[comment {- - -- --- ----- -------- ------------- ---------------------}]
