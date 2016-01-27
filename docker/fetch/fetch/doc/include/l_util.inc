[comment {--- !doctools ---}]
[comment { support :: kettle strutil et. al. :: }]

This, the lowest layer of the system contains general utility commands
for string processing, anonymous procedures and error handling.

[comment {- - -- --- ----- -------- ------------- ---------------------}]
[subsection {Anonymous procedures}]

[list_begin definitions]
[comment {- - -- --- ----- -------- ------------- ---------------------}]
[call [cmd lambda]                  [arg arguments] [arg body] [opt [arg arg]...]]
[call [cmd lambda@] [arg namespace] [arg arguments] [arg body] [opt [arg arg]...]]

These commands are wrappers around Tcl 8.5's builtin [cmd apply]
command, making the creation of anonymous procedures a bit
easier. Apply uses nested lists, the API here flattens that, matching
the API of [cmd proc].

[para] The command arguments are like for [cmd proc], with three
exceptions.

[list_begin enumerated]
[enum]	There is no procedure name. Obviously.
[enum]	After the procedure body we can pre-specify some or all
	of the procedure arguments, i.e. perform currying.
[enum]  The @-variant takes the name of the [arg namespace] the body
	will be executed in.
[list_end]
[list_end]

[comment {- - -- --- ----- -------- ------------- ---------------------}]
[subsection {Error handling}]

[list_begin definitions]
[comment {- - -- --- ----- -------- ------------- ---------------------}]
[call [cmd try] [arg arg]...]

This command is an implementation of Tcl 8.6's try/trap/finally
command in pure Tcl, providing forward-compatibility with 8.6 in this
respect. (Iit is just too useful when it comes to erro handling,
especially cleanup of transient things like temp files).

[para] Syntax and semantics fully match the Tcl 8.6 command. The code
was written by Donal Fellows, it is the initial implementation of the
builtin, before it got re-implemented in C and byte-coded.

[list_end]

[comment {- - -- --- ----- -------- ------------- ---------------------}]
[subsection {String processing}]

[list_begin definitions]
[comment {- - -- --- ----- -------- ------------- ---------------------}]
[call [cmd {kettle strutil}] [method indent] [arg text] [arg prefix]]

This command splits the input [arg text] into lines, indents each line
using the [arg prefix] and then returns the re-joined text.

[para] Note that the prefix is not applied to empty lines (containing
only whitespace). Any whitespace in empty lines is actually completely
eliminated.

[comment {- - -- --- ----- -------- ------------- ---------------------}]
[call [cmd {kettle strutil}] [method padl] [arg list]]
[call [cmd {kettle strutil}] [method padr] [arg list]]

These two commands take a list of strings, compute the maximum length
and then pads all shorter strings to this length (using spaces),
returning the modified list. The order of the strings in the result is
not changed. The commands differ in where the padding is
applied.

[para] [method padr] adds the spaces at the end of the string (to the
right) yielding a left-aligned result.  Whereas [method padl] adds the
spaces at the beginning of the string (to the left) yielding a
right-aligned result.

[para] Regardless of the differences, the result is a list of strings
of the same length. Useful when having to print a table. Provide a
column of the table as input, and the result is properly aligned for
printing.

[comment {- - -- --- ----- -------- ------------- ---------------------}]
[call [cmd {kettle strutil}] [method reflow] [arg text] [opt [arg prefix]]]

This command strips empty header and footer lines from the input
[arg text], undents it and then re-indents using the [arg prefix]. If
the latter is not specified it will default to 4 spaces.

[para] The result of all the modifications is then returned as the
result of the command.

[comment {- - -- --- ----- -------- ------------- ---------------------}]
[call [cmd {kettle strutil}] [method undent] [arg text]]

This command splits the input [arg text] into lines, computes longest
common prefix of whitespace over all lines, removes that prefix and
then returns the re-joined text.

[para] The effect is an un-indenting of the lines in the [arg text]
which preserves the general shape of the left margin.

[para] Note that empty lines (containing only whitespace) do not take
part in the prefix calculation. Any whitespace in empty lines is
actually completely eliminated.

[list_end]
