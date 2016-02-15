# -*- tcl -*- Copyright (c) 2012-2013 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## Kettle package

# @@ Meta Begin
# Package kettle 0
# Meta platform tcl
# Meta author      {Andreas Kupries}
# Meta summary     Build support package.
# Meta description Kettle is a system to make building Tcl
# Meta description packages quick and easy. More importantly,
# Meta description possibly, to make writing the build system
# Meta description for Tcl packages easy.
# Meta description As such kettle is several things:
# Meta description (1) A DSL helping you to write build systems
# Meta description for your packages. (2) A package implementing
# Meta description this DSL. (3) An application which can serve
# Meta description as the interpreter for a build file containing
# Meta description commands in the above DSL.
# Meta subject {build support} critcl teapot {meta data}
# Meta subject doctools diagram
# Meta require {Tcl 8.5-}
# Meta category Builder/Developer support
# Meta location https://core.tcl.tk/akupries/kettle
# @@ Meta End

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
namespace eval ::kettle {}

# # ## ### ##### ######## ############# #####################
## Export

namespace eval ::kettle {
    namespace export {[a-z]*}
    namespace ensemble create
}

# # ## ### ##### ######## ############# #####################
## @owns: app.tcl
## @owns: atexit.tcl
## @owns: benchmarks.tcl
## @owns: critcl.tcl
## @owns: depend.tcl
## @owns: doc.tcl
## @owns: figures.tcl
## @owns: gui.tcl
## @owns: invoke.tcl
## @owns: io.tcl
## @owns: lambda.tcl
## @owns: mdref.tcl
## @owns: meta.tcl
## @owns: options.tcl
## @owns: ovalidate.tcl
## @owns: path.tcl
## @owns: recipes.tcl
## @owns: special.tcl
## @owns: standard.tcl
## @owns: status.tcl
## @owns: stream.tcl
## @owns: strutil.tcl
## @owns: tcl.tcl
## @owns: tclapp.tcl
## @owns: testsuite.tcl
## @owns: tool.tcl
## @owns: try.tcl

# # ## ### ##### ######## ############# #####################

## The next two files are not sourced as part of the kettle application.
##
# The first is the main entry point for the 'test' and related
# recipes, i.e. the application running a specific .test file. It is
# used to communicate build configuration data into the test
# environment.
##
# The other provides lots of utilities to make writing tests easier.

## @owns: testmain.tcl
## @owns: testutilities.tcl

## The next three files are not sourced as part of the kettle application.
##
# The first is the main entry point for the 'benchmark' recipe, i.e. the
# application running a specific .bench file. It is used to communicate
# build configuration data into the benchmarking environment.
##
# The second provides lots of utilities to make writing tests easier.
##
# The third is the actual application, snarfed from Tcllib, implementing
# the benchmark commands and running files.

## @owns: benchmain.tcl
## @owns: benchutilities.tcl
## @!owns: libbench.tcl

# # ## ### ##### ######## ############# #####################

::apply {{selfdir} {
    # # ## ### ##### ######## ############# ##################### Foundation
    source $selfdir/atexit.tcl     ; # Application shutdown handlers.
    source $selfdir/lambda.tcl     ; # Nicer way of writing apply
    source $selfdir/try.tcl        ; # try/finally coded in Tcl, snarfed from 8.6
    source $selfdir/strutil.tcl    ; # String utilities.
    source $selfdir/io.tcl         ; # Message output support.
    # # ## ### ##### ######## ############# #####################
    source $selfdir/status.tcl     ; # General goal status.
    source $selfdir/path.tcl       ; # General path utilities.
    source $selfdir/mdref.tcl      ; # Teapot pkg ref utilities.
    source $selfdir/meta.tcl       ; # Teapot meta data utilities.
    source $selfdir/ovalidate.tcl  ; # Option Validation sub layer.
    source $selfdir/options.tcl    ; # Option management.
    # # ## ### ##### ######## ############# #####################
    source $selfdir/recipes.tcl    ; # Recipe management.
    source $selfdir/invoke.tcl     ; # Goal recursion via sub-processes.
    source $selfdir/tool.tcl       ; # Manage tool requirements.
    source $selfdir/stream.tcl     ; # Log streams
    # # ## ### ##### ######## ############# #####################
    source $selfdir/gui.tcl        ; # GUI support.
    source $selfdir/special.tcl    ; # Special commands.
    source $selfdir/app.tcl        ; # Application core.
    # # ## ### ##### ######## ############# #####################
    source $selfdir/standard.tcl   ; # Standard recipes.
    # # ## ### ##### ######## ############# #####################
    # # ## ### ##### ######## ############# ##################### DSL
    source $selfdir/depend.tcl     ; # dependency setup.
    source $selfdir/tclapp.tcl     ; # tcl script applications
    source $selfdir/figures.tcl    ; # figures       (diagram)
    source $selfdir/testsuite.tcl  ; # testsuite     (tcltest)
    source $selfdir/benchmarks.tcl ; # benchmarks    (tclbench)
    # # ## ### ##### ######## ############# #####################
    source $selfdir/doc.tcl        ; # documentation (doctools, gh-pages)
    # # ## ### ##### ######## ############# #####################
    source $selfdir/tcl.tcl        ; # tcl packages
    source $selfdir/critcl.tcl     ; # critcl v3 packages
    # # ## ### ##### ######## ############# #####################
    kettle::option::set @kettledir $selfdir
}} [file dirname [file normalize [info script]]]

# # ## ### ##### ######## ############# #####################
## Ready

package provide kettle 1
return

# # ## ### ##### ######## ############# #####################
