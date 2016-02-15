[comment {--- !doctools ---}]
[comment { DSL :: kettle figures :: }]

[comment {- - -- --- ----- -------- ------------- ---------------------}]
[call [cmd {kettle figures}] [opt [arg figroot]]]

This command declares the presence of [package diagram]-based figures
under the directory [arg figroot], which is a path relative to the
source directory.

[para] If not specified [arg figroot] defaults to [file doc/figures].

[para] While this command can be invoked multiple times, only the
first invokation will have an effect. Every invokation after that is
ignored.

The command [cmd {kettle doc}] (and indirectly [cmd {kettle tcl}] and
[cmd {kettle critcl3}]) runs this command implicitly, with the default
paths.

This means that if diagrams are stored in a non-standard location
[cmd {kettle figures}] must be run explicitly before them, with the
proper path.

[para] The package diagram directory is scanned to locate the diagram
files. They are recognized by containing the marker string

[list_begin itemized]
[item] "[const "tcl.tk//DSL diagram//EN//"]"
[list_end]

in their first 1024 characters.

[para] When diagram files are found the command will define recipes to
convert the diagrams into PNG raster images (saved as siblings to
their source files), and to render the diagrams on a Tk canvas.

[list_begin definitions]
[def [const figures]]
[def [const show-figures]]
[list_end]

[para] The recipes use the [syscmd dia] application (of [package tklib])
to perform the conversions, and GUI rendering.

[list_begin options]
[include o_with_dia.inc]
[list_end]

[comment {- - -- --- ----- -------- ------------- ---------------------}]
