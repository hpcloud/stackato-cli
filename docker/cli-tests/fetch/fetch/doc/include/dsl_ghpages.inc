[comment {--- !doctools ---}]
[comment { DSL :: kettle gh-pages :: }]

[comment {- - -- --- ----- -------- ------------- ---------------------}]
[call [cmd {kettle gh-pages}]]

This command declares the presence of a [term gh-pages] branch in the
repository, as is used by, for example, [uri http://github.com], to
manage the web-site for a project in the rpeository of the project.

[para] The command confirms the presence of documentation and that the
local repository is [syscmd git]-based. If neither is true nothing
done.

[para] While this command can be invoked multiple times, only the
first invokation will have an effect. Every invokation after that is
ignored.

It runs the command [cmd {kettle doc}] command implicitly, with the
default paths, to ensure that its own check for documentation work
properly.

This means that if documentation is stored in a non-standard location
[cmd {kettle doc}] must be run explicitly before this command, with
the proper path.

[para] When the above tests pass the command will define a recipe
named [const gh-pages], which performs all the automatable steps to
copy the embedded documentation of the project into its
[term gh-pages] branch. Afterward the checkout is left at the
[term gh-pages] branch, for the user to review and commit. While the
last step could be automated the review cannot, making the point moot.

[comment {- - -- --- ----- -------- ------------- ---------------------}]
