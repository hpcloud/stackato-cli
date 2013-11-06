#!/bin/sh

rm -f X.* tests/*.out tests/*.err && \
clear     && \
echo      && \
time ./build.tcl test --log X "$@"
date

# Requirements: Tcl, Kettle package and app.

