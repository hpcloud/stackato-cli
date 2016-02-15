#!/bin/sh
## Generate help files

HOME=$(pwd)

echo categorized...
stackato help --width 79 --no-pager         > h-categorized.txt

echo list...
stackato help --width 79 --no-pager --list  > h-list.txt

echo short...
stackato help --width 79 --no-pager --short > h-short.txt

rm -rf .stackato
