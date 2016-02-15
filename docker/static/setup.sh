#!/bin/sh
# One-shot setup of a target for the testsuite.

# These variables must contain information created before testing, i.e. target, and target setup
# This script uses them here to perform the setup

# ATTENTION: The configuration used in the file "run-tests.sh" must
# match the configuration initialized here.

STACKATO_CLI_TEST_TARGET=${STACKATO_CLI_TEST_TARGET:-api.192.168.69.51.xip.io}
STACKATO_CLI_TEST_ADMIN=${STACKATO_CLI_TEST_ADMIN:-cli-test-admin@test}
STACKATO_CLI_TEST_APASS=${STACKATO_CLI_TEST_APASS:-cli-test-admin-pass}
STACKATO_CLI_TEST_ORG=${STACKATO_CLI_TEST_ORG:-cli-test-org}
STACKATO_CLI_TEST_SPACE=${STACKATO_CLI_TEST_SPACE:-cli-test-space}

# ATTENTION
# It is expected that the STACKATO_CLI_TEST_SPACE is the one and only
# space within the STACKATO_CLI_TEST_ORG.

# Execute the setup.

stackato target       -n $STACKATO_CLI_TEST_TARGET
stackato login        -n stackato --password stackato
stackato create-org   -n $STACKATO_CLI_TEST_ORG
stackato create-space -n $STACKATO_CLI_TEST_SPACE
stackato create-user  -n $STACKATO_CLI_TEST_ADMIN --email $STACKATO_CLI_TEST_ADMIN --password $STACKATO_CLI_TEST_APASS --admin
stackato login        -n stackato --password stackato

# This is configuration outside of the target itself
#STACKATO_CLI_TEST_DRAIN=tcp://flux.activestate.com:11100
exit
