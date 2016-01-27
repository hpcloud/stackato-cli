[comment {--- !doctools ---}]
[comment { support :: kettle status :: }]

The command of this layer manage the status of the currently executing
recipe and the database holding the knowledge about all executed
recipes, keyed by their name, location and relevant configuration.
This database is shared among instances of kettle during recursive
invokation.

[list_begin definitions]
[call [cmd {kettle status}] [method begin]]
[call [cmd {kettle status}] [method fail]]
[call [cmd {kettle status}] [method ok]]
[call [cmd {kettle status}] [method is]]
[call [cmd {kettle status}] [method save]]
[call [cmd {kettle status}] [method load]]
[call [cmd {kettle status}] [method clear]]
[list_end]
