## (c) 2013 Andreas Kupries
# # ## ### ##### ######## ############# #####################

package require fileutil
package require try

# # ## ### ##### ######## ############# #####################
## Configuration.

apply {{} {
    global env
    foreach {ev proc fallback} {
	STACKATO_CLI_TEST_TARGET    theplaintarget todo-fallback-target
	STACKATO_CLI_TEST_USER      theuser        todo-fallback-nonadminusername
	STACKATO_CLI_TEST_GROUP     thegroup       todo-fallback-groupname
	STACKATO_CLI_TEST_DRAIN     thedrain       todo-fallback-drainurl
	STACKATO_CLI_TEST_ADMIN     adminuser      todo-fallback-adminusername
	STACKATO_CLI_TEST_APASS     adminpass      todo-fallback-adminpassword
	STACKATO_CLI_TEST_ORG       theorg         todo-fallback-org
	STACKATO_CLI_TEST_SPACE     thespace       todo-fallback-space
	STACKATO_CLI_TEST_SBROKER_L thebroker      todo-service-broker-location-url
	STACKATO_CLI_TEST_SBROKER_U thebrokeruser  todo-service-broker-user-name
	STACKATO_CLI_TEST_SBROKER_P thebrokerpass  todo-service-broker-user-password
    } {
	if {[info exists env($ev)]} {
	    set value $env($ev)
	} else {
	    set value $fallback
	}

	proc $proc {} [list return $value]
	#kt::Note $ev $value
    }
}}

# # ## ### ##### ######## ############# #####################

proc NOTE {args} {
    #puts "@=NOTE: $args"
    return
}

proc TODO {args} {
    #puts "@=TODO: $args"
    return
}

proc DEBUG-CHECKS {} {
    # Various checks to help debug the testsuites themselves.
    # 1. Look for a leaked "appdir" application.
    if {![catch {
	 run guid app appdir
    }]} {
	puts "@=NOTE: HAS app|appdir"
    }
}

# # ## ### ##### ######## ############# #####################
## Values derived from configuration

proc thetarget {} {
    return https://[theplaintarget]
}

proc targetdomain {} {
    return [join [lrange [split [thetarget] .] 1 end] .]
}

proc mapurl {} {
    return somewhere.[targetdomain]
}

proc thebase {} {
    return [join [lrange [split [thetarget] .] 1 end] .]
}

# # ## ### ##### ######## ############# #####################
##

proc tmp {} { tcltest::configure -tmpdir }

proc example {x} {
    return [file join [tmp] data apps $x]
}

proc result {x {suffix {}}} {
    global isv1 isv2
    if {$isv1} { lappend files ${x}-cfv1.txt }
    if {$isv2} { lappend files ${x}-cfv2.txt }
    lappend files ${x}.txt
    foreach f $files {
	set path [file join [tmp] data results$suffix $f]
	if {![file exists $path]} continue
	return [string trim [fileutil::cat $path]]
    }
    # Failed all, default contents, of nothing
    return {}
}

proc map {x args} {
    string map $args $x
}

proc themanifest {path} {
    foreach f {
	stackato.yml manifest.yml
    } {
	set maybe $path/$f
	if {![file exists $maybe]} continue
	return $maybe
    }
    error "No manifest found in $path."
}

proc thehome {} {
    set r [file join [tmp] thehome]
    proc thehome {} [list return $r]
    return $r
}

proc appdir {} {
    set r [file join [tmp] appdir]
    file mkdir $r
    return $r
}

proc remove-appdir {} {
    file delete [appdir]
    return
}

proc indir {dir script} {
    set here [pwd]
    try {
	cd $dir
	uplevel 1 $script
    } finally {
	# Move kept files, if any, out of the temp directory to the
	# persistent place.
	foreach f [glob -nocomplain kept.*] {
	    file rename -force $f $here
	}
	cd $here
    }
}

proc withenv {script args} {
    global env
    set saved [array get env]
    try {
	array set env $args
	uplevel 1 $script
    } finally {
	array unset env *
	array set env $saved
    }
}

proc touch {path} {
    file mkdir [thehome]
    set path [thehome]/$path
    file mkdir [file dirname $path]
    fileutil::touch $path
    return $path
}

proc touchdir {path} {
    set path [thehome]/$path
    file mkdir $path
    return $path
}

proc debug   {} { variable verbose 1 }
proc nodebug {} { variable verbose 0 }

proc keep   {} { variable keep 1 }
proc nokeep {} { variable keep 0 }

