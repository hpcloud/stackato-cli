
[subsection Tklib]

Kettle's "gui" recipe requires the following three packages found in
Tklib. If Tk or these packages are not installed the "gui" recipe
cannot be used, and attempting to do so will fail.

[list_begin enumerated]
[enum] [package widget::scrolledwindow]
[enum] [package widget::listsimple]
[enum] [package widget::dialog]
[list_end]

[para] Beyond that however the rest of Kettle will be fully
functional.

[para] Out of the many possibilites for getting Tclx (OS vendor,
os-independent vendor, building from sources) use whatever you are
comfortable with.

Well, mostly. The package [package widget::listsimple] currently
exists only in the CVS repository of Tklib (location at the end of the
section), and in ActiveState's TEApot.

[para] For myself, I am most comfortable with using
[uri http://www.activestate.com ActiveState's]
ActiveTcl distribution and TEApot.

[para] See the previous section ([sectref Tcl]) for disclosure and
information on how to get it.

[para] Assuming that ActiveTcl got installed running the commands

[example {
    teacup install widget::scrolledwindow
    teacup install widget::listsimple
    teacup install widget::dialog
}]

will install them for your platform, if you have not done the more
inclusive

[example {
    teacup update
}]

to get everything and the kitchensink.

[para] For those wishing to build and install Tklib on their own, the
relevant sources can be found at

[list_begin definitions]
[def Tcllib/Tklib] [uri http://sourceforge.net/projects/tcllib]
[list_end]

together with the necessary instructions on how to build it.

[para] If there are problems with building, installing, or using Tklib
and its packages please file a bug against Tklib, or the vendor of
your distribution, and not Kettle.
