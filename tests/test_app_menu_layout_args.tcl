# Real persistence through the same action ids as the layout menu.
package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
namespace eval ::scidb::test::layoutargs {
    proc call {id args} {
        set reply [::knowledge::RunAction $id $args]
        if {[string match error:* $reply]} {error $reply}
        return $reply
    }
}

tcltest::test layout-args-persistence {save, list, rename and delete operate on real layout files without dialogs} -setup {
    ::scidb::test::actions::ready
    set twm [::menu::CurrentTWM]
    set id $::application::Vars($twm:id)
    set original [::application::twm::currentLayoutName $twm]
    set name "Generated layout [pid]"
    set renamed "$name renamed"
    set file [::application::twm::makeFilename $id normal $name]
    set target [::application::twm::makeFilename $id normal $renamed]
    set hook $::action::ConfirmHook
    set ::action::ConfirmHook ::scidb::test::actions::yes
} -body {
    ::scidb::test::layoutargs::call menu.view.layout.save_as name $name
    set ch [open $file];set contents [read $ch];close $ch
    set saved [expr {[info complete $contents] && [string first ::application::twm::setup $contents] >= 0}]
    set listed [expr {$name in [::scidb::test::layoutargs::call menu.view.layout.manage operation list]}]
    set duplicate [::action::run menu.view.layout.save [list name $name]]
    ::scidb::test::layoutargs::call menu.view.layout.save name $name overwrite true
    ::scidb::test::layoutargs::call menu.view.layout.manage operation rename name $name new_name $renamed
    set moved [expr {![file exists $file] && [file exists $target] && [::application::twm::currentLayoutName $twm] eq $renamed}]
    ::scidb::test::layoutargs::call menu.view.layout.manage operation delete name $renamed
    list $saved $listed [string match {error:*already exists*} $duplicate] $moved \
        [expr {![file exists $target] && [::application::twm::currentLayoutName $twm] eq ""}] \
        [winfo exists $twm.save] [winfo exists $twm.layout]
} -cleanup {
    foreach n [list $name $renamed] {
        foreach v $::application::twm::layoutVariants {
            catch {file delete [::application::twm::makeFilename $id $v $n]}
        }
    }
    set ::application::twm::Options($id:layout:name) $original
    set ::action::ConfirmHook $hook
} -result {1 1 1 1 1 0 0}

tcltest::test layout-args-invalid {invalid names and missing layouts fail before writing or opening a dialog} -setup {
    ::scidb::test::actions::ready
} -body {
    set results {}
    foreach name {../escape {a/b} {a\b} {a:b} {trailing.} { }} {
        lappend results [string match {error:*invalid layout name*} [::action::run menu.view.layout.save [list name $name]]]
    }
    lappend results [string match {error:*does not exist*} [::action::run menu.view.layout.manage {operation delete name {Generated missing layout}}]]
    set results
} -result {1 1 1 1 1 1 1}

tcltest::test layout-args-mutation-declined {a declined registry confirmation leaves the saved file intact} -setup {
    ::scidb::test::actions::ready
    set twm [::menu::CurrentTWM]
    set id $::application::Vars($twm:id)
    set original [::application::twm::currentLayoutName $twm]
    set name "Generated guarded layout [pid]"
    set file [::application::twm::makeFilename $id normal $name]
    set hook $::action::ConfirmHook
    proc ::scidb::test::layoutargs::no {args} {return 0}
    set ::action::ConfirmHook ::scidb::test::layoutargs::no
} -body {
    ::scidb::test::layoutargs::call menu.view.layout.save name $name
    set reply [::action::run menu.view.layout.manage [list operation delete name $name]]
    list $reply [file exists $file] [::application::twm::currentLayoutName $twm]
} -cleanup {
    file delete $file
    set ::application::twm::Options($id:layout:name) $original
    set ::action::ConfirmHook $hook
    rename ::scidb::test::layoutargs::no {}
} -result [list declined 1 "Generated guarded layout [pid]"]

tcltest::test layout-args-load-replace {load and replace restore the actual saved pane arrangement} -setup {
    ::scidb::test::actions::ready
    set twm [::menu::CurrentTWM]
    set id $::application::Vars($twm:id)
    set original [::application::twm::currentLayoutName $twm]
    set name "Generated restorable layout [pid]"
    set file [::application::twm::makeFilename $id normal $name]
} -body {
    ::scidb::test::layoutargs::call menu.view.layout.save name $name
    set ch [open $file]; set layout [lindex [gets $ch] 3]; close $ch
    ::scidb::test::layoutargs::call menu.view.layout.fold fold 1
    set changed [expr {![::application::twm::actualLayoutIsEqTo $twm $layout true]}]
    ::scidb::test::layoutargs::call menu.view.layout.manage operation load name $name
    update
    set loaded [expr {[::application::twm::actualLayoutIsEqTo $twm $layout true] ? 1 : 0}]
    ::scidb::test::layoutargs::call menu.view.layout.fold fold 1
    ::scidb::test::layoutargs::call menu.view.layout.manage operation replace name $name
    update
    list $changed $loaded [expr {[::application::twm::actualLayoutIsEqTo $twm $layout true] ? 1 : 0}] \
        [winfo exists $twm.layout] [winfo exists $twm.save]
} -cleanup {
    file delete $file
    set ::application::twm::Options($id:layout:name) $original
} -result {1 1 1 0 0}

tcltest::test layout-args-links {the manager links and unlinks non-board layouts by name} -setup {
    ::scidb::test::actions::ready
    set board [::menu::CurrentTWM]
    set boardOriginal [::application::twm::currentLayoutName $board]
    set name "Generated linked layout [pid]"
    ::scidb::test::layoutargs::call menu.view.layout.save name $name
    ::application::switchTab database
    update
    set twm [::menu::CurrentTWM]
    set id $::application::Vars($twm:id)
    set original [::application::twm::currentLayoutName $twm]
    ::scidb::test::layoutargs::call menu.view.layout.save name $name
} -body {
    ::scidb::test::layoutargs::call menu.view.layout.manage operation link name $name link $name
    set linked [::application::twm::getLink $id $name]
    ::scidb::test::layoutargs::call menu.view.layout.manage operation link name $name link {}
    list [expr {$id ne "board"}] [expr {$linked eq $name}] [::application::twm::getLink $id $name]
} -cleanup {
    foreach layoutId [list board $id] {
        foreach v $::application::twm::layoutVariants {
            catch {file delete [::application::twm::makeFilename $layoutId $v $name]}
        }
    }
    ::application::twm::setLink $id $name {}
    set ::application::twm::Options(board:layout:name) $boardOriginal
    set ::application::twm::Options($id:layout:name) $original
    ::application::switchTab board
} -result {1 1 {}}
tcltest::cleanupTests
