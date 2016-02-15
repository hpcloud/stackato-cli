[comment {--- !doctools ---}]
[comment { option :: --state :: }]

[comment {- - -- --- ----- -------- ------------- ---------------------}]
[opt_def --state path]

This is an internal option used by kettle for the communication
between parent and child instances when handling a recursive
invokation. The generated file specified as the value of the option
holds the work state of the parent, for the child to read and extend.

[comment {- - -- --- ----- -------- ------------- ---------------------}]
