[comment {--- !doctools ---}]
[comment { option :: --with-critcl3 :: }]

[comment {- - -- --- ----- -------- ------------- ---------------------}]
[opt_def --with-critcl3 path]

This configuration option specifies the path to the tool

[syscmd critcl3] for the compilation and installation of critcl-based
C code.

[para] The default value is the path to the first of
[list_begin enumerated]
[enum] [file critcl3],
[enum] [file critcl3.kit],
[enum] [file critcl3.tcl],
[enum] [file critcl3.exe],
[enum] [file critcl],
[enum] [file critcl.kit],
[enum] [file critcl.tcl], and
[enum] [file critcl.exe]
[list_end]

found on the [var PATH]. None of these matter however should the
system find the package [package critcl] version 3 or higher among the
packages known to the [syscmd tclsh] running the [syscmd kettle]
application. In that case kettle will run everything in itself,
without invoking critcl child processes.

[comment {- - -- --- ----- -------- ------------- ---------------------}]
