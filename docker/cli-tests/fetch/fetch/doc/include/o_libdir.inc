[comment {--- !doctools ---}]
[comment { option :: --lib-dir :: }]

[comment {- - -- --- ----- -------- ------------- ---------------------}]
[opt_def --lib-dir path]

This configuration option specifies the path to the directory packages
(binary and script) will be installed into.

[para] The default value is the [lb][cmd {info library}][rb] directory
of the [syscmd tclsh] used to run the [syscmd kettle] application.

[para] If the option [option --exec-prefix] is modified the default
value changes to [file [var --exec-prefix]/lib].

[comment {- - -- --- ----- -------- ------------- ---------------------}]
