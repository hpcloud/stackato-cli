# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require json::write
package require dictutil ;# get'

# pretty json, all the way.
json::write indented 1
json::write aligned 1

namespace eval ::stackato::jmap {}
namespace eval ::stackato {
    namespace export jmap
    namespace ensemble create
}

# # ## ### ##### ######## ############# #####################
## Convenience commands encapsulating the VMC data structure
## definitions.

proc ::stackato::jmap::manifest {m} {
    map {dict {
	env       array
	staging   {dict {
	    runtime nstring
	    stack   nstring
	}}
	resources dict
	services  array
	uris      narray
	meta      dict
    }} $m
}

proc ::stackato::jmap::drain {d} {
    map {dict {json bool}} $d
}

proc ::stackato::jmap::limits {d} {
    map {dict {sudo bool}} $d
}

proc ::stackato::jmap::bool {_ s} {
    if {$s} {
	return true
    } else {
	return false
    }
}

proc ::stackato::jmap::nbool {_ s} {
    if {$s eq "null"} { return null }
    if {$s eq {}}     { return null }
    if {$s} {
	return true
    } else {
	return false
    }
}

proc ::stackato::jmap::number {_ s} {
    return $s
}

proc ::stackato::jmap::nnumber {_ s} {
    if {$s eq "null"} { return null }
    if {$s eq {}}     { return null }
    return $s
}

proc ::stackato::jmap::nstring {_ s} {
    if {$s eq "null"} { return null }
    if {$s eq {}}     { return null }
    return [map string $s]
}

proc ::stackato::jmap::narray {t s} {
    if {$s eq {}} { return null }
    if {$s eq "null"} { return null }
    return [map [list array $t] $s]
}

proc ::stackato::jmap::seen-clear {} {
    variable seen {}
    return
}

proc ::stackato::jmap::1ref {_ s} {
    # The json data is an inlined referenced entity. We have an object
    # for this in memory, generated during processing of the inlined
    # json when resolving the phantom the current json belongs to. We
    # can determine this object and ask it directly for its json. This
    # will in turn recurse through any references it may have.
    variable seen
    set url [dict get $s metadata url]
    if {[dict exists $seen $url]} {
	return null
    }
    dict set seen $url .
    # Go through the secondary entry-point to keep the knowledge of
    # seen entities.
    return [[stackato v2 deref $url] as-json-map]
}

proc ::stackato::jmap::crashed    {c}  { map {array dict} $c }
proc ::stackato::jmap::aliases    {as} { map dict $as }
proc ::stackato::jmap::target     {t}  {
    map {dict {
	space        dict
	organization dict
    }} $t
}
proc ::stackato::jmap::env        {e}  { map array $e  }
proc ::stackato::jmap::targets    {ts} { map dict $ts }
proc ::stackato::jmap::tadjunct   {ts} { map {dict {* dict}} $ts }
proc ::stackato::jmap::tgroups    {gs} { map dict $gs }
proc ::stackato::jmap::runtimes   {rs} {
    map {dict {
	* dict
    }} $rs
}

proc ::stackato::jmap::v2-stacks  {st} { map {array dict} $st }
proc ::stackato::jmap::frameworks {fs} { map {dict {* array}} $fs }
proc ::stackato::jmap::resources  {rs} {
    map {array {dict {
	size number
    }}} $rs
}

proc ::stackato::jmap::apps    {as} {
    # @todo jmap apps - element type
    map {array {dict {
	env       array
	meta      dict
	resources dict
	services  array
	staging   dict
	uris      array
	services_connect_info {array {dict {
	    tags        array
	    credentials dict
	}}}
    }}} $as
}

proc ::stackato::jmap::v2-uaa-user {u} {
    map {dict {
	meta      dict
	name      dict
	emails    {array dict}
	groups    {array dict}
	approvals array
	schemas   array
    }} $u
}

proc ::stackato::jmap::v2-apps-summary {as} {
    map {dict {
	services {array {dict {
	    bound_app_count number
	    service_plan {dict {
		service dict
	    }}
	}}}
	apps {array {dict {
	    urls array
	    routes {array {dict {
		domain dict
	    }}}
	    service_count number
	    running_instances number
	    production bool
	    buildpack nstring
	    command nstring
	    debug nstring
	    environment_json dict
	    console   bool
	    instances number
	    memory    number
	    disk_quota number
	}}}
    }} $as
}

proc ::stackato::jmap::user1 {ui} {
    # Note how this contains a copy of appinfo.
    map {dict {
	apps {array {dict {
	    env       array
	    meta      dict
	    resources dict
	    services  array
	    staging   dict
	    uris      array
	    services_connect_info {array {dict {
		tags        array
		credentials dict
	    }}}
	}}}
    }} $ui
}

proc ::stackato::jmap::users {us} {
    map {array {dict {
	apps {array dict}
    }}} $us
}

proc ::stackato::jmap::v2uconfig {u} {
    map {dict {
	name   dict
	emails {array dict}
    }} $u
}

proc ::stackato::jmap::groups {gs} {
    map {dict {* array}} $gs
}

proc ::stackato::jmap::appinfo {ai} {
    map {dict {
	env       array
	meta      dict
	resources dict
	services  array
	staging   dict
	uris      array
	services_connect_info {array {dict {
	    tags        array
	    credentials dict
	}}}
    }} $ai
}

