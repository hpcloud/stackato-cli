## (c) 2013 Andreas Kupries
# # ## ### ##### ######## ############# #####################

package require fileutil
package require try

# # ## ### ##### ######## ############# #####################
## Configuration.

apply {{} {
    global env
    foreach {ev proc fallback} {
	STACKATO_CLI_TEST_TARGET theplaintarget todo-fallback-target
	STACKATO_CLI_TEST_USER   theuser        todo-fallback-nonadminusername
	STACKATO_CLI_TEST_GROUP	 thegroup       todo-fallback-groupname
	STACKATO_CLI_TEST_DRAIN	 thedrain       todo-fallback-drainurl
	STACKATO_CLI_TEST_ADMIN  adminuser      todo-fallback-adminusername
	STACKATO_CLI_TEST_APASS  adminpass      todo-fallback-adminpassword
	STACKATO_CLI_TEST_ORG    theorg         todo-fallback-org
	STACKATO_CLI_TEST_SPACE  thespace       todo-fallback-space
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
    set path [file join [tmp] data results$suffix ${x}.txt]
    if {![file exists $path]} { return {} }
    string trim [fileutil::cat $path]
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

proc debug   {} { variable verbose 1 }
proc nodebug {} { variable verbose 0 }

proc keep   {} { variable keep 1 }
proc nokeep {} { variable keep 0 }

proc run {args} {
    variable verbose
    if {$verbose} { puts "%% s $args" }

    set out [file join [tmp] [pid].out]
    set err [file join [tmp] [pid].err]

    global env
    set here $env(HOME)
    try {
	file delete $out $err
	set env(HOME) [thehome]
	set fail [catch {
	    exec > $out 2> $err [Where] {*}$args
	}]
    } finally {
	set env(HOME) $here
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
    return "Not Authorized\nYou are using an expired or deleted login\nPlease use 'stackato login'"
}

proc no-application {cmd} {
    return "No manifest\nNo application specified, and no manifest found.\n$cmd *"
}

proc no-application-q {cmd} {
    return "No application specified, and no manifest found.\n$cmd *"
}

proc expected-app {x cmd} {
    return "Error: The application \[$x\] is not deployed. Please deploy it, or choose a different application to $cmd."
}

proc ssh-cmd {app dry} {
    return "/*/ssh -i */key_* -o IdentitiesOnly=yes -t -o \"PasswordAuthentication no\" -o \"ChallengeResponseAuthentication no\" -o \"PreferredAuthentications publickey\" -2 -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null stackato@[theplaintarget] stackato-ssh * $app 0 $dry"
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
	run login -n [adminuser] --password [adminpass] --organization [theorg]
    }
}

proc be-non-admin {} {
    global isv1
    run logout --all
    if {$isv1} {
	run login -n [theuser] --password P
    } else {
	run login --ignore-missing -n [theuser] --password P --organization [theorg]
    }
}

proc make-non-admin {} {
    global isv1
    if {$isv1} {
	run add-user -n [theuser] --password P
    } else {
	run add-user -n [theuser] --email [theuser] --password P --organization [theorg]
	run link-user-org   [theuser] [theorg]   --developer
	run link-user-space [theuser] [thespace] --developer
    }
}

proc remove-non-admin {} {
    run delete-user -n [theuser]
}

proc go-admin {} {
    ref-target
    be-admin
}

proc go-non-admin {} {
    make-non-admin
    be-non-admin
}

proc make-test-app {{name TEST} {appdir {}}} {
    global isv2
    if {$isv2} {
	catch {
	    run delete-route -n [string tolower $name].[targetdomain]
	}
    }
    if {$appdir eq {}} {
	set appdir [appdir]
    }
    indir $appdir { run create-app -n $name }
    return
}

proc remove-test-app {{name TEST}} {
    global isv1
    run delete -n $name
    if {$isv1} return
    run delete-route -n [string tolower $name].[targetdomain]
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

set isv1 [expr {[dict get [run debug-target --target [thetarget]] API] <  2}]
set isv2 [expr {[dict get [run debug-target --target [thetarget]] API] >= 2}]

tcltest::testConstraint cfv1    $isv1 ;# target is v1
tcltest::testConstraint cfv2    $isv2 ;# target is v2
tcltest::testConstraint cfv2uaa $isv1 ;# target does not have cc/uaa split issues (== is v1)

# # ## ### ##### ######## ############# #####################
return