proc run {args} {
    variable verbose
    if {$verbose} { puts "\n\n%% s $args" }

    set out [file join [tmp] [pid].out]
    set err [file join [tmp] [pid].err]

    global env
    set here $env(HOME)
    try {
	file delete $out $err
	set env(HOME) [thehome]
	set env(STACKATO_NO_WRAP) 1
	set fail [catch {
	    exec > $out 2> $err [Where] {*}$args
	}]
    } finally {
	set   env(HOME) $here
	unset env(STACKATO_NO_WRAP)
    }

    Capture $out $err $fail
}

proc run-any {args} {
    variable verbose
    if {$verbose} { puts "\n\n%% s $args" }

    set out [file join [tmp] [pid].out]
    set err [file join [tmp] [pid].err]

    global env
    set here $env(HOME)
    try {
	file delete $out $err
	set env(HOME) [thehome]
	set env(STACKATO_NO_WRAP) 1
	set fail [catch {
	    exec > $out 2> $err {*}$args
	}]
    } finally {
	set   env(HOME) $here
	unset env(STACKATO_NO_WRAP)
    }

    Capture $out $err $fail
}

proc stage-open {} {
    file delete -force [thehome];# auto close if left open.
    file mkdir         [thehome]
    return
}

proc stage-close {} {
    file delete -force [thehome]
    return
}

proc Where {} {
    set r [auto_execok stackato]
    proc Where {} [list return $r]
    return $r
}

proc Capture {out err fail} {
    global status stdout stderr all verbose keep

    set status $fail
    set stdout [string trim [fileutil::cat $out]]
    set stderr [string trim [fileutil::cat $err]]

    # Trim devbuild warning from output.
    set stdout [split $stdout \n]
    if {[string match *DEV* [lindex $stdout 0]]} {
	set stdout [lrange $stdout 1 end]
    }
    set stdout [string trim [join $stdout \n]]

    set all [list $status $stdout $stderr]

    if {$keep} {
	file rename -force $out kept.out
	file rename -force $err kept.err
    } else {
	file delete $out $err
    }

    if {$verbose} {
	puts status||$status|
	puts stdout||$stdout|
	puts stderr||$stderr|
    }

    if {$fail || ($stderr ne {})} {
	if {$stderr ne {}} {
	    set msg $stderr
	} elseif {$stdout ne {}} {
	    set msg $stdout
	} else {
	    set msg {}
	}
	return -code error -errorcode FAIL $msg
    }

    return $stdout
}

proc login-required {} {
    return "Login Required\nPlease use 'stackato login'"
}

proc not-authorized {} {
    return "Not Authorized\nYou are not authorized to perform the requested action (403)\nPlease use 'stackato login'"
}

proc no-application {cmd} {
    return "No manifest\nNo application specified, and no manifest found.\nstackato $cmd *"
}

proc no-application-q {cmd} {
    return "No application specified, and no manifest found.\nstackato $cmd *"
}

proc expected-app {x cmd} {
    return "Error: The application \[$x\] is not deployed. Please deploy it, or choose a different application to $cmd."
}

proc already {ptype pname type name {context {}}} {
    if {[string match {A *} $type] ||
	[string match {An *} $type]} {
	set lead {}
    } elseif {[string match {[aeiouAEIOU]*} $type]} {
	set lead {An }
    } else {
	set lead {A }
    }
    return "Found a problem with $ptype \"$pname\": $lead$type named \"$name\" already exists$context. Please use a different name."
}

proc unexpected {ptype pname type name {context {}}} {
    if {[string match {A *} $type] ||
	[string match {An *} $type]} {
	set lead {}
    } elseif {[string match {[aeiouAEIOU]*} $type]} {
	set lead {An }
    } else {
	set lead {A }
    }
    return "Found a problem with $ptype \"$pname\": $lead$type \"$name\" does not exist$context. Please use a different value."
}


proc ssh-cmd {app dry {group {}}} {
    if {$group ne {}} { set group " -G $group" }
    return "/*/ssh -i */key_* -o IdentitiesOnly=yes -t -o \"PasswordAuthentication no\" -o \"ChallengeResponseAuthentication no\" -o \"PreferredAuthentications publickey\" -2 -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null stackato@[theplaintarget] stackato-ssh${group} * $app 0 $dry"
}

proc ref-target {} {
    run target -n [thetarget] --allow-http
}

proc be-admin {} {
    global isv1
    run logout --all
    if {$isv1} {
	run login -n [adminuser] --password [adminpass]
    } else {
	run login -n [adminuser] --password [adminpass] --organization [theorg] --space [thespace]
    }
}

