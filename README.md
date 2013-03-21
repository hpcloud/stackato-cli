What is stackato-cli?
===

This repository contains the source code to the [Stackato](http://activestate.com/stackato) Platform-as-a-Service command line client, written in Tcl.


Prerequisites
===

1. Install [ActiveTcl 8.5](http://activestate.com/activetcl) somewhere (INSTALLDIR)

2. Put the ``INSTALLDIR/bin`` directory of the above installation on the PATH.

3. Run the command ``INSTALLDIR/bin/teacup install <package>`` for the following packages (may require sudo privileges depending on platform)

    * TclOO
    * Tclx
    * Trf
    * autoproxy
    * base64
    * cmdline
    * control
    * crc32
    * fileutil
    * fileutil::decode
    * fileutil::magic::mimetype
    * fileutil::magic::rt
    * fileutil::traverse
    * json
    * json::write
    * linenoise
    * logger
    * md5
    * ncgi
    * report
    * sha1
    * snit 2
    * struct::list
    * struct::matrix
    * tar
    * tcl::chan::cat
    * tcl::chan::core
    * tcl::chan::events
    * tcl::chan::string
    * tcllibc ; # to speed up md5, sha1, crc32, base64
    * tclyaml
    * term::ansi::code
    * term::ansi::code::attr
    * term::ansi::code::ctrl
    * term::ansi::ctrl::unix
    * textutil::adjust
    * textutil::repeat
    * textutil::string
    * tls
    * twapi ; # windows only
    * uri
    * uuid
    * zipfile::decode
    * zipfile::encode
    * zlibtcl

4. Alternatively to step 3…
	* (UNIX shell platforms) run ``depends.sh`` to install just this list of packages
	* run the command ``INSTALLDIR/bin/teacup update`` to get and install _all_ packages provided by ActiveState's TEApot repository for your platform.

5. Either
   * make a link ``INSTALLDIR/bin/tclsh`` to ``INSTALLDIR/bin/tclsh8.5``
   * copy the file
   * edit ``bin/stackato`` to use 'tclsh8.5' instead of 'tclsh' in its #! line

6. Run ``bin/stackato`` as you see fit.

Structure of the client
===

See the file [doc/devguide.txt](https://github.com/ActiveState/stackato-cli/raw/master/doc/devguide.txt) for more information on the internals.