# services connect info
proc ::stackato::jmap::sci {ai} {
    map {dict {
	tags        array
	credentials dict
    }} $ai
}

# dbshell
proc ::stackato::jmap::dbs {v} {
    map {dict {
	args array
	env  dict
    }} $v
}

proc ::stackato::jmap::stats {ss} {
    # @todo jmap stats - element type
    map {array {dict {
	stats {dict {
	    usage dict
	    uris array
	}}
    }}} $ss
}

proc ::stackato::jmap::v2-stats {ss} {
    map {dict {* {dict {
	since number
	stats {dict {
	    disk_quota number
	    fds_quota  number
	    mem_quota  number
	    port       number
	    uptime     number
	    usage {dict {
		mem  number
		disk number
		cpu  number
	    }}
	}}
    }}}} $ss
}

proc ::stackato::jmap::instances {is} {
    # @todo jmap instances - element type
    map {array dict} $is
}

proc ::stackato::jmap::v2-instances {is} {
    # @todo jmap instances - element type
    map {dict {* {dict {
	since number
    }}}} $is
}

proc ::stackato::jmap::instancemap {is} {
    # @todo jmap instances - element type
    map dict $is
}

proc ::stackato::jmap::service {s} {
    map {dict {
	credentials dict
	meta {dict {
	    tags array
	}}
    }} $s
}

proc ::stackato::jmap::services   {ss} {
    # @todo jmap services, fill deeper dicts
    # Descriptions of the *, in order of nesting:
    # - service-type
    # - vendor (name)
    # - version
    # - tier-type
    map {dict {
	system      {dict {
	    * {dict {
		* {dict {
		    * {dict {
			tiers {dict {
			    * {dict {
				options dict
			    }}
			}}
		    }}
		}}
	    }}
	}}
	provisioned {array {dict {
	    meta {dict {
		tags array
	    }}
	    credentials dict
	}}}
    }} $ss
}

proc ::stackato::jmap::usageinfo {ui} {
    map {dict {
	allocated dict
	usage     dict
    }} $ui
}

proc ::stackato::jmap::clientinfo {ci} {
    map {dict {
	all_groups array
	usage  dict
	limits {dict {
	    sudo bool
	}}
	frameworks {dict {
	    * {dict {
		appservers {array dict}
		runtimes   {array dict}
		detection  {narray dict}
		sub_frameworks array
	    }}
	}}
	stackato {dict {
	    app_store_enabled bool
	    aok_enabled       bool
	    license_accepted  bool
	}}
    }} $ci
}

proc ::stackato::jmap::fwinfo {ci} {
    map {dict {
	* {dict {
	    appservers {array dict}
	    runtimes   {array dict}
	    detection  {array dict}
	}}
    }} $ci
}

proc ::stackato::jmap::cc_config {data} {
    map {dict {
	admins {array}
    }} $data
}

# # ## ### ##### ######## ############# #####################
## Core - Should go into json::write
## Alt implementation: typecodes = name of helper commands in a namespace.
## => Extensible with user commands => Actually, the commands complex types
## -- would be such user commands.

proc ::stackato::jmap::Quote {string} {
    set r {}
    foreach c [split $string {}] {
	scan $c %c cu
	if {$cu > 127} {
	    set c \\u[format %04x $cu]
	}
	append r $c
    }
    return $r
}

proc ::stackato::jmap::map {type data} {
    lassign $type type detail
    switch -exact -- $type {
	{} - string {
	    return [Quote [json::write string $data]]
	}
	ref {
	    # detail = type name.
	    # data is dict
	    set id [dict get $data metadata guid]
	    return [Quote [json::write string "--> $detail $id"]]
	}
	array - list {
	    set tmp {}
	    # detail = type of array elements
	    foreach x $data {
		lappend tmp [map $detail $x]
	    }
	    return [json::write array {*}$tmp]
	}
	dict - object {
	    #puts map/==============================
	    #puts map/type
	    #puts |$type|
	    #puts map/data
	    #puts |$data|
	    #puts map/==============================

	    # detail = dict mapping keys to the types of their values.
	    #          un-listed keys default to type of key '*', if
	    #          present, and string otherwise.
	    #checker -scope local exclude badOption
	    set defaulttype [dict get' $detail * {}]
	    set tmp {}
	    dict for {k v} [dict sort $data] {
		set vtype [dict get' $detail $k $defaulttype]
		lappend tmp $k [map $vtype $v]
	    }
	    return [json::write object {*}$tmp]
	}
	default {
	    if {[llength [info commands ::stackato::jmap::$type]]} {
		return [::stackato::jmap::$type $detail $data]
	    }

	    return -code error -errorcode {JSON MAP BAD TYPE} \
		"Bad json map type \"$type\""
	}
    }
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::jmap {
    namespace export map \
	aliases target targets clientinfo runtimes frameworks \
	services apps stats env instances service resources \
	manifest crashed instancemap appinfo sci users dbs \
	user1 fwinfo groups tgroups usageinfo drain bool limits \
	cc_config tadjunct v2uconfig v2-apps-summary v2-instances \
	v2-stats v2-uaa-user v2-stacks 1ref seen-clear
    namespace ensemble create
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::jmap 0
