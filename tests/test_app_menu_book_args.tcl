package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
namespace eval ::scidb::test::bookargs {
    proc call {args} {
        set reply [::knowledge::RunAction menu.tools.book $args]
        if {[string match error:* $reply]} {error $reply}
        return $reply
    }
    proc weight {fen move} {
        foreach entry [::scidb::book::probe $::book::Priv(handle) $fen] {
            if {[dict get $entry san] eq $move} {return [dict get $entry weight]}
        }
        return -1
    }
}
tcltest::test book-args-edit-persist {native book edits, weights and deletion persist on disk without an editor} -setup {
    ::scidb::test::actions::ready
    set path [file join [file dirname [info script]] tmp-app generated-book-[pid].bin]
    ::application::assistant::runTool open_database [list path [::scidb::test::actions::fixture]]
    ::application::assistant::runTool open_game {number 1}
    ::scidb::game::go start
    set fen [::scidb::pos::fen]
} -body {
    ::scidb::test::bookargs::call operation new filename $path
    ::scidb::test::bookargs::call operation add move e4 weight 5
    set added [::scidb::test::bookargs::weight $fen e4]
    ::scidb::test::bookargs::call operation reweight move e4 weight 9
    ::scidb::test::bookargs::call operation save
    ::scidb::test::bookargs::call operation close
    ::scidb::test::bookargs::call operation open filename $path
    set persisted [::scidb::test::bookargs::weight $fen e4]
    ::scidb::test::bookargs::call operation remove move e4
    set removed [::scidb::test::bookargs::weight $fen e4]
    ::scidb::test::bookargs::call operation save
    ::scidb::test::bookargs::call operation close
    set bytes [file size $path]
    list $added $persisted $removed $bytes $::book::Priv(dialog)
} -cleanup {
    ::book::Close
    file delete $path
    ::scidb::test::actions::cleanup
} -result {5 9 -1 0 {}}

tcltest::test book-args-create {database aggregation and add-last execute natively} -setup {
    ::scidb::test::actions::ready
    set path [file join [file dirname [info script]] tmp-app generated-book-[pid].bin]
    ::application::assistant::runTool open_database [list path [::scidb::test::actions::fixture]]
    ::application::assistant::runTool open_game {number 1}
    ::scidb::game::go start
    set fen [::scidb::pos::fen]
} -body {
    ::scidb::test::bookargs::call operation create filename $path plies 2
    set created [::scidb::test::bookargs::weight $fen e4]
    ::scidb::game::position forward
    ::scidb::test::bookargs::call operation add_last weight 7
    set last [::scidb::test::bookargs::weight $fen e4]
    set collision [::action::run menu.tools.book [list operation new filename $path]]
    list $created $last [string match {error:*already exists*} $collision] $::book::Priv(dialog)
} -cleanup {
    ::book::Close
    file delete $path
    ::scidb::test::actions::cleanup
} -result {1 7 1 {}}
tcltest::cleanupTests
