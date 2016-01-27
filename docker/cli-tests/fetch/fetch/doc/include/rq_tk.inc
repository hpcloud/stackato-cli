
[subsection Tk]

Kettle's "gui" recipe requires Tk, obviously, and three packages found
in Tklib (see next section). If Tk or the other packages are not
installed the "gui" recipe cannot be used, and attempting to do so
will fail.

[para] Beyond that however the rest of Kettle will be fully
functional.

[para] Out of the many possibilites for getting Tk use whatever you
are comfortable with, as long as it provides Tk 8.5, or higher (we use
the themed widgets, and Tcl 8.5 is our base).

This may be a Tk package provided by your operating system
distribution, from a distribution-independent vendor, or built by
yourself.

[para] Myself, I used (and still use)
[uri http://www.activestate.com ActiveState's]
ActiveTcl 8.5 distribution during development, as I am most familiar
with it.

[para] See the previous section ([sectref Tcl]) for disclosure and
information on how to get it.

[para] Assuming that ActiveTcl got installed Tk will be installed as
well.

[para] For or those wishing to build and install Tk on their own, the
relevant sources can be found at

[list_begin definitions]
[def Tk] [uri http://core.tcl.tk/tk/]
[list_end]

together with the necessary instructions on how to build it.

[para] If there are problems with building, installing, or using Tk
please file a bug against Tk, or the vendor of your distribution, and
not Kettle.
