
[subsection tcltest]

Kettle's "test" recipe requires the [package tcltest] package.  If
this package is not installed the "test" recipe cannot be used, and
attempting to do so will fail.

[para] Note however that the sources of tcltest come with a source
distribution of Tcl and the package should always be installed
together with Tcl itself.

[para] If there are problems with using tcltest please file a bug
against Tcl, or the vendor of your Tcl distribution, and not Kettle.
