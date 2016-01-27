[comment {--- !doctools ---}]
[comment { option :: --ignore-glob :: }]

[comment {- - -- --- ----- -------- ------------- ---------------------}]
[opt_def --ignore-glob list]

This option specifies the set of files and directories to ignore
during directory scans, as a Tcl list of glob patterns to match.

[para] The default value is
[list_begin enumerated]
[enum] *~
[enum] _FOSSIL_
[enum] .fslckout
[enum] .fos
[enum] .git
[enum] .svn
[enum] CVS
[enum] .hg
[enum] RCS
[enum] SCCS
[enum] *.bak
[enum] *.bzr
[enum] *.cdv
[enum] *.pc
[enum] _MTN
[enum] _build
[enum] _darcs
[enum] _sgbak
[enum] blib
[enum] autom4te.cache
[enum] cover_db
[enum] ~.dep
[enum] ~.dot
[enum] ~.nib
[enum] ~.plst
[list_end]

matching the special files and directories of various source code
control systems, the backup files of various editors, and the like.

[comment {- - -- --- ----- -------- ------------- ---------------------}]
