#!/bin/sh

start=`date`

rm -f X.* tests/*.out tests/*.err && \
clear     && \
echo      && \
echo Arguments "$@" && \
time ./build.tcl test --log X "$@"

echo Started__ $start
echo Completed `date`

# Requirements: Tcl, Kettle package and app.

