[comment {--- !doctools ---}]
[comment { support :: kettle gui :: }]

This layer contains the command for the creation of the standard
graphical interface to the system.

[list_begin definitions]
[comment {- - -- --- ----- -------- ------------- ---------------------}]
[call [cmd {kettle gui}] [method make]]

This high-level command creates a standard graphical interface
providing access to all options and defined recipes, through two tabs
in a notebook.

[para] Options are handled by type specific fields, the details of
which are created by the option type definitions found under
[cmd {kettle ovalidate}], as specified in section
[sectref {Option Types and Validation}].

[para] Recipes are acessible through one button per recipe.

[para] Output is written to a text widget acting as a log window, in
the same tab which contains the action buttons.

[list_end]
[comment {- - -- --- ----- -------- ------------- ---------------------}]
