## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## CMDR - Help - SQL format. Not available by default.
## Require this package before creation a commander, so that the
## mdr::help heuristics see and automatically integrate the format.

# @@ Meta Begin
# Package cmdr::help::sql 1.0
# Meta author   {Andreas Kupries}
# Meta location https://core.tcl.tk/akupries/cmdr
# Meta platform tcl
# Meta summary     Formatting help as series of SQL commands.
# Meta description Formatting help as series of SQL commands.
# Meta subject {command line}
# Meta require {Tcl 8.5-}
# Meta require debug
# Meta require debug::caller
# Meta require {cmdr::help 1}
# Meta require {cmdr::util 1}
# @@ Meta End

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require debug
package require debug::caller
package require cmdr::help 1
package require cmdr::util 1

# # ## ### ##### ######## ############# #####################

debug define cmdr/help/sql
debug level  cmdr/help/sql
debug prefix cmdr/help/sql {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

# # ## ### ##### ######## ############# #####################

namespace eval ::cmdr::help::format {
    namespace export sql
    namespace ensemble create

    namespace import ::cmdr::help::query
}

# # ## ### ##### ######## ############# #####################

proc ::cmdr::help::format::sql {root width help} {
    debug.cmdr/help/sql {}
    # help = dict (name -> command)

    # TABLES:
    # - commands   (id,name,desc,action)
    # - parameters (id,name,command-id,sequence, ...)
    # - arguments  (parameter-id,name,command-id,sequence)
    # - states     (parameter-id,name,command-id,sequence)
    # - options    (id,name,command-id,parameter-id,desc)
    # - flags      (id,name,type,parameter-id)

    # State, imported into the generator functions.
    set commands   {} ; set cno 0
    set parameters {} ; set pno 0
    set arguments  {} ; # arguments are unique parameters
    set options    {} ; set ono 0
    set states     {} ; # states are unique parameters
    set flags      {} ; # flags match to options

    foreach {cmd desc} $help {
	SQL $cmd $desc
    }

    lappend lines {-- Commands}   {*}$commands   {}
    lappend lines {-- Parameters} {*}$parameters {}
    lappend lines {-- Arguments}  {*}$arguments  {}
    lappend lines {-- Options}    {*}$options    {}
    lappend lines {-- States}     {*}$states     {}
    lappend lines {-- Flags}      {*}$flags      {}

    return \n\n[SQL::schema]\n\n[join $lines \n]\n
}

# # ## ### ##### ######## ############# #####################

namespace eval ::cmdr::help::format::SQL {}

proc ::cmdr::help::format::SQL {name command} {
    # Data structure: see config.tcl,  method 'help'.
    # Data structure: see private.tcl, method 'help'.

    upvar 1 commands   xcommands   cno cno
    upvar 1 parameters xparameters pno pno
    upvar 1 arguments  xarguments
    upvar 1 options    xoptions    ono ono
    upvar 1 states     xstates
    upvar 1 flags      xflags

    # ---

    dict with command {} ; # -> action, desc, options, arguments, parameters, states

    set cid [SQL::++ commands cno [SQL::astring $name] \
		 [SQL::astring $desc] [SQL::astring $action]]

    set sequence 0
    foreach {pname param} $parameters {
	set pid [SQL::++ parameters pno [SQL::astring $pname] \
		     $cid $sequence \
		     {*}[SQL::para $param]]

	dict set pmap $pname $pid

	foreach {fname ftype} [dict get $param flags] {
	    set fid [SQL::++ flags ono [SQL::astring $fname] \
			 [SQL::astring $ftype] $pid]

	    dict set fmap $fname $pid
	    dict set omap $fname $fid
	    # Redundancy: pid --> cid
	}

	incr sequence
    }

    set sequence 0
    foreach aname $arguments {
	set pid [dict get $pmap $aname]
	SQL::== arguments $pid [SQL::astring $aname] \
	    $cid $sequence
	incr sequence
    }

    foreach {flag desc} $options {
	set pid [dict get $fmap $flag]
	set fid [dict get $omap $flag]
	SQL::== options $fid [SQL::astring $flag] \
	    $cid $pid [SQL::astring $desc]
	# Redundancy: fid --> flag
	# Redundancy: fid --> cid
    }

    set sequence 0
    foreach sname $states {
	set pid [dict get $pmap $sname]
	SQL::== states $pid [SQL::astring $sname] \
	    $cid $sequence
	incr sequence
	# Redundancy: pid --> sname
    }

    return
}

proc ::cmdr::help::format::SQL::para {def} {
    set result {}

    foreach {xname xdef} [::cmdr util dictsort $def] {
	switch -glob -- $xname {
	    cmdline -
	    defered -
	    documented -
	    interactive -
	    isbool -
	    list -
	    ordered -
	    presence -
	    required -
	    @bool {
		# normalize to boolean
		set value [expr {!!$xdef}]
	    }
	    threshold {
		# null|integer
		set value [expr {($xdef eq {}) ? "NULL" : $xdef}]
	    }
	    code -
	    default -
	    description -
	    prompt -
	    type -
	    generator -
	    validator -
	    label -
	    @string {
		set value [astring $xdef]
	    }
	    flags {
		# Ignored, handled separately (see caller).
		continue
	    }
	    * {
		error "Unknown key \"$xname\", do not know how to format"
		#lappend tmp $xname [astring $xdef]
	    }
	}
	lappend result $value
    }
    return $result
}

# # ## ### ##### ######## ############# #####################

proc ::cmdr::help::format::SQL::++ {table idvar args} {
    upvar 1 $idvar counter x$table lines
    set last $counter
    lappend lines "INSERT INTO $table VALUES ($counter, [join $args {, }]);"
    incr counter
    return $last
}

proc ::cmdr::help::format::SQL::== {table id args} {
    upvar 1 x$table lines
    lappend lines "INSERT INTO $table VALUES ($id, [join $args {, }]);"
    return
}

proc ::cmdr::help::format::SQL::astring {string} {
    lappend map "\"" "\"\""
    regsub -all -- {[ \n\t]+} $string { } string
    return \"[string map $map [string trim $string]]\"
}

proc ::cmdr::help::format::SQL::schema {} {
    return {
	CREATE TABLE commands (
	       id     INTEGER PRIMARY KEY,
	       name   STRING,
	       desc   STRING,
	       action STRING,
	       UNIQUE ( name )
       );
	CREATE TABLE parameters (
	       id   INTEGER PRIMARY KEY,
	       name STRING,
	       cid  INTEGER REFERENCES commands,
	       seq  INTEGER,
	       -- --- Parameter Details
	       cmdline     INTEGER,
	       code        STRING,
	       dfltvalue   STRING,
	       defered     INTEGER,
	       description STRING,
	       documented  INTEGER,
	       generator   STRING,
	       interactive INTEGER,
	       isbool      INTEGER,
	       list        INTEGER,
	       ordered     INTEGER,
	       presence    INTEGER,
	       prompt      STRING,
	       required    INTEGER,
	       threshold   INTEGER,
	       type        STRING,
	       validator   STRING,
	       -- ---
	       UNIQUE ( cid, seq )
       );
	CREATE INDEX pname on parameters ( name );
	CREATE TABLE arguments (
	       id   INTEGER PRIMARY KEY REFERENCES parameters,
	       name STRING,
	       cid  INTEGER REFERENCES commands,
	       seq  INTEGER,
	       UNIQUE ( cid, seq )
       );
	CREATE INDEX aname on arguments ( name );
	CREATE TABLE options (
	       id   INTEGER PRIMARY KEY,
	       name STRING,
	       cid  INTEGER REFERENCES commands,
	       pid  INTEGER REFERENCES parameters,
	       desc STRING
       );
	CREATE INDEX oname on options ( name );
	CREATE TABLE states (
	       id   INTEGER PRIMARY KEY REFERENCES parameters,
	       name STRING,
	       cid  INTEGER REFERENCES commands,
	       seq  INTEGER,
	       UNIQUE ( cid, seq )
       );
	CREATE INDEX sname on states ( name );
	CREATE TABLE flags (
	       id   INTEGER PRIMARY KEY REFERENCES options,
	       name STRING,
	       type STRING,
	       pid  INTEGER REFERENCES parameters
       );
	CREATE INDEX fname on flags ( name );
    }
}
# # ## ### ##### ######## ############# #####################
## Ready
package provide cmdr::help::sql 1.0
