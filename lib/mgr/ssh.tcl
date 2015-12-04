# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## This module manages ssh connections, both raw (CC node) and to
## instances.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require base64
package require exec
package require platform
package require url
package require lexec ; # TIP 424 exec syntax as package.
package require struct::list
package require cmdr::color
package require stackato::misc
package require stackato::log
package require stackato::mgr::auth
package require stackato::mgr::cgroup
package require stackato::mgr::ctarget
package require stackato::mgr::exit
package require stackato::mgr::self
package require stackato::mgr::targets

namespace eval ::stackato::mgr {
    namespace export ssh
    namespace ensemble create
}

namespace eval ::stackato::mgr::ssh {
    namespace export run cc copy quote quote1
    namespace ensemble create

    namespace import ::cmdr::color
    namespace import ::stackato::misc
    namespace import ::stackato::log::err
    namespace import ::stackato::log::say
    namespace import ::stackato::log::display
    namespace import ::stackato::mgr::auth
    namespace import ::stackato::mgr::cgroup
    namespace import ::stackato::mgr::ctarget
    namespace import ::stackato::mgr::exit
    namespace import ::stackato::mgr::self
    namespace import ::stackato::mgr::targets
}

debug level  mgr/ssh
debug prefix mgr/ssh {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## API

# See also ::stackato::mgr::self -- TODO consolidate

proc ::stackato::mgr::ssh::quote {args} {
    debug.mgr/ssh {}
    set cmd ""
    foreach w $args {
	lappend cmd [quote1 $w]
    }
    return $cmd
}

proc ::stackato::mgr::ssh::quote1 {w} {
    debug.mgr/ssh {}
    if {
	[string match "*\[ \"'()\$\|\{\}\]*" $w] ||
	[string match "*\]*"                 $w] ||
	[string match "*\[\[\]*"             $w]
    } {
	set map [list \" \\\"]
	return \"[string map $map $w]\"
    } else {
	return $w
    }
}

proc ::stackato::mgr::ssh::quote1a {w} {
    debug.mgr/ssh {}
    set map [list \" \\\"]
    return \"[string map $map $w]\"
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::ssh::cc {config arguments} {
    debug.mgr/ssh {}
    global env

    set target [ctarget get]
    regsub ^https?:// $target {} target
    set target [url base $target]

    SSHCommand opts cmd

    # Notes
    # -t : Force pty allocation, to allow the use of
    #      full curses/screen based commands.

    set cmd [list {*}$cmd -t {*}$opts stackato@$target {*}$arguments]

    InvokeSSH $config $cmd
    return
}

proc ::stackato::mgr::ssh::run {config arguments theapp instance {bg 0} {eincmd {}} {eocmd {}}} {
    # eincmd = External INput Command.
    # eocmd  = External Output Command.

    # bg modes
    # 0 - Synchronous child process.
    # 1 - Background child process.
    # 2 - See 0, result is process status.
    # 3 - See 0, no pty (8bit clean, scp)
    # 4 - See 0, result is cmd stdout.

    debug.mgr/ssh {}
    global env

    set client [$config @client]
    if {[$client isv2]} {
	set appname [$theapp id]
	# NOT the name here, but the unique v2 identifier, which is the uuid.
    } else {
	set appname $theapp
    }

    set target  [ctarget get]
    set token   [auth get]
    set keyfile [targets keyfile $target $token]

    if {![file exists $keyfile]} {
	if {$bg == 1} {
	    say [color warning "\nDisabled real-time view of staging, no ssh key available for target \[$target\]"]
	    return {}
	} else {
	    err "No ssh key available for target \[$target\]"
	}
    }

    debug.mgr/ssh {target  = ($target)}

    regsub ^https?:// $target {} target

    debug.mgr/ssh {target' = ($target)}

    SSHKeyOptions opts
    SSHCommand    opts cmd

    # Notes
    # -i keyfile            : Non-standard private key.
    # -o IdentitiesOnly=yes : ignore keys offered by ssh-agent
    # -t                    : Force pty allocation, to allow the use of
    #                         full curses/screen based commands.
    #
    # (bg == 3) => no pty, for 8bit clean data transfer (scp)

    lappend cmd -i $keyfile -o IdentitiesOnly=yes
    if {$bg == 3} {
	# no pty, and handle as plain sync child process.
	set bg 0
    } else {
	lappend cmd -t
    }
    lappend cmd {*}$opts stackato@$target stackato-ssh

    if {(![$client isv2]) && ([cgroup get] ne {})} {
	lappend cmd -G [cgroup get]
    }

    lappend cmd $token $appname $instance {*}$arguments

    return [InvokeSSH $config $cmd $bg $eincmd $eocmd]
}

proc ::stackato::mgr::ssh::copy {config paths theapp instance} {
    debug.mgr/ssh {}

    set client [$config @client]
    if {[$client isv2]} {
	set appname [$theapp id]
	# NOT the name here, but the unique v2 identifier, which is the uuid.
    } else {
	set appname $theapp
    }

    set dst [lindex $paths end]
    set src [lrange $paths 0 end-1]

    # Classify destination and sources in terms of local and remote.
    # Note that all sources have to have the same classification.

    set dst [PClass $dst dclass]
    set sclass {}
    foreach s $src {
	set s [PClass $s sc]
	if {($sclass ne {}) && ($sc ne $sclass)} {
	    return -code error -errorcode {STACKATO CLIENT CLI} \
		{Illegal mix of local and remote source paths}
	}
	set sclass $sc
	lappend new $s
    }
    set src $new

    # Four possibilities for src/dst classes:
    # (1) local -> local
    # (2) local -> remote
    # (3) remote -> local
    # (4) remote -> remote

    debug.mgr/ssh {mode = $sclass/$dclass}
    switch -exact -- $sclass/$dclass {
	local/local {
	    # Copying is purely local.
	    # This can be done using the builtin 'file copy'.
	    # To match the semantics of unix's 'cp' command we
	    # have to fully normalize the paths however, to ensure
	    # that files are copied, and not the symlinks.

	    set dst [misc full-normalize $dst]
	    set src [struct::list map $src ::stackato::misc::full-normalize]

	    if {[catch {
		file copy -force {*}$src $dst
	    } e o]} {
		# Translate into CLI error, not internal.
		return {*}$o -errorcode {STACKATO CLIENT CLI} $e
	    }
	}
	local/remote {
	    # Stream local to remote, taking destination path type
	    # (file, directory, missing) into account.
	    CopyLocalRemote $config $theapp $instance $src $dst
	}
	remote/local {
	    # Stream remote to local, taking destination path type
	    # (file, directory, missing) into account.
	    CopyRemoteLocal $config $theapp $instance $src $dst
	}
	remote/remote {
	    # Copying is purely on the remote side. This is done
	    # using the unix 'cp' we can expect to exist there.
	    run $config \
		[list "cp -r [join [quote {*}$src]] [quote1 $dst]"] \
		$theapp $instance
	}
	default { error "Cannot happen" }
    }

    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::ssh::PClass {path cvar} {
    debug.mgr/ssh {}
    upvar 1 $cvar class
    if {[string match :* $path]} {
	set class remote
	set path [string range $path 1 end]
    } else {
	set class local
    }

    debug.mgr/ssh {==> $class ($path)}
    return $path
}

proc ::stackato::mgr::ssh::CopyLocalRemote {config theapp instance src dst} {
    debug.mgr/ssh {}
    # src - all local, dst - remote

    # scp semantics...
    # dst exists ? File or directory ?
    #
    # dst a file?
    # yes: multiple sources?
    #      yes: error (a)
    #      no:  copy file, overwrite existing file (b)
    #
    # dst a directory?
    # yes: copy all sources into the directory (c)
    #
    # now implied => dst missing.
    # multiple sources?
    # yes: error (d)
    # no:  copy file or directory, create destination
    #

    if {($dst ne {}) && [TestIsFile $dst]} {
	# destination exists, is a file.
	# must have single source, must be a file.

	if {[llength $src] > 1} {
	    # (Ad a)
	    return -code error -errorcode {STACKATO CLIENT CLI} \
		"copying multiple files, but last argument `$dst' is not a directory"
	}

	set src [lindex $src 0]
	if {[file isdirectory $src]} {
	    return -code error -errorcode {STACKATO CLIENT CLI} \
		"cannot overwrite non-directory `$dst' with directory `$src'"

	}

	# (Ad b)
	CopyLocalRemoteFileFile $src $dst
	return
    }

    if {($dst eq {}) || [TestIsDirectory $dst]} {
	# (Ad c)
	CopyLocalRemoteMultiDir $src $dst
	return
    }

    # destination doesn't exist.
    # single source: copy file to file.
    # single source: copy directory to directory.
    # multiple sources: error, can't copy to missing directory.

    if {[llength $src] == 1} {
	# (Ad e)

	set src [lindex $src 0]
	if {[file isdirectory $src]} {
	    # single directory to non-existing destination.
	    # destination is created as directory, then src
	    # contents are streamed.

	    cd::indir $src {
		set paths \
		    [struct::list filter \
			 [lsort -unique [glob -nocomplain .* *]] \
			 [lambda {x} {
			     return [expr {($x ne ".") && ($x ne "..")}]
			 }]]
		CopyLocalRemoteMultiDir $paths $dst
	    }
	} else {
	    CopyLocalRemoteFileFile $src $dst
	}
	return
    }

    # (Ad d)
    return -code error \
	-errorcode {STACKATO CLIENT CLI} \
	"`$dst': specified destination directory does not exist"
    return
}

proc ::stackato::mgr::ssh::CopyRemoteLocal {config theapp instance src dst} {
    debug.mgr/ssh {}
    # src - all remote, dst - local

    # scp semantics...
    # dst exists ? File or directory ?
    #
    # dst a file?
    # yes: multiple sources?
    #      yes: error (a)
    #      no:  copy file, overwrite existing file (b)
    #
    # dst a directory?
    # yes: copy all sources into the directory (c)
    #
    # now implied => dst missing.
    # multiple sources?
    # yes: error (d)
    # no:  copy file, overwrite existing file (e)
    #

    lassign [CheckSources $src] src ftype
    # Expanded list of source paths, plus mapping to path-type
    # Includes test for existence as well.

    if {[file isfile $dst]} {
	# destination exists, is a file.
	# must have single source, must be a file.

	if {[llength $src] > 1} {
	    # (Ad a)
	    return -code error -errorcode {STACKATO CLIENT CLI} \
		"copying multiple files, but last argument `$dst' is not a directory"
	}

	set src [lindex $src 0]
	if {[dict get $ftype $src] eq "directory"} {
	    return -code error -errorcode {STACKATO CLIENT CLI} \
		"cannot overwrite non-directory `$dst' with directory `$src'"

	}

	# (Ad b)
	CopyRemoteLocalFileFile $src $dst
	return
    }

    if {[file isdirectory $dst]} {
	# (Ad c)
	CopyRemoteLocalMultiDir $src $dst
	return
    }

    # destination doesn't exist.
    # single source: copy file to file.
    # single source: copy directory to directory.
    # multiple sources: error, can't copy to missing directory.

    if {[llength $src] == 1} {
	# (Ad d)

	set src [lindex $src 0]
	if {[dict get $ftype $src] eq "directory"} {
	    # single directory to non-existing destination.
	    # destination is created as directory, then src
	    # contents are streamed.
	    CopyRemoteLocalDirDir $src $dst
	} else {
	    CopyRemoteLocalFileFile $src $dst
	}
	return
    }

    # (Ad e)
    return -code error \
	-errorcode {STACKATO CLIENT CLI} \
	"`$dst': specified destination directory does not exist"
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::ssh::CopyLocalRemoteFileFile {src dst} {
    # copy file to file (existing or new), streamed via cat on both
    # sides.  The double list-quoting for the remote command hides the
    # output redirection from the local exec.

    upvar 1 config config theapp theapp instance instance

    debug.mgr/ssh {local/remote file/file}

    run $config [list "cat > [quote1 $dst]"] \
	$theapp $instance 3 \
	[list {*}[self exe] scp-xfer-transmit1 $src]
    return
}

proc ::stackato::mgr::ssh::CopyLocalRemoteMultiDir {srclist dst} {
    # destination created if not existing, is a directory.
    # copy all sources into that directory.
    # streamed via tar on both sides.

    upvar 1 config config theapp theapp instance instance

    debug.mgr/ssh {local/remote */dir}

    # No directory specified, force use of the working directory
    # <==> app home directory.
    if {$dst eq {}} { set dst . }

    set dst [quote1 $dst]
    run $config [list "mkdir -p $dst ; cd $dst ; tar xf -"] \
	$theapp $instance 3 \
	[list {*}[self exe] scp-xfer-transmit {*}$srclist]
    return
}

proc ::stackato::mgr::ssh::CopyRemoteLocalFileFile {src dst} {
    # copy file to file, streamed via cat on both sides.
    upvar 1 config config theapp theapp instance instance

    debug.mgr/ssh {remote/local file/file}

    run $config [list "cat [quote1 $src]"] \
	$theapp $instance 3 \
	{} [list {*}[self exe] scp-xfer-receive1 $dst]
    return
}

proc ::stackato::mgr::ssh::CopyRemoteLocalMultiDir {srclist dst} {
    # destination exists, is a directory.
    # copy all sources into that directory.
    # streamed via tar on both sides.

    upvar 1 config config theapp theapp instance instance

    # NOTE: CheckSources not only returned file/dir information, but
    # NOTE: also performed glob expansion. We can assume to have only
    # NOTE: exact paths here.

    # We now construct a script which packages up all the remote files
    # in such a way that the stem is stripped of the path names. This
    # matches scp's behaviour. See bug 104473.
    #
    # Note that the creation of the script is a bit more complicated
    # than just issuing one tar command per src. We aggregate multiple
    # files in the same directory into a single tar command as a
    # simple optimization.

    # Phase I. Aggregate files per base directory.
    foreach src $srclist {
	set base  [file dirname $src]
	set fpath [file tail    $src]
	dict lappend map $base $fpath
    }

    # Phase II. Issue tar command per base directory.
    set script {}
    dict for {base files} $map {
	lappend script "tar cf - -C [quote1 $base] [quote {*}$files]"
    }
    set script [join $script \n]

    # And go.
    set nexpected [llength $srclist]
    run $config [list [SAC $script]] \
	$theapp $instance 3 \
	{} [list {*}[self exe] scp-xfer-receive $dst $nexpected]
    return
}

proc ::stackato::mgr::ssh::CopyRemoteLocalDirDir {src dst} {
    # destination exists, is a directory.
    # copy source directory to that directory.
    # streamed via tar on both sides.

    upvar 1 config config theapp theapp instance instance

    run $config [list "cd [quote1 $src] ; tar cf - ."] \
	$theapp $instance 3 \
	{} [list {*}[self exe] scp-xfer-receive $dst]
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::ssh::CheckSources {paths} {
    upvar 1 config config theapp theapp instance instance
    variable csscript

    debug.mgr/ssh {}

    # Generate a script to bulk check all source-path patterns on the remote side.
    # Bad patterns result in an early MISS we report, and ok patterns are glob-expanded,
    # with the results checked for type, and returned.

    set cmd {}
    foreach src $paths { append cmd " [quote1a $src]" }
    set script [string map [list @@@ $cmd] $csscript]

    set lines [run $config [list [SAC $script]] $theapp $instance 4]

    # Process the result into Tcl structures for the caller (list of
    # paths, plus mapping from paths to their types).

    debug.mgr/ssh {==============================}
    set paths {}
    set ftype {}

    foreach line [split $lines \n] {
	debug.mgr/ssh {=== $line}

        set cmd   [string range $line 0 3]
        set value [string range $line 5 end]
        switch -exact -- $cmd {
	    MISS {
		return -code error -errorcode {STACKATO CLIENT CLI} \
		    "$value: No such file or directory"
	    }
	    FILE {
		lappend paths  $value
		dict set ftype $value file
	    }
	    DIRE {
		lappend paths  $value
		dict set ftype $value directory
	    }
	    default { error "Cannot happen" }
	}
    }
    debug.mgr/ssh {==============================}

    list $paths $ftype
}

proc ::stackato::mgr::ssh::SAC {script} {
    # SAC = Script-As-Command.
    # Encapsulate script into a command which uploads and runs it.
    # The system for transfering commands currently does not like
    # multi-line commands.
    # Transfering everything base64-coded gets around the issue.
    return "echo [base64::encode -maxlen 0 $script] | base64 -d - | bash"
}

proc ::stackato::mgr::ssh::TestIsFile {path} {
    upvar 1 config config theapp theapp instance instance
    # test uses standard unix stati to communicate its result:
    # (0)    == false ==> OK
    # (!= 0) == true  ==> FAIL
    set path [quote1 $path]
    if {![run $config [list "test -f $path"] $theapp $instance 2]} {
	return 1
    } else {
	return 0
    }
}

proc ::stackato::mgr::ssh::TestIsDirectory {path} {
    upvar 1 config config theapp theapp instance instance
    # test uses standard unix stati to communicate its result:
    # (0)    == false ==> OK
    # (!= 0) == true  ==> FAIL
    set path [quote1 $path]
    if {![run $config [list "test -d $path"] $theapp $instance 2]} {
	return 1
    } else {
	return 0
    }
}

proc ::stackato::mgr::ssh::TestExists {path} {
    upvar 1 config config theapp theapp instance instance
    # test uses standard unix stati to communicate its result:
    # (0)    == false ==> OK
    # (!= 0) == true  ==> FAIL
    set path [quote1 $path]
    if {![run $config [list "test -e $path"] $theapp $instance 2]} {
	return 1
    } else {
	return 0
    }
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::ssh::SSHKeyOptions {ov} {
    debug.mgr/ssh {}
    upvar 1 $ov opts

    # Standard options, common parts.
    lappend opts -o {PasswordAuthentication no}
    lappend opts -o {ChallengeResponseAuthentication no}
    lappend opts -o {PreferredAuthentications publickey}
    return
}

proc ::stackato::mgr::ssh::SSHCommand {ov cv} {
    debug.mgr/ssh {}
    global env
    upvar 1 $ov opts $cv cmd

    lappend opts -2
    lappend opts -q -o StrictHostKeyChecking=no

    set helpsuffix ""
    if {$::tcl_platform(platform) eq "windows"} {
	# Platform specific standard options
	lappend opts -o UserKnownHostsFile=NUL:
	append helpsuffix "\nPrecompiled compatible ssh binaries for Windows can be obtained from:"
	append helpsuffix "\n   https://sourceforge.net/apps/trac/mingw-w64/wiki/MSYS"
    } else {
	# Platform specific standard options
	lappend opts -o UserKnownHostsFile=/dev/null
    }

    set cmd [auto_execok ssh]
    if {![llength $cmd]} {
	err "Local helper application ssh not found in PATH.$helpsuffix"
    }

    if {[string match macosx* [platform::generic]]} {
	# On OS X force the use of ipv4 to cut down on delays.
	lappend opts -4
    }

    if {[info exists env(STACKATO_SSH_OPTS)]} {
	lappend opts {*}$env(STACKATO_SSH_OPTS)
    }

    return
}

proc ::stackato::mgr::ssh::GetStatus {options} {
    set status [lindex [dict get $options -errorcode] end]
    debug.mgr/ssh {status = $status}

    if {$status == 255} {
	append msg "Server closed connection."
	append msg " This may have been caused by an out-of-date ssh key."
	append msg " [self please login] to refresh the ssh key."
	err $msg
    }
    return $status
}

proc ::stackato::mgr::ssh::InvokeSSH {config cmd {bg 0} {eincmd {}} {eocmd {}}} {
    # eincmd = External INput Command.
    # eocmd  = External Output Command.
    debug.mgr/ssh {}
    global env

    if {[$config @dry]} {
	display [join [quote {*}$cmd] { }]
	return
    }

    if {$bg == 4} {
	# CheckSources is only caller for bg==4.
	try {
	    set lines [lexec::exec \
			   | $cmd 2>@ stderr <@ stdin]
	} trap {CHILDSTATUS} {e o} {
	    err [lindex [split [dict get $o -errorinfo] \n] 0]
	    #exit fail [GetStatus $o]
	    #set lines {}
	}
	return $lines
    }

    if {$bg == 2} {
	try {
	    lexec::exec \
		| $cmd 2>@ stderr >@ stdout <@ stdin
	} trap {CHILDSTATUS} {e o} {
	    return [GetStatus $o]
	}
	debug.mgr/ssh {status = OK}
	return 0
    }

    if {$bg} {
	if {$::tcl_platform(platform) eq "windows"} {
	    set in NUL:
	    set err NUL:
	} else {
	    set in /dev/null
	    set err /dev/null
	}
	set pid [exec::bg+ [lexec::exec \
				| $cmd \
				2> $err >@ stdout < $in \
				& ]]
	return $pid
    }

    try {
	if {[llength $eincmd] && [llength $eocmd]} {
	    lexec::exec \
		| $eincmd 2>@ stderr \
		| $cmd               \
		| $eocmd   >@ stdout
	} elseif {[llength $eocmd]} {
	    lexec::exec \
		| $cmd   2>@ stderr \
		| $eocmd  >@ stdout
	} elseif {[llength $eincmd]} {
	    lexec::exec \
		| $eincmd 2>@ stderr \
		| $cmd     >@ stdout
	} else {
	    lexec::exec \
		| $cmd 2>@ stderr >@ stdout <@ stdin
	}
    } trap {CHILDSTATUS} {e o} {
	exit fail [GetStatus $o]
    }
    return
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::mgr::ssh {
    # See CheckSources for use. Inserts the patterns to check at @@@.
    # Needs a temp script file for the type-determination as xargs
    # cannot call a bash function. And xargs is required because it
    # gets the separation of paths right in face of spaces and quotes.
    # A plain 'for'-loop does not.

    variable csscript [string map {{	} {}} {cat > .__stackato_type <<'EOF'
	if [ -d "$1" ] ; then
	  echo DIRE "$1"
	else
	  echo FILE "$1"
	fi
	EOF
	chmod u+x .__stackato_type
	function __stackato_check ()
	{
	    for pattern in "$@"
	    do
	      n=$(ls -Q $pattern 2>/dev/null|wc -l)
	      if [ $n -eq 0 ] ; then
	        echo MISS "$pattern"
	        exit
	      fi
	    done
	    for pattern in "$@"
	    do
	      ls -Q $pattern | xargs -n1 ./.__stackato_type
	    done
	}
	__stackato_check @@@
	rm .__stackato_type
    }]
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::ssh 0
