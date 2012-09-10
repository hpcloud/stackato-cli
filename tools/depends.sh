#!/bin/sh
# grab and install all the Tcl package dependencies required
# by Stackato Cloud Foundry client

# specify the PATH to the teacup binary
TEACUP=/usr/local/bin/teacup

# this list of dependencies is taken from the README
# if it changes then this list will also need updating

for i in TclOO Tclx Trf autoproxy base64 cmdline control crc32 fileutil fileutil::decode fileutil::magic::mimetype fileutil::magic::rt fileutil::traverse json json::write logger md5 ncgi report sha1 'snit 2' struct::list struct::matrix tcllibc tclyaml term::ansi::code term::ansi::code::attr term::ansi::code::ctrl term::ansi::ctrl::unix textutil::adjust textutil::repeat textutil::string tls uri uuid zipfile::decode zipfile::encode zlibtcl
do
  echo "\nAttempting to install $i..."
  $TEACUP install $i
done

# NB on Windows, also requires twapi package (not valid on UNIX platforms)
