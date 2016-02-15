[comment {--- !doctools ---}]
[comment { DSL :: kettle ignore +=|= :: }]

[comment {- - -- --- ----- -------- ------------- ---------------------}]
[call [cmd {kettle ignore +=}] [arg pattern]...]

This command adds the specified glob-patterns to the list of patterns
to ignore when scanning the project directory.

[para] Note that at least one pattern is expected.

[para] Any changes to the set of ignore patterns must be done before a
project directory scan to take effect. As such this command should be
before any other DSL command not managing the set.

[comment {- - -- --- ----- -------- ------------- ---------------------}]
[call [cmd {kettle ignore =}] [opt [arg pattern]...]]

This command replaces the list of patterns to ignore when scanning the
project directory with the specified set of glob-patterns.

[para] Note that the set can empty, resetting the set of ignore
patterns.

[para] Any changes to the set of ignore patterns must be done before a
project directory scan to take effect. As such this command should be
before any other DSL command not managing the set.

[comment {- - -- --- ----- -------- ------------- ---------------------}]
