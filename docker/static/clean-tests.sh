#!/bin/sh

if [ "X$1" = "X" ]
then
    stem="X"
else
    stem="$1"
fi

rm -rf ${stem}.* .kettle* tests/*.out tests/*.err tests/thehome
stackato delete-user cli-test-admin@test && stackato delete-space -n cli-test-space && stackato delete-org -n cli-test-org
