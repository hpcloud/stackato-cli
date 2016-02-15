# -*- tcl -*- Copyright (c) 2012 Andreas Kupries
# # ## ### ##### ######## ############# #####################
## Support for the standard gui recipe.

# # ## ### ##### ######## ############# #####################
## Export (internals - recipe definitions, other utilities)

namespace eval ::kettle::gui {
    namespace export {[a-z]*}
    namespace ensemble create
}

# # ## ### ##### ######## ############# #####################
## State

namespace eval ::kettle::gui {
    variable actions     {}
    variable options     {}

    namespace import ::kettle::io
    namespace import ::kettle::ovalidate
    namespace import ::kettle::option
    namespace import ::kettle::recipe
    namespace import ::kettle::status
}

# # ## ### ##### ######## ############# #####################

proc ::kettle::gui::make {} {
    package require Tk

    ttk::notebook .n
    ttk::frame  .options
    ttk::frame  .actions
    ttk::button .exit -command ::_exit -text Exit

    .n add .options -text Configuration -underline 0
    .n add .actions -text Action        -underline 0

    pack .n    -side top   -expand 1 -fill both
    pack .exit -side right -expand 0 -fill both

    Options     .options
    Actions     .actions

    .n select 0 ; # Configuration
    #.n select 1 ; # Actions

    # Disable uncontrolled exit. This may come out of deeper layers,
    # like, for example, critcl compilation.

    rename ::exit   ::_exit
    proc   ::exit {{status 0}} {
	apply {{} {
	    io ok { io puts DONE }
	} ::kettle}
	return
    }

    wm protocol . WM_DELETE_WINDOW ::_exit

    # And start to interact with the user.
    vwait forever
    return
}

proc ::kettle::gui::Options {win} {
    set top $win ; if {$top eq {}} { set top . }

    # TODO: Attach the 'ignore-by-gui-flag' to the option itself in
    # some way.
    set ignore {--state --config}

    foreach o [lsort -dict [option names]] {
	if {$o in $ignore} continue
	AddOption $win $o
    }
    return
}

proc ::kettle::gui::AddOption {win o} {
    variable options
    set row [llength $options]

    set top $win ; if {$top eq {}} { set top . }

    set type [option type $o]

    label                  ${win}.l$row -text $o -anchor w
    ovalidate {*}$type gui ${win}.e$row $o

    grid ${win}.l$row  -row $row -column 0 -sticky new
    grid ${win}.e$row  -row $row -column 1 -sticky new

    grid columnconfigure $top 0 -weight 0
    grid columnconfigure $top 1 -weight 1
    grid rowconfigure    $top $row -weight 0

    lappend options ${win}.i$row
    return
}

# # ## ### ##### ######## ############# #####################

proc ::kettle::gui::Actions {win} {
    set top $win ; if {$top eq {}} { set top . }

    package require widget::scrolledwindow ; # Tklib

    # TODO: Extend recipe definitions to carry this information.
    set special {help help-recipes help-options show show-configuration show-state}
    set ignore  {gui null forever list list-recipes list-options help-dump}

    foreach r $special {
	# treat a few recipes out of order to have them at the top.
	AddActionForRecipe $win $r
    }
    foreach r [lsort -dict [recipe names]] {
	# ignore the standard recipes which are nonsensical for the
	# gui, and those which we treated out of order (see above).
	if {($r in $ignore) || ($r in $special)} continue
	AddActionForRecipe $win $r
    }

    widget::scrolledwindow ${win}.st -borderwidth 1 -relief sunken
    text                   ${win}.t

    ${win}.st setwidget ${win}.t

    set n [NumActions]

    grid ${win}.st -row 0 -column 0 -sticky swen -rowspan $n

    grid columnconfigure $top  0 -weight 1
    grid columnconfigure $top  1 -weight 0
    grid rowconfigure    $top $n -weight 1

    io setwidget ${win}.t
    return
}

# # ## ### ##### ######## ############# #####################
## Internal help.

proc ::kettle::gui::NumActions {} {
    variable actions
    llength $actions
}

proc ::kettle::gui::AddActionForRecipe {win r} {
    AddAction $win [list ::kettle::gui::Run $win $r] [Label $r] 0
}

proc ::kettle::gui::AddAction {win cmd label weight} {
    variable actions
    set row [llength $actions]

    set top $win ; if {$top eq {}} { set top . }

    # ttk::button -> no -anchor option, labels centered.
    button ${win}.i$row -command $cmd -text $label -anchor w
    grid   ${win}.i$row -row $row -column 1 -sticky new
    grid rowconfigure $top $row -weight $weight

    lappend actions ${win}.i$row
    return
}

proc ::kettle::gui::Label {recipe} {
    set result {}
    foreach e [split $recipe -] {
	lappend result [string totitle $e]
    }
    return [join $result { }]
}

proc ::kettle::gui::Run {win recipe} {
    Action disabled

    ${win}.t delete 0.1 end

    recipe run $recipe

    status clear
    Action normal
    return
}

proc ::kettle::gui::Action {e} {
    variable actions
    foreach b $actions {
	$b configure -state $e
    }
    return
}

# # ## ### ##### ######## ############# #####################
return
