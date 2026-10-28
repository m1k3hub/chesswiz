# Dynamic display operations work by id before posting their menu.
package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
namespace eval ::scidb::test::dynamicops {
    proc call {id arguments} {
        set result [::knowledge::RunAction $id $arguments]
        if {[string match error:* $result]} { error $result }
        return $result
    }
}
tcltest::test dynamic-args-theme {the operator selects an installed theme with no chooser} -setup {
    ::scidb::test::actions::ready
    ::knowledge::Ensure
    set old [::theme::currentTheme]
    set before [wm stackorder .]
} -body {
    set target [expr {$old eq "clam" ? "alt" : "clam"}]
    ::scidb::test::dynamicops::call menu.view.theme [dict create name $target]
    update
    list [expr {[::theme::currentTheme] eq $target}] [expr {[wm stackorder .] eq $before}]
} -cleanup { ::theme::setTheme $old } -result {1 1}

tcltest::test dynamic-args-language {the operator selects a language and relabels the app without a chooser} -setup {
    ::scidb::test::actions::ready
    ::knowledge::Ensure
    set old $::mc::langID
} -body {
    set german [::scidb::test::dynamicops::call menu.view.language {name Deutsch}]
    set english [::scidb::test::dynamicops::call menu.view.language {name English}]
    list $german $english
} -cleanup { ::menu::SwitchLanguage $old } -result {de en}

tcltest::test dynamic-args-fold {folding is idempotent and unfolding restores titlebars through the operator} -body {
    ::scidb::test::actions::ready
    ::knowledge::Ensure
    set twm [::menu::CurrentTWM]
    set frames [$twm collect !flat]
    ::scidb::test::dynamicops::call menu.view.layout.fold {fold 1}
    set folded [llength [$twm collect !flat]]
    set repeat [::scidb::test::dynamicops::call menu.view.layout.fold {fold 1}]
    ::scidb::test::dynamicops::call menu.view.layout.fold {fold 0}
    list [expr {[llength $frames]>0}] $folded $repeat [llength [$twm collect flat]]
} -result {1 0 0 0}

tcltest::test dynamic-args-docking {an explicit boolean controls the native docking points} -body {
    ::scidb::test::actions::ready
    set first [::scidb::test::dynamicops::call menu.view.layout.docking {show 1}]
    set last [::scidb::test::dynamicops::call menu.view.layout.docking {show 0}]
    list $first $last
} -result {1 0}

tcltest::test dynamic-args-settings {colors, icons and docking arrows accept explicit values without a dialog} -setup {
    ::scidb::test::actions::ready
    ::knowledge::Ensure
    set oldColor $::colors::Scheme
    set oldIcons $::toolbar::Options(icons:size)
    set oldArrows $::twm::Options(cross:size)
    set before [wm stackorder .]
} -body {
    ::scidb::test::dynamicops::call menu.view.colors {name lite}
    ::scidb::test::dynamicops::call menu.view.icon_size {name large}
    ::scidb::test::dynamicops::call menu.view.layout.arrow_size {pixels 32}
    update
    list $::colors::Scheme $::toolbar::Options(icons:size) $::twm::Options(cross:size) [expr {[wm stackorder .] eq $before}]
} -cleanup {
    set ::colors::Scheme $oldColor
    set ::toolbar::Options(icons:size) $oldIcons
    set ::twm::Options(cross:size) $oldArrows
} -result {lite large 32 1}

tcltest::test dynamic-args-load {the operator restores a named native layout without a chooser} -setup {
    ::scidb::test::actions::ready
    ::knowledge::Ensure
    set twm [::menu::CurrentTWM]
    set name "Generated dynamic [pid]"
    set oldName [::application::twm::currentLayoutName $twm]
    ::application::twm::WriteLayout $twm board $name normal
    set path [::application::twm::makeFilename board normal $name]
    set ::application::twm::Options(board:layout:name) {}
    set before [wm stackorder .]
} -body {
    ::scidb::test::dynamicops::call menu.view.layout.load [dict create name $name]
    update
    list [expr {[::application::twm::currentLayoutName $twm] eq $name}] [expr {[wm stackorder .] eq $before}]
} -cleanup {
    set ::application::twm::Options(board:layout:name) $oldName
    file delete -force $path
} -result {1 1}

tcltest::test dynamic-args-pane {the operator toggles the selected layout pane without opening a dialog} -setup {
    ::scidb::test::actions::ready
    set twm [::menu::CurrentTWM]
    set old [$twm isdocked tree]
    set before [wm stackorder .]
} -body {
    ::scidb::test::dynamicops::call menu.view.layout.pane {uid tree}
    set toggled [$twm isdocked tree]
    ::scidb::test::dynamicops::call menu.view.layout.pane {uid tree}
    update
    list [expr {$toggled != $old}] [expr {[$twm isdocked tree] == $old}] [expr {[wm stackorder .] eq $before}]
} -result {1 1 1}

tcltest::test dynamic-args-invalid {invalid values fail without opening input dialogs} -body {
    set bad {}
    foreach {id arguments} {
        menu.view.theme {name not-an-installed-theme}
        menu.view.language {name not-a-language}
        menu.view.layout.pane {uid not-a-pane}
        menu.view.layout.load {name not-a-layout}
        menu.view.layout.fold {fold not-a-boolean}
        menu.view.layout.docking {show not-a-boolean}
    } {
        if {![string match error:* [::knowledge::RunAction $id $arguments]]} { lappend bad $id }
    }
    set bad
} -result {}
tcltest::cleanupTests
