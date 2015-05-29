#!/bin/sh
# grab and install all the Tcl package dependencies required
# by Stackato Cloud Foundry client

set -e

# specify the PATH to the teacup binary
if [ -n "$TEACUP_BIN_PATH" ]; then
  TEACUP=$TEACUP_BIN_PATH
elif [ -n "`which teacup`" ]; then
  TEACUP="`which teacup`"
elif [ -e /usr/local/bin/teacup ]; then
  TEACUP=/usr/bin/local/teacup
else
  echo "Can't find 'teacup'. Set TEACUP_BIN_PATH."
  exit 1
fi

# Mac hack:
if [ "`uname`" = 'Darwin' ]; then
  TEACUP="sudo $TEACUP"
fi

# this list of dependencies is taken from the README
# if it changes then this list will also need updating

for i in \
    'snit 2' \
    TclOO \
    Tclx \
    Trf \
    autoproxy \
    base64 \
    cmdline \
    clock::iso8601 \
    cmdr \
    cmdr::actor \
    cmdr::ask \
    cmdr::color \
    cmdr::config \
    cmdr::help \
    cmdr::help::json \
    cmdr::history \
    cmdr::officer \
    cmdr::pager \
    cmdr::parameter \
    cmdr::private \
    cmdr::tty \
    cmdr::util \
    cmdr::validate \
    cmdr::validate::common \
    control \
    crc32 \
    debug \
    debug::caller \
    fileutil \
    fileutil::decode \
    fileutil::magic::mimetype \
    fileutil::magic::rt \
    fileutil::traverse \
    'json 1.2' \
    json::write \
    lexec \
    linenoise \
    linenoise::facade \
    linenoise::repl \
    logger \
    md5 \
    ncgi \
    'oo::util 1.2' \
    report \
    sha1 \
    string::token \
    string::token::shell \
    struct::list \
    struct::set \
    struct::matrix \
    struct::queue \
    struct::set \
    'tar 0.8' \
    tcl::chan::cat \
    tcl::chan::core \
    tcl::chan::events \
    tcl::chan::string \
    tcllibc \
    tclyaml \
    term::ansi::code \
    term::ansi::code::attr \
    term::ansi::code::ctrl \
    term::ansi::ctrl::unix \
    textutil::adjust \
    textutil::repeat \
    textutil::string \
    tls \
    uri \
    uuid \
    websocket \
    zipfile::decode \
    zipfile::encode \
    zlibtcl
  do
  echo
  echo "Attempting to install $i..."
  $TEACUP install --force $i
done

# NB on Windows, also requires twapi package (not valid on UNIX platforms)
