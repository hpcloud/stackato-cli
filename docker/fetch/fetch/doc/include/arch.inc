
The high-level architecture is shown in the image below:

[para][image architecture][para]

This document is concerned with the lowest level shown, the core
kettle package itself. The inner boxes of that architectural box show
the parts which are user-visible, i.e. providing the DSL commands
explained in [term {Kettle - Build Declarations}].

For the details we have

[para][image pkg_dependencies][para]

In this image we now see all the components found inside of the kettle
package, their organization into layers and their dependencies. The
latter is actually a bit simplified, showing only the dependencies
between adjacent layers and leaving out the dependencies crossing
layers. Adding them would make the image quite a bit more crowded.

[para] The green boxes are again the user-visible parts, either for
the build declarations. The rest is internal. Note how and that the
components found in the blue box are all dependent on each other,
i.e. these are in circular dependencies.

[para] The names in the boxes directly refer to the file names
containing the code of the component, without the extension,
[file .tcl].

The only file not mentioned is [file kettle.tcl] which is the
entrypoint to the package and sources all the others.
