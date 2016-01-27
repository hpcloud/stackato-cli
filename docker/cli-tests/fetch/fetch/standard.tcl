# -*- tcl -*- Copyright (c) 2012 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## Standard recipes.
## - null    - no operation.
## - recipes - recipe list
## - help    - recipe help
## - gui     - standard GUI to recipes.

# # ## ### ##### ######## ############# #####################

kettle recipe define null {
    No operation. Debugging helper (use with -trace).
} {} {}

kettle recipe define forever {
    No operation, infinite loop. Debugging helper (use with -trace).
} {} {
    file mkdir [set x [path tmpfile x]]
    puts $x
    while {1} {}
}

# # ## ### ##### ######## ############# #####################

kettle recipe define list-recipes {
    List all available recipes, without details.
} {} {
    io puts [lsort -dict [recipe names]]
}

kettle recipe define help-recipes {
    Print the help.
} {} {
    recipe help {Usage: }
}

kettle recipe define help-dump {
    Print the help in Tcl format.
} {} {
    recipe help-dump
}

kettle recipe parent help-recipes help
kettle recipe parent list-recipes list

# # ## ### ##### ######## ############# #####################

kettle recipe define list-options {
    List all available options, without details.
} {} {
    io puts [lsort -dict [option names]]
}

kettle recipe define help-options {
    Print the help about options.
} {} {
    option help
}

kettle recipe parent help-options help
kettle recipe parent list-options list

# # ## ### ##### ######## ############# #####################

kettle recipe define show-configuration {
    Show the state of the option database.
} {} {
    set names [lsort -dict [option names]]
    io puts {}
    foreach name $names padded [strutil padr $names] {
	set value [option get $name]
	if {[string match *\n* $value]} {
	    set value \n[strutil reflow $value "\t    "]
	}
        io puts "\t$padded = $value"
    }
}

kettle recipe define show-state {
    Show the state
} {} {
    set names [lsort -dict [option names @*]]
    io puts {}
    foreach name $names padded [strutil padr $names] {
	set value [option get $name]
	if {[string match *\n* $value]} {
	    set value \n[strutil reflow $value "\t    "]
	}
        io puts "\t$padded = $value"
    }
}

kettle recipe parent show-configuration show
kettle recipe parent show-state         show

# # ## ### ##### ######## ############# #####################

kettle recipe define meta-status {
    Status of meta data for Tcl packages and applications.
} {} {
    meta show-status
}

# # ## ### ##### ######## ############# #####################

kettle recipe define gui {
    Graphical interface to the system.
} {} {
    gui make
}

# # ## ### ##### ######## ############# #####################
return
