[comment {--- !doctools ---}]
[comment { support :: kettle tool :: }]

This layer contains commands to manage the declaration of a dependency
on external comands, and their use.

[list_begin definitions]
[comment {- - -- --- ----- -------- ------------- ---------------------}]
[call [cmd {kettle tool}] [method declare] [arg names] [opt [arg validator]]]

This command declares the need for an external tool which can have any
of the listed [arg names].

The first element of that list is the name the tool will be known
under within kettle, also called the [term {primary name}] of the
tool.

This is the name to hand to [cmd {kettle tool get}] below to retrieve
the tool's location.

[para] Similarly the primary name is used to define an option named
--with-[var name], used to hold the path found by searching for the
tool on the [var PATH] under its various names, and to allow the user
to override kettle's choice.

[para] If [arg validator] is specified it will be treated as the body
of an anonymous procedure with a single argument [arg cmd], the path
of the tool found on [var PATH] and returning a boolean value telling
the caller if this path is acceptable (result == [const true]), or
not. In case of the latter the system will continue searching with the
next name in [arg names].

[comment {
    I should possibly switch from auto_execok to my own search
    command, to find other instances of the current name on
    not-yet-searched paths, before going to the next name.
}]

[comment {- - -- --- ----- -------- ------------- ---------------------}]
[call [cmd {kettle tool}] [method get] [arg name]]

This command returns the path to the [arg name]d tool, assuming that
it was [method declare]d before.

If no such tool is specified the command prints an error message and
aborts the execution of the current recipe and its callers.

[list_end]
[comment {- - -- --- ----- -------- ------------- ---------------------}]
