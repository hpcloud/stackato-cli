Using the cli-tests/ testsuite for the stackoto cli
===================================================

Dependencies
------------

An ActiveTcl installation whose tclsh is in the PATH.
The Tcl packages 'fileutil' and 'try', installable with teacup.
(A run of "teacup update" after AT install might be easiest).

The 'Kettle' package and application.
More details about this in a separate section.

Stackato, of course.
The commands expect the 'stackato' cli in the PATH.


Commands and Scripts
--------------------

- clean-tests.sh	Cleanup left over files from a test run
- setup.sh		Example for configuring a target for the testsuite.
- run-tests.sh		Main script to invoke the testsuite.

Configuration
-------------

The code of the testsuite has a number of configurable settings in the file

	tests/support/common.tcl

To avoid having to modify this file these settings can be overridden
via environment variables.

The list of variables is shown in the script "run-tests.sh", with
their default values.

They fall into two groups. One set specifies things which have to be
configured before the testsuite is run, like the target and its
configuration. The other, smaller, set specifies data used by the
testsuite to generate things while it executes.

The script "setup.sh" shows the variables of the first group again,
and demonstrates how to set a target up with them.

When overriding a variable (most often the target itself), do it in
both scripts.

Performing tests
----------------

(1) Choose a target.
(2) Edit the scripts "run-tests.sh" and "setup.sh" for the chosen target.
    Make any other changes wanted regarding the target configuration.

(3) Run "setup.sh" to configure the target.
    This must be done only once per target and chosen configuration.

(4) Run "run-tests.sh" to run the testsuite.
    The full testsuite can run for 1.5 to 2 hours.

The result of a testsuite run are files named X.*, like X.log,
etc. These contain the results in details. During the run the
testsuite shows only aggregate information per test-file (number of
passed, skipped, failed, and total tests).

(5) Run "cleanup-tests.sh" after each test run to remove the results
    and other leftover files.

    Save the results if they are needed elsewhere.

Kettle
------

Kettle is a package an application to make dev of Tcl packages
easier. Part of that is its ability to drive a tcltest based
testsuite.

Using this part of Kettle for the cli tests was easier than having to
replicate all of that.

The file "build.tcl" is the configuration file for Kettle, and
"fake.tcl" the fake package through which we get the 'test' target.
See inside "run-tests.sh" for where this is used.

The easist way to get the Kettle sources is to copy the directory

	NAS/andreask/Dev/Aside/Tools/Kettle/fetch

to a temp directory of your choice.

To install it then run

	   tclsh ./kettle -f ./build.tcl install

from within that temp directory.

The "tclsh" in the command above must be the tclsh from your
installation of AT for the testsuite.

Advanced use
------------

The script "run-tests.sh" can take the same arguments as the "test"
target of "build.tcl".

Most often used is something like

	./run-tests.sh --tmatch 'foo*'

This restricts the testsuite to execute only those tests whose names
match the pattern, i.e. 'foo*'. This can of course be the exact name
of a test as well.

