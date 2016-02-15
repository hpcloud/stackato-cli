
[subsection Tcl]

As we are building a Tcl package and application it should be pretty
much obvious that a working installation of Tcl itself is needed, and
I will not belabor the point.

[para] Out of the many possibilites use whatever you are comfortable
with, as long as it provides Tcl 8.5, or higher.

This may be a Tcl installation provided by your operating system
distribution, from a distribution-independent vendor, or built by
yourself.

[para] Myself, I used (and still use)
[uri http://www.activestate.com ActiveState's]
ActiveTcl 8.5 distribution during development, as I am most familiar
with it.

[para] [emph {(Disclosure: I, Andreas Kupries, work for ActiveState, maintaining ActiveTcl and TclDevKit for them).}]

[para] This distribution can be found at
[uri http://www.activestate.com/activetcl]. Retrieve the archive of
ActiveTcl 8.5 for your platform and install it as directed by
ActiveState.

[para] Assuming that ActiveTcl got installed I usually run the command

[example {
    teacup update
}]

to install all packages ActiveState provides, and the kitchensink, as
the distribution itself usually contains only the most important set
of packages. This ensures that the dependencies for Kettle are all
present, and more.

[para] If that is not your liking you have to read the other sections
about Kettle's dependencies to determine the exact set of packages
required, and install only these using

[example {
    teacup install $packagename
}]

[para] Both [syscmd teacup] commands above assume that ActiveState's
TEApot repository at [uri http://teapot.activestate.com] is in the
list of repositories accessible to [syscmd teacup]. This is automatically
ensured for the ActiveTcl distribution. Others may have to run

[example {
    teacup archive add http://teapot.activestate.com
}]

to make this happen.

[para] For those wishing to build and install Tcl on their own, the
relevant sources can be found at

[list_begin definitions]
[def Tcl] [uri http://core.tcl.tk/tcl/]
[list_end]

together with the necessary instructions on how to build it.

[para] If there are problems with building, installing, or using Tcl
please file a bug against Tcl, or the vendor of your distribution, and
not Kettle.
