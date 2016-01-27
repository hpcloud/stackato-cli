# -*- tcl -*- Copyright (c) 2012 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## Benchmark Application (Entry point into .bench files)
##
## argv = benchfile (bench arguments ...)

# Kettle is designed to accomodate 8.5+
package require Tcl 8.5

# Accomodate use of wish as benchmark shell.
catch {wm withdraw .}

# # ## ### ##### ######## ############# #####################
## Get the kettle information before loading tclbench. Everything goes
## into the ::kb namespace to separate things from tclbench and others
## (the benchmarks).

namespace eval ::kb {}

set argv [lassign $argv kb::uconfig kb::benchfile]
set argv $kb::benchfile

set ::kb::localprefix [dict get $::kb::uconfig prefix]
dict unset $kb::uconfig prefix

# # ## ### ##### ######## ############# #####################
## Import tclbench - Local copy. Snarfed from tcllib/bench.
## Later, when running the bench file. This is the main script,
## behaves like an application, not a package.

# # ## ### ##### ######## ############# #####################
## Management utilities for communication with the 'benchmarks' recipe
## support code in our caller.

proc kb::Note {k v} {
    puts  stdout [list @@ $k $v]
    flush stdout
    return
}

proc kb::Now {} {return [clock seconds]}

# Ensure an fully normalized absolute path to the benchmark location.
set kb::benchDirectory [file dirname [file dirname [file normalize $kb::benchfile]/___]]

# # ## ### ##### ######## ############# #####################
## Start reporting, the environment in which the benchmarks are run.

puts stdout ""
kb::Note Host       [info hostname]
kb::Note Platform   $tcl_platform(os)-$tcl_platform(osVersion)-$tcl_platform(machine)
kb::Note BenchDir   $::kb::benchDirectory
kb::Note LocalDir   $::kb::localprefix
kb::Note BenchCWD   [pwd]
kb::Note Shell      [info nameofexecutable]
kb::Note Tcl        [info patchlevel]

# Host  => Platform | Identity of the Benchmark environment.
# Shell => Tcl      |
# CWD               | Identity of the package getting profiles.

if {[llength [set v [dict get $::kb::uconfig MATCH]]]}  { kb::Note MatchTestsG $v }
if {[llength [set v [dict get $::kb::uconfig RMATCH]]]} { kb::Note MatchTestsR $v }

# # ## ### ##### ######## ############# #####################
## Import kettle provided utility commands (kb:: namespace)
## the benchmarks can use. And a try/finally for ourselves.

source [file dirname [file normalize [info script]]]/try.tcl
source [file dirname [file normalize [info script]]]/benchutilities.tcl
#source [file dirname [file normalize [info script]]]/libbench.tcl

# Override the global configuration defaults with the user's choices.
array set kb::config $kb::uconfig

# # ## ### ##### ######## ############# #####################
## Run the benchmarks

kb::Note Benchmark $kb::benchfile
kb::Note Start [kb::Now]

if {[catch {
    # Read the main application file. This defines
    # bench commands, processes argv and runs the
    # bench file found there.
    source $kb::benchfile
} msg]} {
    # Transmit stack trace in capturable format.
    puts stdout "@+"
    puts stdout @|[join [split $errorInfo \n] "\n@|"]
    puts stdout "@-"
}

kb::Note End [kb::Now]
puts ""

# # ## ### ##### ######## ############# #####################
# FRINK: nocheck
# Use of 'exit' ensures proper termination of the test system when
# driven by a 'wish' instead of a 'tclsh'. Otherwise 'wish' would
# enter its regular event loop and no tests would complete.
exit
