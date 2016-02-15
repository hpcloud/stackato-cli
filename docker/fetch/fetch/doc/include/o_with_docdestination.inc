[comment {--- !doctools ---}]
[comment { option :: --with-doc-destination :: }]

[comment {- - -- --- ----- -------- ------------- ---------------------}]
[opt_def --with-doc-destination path]

This configuration option specifies the path to the directory the
generated documentation should be placed into for the documentation
installa recipes to pick up from.

[para] This should be a relative path, which will interpreted relative
to the package source directory.

[para] The default value is [file embedded].

[para] A build declaration file can override this default with the
[cmd {kettle doc-destination}] command.

[comment {- - -- --- ----- -------- ------------- ---------------------}]
