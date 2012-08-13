Structure of the Tcl STACKATO command-line client
=================================================

See the file "doc/devguide.txt".


Getting the Tcl STACKATO client to run
======================================

1. Install ActiveTcl 8.5 somewhere.
   INSTALLDIR

2. Put the INSTALLDIR/bin directory of the above installation on the
   PATH.

3. Run the command

	INSTALLDIR/bin/teacup install <package>

   for the following packages

	TclOO
	Tclx
	Trf
	autoproxy
	base64
	cmdline
	control
	crc32
	fileutil
	fileutil::decode
	fileutil::magic::mimetype
	fileutil::magic::rt
	fileutil::traverse
	json
	json::write
	logger
	md5
	ncgi
	report
	sha1
	snit 2
	struct::list
	struct::matrix
	tcllibc ; # to speed up md5, sha1, crc32, base64
	tclyaml
	term::ansi::code
	term::ansi::code::attr
	term::ansi::code::ctrl
	term::ansi::ctrl::unix
	textutil::adjust
	textutil::repeat
	textutil::string
	tls
	twapi ; # windows only
	uri
	uuid
	zipfile::decode
	zipfile::encode
	zlibtcl

4. Alternatively to 3. run the command

	INSTALLDIR/bin/teacup update

   to get and install all packages provided by ActiveState's TEApot
   repository for your platform.

5. Either

   (a) make a link INSTALLDIR/bin/tclsh to INSTALLDIR/bin/tclsh8.5,
   (b) copy the file, or
   (c) Edit bin/stackato to use 'tclsh8.5' instead of 'tclsh' in its #! line.

6. Run bin/stackato as you see fit.
