[comment {--- !doctools ---}]
[comment { option :: --color :: }]

[comment {- - -- --- ----- -------- ------------- ---------------------}]
[opt_def --color boolean]

The value of this configuration option determines if output is
colorized or not.

[para] The default value is platform-dependent.

On windows the default is [const off], disabling colorization.

On unix the default is [const on], activating colorization. Except if
it could be determined that the script's [const stdout] is not a
proper terminal, then the default is [const off].

[para] For this last check the system attempts to use the package
[package Tclx]. If that package is not available then it cannot be
determined if [const stdout] is a proper terminal, thus colorization
is active.

[comment {- - -- --- ----- -------- ------------- ---------------------}]
