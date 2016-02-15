[comment {--- !doctools ---}]
[comment { option :: --bin-dir :: }]

[comment {- - -- --- ----- -------- ------------- ---------------------}]
[opt_def --bin-dir path]

This configuration option specifies the path to the directory
applications (binary and script) will be installed into.

[para] The default value is the directory of the [syscmd tclsh] used
to run the [syscmd kettle] application.

[para] If the option [option --exec-prefix] is modified the default
value changes to [file [var --exec-prefix]/bin].

[comment {- - -- --- ----- -------- ------------- ---------------------}]
