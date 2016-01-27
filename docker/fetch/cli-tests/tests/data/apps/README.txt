
README.txt	This file

	Directory		Notes
	---------		-------------------------------------------------------------------
*	a.original.node-env	Original basic node-env application
	---------		-------------------------------------------------------------------
*	appdir			+ app-dir (restructured dir hierarchy)
*	env			+ env, +hooks (checkable output)
				/variants: --env from command line, --env-mode (update)
*	env-manifest.yml	+ stackato:env, + stackato:hooks, see env, from manifest.yml
*	hooks			+ hooks, check stdout/err for the log entries proving hook execution
*	instances-1		+ instances: -1  \Check stdout for the message
*	instances0		+ instances: 0   /"Forcing use of minimum instances requirement:"
*	instances2		+ instances: 2, should be just ok
*	memory-1		+ memory: -1	\Check stdout for the message
*	memory0			+ memory: 0	/"Forcing use of minimum memory requirement:"
*	minclient-bad		+ min_version:client:10000	fail push
*	minclient-ok		+ min_version:client:1.7.1	ok push
*	minserver-bad		+ min_version:server:10000	fail push
*	minserver-ok		+ min_version:server:2.8	ok push
*	multi-depends-on	+ depends-on (multi-manifest.yml variant)
*	multi-inherit		+ inherit (multi-depends-on variant)
*	multi-manifest.yml	multi-app via manifest.yml, standard
*	multi-stackato.yml-m	multi-app via stackato.yml (same manifest syntax)
*	multi-stackato.yml-s	multi-app via stackato.yml (more stackato-like syntax)
 (-)	requirements		+ requirements
*	requirements-already	+ requirements:ubuntu/libaio-dev (already present)
*	requirements-bad	+ requirements:ubuntu/bogus
*	services		+ services (Note: Delete services with app! -n --force)
*	urls			+ urls
*	ignores-empty		+ ignores (empty list, nothing ignored)
*	ignores-other		+ ignores (.git/, *LOG)
	---------		-------------------------------------------------------------------

TODO
	twiddle framework, runtime
	twiddle special framework settings
	- app-server,
	- document-root,
	- home-dir,
	- start-file,
	- (start-command?)
	standalone + command
	processes:web
	cron:

	push with --group, --target, --token, --token-file
	push with group (current group)
