#!/bin/bash
function finish {
	cli-tests/clean-tests.sh
}
trap finish EXIT

cd cli-tests
egrep -o "api\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.xip\.io" setup.sh
stackato target $(egrep -o "api\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.xip\.io" setup.sh)
stackato login stackato --password stackato
./setup.sh
./run-tests.sh

