#!/bin/sh

## Copyright (c) 2013 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

rm -f X.* tests/*.out tests/*.err && \
clear     && \
echo      && \
time ./build.tcl test --log X "$@"
date

# Requirements: Tcl, Kettle package and app.

