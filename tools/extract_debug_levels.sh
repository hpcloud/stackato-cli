#!/bin/bash

config=$(cd $(dirname $0)/../config ; pwd)

grep -rn 'debug prefix ' lib bin "$@" |projection 3 >  $$
grep -rn 'debug define ' lib bin "$@" |projection 3 >> $$

cat $$ | grep -v '::' | sort -u > $config/debug-levels.txt
rm  $$
