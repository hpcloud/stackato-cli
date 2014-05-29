Using the "cli-tests/" testsuite for the stackoto cli
=====================================================

Dependencies
------------

An ActiveTcl installation whose tclsh is in the PATH.

The Tcl packages 'fileutil' and 'try', installable with teacup. A run
of "teacup update" after AT install might be easiest.

The 'Kettle' package and application, plus dependencies. More details
about this in a moment, see the next section.

Stackato, of course.
The commands expect to find the "stackato" cli in the PATH.

Kettle
------

Kettle is a package and application to ease the development of Tcl
packages. Part of that is its ability to drive a tcltest based
testsuite.

The file "build.tcl" is the configuration file for Kettle, and
"fake.tcl" the fake Tcl package through which we get the 'test'
target.  See inside "run-tests.sh" for where this is used.

To install Kettle go to

	(main site)	https://core.tcl.tk/akupries/kettle/index
or	(2dary site)	https://chiselapp.com/user/andreas_kupries/repository/Kettle/index

and follow the instructions on

	How To Get The Sources
and	How To Build And Install The Packages

found on these pages.

Assuming that ActiveTcl is used as foundation I reiterate that using
the command "teacup update" is the easiest way of getting all the
necessary dependencies.

Commands and Scripts
--------------------

- clean-tests.sh	Cleanup left over files from a test run
- setup.sh		Example for configuring a target for the testsuite.
- run-tests.sh		Main script to invoke the testsuite.

Configuration
-------------

The code of the testsuite has a number of configurable settings, all
found in the file

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

When overriding a variable (most often the target itself), it should
be done in both scripts.

Performing tests
----------------

(1) Choose a target.
(2) Edit the scripts "run-tests.sh" and "setup.sh" for the chosen target.
    Make any other changes wanted regarding the target configuration.

(3) Run "setup.sh" to configure the target.
    This must be done only once per target and chosen configuration.

(4) Run "run-tests.sh" to run the testsuite.
    The full testsuite can run for 1.5 to 2 hours.
    This depends on the network and the speed of the target.

    The results of a testsuite run are found in files named X.*, like
    X.log, etc. These contain the results in details. During the run
    the testsuite shows only aggregate information per test-file
    (number of passed, skipped, failed, and total tests).

(5) Run "cleanup-tests.sh" after each test run to remove the results
    and other leftover files.

    Save the results if they are needed elsewhere.

Advanced use
------------

The script "run-tests.sh" can take the same arguments as the "test"
target of "build.tcl".

Most often used is something like

	./run-tests.sh --tmatch 'foo*'

This restricts the testsuite to execute only those tests whose names
match the pattern, i.e. 'foo*'. This can of course be the exact name
of a test as well.
