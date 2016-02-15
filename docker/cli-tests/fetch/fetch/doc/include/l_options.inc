[comment {--- !doctools ---}]
[comment { support :: kettle option :: }]

This layer manages the option database, which both holds the
configuration options, their definitions and values, as also named
shared global state.

[list_begin definitions]
[call [cmd {kettle option}] [method define]]
[call [cmd {kettle option}] [method onchange]]
[call [cmd {kettle option}] [method no-work-key]]
[call [cmd {kettle option}] [method exists]]
[call [cmd {kettle option}] [method names]]
[call [cmd {kettle option}] [method help]]
[call [cmd {kettle option}] [method set]]
[call [cmd {kettle option}] [method set-default]]
[call [cmd {kettle option}] [method set!]]
[call [cmd {kettle option}] [method unset]]
[call [cmd {kettle option}] [method get]]
[call [cmd {kettle option}] [method type]]
[call [cmd {kettle option}] [method save]]
[call [cmd {kettle option}] [method load]]
[call [cmd {kettle option}] [method config]]
[list_end]
