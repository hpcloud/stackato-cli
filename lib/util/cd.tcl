# # ## ### ##### ######## ############# #####################
## Copyright (c) 2011-2015 ActiveState Software Inc
## (c) Copyright 2015 Hewlett Packard Enterprise Development LP

package provide cd 0

namespace eval ::cd {}

proc ::cd::indir {path script} {
    set here [pwd]
    set code [catch {
	cd $path
	uplevel 1 $script
    } result]

    if {$code} {
	# return to correct working directory, then ...
	cd $here
	# ... rethrow
	return -code $code -errorcode $::errorCode \
	    -errorinfo $::errorInfo $result
    }

    cd $here
    return $result
}

namespace eval ::cd {
    namespace export indir
    #namespace ensemble create
}
