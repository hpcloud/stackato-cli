#!/bin/sh

id="$1"
tkdiff X.result.*${id}.expected X.result.*${id}.actual
