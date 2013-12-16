# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## App entity definition

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require TclOO
package require oo::util
package require stackato::v2::base

# # ## ### ##### ######## ############# #####################

debug level  v2/app
debug prefix v2/app {[debug caller] | }

# # ## ### ##### ######## ############# #####################

stackato v2 register app
oo::class create ::stackato::v2::app {
    superclass ::stackato::v2::base

    # # ## ### ##### ######## #############
    ## State
    #

    ## - myimap: A map from instance indices (numeric) to the
    ##           'appinstance' object holding its state. Reuses the
    ##           objects as much as possible.

    variable myimap

    # # ## ### ##### ######## #############
    ## Life cycle

    constructor {{url {}}} {
	debug.v2/app {}
	set myimap {}

	my Forbidden uris running_instances
	# The internal data cache is also used by the non-attribute
	# keys 'running_instances' and 'uris' (See various methods
	# here). When changing attribute names make sure to not
	# collide with these.

	my Attribute name             string
	my Attribute space            &space
	my Attribute environment_json dict    label {Environment} default {}
	my Attribute memory           integer label {Memory     } default 256            ;# integer0 is better
	my Attribute total_instances  integer label {Instances  } default 1 as instances ;# integer0 actually.
	my Attribute disk_quota       integer label {Disk       } default 256            ;# integer0 is better
	my Attribute state            string  label {State      } default STOPPED        ;# state enum might help
	my Attribute command          string  label {Command    } default {}
	my Attribute console          boolean label {Console    } default off
	my Attribute buildpack        string  label {Buildpack  } default {}
	my Attribute stack            &stack  label {Stack      } default {}
	my Attribute debug            string  label {Debug      } default {}

	my Many service_bindings
	my Many	routes
	my Many	events app_event

	#my SearchableOn name
	#my SearchableOn space
	#my SearchableOn organization

	# Special keys in summaries and how to handle them.
	my Summary \
	    urls              [mymethod S.urls] \
	    running_instances [mymethod S.ri] \
	    instances         [mymethod S.instances] \
	    service_names     [mymethod S.services]

	# TODO scoped_to_space

	next $url

	debug.v2/app {/done}
    }

    # # ## ### ##### ######## #############

    classmethod list-by-name  {name {depth 0}} { my list-filter name $name $depth }
    classmethod first-by-name {name {depth 0}} { lindex [my list-by-name $name $depth] 0 }
    classmethod find-by-name  {name {depth 0}} { my find-by name $name $depth }

    # # ## ### ##### ######## #############

    classmethod list-by-space  {space {depth 0}} { my list-filter space $space $depth }
    classmethod first-by-space {space {depth 0}} { lindex [my list-by-space $space $depth] 0 }
    classmethod find-by-space  {space {depth 0}} { my find-by space $space $depth }

    # # ## ### ##### ######## #############

    classmethod list-by-organization  {organization {depth 0}} { my list-filter organization $organization $depth }
    classmethod first-by-organization {organization {depth 0}} { lindex [my list-by-organization $organization $depth] 0 }
    classmethod find-by-organization  {organization {depth 0}} { my find-by organization $organization $depth }

    # # ## ### ##### ######## #############
    ## Drain handling -- Note how drains are addressed by name
    ## Note how drains are not a new type entity with full UUID.

    method drain-create {name uri json} {
	debug.v2/app {}
	[authenticated] drain-create-of [my url] $name $uri $json
	return
    }

    method drain-delete {name} {
	debug.v2/app {}
	[authenticated] drain-delete-of [my url] $name
	return
    }

    method drain-list {} {
	debug.v2/app {}
	[authenticated] drain-list-of [my url]
    }

    # # ## ### ##### ######## #############
    ## Special APIs ... Accessors ...

    method services {} {
	debug.v2/app {}
	variable mydata
	if {[dict exists $mydata service_names]} {
	    return [dict get $mydata service_names]
	}
	try {
	    set services [my @service_bindings @service_instance @name]
	} trap {STACKATO CLIENT V2 UNDEFINED ATTRIBUTE service_bindings} {e o} {
	    set services {}
	}
	return $services
    }

    method uris {} {
	debug.v2/app {}
	variable mydata
	if {[dict exists $mydata uris]} {
	    return [dict get $mydata uris]
	}
	return [my @routes name]
    }

    method uri {} {
	debug.v2/app {}
	return [lindex [my uris] 0]
    }

    method running_instances {} {
	debug.v2/app {}
	variable mydata
	if {[dict exists $mydata running_instances]} {
	    debug.v2/app {cached (summary)}

	    return [dict get $mydata running_instances]
	}

	debug.v2/app {count}

	set count 0
	# 'instances' not trapped for in-progress. The caller of using
	# method 'health' wants to know about this exception in some
	# situations.
	dict for {n i} [my instances] {
	    if {[$i running?]} { incr count }
	}

	debug.v2/app {==> $count}
	return $count
    }

    method instances {} {
	debug.v2/app {}
	set json [[authenticated] instances-of [my url]]
	# While we might like to, we cannot really trap the error
	# {STACKATO CLIENT V2 STAGING IN-PROGRESS} here, as there are
	# callers which have to know about this exceptional condition.
	#
	# Thus all the callers are responsible for trapping the issue
	# for themselves.

	set max -1
	dict for {n idata} $json {
	    if {$n > $max} { set max $n }
	    [my I $n] = $idata
	}
	my D $max
	return $myimap
    }

    method health {} {
	debug.v2/app {}

	set state [my @state]
	debug.v2/app {state    = $state}

	if {$state ne "STARTED"} { return $state }
	# assert: STATE == STARTED

	set expected [my @total_instances]
	debug.v2/app {expected = $expected}

	if {!$expected} { return N/A }

	set active [my running_instances]
	debug.v2/app {active   = $active}

	# Hack around a wierd server response.
	if {$active eq "null"} { set active 0 }
	debug.v2/app {active'  = $active}

	if {$active == $expected} {
	    debug.v2/app {All OK}
	    return RUNNING
	}
	if {!$active} {
	    debug.v2/app {All missing}
	    return 0%
	}

	set health [expr {(100 * $active) / $expected}]
	debug.v2/app {health   = $health}

	return ${health}%
    }

    method stopped? {} {
	debug.v2/app {}
	string equal [my @state] STOPPED
    }

    method started? {} {
	debug.v2/app {}
	# Not necessarily healthy!
	string equal [my @state] STARTED
    }

    method healthy? {} {
	debug.v2/app {}
	my invalidate ;# force reload in health.
	string equal [my health] RUNNING
    }

    method logs {n} {
	debug.v2/app {}
	return [[authenticated] logs-of [my url] $n]
    }

    method logs-async {cmd n} {
	debug.v2/app {}
	return [[authenticated] logs-async-of $cmd [my url] $n]
    }

    # # ## ### ##### ######## #############
    ## Special APIs ... Control

    method start! {{mode sync}} {
	debug.v2/app {}
	my @state set STARTED
	my @console set true
	my commit $mode
    }

    method stop! {{mode sync}} {
	debug.v2/app {}
	my @state set STOPPED
	my commit $mode
    }

    method restart! {{mode sync}} {
	debug.v2/app {}
	my stop
	my start $mode
    }

    method commit {{mode sync}} {
	debug.v2/app {}
	# Note that the commit signature differs from the base class.
	# The base class takes a varargs dictionary of form parameters
	# with values. Here we take a single optional mode argument,
	# and translate it to a form parameter with value.

	if {$mode eq "async"} {
	    next stage_async 1
	} else {
	    next
	}
    }

    method delete! {args} {
	debug.v2/app {}
	my delete recursive true {*}$args
	my commit
	return
    }

    method upload! {zip resources} {
	debug.v2/app {}
	[authenticated] upload-by-url [my url]/bits $zip $resources
	return
    }

    # # ## ### ##### ######## #############

    method crashes {} {
	debug.v2/app {}
	[authenticated] crashes-of [my url]
	# json = array (dict ( instance -> id, since -> epoch))
    }

    method stats {} {
	debug.v2/app {}
	[authenticated] stats-of [my url]
    }

    # # ## ### ##### ######## #############
    ## Instance specific operations.

    method for-instance {index operation args} {
	debug.v2/app {}
	my instance-$operation $index {*}$args
    }

    method instance-files {index path} {
	debug.v2/app {}
	[authenticated] files [my url] $path $index
    }

    # # ## ### ##### ######## #############
    ## Summary callbacks.

    method S.urls {x} {
	debug.v2/app {}
	variable mydata
	# Direct placement into the entity data cache.
	# Outside of regular attributes and control.
	dict set mydata uris $x
	return
    }

    method S.ri {x} {
	debug.v2/app {}
	variable mydata
	# Direct placement into the entity data cache.
	# Outside of regular attributes and control.
	dict set mydata running_instances $x
	return
    }

    method S.services {x} {
	debug.v2/app {}
	variable mydata
	# Direct placement into the entity data cache.
	# Outside of regular attributes and control.
	dict set mydata service_names $x
	return
    }

    method S.instances {x} {
	debug.v2/app {}
	variable mydata
	# Map to actual attribute 'total_instances'.
	my @total_instances set $x
	return
    }

    # # ## ### ##### ######## #############
    ## Internal.

    method I {n} {
	if {![dict exists $myimap $n]} {
	    set obj [v2 appinstance new [self] $n]
	    dict set myimap $n $obj
	} else {
	    set obj [dict get $myimap $n]
	}
	return $obj
    }

    method D {max} {
	foreach n [dict keys $myimap] {
	    if {$n <= $max} continue
	    dict unset myimap $n
	}
	return
    }

    # # ## ### ##### ######## #############
    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
## Helper class capturing application instance state.  Sets of
## instance instances are wholly managed by application entity
## instances.

oo::class create ::stackato::v2::appinstance {
    # # ## ### ##### ######## #############
    ## State
    #
    ## - myapp  - Application the instance belongs to.
    ## - mynum  - Numeric index of the instance for REST calls.
    ## - myjson - Instance state object (dict)

    variable myapp mynum myjson

    classmethod states {} {
	return {
	    DOWN
	    FLAPPING
	    RUNNING
	    STARTING
	}
    }

    # # ## ### ##### ######## #############
    ## Lifecycle

    constructor {app num {data {}}} {
	debug.v2/app {}
	set myapp  $app
	set mynum  $num
	set myjson $data

	# Forwards to instance's container
	interp alias {} [self namespace]::app    {} $myapp
	interp alias {} [self namespace]::app-do {} $myapp for-instance $mynum

	debug.v2/app {/done}
	return
    }

    destructor {
	debug.v2/app {}
    }

    # # ## ### ##### ######## #############
    ## API

    method = {json} {
	set myjson $json
	return
    }
    export =

    method as-json {} {
	return $myjson
    }

    method down?     {} { string equal [my state] DOWN     }
    method flapping? {} { string equal [my state] FLAPPING }
    method running?  {} { string equal [my state] RUNNING  }
    method starting? {} { string equal [my state] STARTING }

    method state {} { dict get $myjson state }
    method since {} { dict get $myjson since }

    method debugger {} {
	if {![dict exists $myjson debug_ip] ||
	    ![dict exists $myjson debug_port]} {
	    return {}
	}

	dict set r ip   [dict get $myjson debug_ip]
	dict set r port [dict get $myjson debug_port]
	return $r
    }

    method console {} {
	if {![dict exists $myjson console_ip] ||
	    ![dict exists $myjson console_port]} {
	    return {}
	}

	dict set r ip   [dict get $myjson console_ip]
	dict set r port [dict get $myjson console_port]
	return $r
    }

    method healthy? {} {
	set s [my state]
	if {$s in {STARTING RUNNING}} { return 1 }
	if {$s in {DOWN FLAPPING}} { return 0 }
	error "Unable to determine instance health from state $s"
    }

    # TODO: stream_file

    forward files app-do files
    forward file  app-do files

    # # ## ### ##### ######## #############
}

# # ## ### ##### ######## ############# #####################
package provide stackato::v2::app 0
return
