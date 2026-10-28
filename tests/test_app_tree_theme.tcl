# Tree emphasis columns use a solid background through native theme changes.
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready
::application::switchTab board
update

tcltest::test tree-theme-column-background {theme repaint applies emphasis to both native tree columns without an argument error} -setup {
    set tb $::application::tree::Vars(table)
    set saved {}
    foreach col {number move} {
        lappend saved $col [$tb.t column cget $col -itembackground]
        $tb.t column configure $col -itembackground #ff00ff
    }
} -body {
    ::application::tree::ThemeChanged .application
    set tb $::application::tree::Vars(table)
    set expected [::colors::lookup $::application::tree::Options(-emphasize)]
    set actual {}
    foreach col {number move} {
        lappend actual [expr {[$tb.t column cget $col -itembackground] eq $expected}]
    }
    set actual
} -cleanup {
    foreach {col background} $saved {
        $tb.t column configure $col -itembackground $background
    }
} -result {1 1}

tcltest::cleanupTests
