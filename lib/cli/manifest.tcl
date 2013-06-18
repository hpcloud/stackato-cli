# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require url
package require tclyaml
package require fileutil
package require stackato::log
package require stackato::color
package require stackato::term
package require varsub ; # Utility package, local, variable extraction and resolution

package require stackato::client::cli::config
package require stackato::client::cli::usage

namespace eval ::stackato::client::cli::manifest::usage {
    namespace import ::stackato::client::cli::usage::me
}

debug level  cli/manifest/core
debug prefix cli/manifest/core {}

debug level  cli/manifest/core/resolve
debug prefix cli/manifest/core/resolve {}

# # ## ### ##### ######## ############# #####################
## API. Our own. Hide structural details of the manifest from higher levels.
## Write to a manifest.
##
## NOTE: The generated structure is that of stackato.yml, with only CF
##       specific parts (like url, and extended framework) in manifest.yml
##       syntax. This also assumes a single-application manifest.

proc ::stackato::client::cli::manifest::save {dstfile} {
    variable outmanifest

    Debug.cli/manifest/core {=== Saving to $dstfile}
    Debug.cli/manifest/core {=== RECORDED MANIFEST FROM INTERACTION ====}
    Debug.cli/manifest/core {[DumpX $outmanifest]}
    Debug.cli/manifest/core {===========================================}

    tclyaml writeTags file $dstfile [RetagMappingKeys $outmanifest]

    Debug.cli/manifest/core {Saved}
    return
}

proc ::stackato::client::cli::manifest::resetout {} {
    variable          outmanifest
    unset -nocomplain outmanifest
    return
}

proc ::stackato::client::cli::manifest::name= {name} {
    variable outmanifest
    InitializeOutManifest
    DictSet outmanifest name [Cscalar $name]
    return
}

proc ::stackato::client::cli::manifest::url= {urls} {
    variable outmanifest
    InitializeOutManifest

    if {[llength $urls] > 1} {
	set ts {}
	foreach u $urls {
	    lappend ts [Cscalar $u]
	}
	DictSet outmanifest applications . url \
	    [Csequence {*}$ts]
    } else {
	DictSet outmanifest applications . url \
	    [Cscalar [lindex $urls 0]]
    }
    return
}

proc ::stackato::client::cli::manifest::instances= {n} {
    variable outmanifest
    InitializeOutManifest
    DictSet outmanifest instances [Cscalar $n]
    return
}

proc ::stackato::client::cli::manifest::mem= {mem} {
    variable outmanifest
    InitializeOutManifest
    DictSet outmanifest mem [Cscalar $mem]
    return
}

proc ::stackato::client::cli::manifest::framework= {type} {
    variable outmanifest
    InitializeOutManifest
    DictSet outmanifest framework type [Cscalar $type]
    return
}

proc ::stackato::client::cli::manifest::runtime= {runtime} {
    variable outmanifest
    InitializeOutManifest
    DictSet outmanifest framework runtime [Cscalar $runtime]
    return
}

proc ::stackato::client::cli::manifest::command= {command} {
    variable outmanifest
    InitializeOutManifest
    DictSet outmanifest command [Cscalar $command]
    return
}

proc ::stackato::client::cli::manifest::services= {services} {
    variable outmanifest
    InitializeOutManifest

    # services = (servicename vendor ...)
    set ts {}
    foreach {s v} $services {
	# Save in order servicename -> vendor
	lappend ts $s [Cscalar $v]
    }
    DictSet outmanifest services [Cmapping {*}$ts]
    return
}

proc ::stackato::client::cli::manifest::InitializeOutManifest {} {
    variable outmanifest
    if {[info exists outmanifest]} return
    set outmanifest {mapping {}}
    return
}

# # ## ### ##### ######## ############# #####################
## API. Our own. Hide structural details of the manifest from higher levels.
## Read from the manifest.

proc ::stackato::client::cli::manifest::minVersionClient {v} {
    upvar 1 $v version
    variable currentappinfo
    if {![info exists currentappinfo]} { return 0 }
    return [FindInDictionary $currentappinfo version \
		stackato min_version client]
}

proc ::stackato::client::cli::manifest::minVersionServer {v} {
    upvar 1 $v version
    variable currentappinfo
    if {![info exists currentappinfo]} { return 0 }
    return [FindInDictionary $currentappinfo version \
		stackato min_version server]
}

