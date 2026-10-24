# Source in the running app: inspect every registered handler plus menu::Do.
# Does not invoke actions or perform destructive operations.
namespace eval ::handlercheck {
    variable scanner [file join [file dirname [info script]] menu_handler_check.py]
}
proc ::handlercheck::audit {} {
    variable scanner
    set failures {}
    set queue {::menu::Do ::context::Command}
    dict for {id rec} $::action::Registry {
        set handler [dict get $rec handler]
        if {![llength $handler]} { lappend failures "$id: empty handler"; continue }
        set cmd [lindex $handler 0]
        set argc [llength $handler]
        # action::run appends one validated argument dictionary.
        lappend failures {*}[check $id $cmd $argc]
        if {[llength [info procs $cmd]]} { lappend queue $cmd }
    }
    set seen {}
    foreach cmd [lsort -unique $queue] {
        if {![llength [info procs $cmd]]} continue
        dict set seen $cmd 1
        set calls [exec python3 $scanner << [info body $cmd]]
        foreach call $calls {
            lassign $call target argc expanded
            if {!$expanded} { lappend failures {*}[check $cmd $target $argc] }
        }
    }
    puts "Handler audit: [dict size $::action::Registry] actions, [dict size $seen] handler bodies"
    return [lsort -unique $failures]
}
proc ::handlercheck::check {owner cmd argc} {
    # Optional/platform-only commands are guarded at their dispatch sites.
    if {$cmd eq "::menu::AssignFileTypes" && ![llength [info commands $cmd]] && ![::menu::ModulePresent filetypes]} { return {} }
    if {$cmd eq "::menu::MacAbout" && [tk windowingsystem] ne "aqua"} { return {} }
    if {![llength [info commands $cmd]]} { return [list "$owner: missing $cmd ($argc arguments)"] }
    if {![llength [info procs $cmd]]} { return {} }
    set min 0
    set max 0
    foreach arg [info args $cmd] {
        if {$arg eq "args" && $arg eq [lindex [info args $cmd] end]} { set max 100000; break }
        incr max
        if {![info default $cmd $arg default]} { incr min }
    }
    if {$argc < $min || $argc > $max} {
        return [list "$owner: $cmd takes $min..$max arguments, called with $argc"]
    }
    return {}
}
