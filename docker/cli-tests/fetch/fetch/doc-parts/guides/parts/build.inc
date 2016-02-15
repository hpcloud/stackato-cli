[comment {
    @EDIT Please edit to suit - Kettle based build and installation.
}]

[vset PTITLE] uses the Kettle application and package to handle building
and installation. It is assumed to be installed and working. Please see
section [sectref Kettle] in [sectref Requisites] for more information.

[para] Note that all access to Kettle is mediated by the [file build.tcl]
script, found in the top-level directory of the project.

[para] For the most basic installation of [vset PTITLE] run

[example_begin]
% /path/to/[vset PROJECT]/build.tcl install
[example_end]

This command uses the [syscmd kettle] application found in the
[variable PATH], and the associated [syscmd tclsh].

[para] The command builds all packages and applications of [vset PTITLE],
and then installs them so that the associated [syscmd tclsh] has access
to them. Any applications will become siblings of [syscmd tclsh].


[para] For more control about which version of [syscmd kettle] and/or
[syscmd tclsh] gets used run either

[example_begin]
% /path/to/kettle /path/to/[vset PROJECT]/build.tcl install
[example_end]

or even

[example_begin]
% /path/to/tclsh /path/to/kettle /path/to/[vset PROJECT]/build.tcl install
[example_end]

to specify the exact files to use.

[para]

On Windows it is possible to invoke the the file [file build.tcl] with a
double-click. This will start a graphical interface to the system, with
buttons for all the possible actions, which includes 'install'ation.

[para]

On unix the same GUI is acessible by invoking [file build.tcl] with the
arguments [cmd gui], i.e. as 

[example_begin]
% /path/to/[vset PROJECT]/build.tcl gui
[example_end]

[para]

To get help about the methods of [file build.tcl], and their complete
syntax, simply invoke [file build.tcl] like

[example_begin]
% /path/to/[vset PROJECT]/build.tcl gui
[example_end]