proc be-non-admin {} {
    global isv1
    run logout --all
    if {$isv1} {
	run login -n [theuser] --password P
    } else {
	run login -n --ignore-missing [theuser] --password P --organization [theorg] --space [thespace]
    }
}

proc make-non-admin {} {
    global isv1
    if {$isv1} {
	run add-user -n [theuser] --password P
    } else {
	run add-user -n [theuser] --email [theuser] --password P --organization [theorg]
	run link-user-org   [theuser] [theorg] ;# --developer implied and default
	run link-user-space [theuser] [thespace]  --developer
    }
}

proc remove-non-admin {} {
    run delete-user -n [theuser]
}

proc go-admin {} {
    ref-target
    be-admin
    # DEBUG-CHECKS
}

proc go-non-admin {} {
    make-non-admin
    be-non-admin
}

proc de-route {name} {
    global isv2
    if {!$isv2} return
    catch {
	run delete-route -n [string tolower $name].[targetdomain]
    }
}

proc make-test-app {{name TEST} {appdir {}}} {
    de-route $name
    if {$appdir eq {}} {
	set appdir [appdir]
    }
    indir $appdir { run create-app -n $name }
}

proc remove-test-app {{name TEST}} {
    global isv1
    run delete -n $name
    if {$isv1} return
    catch {
	run delete-route -n [string tolower $name].[targetdomain]
    }
    return
}

proc recycle-org {} {
    # Delete domain owned by an org by killing the container, and
    # regenerating it and the space.
    run delete-org   -n [theorg] --recursive
    run create-org   -n [theorg]
    run create-space -n [thespace]
    run link-user-org   -n [adminuser] [theorg]
    run link-user-space -n [adminuser] [thespace] --developer --manager
    return
}

# # ## ### ##### ######## ############# #####################

# Ok if the pattern is NOT matched.
proc antiglob {pattern string} {
    expr {![string match $pattern $string]}
}
tcltest::customMatch anti-glob antiglob


proc services {} {
    return [per-api {
	filesystem
	harbor
	memcached
	mongodb
	mysql
	postgresql
	rabbitmq
	redis
    } {
	filesystem
	harbor
	mongodb
	mysql
	postgresql
	rabbitmq
	rabbitmq3
	redis
    }]
}

proc per-api {v1 v2} {
    global isv1
    return [expr {$isv1 ? $v1 : $v2}]
}

# # ## ### ##### ######## ############# #####################

nodebug
nokeep

# # ## ### ##### ######## ############# #####################
## Standard constraints. Predicated on the target API version.

apply {{spec} {
    # The variables are used in other parts of common code.
    global isv1 isv2 post30 pre32 post32 pre34

    set isv1   [expr {[dict get $spec API] <  2}]
    set isv2   [expr {[dict get $spec API] >= 2}]
    set post30 [expr {[package vcompare [dict get $spec Version] 3.1] >= 0}]
    set pre32  [expr {[package vcompare [dict get $spec Version] 3.1] < 0}]

    set post32 [expr {[package vcompare [dict get $spec Version] 3.3] >= 0}]
    set pre34  [expr {[package vcompare [dict get $spec Version] 3.3] < 0}]

    tcltest::testConstraint cfv1    $isv1 ;# target is v1
    tcltest::testConstraint cfv2    $isv2 ;# target is v2
    tcltest::testConstraint s34ge   [expr {$isv2 && $post32}]
    tcltest::testConstraint s32ge   [expr {$isv2 && $post30}]
    tcltest::testConstraint s32     [expr {$isv2 && $post30 && $pre34}]
    tcltest::testConstraint s32le   [expr {$isv2 && $pre34}]
    tcltest::testConstraint s30le   [expr {$isv2 && $pre32}]

}} [run debug-target --target [thetarget]]

# # ## ### ##### ######## ############# #####################
## Activate when debugging issues with constraints.
NOTE
NOTE "cfv1  = [tcltest::testConstraint cfv1]"
NOTE "cfv2  = [tcltest::testConstraint cfv2]"
NOTE "s30le = [tcltest::testConstraint s30le]"
NOTE "s32ge = [tcltest::testConstraint s32ge]"
NOTE "s32le = [tcltest::testConstraint s32le]"
NOTE "s32   = [tcltest::testConstraint s32]"
NOTE "s34ge = [tcltest::testConstraint s34ge]"

# # ## ### ##### ######## ############# #####################
return
