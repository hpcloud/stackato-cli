#!/bin/sh

if [ "X$1" = "X" ]
then
    stem="X"
else
    stem="$1"
fi

rm -rf ${stem}.* .kettle* tests/*.out tests/*.err tests/thehome