proc ::stackato::client::cli::manifest::name {} {
    variable currentappinfo
    return [DictGet' $currentappinfo name {}]
}

proc ::stackato::client::cli::manifest::services {} {
    variable currentappinfo
    return [DictGet' $currentappinfo services {}]
}

proc ::stackato::client::cli::manifest::instances {} {
    variable currentappinfo
    return [DictGet' $currentappinfo instances 1]
}

proc ::stackato::client::cli::manifest::runtime {} {
    variable currentappinfo
    set res [DictGet' $currentappinfo runtime {}]
    Debug.cli/manifest/core {manifest::runtime ($currentappinfo)}
    Debug.cli/manifest/core {manifest::runtime ==> ($res)}
    return $res
}

proc ::stackato::client::cli::manifest::command {} {
    variable currentappinfo
    return [DictGet' $currentappinfo command {}]
}

proc ::stackato::client::cli::manifest::framework {} {
    variable currentappinfo
    return [DictGet' $currentappinfo framework name {}]
}

proc ::stackato::client::cli::manifest::framework-info {} {
    variable currentappinfo
    return [DictGet' $currentappinfo framework info {}]
}

proc ::stackato::client::cli::manifest::mem {} {
    variable currentappinfo
    return [DictGet' $currentappinfo mem {}]
}

proc ::stackato::client::cli::manifest::exec {} {
    variable currentappinfo
    return [DictGet' $currentappinfo exec {}]
}

proc ::stackato::client::cli::manifest::urls {} {
    Debug.cli/manifest/core {}
    variable currentappinfo
    if {[FindInDict $currentappinfo ulist url] ||
	[FindInDict $currentappinfo ulist urls]} {
	Debug.cli/manifest/core {Found = $ulist}
	lassign [Tags! {scalar sequence} $ulist {key "url(s)"}] tag data
	switch -exact -- $tag {
	    scalar   { return [list $data] }
	    sequence { return [StripTags $ulist] }
	    default {
		error "Internal error, Tags! failed to block unknown tag '$tag'"
	    }
	}
    } else {
	Debug.cli/manifest/core {Nothing}
	return {}
    }
}

proc ::stackato::client::cli::manifest::p-web {} {
    variable currentappinfo
    if {[FindInDictionary $currentappinfo result \
	     stackato processes web]} {
	# Check for explicit null value, translate to empty.
	# (for the purposes of 'generic').
	if {$result in {null Null NULL ~}} { return {} }
	return $result
    } else {
	# undefined, empty for the purposes of 'generic'.
	return {}
    }
}

proc ::stackato::client::cli::manifest::standalone {} {
    variable currentappinfo
    # A defined processes/web key which is empty, or null means 'standalone'.
    # An undefined key is _not_ standalone, but default serverside handling.
    if {[FindInDictionary $currentappinfo result \
	     stackato processes web] &&
	($result in {{} null Null NULL ~})} {
	return 1
    } else {
	# undefined, or not empty. NOT standalone.
	return 0
    }
}

proc ::stackato::client::cli::manifest::env {} {
    variable currentappinfo
    return [DictGet' $currentappinfo stackato env {}]
}

proc ::stackato::client::cli::manifest::ignorePatterns {} {
    variable currentappinfo

    # The defaults contain patterns to drop the dot-files and
    # -directories of various source code control systems.

    return [DictGet' $currentappinfo stackato ignores {
	.git/
	*.svn/
	.hg/
	*CVS/
	_FOSSIL_ .fos .fslckout
	*.bzr
	*.cdv
	*.pc
	*RCS
	*SCCS
	*_MTN
	*_build
	*_darcs
	*_sgbak
	*autom4te.cache
	*blib
	*cover_db
	*~
	\#*\#
	*.log
	*~.dep
	*~.dot
	*~.nib
	*~.plst
	~*/
    }]
    return
}

# # ## ### ##### ######## ############# #####################
## API (vmc - cli/manifest_helper.rb)

proc ::stackato::client::cli::manifest::rememberapp {} {
    variable remember 1
    return
}

proc ::stackato::client::cli::manifest::1orall {appname cmd {revers 0}} {
    if {$appname eq {}} {
	# Check usability of the configuration, counting applications,
	# and presence of proper application names.

	set have 0
	set bad 0
	foreach_app name {
	    incr have
	    if {$name eq {}} { incr bad }
	} 0 ; # Do not fail if there are no applications. We generate
	#     # our own error message.

	if {!$have} {
	    stackato::log::err "No application specified, and none found in current working directory."
	}

	if {$bad} {
	    if {$have > 1} {
		# Multiple applications, at least one without name.
		stackato::log::err "$bad of $have applications found are without 'name'."
	    } else {
		# Have one application, it must be without name.
		# Ask user for the name to use.

		variable savedapp
		if {![info exists savedapp]} {
		    variable basepath
		    set maybe [::file tail $basepath]
		    if {[uplevel 1 {my promptok}]} {
			set proceed [::stackato::term ask/yn \
					 "Would you like to use '$maybe' as application name ? "]
			if {$proceed} {
			    set appname $maybe
			} else {
			    set appname [::stackato::term ask/string "Application Name: "]
			}
		    } else {
			set appname $maybe
		    }

		    Debug.cli/manifest/core {- user ($appname)}

		    variable remember
		    if {[info exists remember]} {
			unset remember
			variable savedapp $appname
		    }
		} else {
		    set appname $savedapp
		    unset savedapp
		}
	    }
	}

	if {$revers} {
	    foreach_app name {
		uplevel 1 {my MinVersionChecks}
		if {$name eq {}} { set name $appname }
		lappend apps $name
	    }
	    foreach name [lreverse $apps] {
		{*}$cmd $name
	    }

	} else {
	    foreach_app name {
		uplevel 1 {my MinVersionChecks}
		if {$name eq {}} { set name $appname }
		{*}$cmd $name
	    }
	}
	return
    }

    current@path
    uplevel 1 {my MinVersionChecks}
    {*}$cmd $appname
    return
}

proc ::stackato::client::cli::manifest::1app {appname cmd} {
    # Note that these two uplevel's are hackish, expecting the caller
    # to have a specific environment (Inside method of an TclOO
    # instance with ServiceHelp among its superclasses).

    # See also c_svchelp.tcl, method 'AppName'.

    Debug.cli/manifest/core {1app a=($appname) \[$cmd\]}

    # (1) appname from the options...
    if {$appname eq {}} {
	set appname [dict get' [uplevel 1 {my options}] name {}]

	Debug.cli/manifest/core {- options ($appname)}
    }

    # (2) configuration files (stackato.yml, manifest.yml)
    if {$appname eq {}} {
	set have 0
	foreach_app name {
	    lappend apps $name
	    incr have
	} 0 ; # don't panic if no applications are found.

	if {$have > 1} {
	    ::stackato::log::err \
		" Found more than one application in the configuration.\n\tUnable to choose.\n\tPlease specify the application to operate on."
	}
	# have in {0,1}
	if {$have} {
	    set appname [lindex $apps 0]
	}

	Debug.cli/manifest/core {- configuration ($appname)}
    }

    # (3) May ask the user, use deployment path as default ...
    if {$appname eq {}} {
	variable basepath
	set maybe [::file tail $basepath]
	if {[uplevel 1 {my promptok}]} {
	    set proceed [::stackato::term ask/yn \
			     "Would you like to use '$maybe' as application name ? "]
	    if {$proceed} {
		set appname $maybe
	    } else {
		set appname [::stackato::term ask/string "Application Name: "]
	    }
	} else {
	    set appname $maybe
	}

	Debug.cli/manifest/core {- user ($appname)}
    }

    # Fail without name
    if {$appname eq {}} {
	stackato::log::err "Application Name required."
    }

    Debug.cli/manifest/core {- exists? ($appname)}

    if {![uplevel 1 [list my app_exists? $appname]]} {
	::stackato::log::err "Application '$appname' could not be found"
    }

    Debug.cli/manifest/core {- check version, and invoke cmd}

    uplevel 1 {my MinVersionChecks}
    return [{*}$cmd $appname]
}

proc ::stackato::client::cli::manifest::current {} {
    variable currentapp ; # XXX abs path. Not sure if good.
    return  $currentapp
}

proc ::stackato::client::cli::manifest::currentInfo {dstfile} {
    variable currentappinfo
    variable currentistotal
    variable manifest

    Debug.cli/manifest/core {currentInfo => $dstfile}
    Debug.cli/manifest/core {  total = $currentistotal}
    Debug.cli/manifest/core {=== APP INFO MANIFEST =====================}
    Debug.cli/manifest/core {[DumpX $currentappinfo]}
    Debug.cli/manifest/core {===========================================}
    Debug.cli/manifest/core {=== FULL MANIFEST =========================}
    Debug.cli/manifest/core {[DumpX $manifest]}
    Debug.cli/manifest/core {===========================================}

    if {$currentistotal} {
	# app info is whole manifest, with outer container and all
	set todump $currentappinfo
    } else {
	# Wrap a fake outer container around the
	# just-one-application-data, using path ".".

	set todump [dict create applications [Cmapping . $currentappinfo]]

	# Further, copy all toplevel keys found in the manifest which
	# are not in the appinfo. These are unknown keys (to us) we
	# should transfer as-is, in case the server understands them.

	set cai [Tag! mapping $currentappinfo {}]
	foreach {k v} [Tag! mapping $manifest {}] {
	    if {$k eq "applications"} continue
	    if {[dict exists $cai $k]} continue
	    dict set todump $k $v
	}

	# Finalize the wrapping.
	set todump [Cmapping {*}$todump]
    }

    Debug.cli/manifest/core {   dump = $todump}

    # Bug 92878: Generate an empty tagged structure if the manifest is empty overall.
    if {$todump eq {}} { set todump {mapping {}} }

    set todump [RetagMappingKeys $todump]

    Debug.cli/manifest/core {  dump' = $todump}

    tclyaml writeTags file $dstfile $todump

    Debug.cli/manifest/core {=== GENERATED MANIFEST ====================}
    Debug.cli/manifest/core {[Dump $todump]}
    Debug.cli/manifest/core {===========================================}
    return
}

proc ::stackato::client::cli::manifest::current@path {} {
    Debug.cli/manifest/core {manifest.current@path}

    variable basepath
    variable manifest
    variable currentapp [::file normalize $basepath]
    variable currentistotal 1
    variable currentappinfo {}

    Debug.cli/manifest/core {  basepath       = $basepath}
    Debug.cli/manifest/core {  currentapp     = $currentapp}

    if {![info exists manifest]} return
    variable currentappinfo $manifest

    Debug.cli/manifest/core {  currentappinfo = $currentappinfo}
    return
}

proc ::stackato::client::cli::manifest::recurrent {} {
    # re(load) current (application)
    Debug.cli/manifest/core {manifest.recurrent}

    variable manifest
    # Bug 95161. Without a manifest there is nothing to truly reload.
    if {![info exists manifest]} return

    Debug.cli/manifest/core {  manifest       = $manifest}

    variable basepath
    variable currentapp
    variable currentappinfo

    Debug.cli/manifest/core {  basepath       = $basepath}
    Debug.cli/manifest/core {  currentapp     = $currentapp}

    FindInDict $manifest allapps applications
    set allapps [Tag! mapping $allapps {key "applications"}]

    set ok 0
    foreach {path config} $allapps {
	set fullpath [repath $path]
	if {$fullpath ne $currentapp} continue
	set currentappinfo $config
	set ok 1
	break
    }

    if {!$ok} {
	error "Unable to reload current application configuration, unable to find $currentapp"
    }

    Debug.cli/manifest/core {  currentappinfo = $currentappinfo}
    return
}

proc ::stackato::client::cli::manifest::foreach_app {nv body {panic 1}} {
    variable currentapp     {}
    variable currentappinfo {}
    variable currentistotal 0
    variable manifest
    variable basepath
    upvar 1 $nv loopvariable

    Debug.cli/manifest/core {manifest.foreach_app $nv $panic ...}

    set where [::file normalize $basepath]

    Debug.cli/manifest/core {    where = $where}

    if {[info exists manifest] &&
	[FindInDict $manifest allapps applications]
    } {
	# Check if the manifest contains an application whose full
	# path is a prefix to the current directory.  If yes, it means
	# that the user's CWD is in that application's directory, or
	# deeper, and that we must operate on only this application.

	set allapps [Tag! mapping $allapps {key "applications"}]

	Debug.cli/manifest/core {    manifest - apps /[llength $allapps]}

	foreach {path config} $allapps {
	    set fullpath [repath $path]

	    Debug.cli/manifest/core {    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%}
	    Debug.cli/manifest/core {    checking $path}
	    Debug.cli/manifest/core {           : $fullpath}
	    Debug.cli/manifest/core {       where $where}
	    Debug.cli/manifest/core {           : [fileutil::stripPath $fullpath $where]}

	    if {[fileutil::stripPath $fullpath $where] ne $where} {
		# full path is-prefix-of where
		set currentapp     $fullpath
		set currentappinfo $config
		set currentistotal 0
		set loopvariable   [DictGet' $currentappinfo name {}]

		Debug.cli/manifest/core {      currentapp     = $currentapp}
		Debug.cli/manifest/core {      currentappinfo = $manifest}
		Debug.cli/manifest/core {      RUN BODY... }

		try {
		    uplevel 1 $body
		} finally {
		    unset currentapp
		    unset currentappinfo
		}
		# Abort all further processing.
		Debug.cli/manifest/core {    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%}
		Debug.cli/manifest/core {    DONE... }
		return
	    }
	}

	Debug.cli/manifest/core {    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%}

	if {$where ne [repath {}]} {
	    ::stackato::log::err "Path '$basepath' is not known to manifest '[file]'."
	}

	# Time to process all applications in the manifest, ordered by
	# dependencies. Topological sorting ahoy.

	foreach {path config} [DependencyOrdered $allapps] {
	    set fullpath [repath $path]

	    set currentapp     $fullpath
	    set currentappinfo $config
	    set currentistotal 0
	    set loopvariable   [DictGet' $currentappinfo name {}]
	    try {
		uplevel 1 $body
	    } finally {
		unset currentapp
		unset currentappinfo
	    }
	}
    } elseif {[info exists manifest]} {
	Debug.cli/manifest/core {manifest foreach_app - Main manifest}

	set currentapp     $where
	set currentappinfo $manifest
	set currentistotal 1
	set loopvariable   [DictGet' $currentappinfo name {}]
	try {
	    uplevel 1 $body
	} finally {
	    unset currentapp
	    unset currentappinfo
	}
    } else {
	Debug.cli/manifest/core {manifest foreach_app - No applications}

	if {$panic} {
	    ::stackato::log::err "No applications"
	}
    }
}

# # ## ### ##### ######## ############# #####################
## API (vmc - cli/commands/base.rb, manifest parts)

proc ::stackato::client::cli::manifest::setup {obj path manifestfile {reset {}}} {
    Debug.cli/manifest/core {manifest setup ($path) ($manifestfile) /$reset}

    variable cmd      $obj
    variable basepath $path

    if {$reset ne {}} {
	variable rootfile ; unset -nocomplain rootfile
	variable manifest ; unset -nocomplain manifest
    }

    if {$manifestfile ne {}} {
	variable rootfile [::file normalize $manifestfile]
    }

    file
    Load
    return
}

proc ::stackato::client::cli::manifest::file {} {
    variable basepath
    variable rootfile
    if {[info exists rootfile]} {
	Debug.cli/manifest/core {manifest file = ($rootfile) /cached}
	return $rootfile
    }
    if {(![FindStackato.yml $basepath rootfile]) &&
	(![FindManifest.yml $basepath rootfile])} {
	set rootfile {}
    }

    Debug.cli/manifest/core {manifest file = ($rootfile)}
    return $rootfile
}

proc ::stackato::client::cli::manifest::repath {path {root {}}} {
    variable rootfile
    if {$root eq {}} { set root $rootfile }
    return [::file normalize [::file join [::file dirname $root] $path]]
}

# # ## ### ##### ######## ############# #####################
## Read an inheritance tree of {stackato,manifest}.yml files

proc ::stackato::client::cli::manifest::load_structure {rootfile {already {}}} {
    set rootfile [::file normalize $rootfile]
    Debug.cli/manifest/core {load_structure ($rootfile)}

    if {[dict exists $already $rootfile]} {
	return -code error -errorcode {STACKATO CLIENT CLI MANIFEST INHERITANCE CYCLE} \
	    "Manifest error: Circular manifest inheritance detected involving:\n\t[join [dict keys $already] \n\t]"
    }
    dict set already $rootfile .


    set m [LoadBase $rootfile]

    set manifest [Tag! mapping $m manifest]

    # (1) Merge the files explicitly named as sources to inherit from.

    if {[dict exists $manifest inherit]} {
	Debug.cli/manifest/core {=== PROCESSING FILE INHERITANCE ===========}

	lassign [Tags! {scalar sequence} \
		     [dict get $manifest inherit] {key "inherit"}] \
	    itag inherit

	# Keep the inheritance information out of the in-memory
	# representation, not relevant now that it resolved.
	dict unset manifest inherit
	set m [Cmapping {*}$manifest]

	switch -exact -- $itag {
	    scalar {
		set ifile [repath $inherit $rootfile]
		# Resolves inheritance in the loaded file first.
		set m [DeepMerge $m [load_structure $ifile $already]]
	    }
	    sequence {
		foreach v $inherit {
		    set ifile [repath [Tag! scalar $v {inheritance element}] $rootfile]
		    # Resolves inheritance in the loaded file first.
		    set m [DeepMerge $m [load_structure $ifile $already]]
		}
	    }
	    default {
		error "Internal error, Tags! failed to block unknown tag '$itag'"
	    }
	}

	Debug.cli/manifest/core {load_structure ($rootfile)}
	Debug.cli/manifest/core {=== AFTER FILE INHERITANCE ================}
	Debug.cli/manifest/core {[DumpX $m]}
	Debug.cli/manifest/core {===========================================}
    }

    # (2) We treat the per-application configurations as something the
    # whole manifest can inherit from as well. This part is however
    # restricted to the applications living in the directory hierarchy
    # below the manifest file itself. -- I suspect that this was done
    # for the upcoming symbol resolution.

    if {[dict exists $manifest applications]} {
	set avalue [Tag! mapping [dict get $manifest applications] {key "applications"}]

	foreach {apath aconfig} $avalue {
	    Debug.cli/manifest/core {=== PROCESSING INTERNAL INHERITANCE =======}

	    set anpath [repath $apath $rootfile]
	    if {$anpath eq [::fileutil::stripPwd $anpath]} continue

	    set m [DeepMerge $m $aconfig]

	    Debug.cli/manifest/core {load_structure ($rootfile) - $apath}
	    Debug.cli/manifest/core {=== AFTER INTERNAL INHERITANCE ============}
	    Debug.cli/manifest/core {[DumpX $m]}
	    Debug.cli/manifest/core {===========================================}
	}
    }


    Debug.cli/manifest/core {load_structure ($rootfile)}
    Debug.cli/manifest/core {=== LOADED ================================}
    Debug.cli/manifest/core {[DumpX $m]}
    Debug.cli/manifest/core {===========================================}

    return $m
}

# # ## ### ##### ######## ############# #####################
## Resolve symbols in a fully loaded manifest structure.

proc ::stackato::client::cli::manifest::resolve_manifest {manifestvar} {
    Debug.cli/manifest/core {resolve_manifest ($manifestvar)}

    upvar 1 $manifestvar manifest

    set context [list $manifest]

    if {[dict exists $manifest applications]} {
	set avalue [Tag! mapping [dict get $manifest applications] {key "applications"}]

	foreach {apath aconfig} $avalue {
	    resolve_lexically aconfig $context
	    lappend new $apath $aconfig
	}

	dict set manifest applications $new
    }

    resolve_lexically manifest $context

    Debug.cli/manifest/core {resolve_manifest ($manifestvar)}
    Debug.cli/manifest/core {=== AFTER SYMBOL RESOLUTION ===============}
    Debug.cli/manifest/core {[DumpX $manifest]}
    Debug.cli/manifest/core {===========================================}
    return
}

proc ::stackato::client::cli::manifest::resolve_lexically {valuevar {contextlist {}} {already {}}} {
    if {![llength $contextlist]} {
	variable manifest
	variable outmanifest
	# Bug 93209. Changes made by the user (cmdline, interactive,
	# etc.), and stored in the manifest-to-be-saved have priority
	# over the data in the read manifest.
	if {[info exists outmanifest]} { lappend contextlist $outmanifest }
	if {[info exists manifest]}    { lappend contextlist $manifest    }
    }

    Debug.cli/manifest/core {resolve_lexically ($valuevar)}
    Debug.cli/manifest/core {          Already ($already)}
    Debug.cli/manifest/core {          Context ($contextlist)}

    upvar 1 $valuevar value

    lassign $value vtag vvalue

    Debug.cli/manifest/core {   tag    = ($vtag)}
    Debug.cli/manifest/core {   value  = ($vvalue)}

    set new {}
    switch -exact -- $vtag {
	mapping {
	    foreach {key child} $vvalue {
		# Resolve variables in the key string as well.
		set newkey [varsub::resolve $key \
				[list ::stackato::client::cli::manifest::ResolveSymbol \
				     $contextlist $already]]

		resolve_lexically child [linsert $contextlist 0 $value] $already
		lappend new $newkey $child
	    }
	}
	sequence {
	    foreach child $vvalue {
		resolve_lexically child $contextlist $already
		lappend new $child
	    }
	}
	scalar {
	    set new [varsub::resolve $vvalue \
			 [list ::stackato::client::cli::manifest::ResolveSymbol $contextlist $already]]
	}
	default {
	    return -code error "Illegal tag '$vtag'"
	}
    }

    Debug.cli/manifest/core {   value' = ($new)}

    # Construct the resolved value.
    set value [list $vtag $new]
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::client::cli::manifest::target_url {{contextlist {}}} {
    Debug.cli/manifest/core {target_url}

    variable cmd
    if {[FindSymbol "target" $contextlist symvalue]} {
	# NOTE how this is NOT resolved recursively.
	Debug.cli/manifest/core {target_url = $symvalue}
	return $symvalue
    }

    if {$cmd ne {}} {
	set symvalue [[$cmd client] target]

	Debug.cli/manifest/core {target_url/target = $symvalue}
	return $symvalue
    }

    set symvalue [stackato::client::cli::config target_url]

    Debug.cli/manifest/core {target_url/config = $symvalue}
    return $symvalue
}

proc ::stackato::client::cli::manifest::target_base {{contextlist {}}} {
    Debug.cli/manifest/core {target_base}

    if {[FindSymbol "target" $contextlist symvalue]} {
	# NOTE how this is NOT resolved recursively.
	# vmc: config.base_of (strip first host element (until first .)

	set symvalue [url base $symvalue]

	Debug.cli/manifest/core {target_base/manifest = $symvalue}
	return  $symvalue
    }

    set symvalue [url base [target_url]]

    Debug.cli/manifest/core {target_base/config = $symvalue}
    return $symvalue
}

# # ## ### ##### ######## ############# #####################
## Read structure and resolve symbols.

proc ::stackato::client::cli::manifest::Load {} {
    Debug.cli/manifest/core {Load}
    variable rootfile
    if {![info exists rootfile]} return
    if {$rootfile eq {}} return
    Debug.cli/manifest/core {Load rootfile = ($rootfile)}
    variable manifest [load_structure $rootfile]
    resolve_manifest manifest
    return
}

# # ## ### ##### ######## ############# #####################
## Read a single {stackato,manifest}.yml file

proc ::stackato::client::cli::manifest::LoadBase {path} {
    Debug.cli/manifest/core {LoadBase ($path)}

    # Load a yml configuration file, either stackato.yml, or
    # manifest.yml. The transformation we apply (Decompose, etc.)
    # then unifies the structures, regardless of origin.

    if {[catch {
	# Note that we retrieve a __tagged__ data structure here.
	# This is needed to properly handle the deep merging and symbol
	# resolution, which requires type information. It also helps
	# to distinguish between variant values for some keys and their
	# canonicalization.

	set data [lindex [tclyaml readTags file $path] 0 0]
    } msg]} {
	stackato::log::err "Syntax error in \[$path\]: $msg"
    }

    if {![llength $data]} {
	set data {mapping {}}
    }

    Debug.cli/manifest/core {=== RAW TCL ===============================}
    Debug.cli/manifest/core {$data}
    Debug.cli/manifest/core {===========================================}

    Debug.cli/manifest/core {=== RAW ===================================}
    Debug.cli/manifest/core {[Dump $data]}
    Debug.cli/manifest/core {===========================================}

    # Make the result a bit easier to handle, by stripping the keys of
    # mappings of their tags, generating something more dict like.

    set data [StripMappingKeyTags $data]

    # Decompose structure into stackato and manifest pieces, then
    # transform the stackato part to match structures and merge them
    # back into one. This part unifies/canonicalizes the input,
    # regardless of the origin.

    lassign [Decompose $data] stackato manifest

    Debug.cli/manifest/core {=== DEC STACKATO STRUCTURE ================}
    Debug.cli/manifest/core {[DumpX $stackato]}
    Debug.cli/manifest/core {===========================================}

    Debug.cli/manifest/core {=== DEC MANIFEST STRUCTURE ================}
    Debug.cli/manifest/core {[DumpX $manifest]}
    Debug.cli/manifest/core {===========================================}

    if {[llength [lindex $stackato 1]]} {
	set stackato [TransformToMatch $stackato]
    }

    Debug.cli/manifest/core {=== TRANS STACKATO STRUCTURE ==============}
    Debug.cli/manifest/core {[DumpX $stackato]}
    Debug.cli/manifest/core {===========================================}

    if {[llength [lindex $manifest 1]]} {
	# Bug 97113.
	set manifest [TransformM2CF1 $manifest]
    }

    Debug.cli/manifest/core {=== TRANS CF/MANIFEST STRUCTURE ==============}
    Debug.cli/manifest/core {[DumpX $manifest]}
    Debug.cli/manifest/core {===========================================}

    set data [DeepMerge $stackato $manifest]

    Debug.cli/manifest/core {=== CANONICAL STRUCTURE ===================}
    Debug.cli/manifest/core {[DumpX $data]}
    Debug.cli/manifest/core {===========================================}

    # Bug 93955. If we have user data from a push merge this in.  The
    # only place where this can happen so far is in methods 'AppName'
    # (c_svchelp.tcl) and 'pushit' (c_apps.tcl).
    
    # The first reloads the manifest after the application name is
    # fully known, if it differs from the manifest. The merge below
    # then overwrites the file's name information with the user's
    # choice.

    # The second is done after all interaction, just before packing
    # and uploading the application's files. At that point we have all
    # the user's choices and have to merge them back into the system,
    # so that the generated manifest.yml properly incorporates this.

    # NOTE that the outmanifest uses stackato structure and thus must
    # be transformed to match the unified layout.

    variable outmanifest
    if {[info exists outmanifest]} {
	set data [DeepMerge [TransformToMatch $outmanifest] $data]

	Debug.cli/manifest/core {=== CANONICAL STRUCTURE + USER CHOICES ====}
	Debug.cli/manifest/core {[DumpX $data]}
	Debug.cli/manifest/core {===========================================}
    }

    ValidateStructure $data
    return $data
}

# # ## ### ##### ######## ############# #####################
## Symbol resolution helper commands.

proc ::stackato::client::cli::manifest::ResolveSymbol {contextlist already symbol} {
    Debug.cli/manifest/core {ResolveSymbol ($symbol)}
    Debug.cli/manifest/core {      Already ($already)}
    Debug.cli/manifest/core {      Context ($contextlist)}

    # NOTE ! We test for and prevent infinite recursion on symbols
    # NOTE ! referencing themselves, directly or indirectly.

    if {[dict exists $already $symbol]} {
	return -code error -errorcode {STACKATO CLIENT CLI MANIFEST SYMBOL CYCLE} \
	    "Manifest error: Circular symbol definition detected involving:\n\t[join [dict keys $already] \n\t]"
    }
    dict set already $symbol .

    switch -exact -- $symbol {
	target-base {
	    return [target_base $contextlist]
	}
	target-url {
	    return [target_url $contextlist]
	}
	random-word {
	    return [format %04x [expr {int(0x100000 * rand())}]]
	}
	default {
	    if {![FindSymbol $symbol $contextlist symvalue]} {
		return -code error \
		    -errorcode {STACKATO CLIENT CLI MANIFEST UNKNOWN SYMBOL} \
		    "Manifest error: Unknown symbol in manifest: $symbol"
	    }
	    # Note: symvalue is plain string here, not tagged.

	    # Recursively resolve any symbols in the current symbol's
	    # value, converting into and out of tagged format.

	    set symvalue [Cscalar $symvalue]
            resolve_lexically symvalue $contextlist $already
	    return [lindex $symvalue 1]
	}
    }
    error "Reached unreachable"
}

proc ::stackato::client::cli::manifest::FindSymbol {symbol contextlist resultvar} {
    upvar 1 $resultvar result

    foreach context $contextlist {
	if {![ResolveInContext $symbol $context result]} continue
	return 1
    }
    return 0
}

proc ::stackato::client::cli::manifest::ResolveInContext {symbol context resultvar} {
    variable currentapp
    upvar 1 $resultvar result
    set app {}
    if {[info exists currentapp]} { set app $currentapp }

    set found [expr {
		  [FindInDict $context localresult properties $symbol] ||
		  [FindInDict $context localresult applications $app $symbol] ||
		  [FindInDict $context localresult $symbol]
	      }]

    # Accept only scalar values for use in the
    # resolution. Interpolation of structured values is fraught with
    # peril and not supported. Of course this matters only if
    # we actually found a definition at all.

    if {!$found || ([TagOf $localresult] ne "scalar")} {
	return 0
    }

    set result [StripTags $localresult]
    return 1
}

proc ::stackato::client::cli::manifest::DictGet {dict args} {
    Debug.cli/manifest/core {DictGet ($dict) ($args)}
    set found [FindInDictionary $dict result {*}$args]
    if {!$found} { return -code error "key path '$args' not known in dictionary" }
    return $result
}

proc ::stackato::client::cli::manifest::DictGet' {dict args} {
    Debug.cli/manifest/core {DictGet ($dict) ($args)}
    set default [lindex $args end]
    set args [lrange $args 0 end-1]
    set found [FindInDictionary $dict result {*}$args]
    if {!$found} { return $default }
    return $result
}

proc ::stackato::client::cli::manifest::DictExists {dict args} {
    Debug.cli/manifest/core {DictExists ($dict) ($args)}
    return [FindInDictionary $dict __dummy__ {*}$args]
}

proc ::stackato::client::cli::manifest::FindInDictionary {context resultvar args} {
    # Follow the specified path of keys down into the context structure (tagged).
    # Stop and fail when intermediate structures are not mappings or do not contain
    # the key. Result is stripped of any tags.

    upvar 1 $resultvar result
    if {[FindInDict $context result {*}$args]} {
	set result [StripTags $result]
	return 1
    } else {
	return 0
    }
}

proc ::stackato::client::cli::manifest::FindInDict {context resultvar args} {
    # Follow the specified path of keys down into the context structure (tagged).
    # Stop and fail when intermediate structures are not mappings or do not contain
    # the key.

    Debug.cli/manifest/core/resolve {FID -> $resultvar}
    Debug.cli/manifest/core/resolve {FID <- $args}
    Debug.cli/manifest/core/resolve {FID % ($context)}
    Debug.cli/manifest/core/resolve {[DumpX $context]}

    upvar 1 $resultvar result
    foreach symbol $args {
	if {[catch {
	    set cv [Tag! mapping $context context]
	}]} {
	    return 0
	}
	if {![dict exists $cv $symbol]} {
	    return 0
	}
	set context [dict get $cv $symbol]
    }

    # NOTE: At this point the result is still a tagged structure!
    # Could be scalar, or more complex. Regardless, for the resolution
    # we need a proper string to replace the symbol with. Hence the
    # StripTags we created early on.

    Debug.cli/manifest/core/resolve {FID = ($context)}
    Debug.cli/manifest/core/resolve {[DumpX $context]}

    set result $context
    return 1
}

proc ::stackato::client::cli::manifest::DictSet {dictvar args} {
    Debug.cli/manifest/core {DictSet ($dictvar) ($args)}

    upvar 1 $dictvar dict

    set value [lindex $args end]
    set keys  [lrange $args 0 end-1]

    if {![llength $keys]} {
	error "No keys"
    }

    # Read
    set dictvalue [Tag! mapping $dict]
    set head [lindex $keys 0]
    set tail [lrange $keys 1 end]

    if {[dict exists $dictvalue $head]} {
	set child [dict get $dictvalue $head]
    } else {
	set child {mapping {}}
    }

    # Modify
    if {[llength $tail]} {
	DictSet child {*}$tail $value
    } else {
	set child $value
    }

    # Write back
    dict set dictvalue $head $child
    set dict [Cmapping {*}$dictvalue]
    return
}

# # ## ### ##### ######## ############# #####################
## Locate the yaml files, our's and CF's.

proc ::stackato::client::cli::manifest::FindStackato.yml {path filevar} {
    upvar 1 $filevar ymlfile
    Debug.cli/manifest/core {find-stackato.yml ($path -> $filevar)}

    set setup $path/stackato.yml

    if {![::file exists $setup]} {
	return 0
    }

    set ymlfile $setup
    return 1
}

proc ::stackato::client::cli::manifest::FindManifest.yml {path filevar} {
    upvar 1 $filevar ymlfile
    Debug.cli/manifest/core {find-manifest.yml ($path -> $filevar)}
    #Debug.cli/manifest/core {}

    set path [::file normalize $path]
    #set last $path

    while {1} {
	set setup $path/manifest.yml
	if {[::file exists $setup]} {
	    set ymlfile $setup
	    return 1
	}

	set new [::file dirname $path]

	# Stop on reaching the root of the path.
	if {$new eq $path} break
	set path $new
    }

    return 0
}

# ## ### ##### ######## ############# #####################
## Yaml processing helper.
## Go from a fully tagged format to one where mapping keys
## are not tagged. We expect them to be scalars anyway.

proc ::stackato::client::cli::manifest::StripMappingKeyTags {yml} {
    lassign $yml tag value
    switch -exact -- $tag {
	scalar {
	    # Unchanged.
	    return $yml
	}
	mapping {
	    set new {}
	    foreach {k v} $value {
		set kvalue [Tag! scalar $k {mapping key}]
		lappend new $kvalue [StripMappingKeyTags $v]
	    }
	    return [list $tag $new]
	}
	sequence {
	    set new {}
	    foreach v $value {
		lappend new [StripMappingKeyTags $v]
	    }
	    return [list $tag $new]
	}
	default {
	    return -code error "Illegal tag '$tag'"
	}
    }
    error "Reached unreachable."
}

# ## ### ##### ######## ############# #####################
## Yaml processing helper. Go to full untagged format.

proc ::stackato::client::cli::manifest::StripTags {yml} {
    lassign $yml tag value
    switch -exact -- $tag {
	scalar {
	    return $value
	}
	mapping {
	    set new {}
	    foreach {k v} $value {
		lappend new $k [StripTags $v]
	    }
	    return $new
	}
	sequence {
	    set new {}
	    foreach v $value {
		lappend new [StripTags $v]
	    }
	    return $new
	}
	default {
	    error "Illegal tag '$tag'"
	}
    }
    error "Reached unreachable."
}

# ## ### ##### ######## ############# #####################
## Yaml processing helper. Complement of StripMappingKeyTags.

proc ::stackato::client::cli::manifest::RetagMappingKeys {yml} {
    #Debug.cli/manifest/core {ReTag ($yml)}
    lassign $yml tag value
    switch -exact -- $tag {
	scalar {
	    # Unchanged.
	    return $yml
	}
	mapping {
	    set new {}
	    foreach {k v} $value {
		lappend new \
		    [Cscalar $k] \
		    [RetagMappingKeys $v]
	    }
	    return [list $tag $new]
	}
	sequence {
	    set new {}
	    foreach v $value {
		lappend new [RetagMappingKeys $v]
	    }
	    return [list $tag $new]
	}
	default {
	    error "Illegal tag '$tag'"
	}
    }
    error "Reached unreachable."
}

# # ## ### ##### ######## ############# #####################
## Helpers for LoadBase. Separate stackato information, and
## transform to match the CF format, with extensions.

proc ::stackato::client::cli::manifest::Decompose {yml} {
    Debug.cli/manifest/core {Decompose ($yml)}

    # Assumes that the yml underwent StripMappingKeyTags
    # before provided as argument.

    # The code picks out which pieces are CF manifest.yml, and which
    # are stackato.yml, separating them into their own structures.

    set value [Tag! mapping $yml root]

    # Pull all the known stackato.yml keys (toplevel!) out of the
    # structure. The remainder is considered to be manifest.yml data.

    # Bug 98145. For the purposes of the transform the m.yml
    # _application_ keys "url", "urls", and "depends-on" are
    # recognized as s.yml _toplevel_ keys also, and later moved into
    # the correct place.

    set s {}
    foreach k {
	name instances mem framework services processes
	min_version env ignores hooks cron requirements
	command app-dir url urls depends-on
    } {
	if {![dict exists $value $k]} continue
	set v [dict get $value $k]
	dict unset value $k
	lappend s $k $v
    }

    return [list [Cmapping {*}$s] [Cmapping {*}$value]]
}

proc ::stackato::client::cli::manifest::Vendors {} {
    variable cmd
    set choices {}
    foreach {service_type value} [[$cmd client] services_info] {
	foreach {vendor version} $value {
	    lappend choices $vendor
	}
    }
    return $choices
}

proc ::stackato::client::cli::manifest::TransformToMatch {yml} {
    Debug.cli/manifest/core {TransformToMatch ($yml)}

    # Assumes that the input is the stackato.yml data for an
    # application and generates a structure matching the CF
    # manifest.yml, with extensions, so that it is mergable with data
    # from such files.

    set value [Tag! mapping $yml root]

    # Pull an app directory specification out of the data first, and
    # squash it for the rest of the conversion. It becomes important
    # only at the very end, when we assemble the main structure, where
    # the directory itself is a key of the applications mapping, and
    # not specified as the value of some fixed key.

    set appdir .
    if {[dict exists $value app-dir]} {
	set appdir [Tag! scalar [dict get $value app-dir] {key "app-dir"}]
	dict unset value app-dir
    }

    # Transform all the known stackato.yml keys to match their
    # manifest.yml counterpart. Those without counterpart move into a
    # nested 'stackato' mapping.

    # (1) name, instances, mem - 1:1, nothing to change.
    # (2) framework - handle stackato A/B variants and map.
    # (3) services - re-map
    # (4) requirements processes min_version env ignores hooks cron - move into stackato sub-map.
    # (4a) env: Has A/B variants, normalize

    # (Ad 2)
    if {[dict exists $value framework]} {
	set f [dict get $value framework]
	lassign $f tag f

	if {$tag eq "scalar"} {
	    # stackato A, f = type = CF 'name'
	    dict set value framework [Cmapping name [Cscalar $f]]
	} elseif {$tag eq "mapping"} {
	    # stackato B f = dict (type, runtime)

	    if {[dict exists $f type]} {
		set t [dict get $f type]
		# t is a tagged value
		dict set   f name $t
		dict unset f type
	    }
	    if {[dict exists $f runtime]} {
		set r [dict get $f runtime]
		# r is a tagged value
		dict set value runtime $r
		dict unset f runtime
	    }
	    # Done changing the framework content. Push the changes
	    # back into the outer dict.
	    if {![llength $f]} {
		dict unset value framework
	    } else {
		dict set value framework [list $tag $f]
	    }
	} else {
	    error "Expected framework scalar or mapping, got $tag"
	}
    }

    # (Ad 3)
    if {[dict exists $value services]} {
	lassign [Tags! {scalar mapping} [dict get $value services] {key "services"}] t services
	if {$t eq "scalar"} {
	    set services [string trim $services]
	    if {$services ne {}} {
		return -code error -errorcode {STACKATO CLIENT CLI MANIFEST SYNTAX} \
		    "Manifest error: Bad syntax, expected a yaml mapping for key \"services\", got a non-empty string instead."
	    }
	}

	set choices [Vendors]

	set new {}
	foreach {outer inner} $services {
	    # 3 possibilities
	    # (a) stackato.yml /old : (outer, inner) = (vendor, name/scalar)
	    # (b) stackato.yml /new : (outer, inner) = (name, vendor/scalar)
	    # (c) manifest.yml : (outer, inner) = (name, (mapping, 'type': vendor))

	    lassign [Tags! {scalar mapping} $inner {service definition}] tag innervalue
	    switch -exact -- $tag {
		scalar {
		    # (a, b)
		    if {($outer in $choices) && ($innervalue ni $choices)} {
			# (a)
			set name   $innervalue
			set vendor $outer

			stackato::log::say! [stackato::color::yellow "Deprecated syntax (vendor: name) in service specification \"$outer: $innervalue\".\n\tPlease swap, i.e. use (name: vendor)."]

		    } elseif {($outer ni $choices) && ($innervalue in $choices)} {
			# (b)
			set name   $outer
			set vendor $innervalue
		    } elseif {($outer ni $choices) && ($innervalue ni $choices)} {
			# Neither value is a proper vendor.
			return -code error  -errorcode {STACKATO CLIENT CLI MANIFEST BAD SERVICE} \
			    "Manifest error: Bad service definition \"$outer: $innervalue\" in manifest. Neither \[$outer\] nor \[$innervalue\] are supported system services.\nPlease use '[usage::me] services' to see the list of system services supported by the target."
		    } else {
			# Both values are proper vendors.
			return -code error  -errorcode {STACKATO CLIENT CLI MANIFEST BAD SERVICE} \
			    "Manifest error: Bad service definition \"$outer: $innervalue\" in manifest. Both \[$outer\] and \[$innervalue\] are supported system services. Unable to decide which is the service name."
		    }
		}
		mapping {
		    # (c)
		    set name   $outer
		    set type   [dict get $innervalue type]
		    set vendor [Tag! scalar $type type]
		}
		default {
		    error "Internal error, Tags! failed to block unknown tag '$tag'"
		}
	    }

	    lappend new $name [Cmapping type [Cscalar $vendor]]
	}
	dict set value services [Cmapping {*}$new]
    }

    # (Ad 4)
    foreach k {
	processes min_version env ignores hooks cron
	requirements
    } {
	if {![dict exists $value $k]} continue

	set data [dict get $value $k]

	# (Ad 4a) Normalize old/new style of env'ironment data.
	if {$k eq "env"} {
	    set new {}
	    foreach {ekey evalue} [Tag! mapping $data {key "env"}] {
		set etag [lindex [Tags! {scalar mapping} $evalue "value of key \"env:$ekey\""] 0]
		switch -exact -- $etag {
		    scalar {
			# Old style. Scalar value. Transform into new
			# style, make the value the default.
			lappend new $ekey [Cmapping default $evalue]
		    }
		    mapping {
			# New-style, mapping. Passed through unchanged.
			lappend new $ekey $evalue
		    }
		    default {
			error "Internal error, Tags! failed to block unknown tag '$etag'"
		    }
		}
	    }
	    set data [Cmapping {*}$new]
	}

	# Need the sub-map, create if not present yet.
	if {![dict exists $value stackato]} {
	    dict set value stackato {}
	}
	# Put into sub-map, untagged.
	dict set value stackato $k $data

	# Drop from original location
	dict unset value $k
    }
    if {[dict exists $value stackato]} {
	# Fix the tagging.
	dict set value stackato [Cmapping {*}[dict get $value stackato]]
    }

    # Treat the stackato data as the main application under the '.' path.

    return [Cmapping applications [Cmapping $appdir [Cmapping {*}$value]]]
}

proc ::stackato::client::cli::manifest::TransformM2CF1 {yml} {
    Debug.cli/manifest/core {TransformM2CF1 ($yml)}

    # Bug 97113.
    # Assumes that the input is the manifest.yml data for an
    # application, in either CF1 or CF2 format and generates a
    # structure matching the CF1 manifest.yml, with extensions, so
    # that it is mergable with a transformed stackato.yml.

    set value [Tag! mapping $yml root]

    foreach {k v} $value {
	# Ignore toplevel keys, but 'applications'
	if {$k ne "applications"} continue

	# Recurse into and transform each application tree.
	foreach {a def} [Tag! mapping $v applications] {
	    dict set new $a [TransformM2CF1App $a $def]
	}
	dict set value applications [Cmapping {*}$new]
    }

    return [Cmapping {*}$value]
}

proc ::stackato::client::cli::manifest::TransformM2CF1App {a yml} {
    Debug.cli/manifest/core {TransformM2CF1App ($yml)}

    # See caller (TransformM2CF1) for notes.
    # To transform: framework+runtime, if framework value is a scalar.

    set value [Tag! mapping $yml applications:$a]

    if {[dict exists $value framework] && 
	([TagOf [dict get $value framework]] eq "scalar")} {
	# framework is scalar. Transform to mapping, with value moved to sub-key name.
	dict set value framework \
	    [Cmapping name [Cscalar [ValueOf [dict get $value framework]]]]
    }

    # At this point 'framework is either missing, or exists as a mapping.

    # Bug 97958: Moving runtime to framework:runtime seems to be wrong. Disabled.
    if {0&&[dict exists $value runtime]} {
	# move the runtime information into the framework mapping.
	set runtime [dict get $value runtime]

	if {![dict exists $value framework]} {
	    # mapping not present, create.
	    dict set value framework [Cmapping runtime $runtime]
	} else {
	    # extend the mapping.
	    set fw [ValueOf [dict get $value framework]]
	    dict set fw runtime $runtime
	    dict set value framework [Cmapping {*}$fw]
	}

	dict unset value runtime
    }

    #array set __ $value ; parray __ ; unset __

    return [Cmapping {*}$value]
}

proc ::stackato::client::cli::manifest::ValidateStructure {yml} {
    Debug.cli/manifest/core {ValidateStructure $yml}

    # Validate the structure of the yml as much as possible
    # (I.e. expect mappings, sequences, strings, etc. ...)

    # This is done by explicitly recursing into the tagged structure
    # of the yaml data and testing the tags encountered, based on the
    # keys seen.

    set value [lindex [dict get' [Tag! mapping $yml root] applications {mapping {}}] 1]

    foreach {path value} $value {
	ValidateGlobMap $value application {
	    name      { Tag! scalar $value {key "name"} }
	    instances { Tag! scalar $value {key "instances"} }
	    mem       { Tag! scalar $value {key "mem"} }
	    runtime   { Tag! scalar $value {key "runtime"} }
	    command   { Tag! scalar $value {key "command"} }
	    url -
	    urls {
		Tags! {scalar sequence} $value {key "url"}
	    }
	    depends-on {
		Tags! {scalar sequence} $value {key "depends-on"}
	    }
	    services  {
		ValidateGlobMap $value services {
		    * {
			ValidateGlobMap $value $key {
			    type { Tag! scalar $value {key "type"} }
			    * {
				upvar 1 key ekey
				UnknownKey services:$ekey:$key
			    }
			}
		    }
		}
	    }
	    framework {
		ValidateGlobMap $value framework {
		    name          { Tag! scalar $value {key "framework:name"} }
		    runtime       { Tag! scalar $value {key "framework:runtime"} }
		    app-server    { Tag!Warn scalar $value {key "framework:app-server"} }
		    document-root { Tag!Warn scalar $value {key "framework:document-root"} }
		    home-dir      { Tag!Warn scalar $value {key "framework:home-dir"} }
		    start-file    { Tag!Warn scalar $value {key "framework:start-file"} }
		    *             { UnknownKey framework:$key }
		}
	    }
	    stackato {
		ValidateGlobMap $value stackato {
		    min_version {
			ValidateGlobMap $value min_version {
			    server {
				set v [Tag! scalar $value {key "min_version:server"}]
				if {[catch {
				    package vcompare 0 $v
				}]} {
				    return -code error -errorcode {STACKATO CLIENT CLI MANIFEST TAG} \
					"Manifest error: Expected version number for key \"min_version:server\", got \"$v\""
				}
			    }
			    client {
				set v [Tag! scalar $value {key "min_version:client"}]
				if {[catch {
				    package vcompare 0 $v
				}]} {
				    return -code error -errorcode {STACKATO CLIENT CLI MANIFEST TAG} \
					"Manifest error: Expected version number for key \"min_version:client\", got \"$v\""
				}
			    }
			    * { IllegalKey min_version:$key }
			}
		    }
		    processes {
			ValidateGlobMap $value processes {
			    web { Tag! scalar $value {key "processes:web"} }
			    *   { UnknownKey processes:$key }
			}
		    }
		    requirements {
			ValidateGlobMap $value requirements {
			    pypm   { Tags! {scalar sequence} $value {key "requirements:pypm"} }
			    ppm    { Tags! {scalar sequence} $value {key "requirements:ppm "} }
			    cpan   { Tags! {scalar sequence} $value {key "requirements:cpan"} }
			    pip    { Tags! {scalar sequence} $value {key "requirements:pip "} }
			    ubuntu { Tags! {scalar sequence} $value {key "requirements:ubuntu"} }
			    redhat { Tags! {scalar sequence} $value {key "requirements:redhat"} }
			    unix   { Tags! {scalar sequence} $value {key "requirements:unix  "} }
			    staging {
				ValidateGlobMap $value staging {
				    ubuntu { Tags! {scalar sequence} $value {key "requirements:staging:ubuntu"} }
				    redhat { Tags! {scalar sequence} $value {key "requirements:staging:redhat"} }
				    unix   { Tags! {scalar sequence} $value {key "requirements:staging:unix  "} }
				    *      { UnknownKey requirements:staging:$key }
				}
			    }
			    running {
				ValidateGlobMap $value running {
				    ubuntu { Tags! {scalar sequence} $value {key "requirements:running:ubuntu"} }
				    redhat { Tags! {scalar sequence} $value {key "requirements:running:redhat"} }
				    unix   { Tags! {scalar sequence} $value {key "requirements:running:unix  "} }
				    *      { UnknownKey requirements:running:$key }
				}
			    }
			    * { UnknownKey requirements:$key }
			}
		    }
		    env {
			ValidateGlobMap $value env {
			    * {
				# We assume normalized data here! See
				# marker "4a" in TransformToMatch.
				ValidateGlobMap $value "env:$key" {
				    default {
					upvar 1 key ekey
					Tag! scalar $value "key \"env:${ekey}:default\""
				    }
				    hidden -
				    required -
				    inherit {
					upvar 1 key ekey
					set value [Tag! scalar $value "key \"env:${ekey}:$key\""]
					if {$value ni {y Y yes Yes YES n N no No NO true True TRUE false False FALSE on On ON off Off OFF}} {
					    return -code error  -errorcode {STACKATO CLIENT CLI MANIFEST TAG} \
						"Manifest error: Expected boolean value for key \"env:$ekey:$key\", got \"$value\""
					}
				    }
				    prompt {
					upvar 1 key ekey
					Tag! scalar $value "key \"env:${ekey}:prompt\""
				    }
				    choices {
					upvar 1 key ekey
					Tag! sequence $value "key \"env:${ekey}:choices\""
				    }
				    scope {
					upvar 1 key ekey
					set value [Tag! scalar $value "env:${ekey}:scope"]
					if {$value ni {staging runtime both}} {
					    return -code error  -errorcode {STACKATO CLIENT CLI MANIFEST TAG} \
						"Manifest error: Expected one of 'both', 'runtime' or 'staging' for key \"env:$ekey:scope\", got \"$value\""
					}
				    }
				    * {
					upvar 1 key ekey
					IllegalKey env:${ekey}:$key
				    }
				}
			    }
			}
		    }
		    hooks {
			Tag! mapping $value hooks
			ValidateGlobMap $value hooks {
			    pre-staging  { ValidateCommand $value hooks:pre-staging  }
			    post-staging { ValidateCommand $value hooks:post-staging }
			    pre-running  { ValidateCommand $value hooks:pre-running  }
			    *            { UnknownKey hooks:$key }
			}
		    }
		    cron    { ValidateCommand $value cron }
		    ignores {
			Tag! sequence $value {key "ignores"}
		    }
		    * {
			UnknownKey stackato:$key
		    }
		}
	    }
	    * {
		UnknownKey $key
	    }
	}
    }

    foreach {k v} [Tag! mapping $yml root] {
	if {$k eq "applications"} continue
	if {$k eq "inherit"}      continue
	UnknownKey $k
    }
    return
}

proc ::stackato::client::cli::manifest::IllegalKey {k} {
    return -code error  -errorcode {STACKATO CLIENT CLI MANIFEST TAG} \
	"Manifest error: Found illegal key \"$k\""
}

proc ::stackato::client::cli::manifest::UnknownKey {k} {
    #error $k
    stackato::log::say! [stackato::color::yellow "Manifest warning: Unknown key \"$k\""]
    return
}

proc ::stackato::client::cli::manifest::ValidateMap {value label switch} {
    Debug.cli/manifest/core {ValidateMap $label = $value}

    lappend switch default {}
    set value [Tag! mapping $value "key \"$label\""]
    foreach {key value} $value {
	Debug.cli/manifest/core {ValidateMap $label :: $key}
	switch -exact -- $key $switch
    }
    return
}

proc ::stackato::client::cli::manifest::ValidateGlobMap {value label switch} {
    Debug.cli/manifest/core {ValidateMap $label = $value}

    lappend switch default {}
    set value [Tag! mapping $value "key \"$label\""]
    foreach {key value} $value {
	Debug.cli/manifest/core {ValidateMap $label :: $key}
	switch -glob -- $key $switch
    }
    return
}

proc ::stackato::client::cli::manifest::ValidateCommand {value key} {
    lassign [Tags! {scalar sequence} $value "key \"$key\""] tag value
    if {$tag eq "scalar"} return
    # sequence - all elements must be scalar.
    foreach element $value {
	Tag! scalar $element "element of sequence key \"$key\""
    }
}

# # ## ### ##### ######## ############# #####################
## Helper. Order a set of applications by their dependencies

proc ::stackato::client::cli::manifest::DependencyOrdered {dict} {
    Debug.cli/manifest/core {DependencyOrdered}

    variable docache
    if {[info exists docache]} { return $docache }

    # Note: Our topological sorter is an iterative solution, not
    # recursive as the original ruby, and doesn't make use of
    # yield/coro/uplevel either.

    array set required {} ; # path == app -> count of dependencies
    array set users    {} ; # path -> list of apps depending on this one.
    set remainder      {} ; # list of not yet processed paths/apps
    set result         {} ; # Outgoing list, properly ordered.

    # Fill the dependency structures.

    foreach {path config} $dict {
	Debug.cli/manifest/core {DependencyOrdered: $path = $config}
	lappend remainder $path
	set abs($path) [repath $path]
	set required($path) 0
	if {[FindInDictionary $config dependencies depends-on]} {
	    set required($path) [llength $dependencies]
	    foreach d $dependencies {
		lappend users($d) $path
	    }
	}
    }

    # Check that the dependencies do not mention applications
    # which are not specified by the manifest.

    foreach a [array names users] {
	if {[info exists required($a)]} continue
	return -code error -errorcode {STACKATO CLIENT CLI MANIFEST APP-DEPENDENCY UNKNOWN} \
		"Manifest error: Reference '$a' in key \"depends-on\" is unknown."
    }

    # Iteratively move the applications without dependencies into the
    # result, and adjust the dependency counters of their users, until
    # all applications are processed, or nothing could be moved. The
    # latter indicating one or more cycles.

    Debug.cli/manifest/core {DependencyOrdered: Returning}

    while {[llength $remainder]} {
	set keep {}

	foreach r $remainder {
	    if {$required($r) > 0} {
		# Elements still having dependencies are kept for the
		# next round.
		lappend keep $r
	    } else {
		# Elements without dependencies move to the result.
		# The dependency counts of their users get adjusted down.
		# This may allow their move to the result later on.
		# Possibly even in this round already.

		Debug.cli/manifest/core {DependencyOrdered: $r = [dict get $dict $r]}

		lappend result $r [dict get $dict $r]
		if {[info exists users($r)]} {
		    foreach u $users($r) {
			incr required($u) -1
		    }
		    unset users($r)
		}
		unset required($r)
	    }
	}

	if {[llength $keep] == [llength $remainder]} {
	    # Oops. Nothing was processed in this round.  This means
	    # that all the remaining elements are in at least one
	    # dependency cycle (could be several).
	    return -code error -errorcode {STACKATO CLIENT CLI MANIFEST APP-DEPENDENCY CYCLE} \
		"Manifest error: Circular application dependency detected involving:\n\t[join $remainder \n\t]"
	}

	# Prepare for the next round, if any.
	set remainder $keep
    }

    set docache $result
    return $result
}

# # ## ### ##### ######## ############# #####################
## Helper. Deep merging of manifest data structures.

proc ::stackato::client::cli::manifest::DeepMerge {child parent} {
    Debug.cli/manifest/core {DeepMerge ($child) ($parent)}

    # Assumes that the incoming yml values underwent
    # 'StripMappingKeyTags' before handed here.

    # Child key values have precedence over parent values.

    lassign $child  ctag cvalue
    lassign $parent ptag pvalue

    # If either child or parent is not having a mapping the values
    # cannot be merged. The child then has precedence.
    if {($ctag ne "mapping") ||
	($ptag ne "mapping")} {
	return $child
    }

    # When both values are mappings we recurse and merge their values.

    set result {}
    dict for {k v} $cvalue {
	# k = scalar, untagged
	# v = tagged value.
	if {[dict exists $pvalue $k]} {
	    # Unify child and parent values.
	    lappend result $k [DeepMerge $v [dict get $pvalue $k]]
	} else {
	    # Keep the child, no parent.
	    lappend result $k $v
	}
    }

    dict for {k v} $pvalue {
	# k = scalar, untagged
	# v = tagged value.

	# Ignore values known to the child. Have been merged
	# already, above, where necessary.
	if {[dict exists $cvalue $k]} continue

	# Add parent key, nothing from the child
	lappend result $k $v
    }

    # Done.
    return [list $ctag $result]
}

# # ## ### ##### ######## ############# #####################
## Helpers. Construction of tagged structures.
## Proc names chosen for composability with tag values.

proc ::stackato::client::cli::manifest::Cmapping  {args}   { list mapping  $args   }
proc ::stackato::client::cli::manifest::Csequence {args}   { list sequence $args   }
proc ::stackato::client::cli::manifest::Cscalar   {string} { list scalar   $string }


# # ## ### ##### ######## ############# #####################
## Helpers. Access with tag checking.

proc ::stackato::client::cli::manifest::Tag!Warn {tag yml {label structure}} {
    lassign $yml thetag thevalue
    if {$thetag eq $tag} return
    stackato::log::say! \
	[stackato::color::yellow \
	     "Manifest warning: Expected a yaml $tag for $label, got a $thetag ($thevalue)"]
}

proc ::stackato::client::cli::manifest::Tag! {tag yml {label structure}} {
    lassign $yml thetag thevalue
    if {$thetag eq $tag} { return $thevalue }
    return -code error -errorcode {STACKATO CLIENT CLI MANIFEST TAG} \
	"Manifest validation error: Expected a yaml $tag for $label, got a $thetag ($thevalue)"
}

proc ::stackato::client::cli::manifest::Tags! {tags yml {label structure}} {
    lassign $yml thetag _
    if {$thetag in $tags} { return $yml }
    return -code error -errorcode {STACKATO CLIENT CLI MANIFEST TAG} \
	"Manifest validation error: Expected a yaml [linsert [join $tags {, }] end-1 or] for $label, got a $thetag ($thevalue)"
}

proc ::stackato::client::cli::manifest::TagOf {yml} {
    return [lindex $yml 0]
}

proc ::stackato::client::cli::manifest::ValueOf {yml} {
    return [lindex $yml 1]
}

# # ## ### ##### ######## ############# #####################
## Helpers for debugging. Show structure.

proc ::stackato::client::cli::manifest::Dump {yml} {
    # Helper command, use it to show intermediate structures.
    tclyaml writeTags channel stdout $yml
    return
}

proc ::stackato::client::cli::manifest::DumpX {yml} {
    # Helper command, use it to show intermediate structures.
    tclyaml writeTags channel stdout [RetagMappingKeys $yml]
    return
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::client::cli::manifest {
    namespace export {[0-9a-z]*}
    namespace ensemble create
}
namespace eval ::stackato::client::cli {
    namespace export manifest
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::client::cli::manifest 0
