# R8: exercise the real Post path, including the minimal public menu declaration.
package require tcltest 2.5
namespace eval ::scidb::test::post {}
proc ::scidb::test::post::cleanup {} {
    catch {grab release .postprobe}
    catch {.postprobe unpost}
    catch {destroy .postprobe}
    update
}

tcltest::test context-post-no-object {right-click without a selected object posts nothing for C1-C12} -body {
    set bad {}
    foreach cid {C1 C2 C3 C4 C5 C6 C7 C8 C9 C10 C11 C12} {
        menu .postprobe -tearoff 0
        set posted [::context::Post $cid .postprobe {} 100 100]
        update
        puts [list POST_NO_OBJECT $cid returned $posted mapped [winfo ismapped .postprobe]]
        if {$posted || [winfo ismapped .postprobe]} {lappend bad $cid}
        ::scidb::test::post::cleanup
    }
    set bad
} -result {}

# Use Define's public input with existing actions. No replacement of Post,
# Build, predicates, registry records or Tk popup; this tests the boundary
# where filtering leaves only Ask, independent of current feature inventory.
tcltest::test context-post-lone-ask {Ask alone and Ask plus a disabled action never post} -body {
    set out {}
    foreach rows {{ask} {ask c9.stay_on_top} {ask c1.copy_fen}} {
        ::context::Define PostProbe $rows
        menu .postprobe -tearoff 0
        set posted [::context::Post PostProbe .postprobe {fen generated} 100 100]
        update
        lappend out [list $posted [winfo ismapped .postprobe]]
        puts [list POST_MINIMAL rows $rows returned $posted mapped [winfo ismapped .postprobe]]
        ::scidb::test::post::cleanup
    }
    set out
} -cleanup {
    dict unset ::context::Menus PostProbe
    ::scidb::test::post::cleanup
} -result {{0 0} {0 0} {1 1}}
tcltest::test context-pane-cascade-dispatch {Ask opens the notation choices and excludes its empty cascades} -setup {
    source [file join [file dirname [info script]] app_actions_support.tcl]
    ::scidb::test::actions::ready
    set twm [::application::twm board]
    ::application::openPane editor
    update
    focus -force [$twm leaf editor]
    update
} -body {
    set ids [lmap row [::action::labels asklist {}] {lindex $row 0}]
    set result [::action::run c9.not.display]
    update
    set m .contextChoices_paneCascade
    list [expr {"c9.not.display" in $ids}] \
        [expr {"c9.not.language" ni $ids && "c9.layout" ni $ids}] \
        $result [winfo ismapped $m] [expr {[$m index end] ne "none"}]
} -cleanup {
    catch {grab release .contextChoices_paneCascade}
    catch {destroy .contextChoices_paneCascade}
} -result {1 1 {opened choices} 1 1}
tcltest::test context-sort-state-shared {an unsortable current table hides both native and alias sort actions from Ask} -setup {
    ::menu::gameNew .application
    set manager $::application::database::Vars(games).twm
    set table [set ::application::database::games::${manager}::Priv(table)]
    set sortableVariable ::gamestable::${table}::Vars(sortable)
    set savedSortable [set $sortableVariable]
    set $sortableVariable 0
} -body {
    set ids [lmap row [::action::labels asklist {}] {lindex $row 0}]
    set bad {}
    foreach id {c3.sort_column c3.sort_asc c3.sort_desc c3.sort.column c3.sort.asc c3.sort.desc} {
        if {$id in $ids || [dict get [::menu::state $id] visible]} {lappend bad $id}
    }
    set bad
} -cleanup {set $sortableVariable $savedSortable} -result {}

tcltest::test context-column-choice-id {dynamic column checkbuttons resolve and toggle through their action id} -setup {
    ::table::table .posttable
    ::table::addcol .posttable date -text Date -removable 1
    set object {table .posttable column date}
} -body {
    set result {}
    foreach visible {0 1} {
        menu .postcolumns -tearoff 0
        ::context::CascadePrefix c10.show_column .postcolumns $object
        set command [.postcolumns entrycget 0 -command]
        lappend result [expr {[lrange $command 0 1] eq {::action::run c10.show_column}}]
        .postcolumns invoke 0
        puts [list COLUMN_CHOICE command $command visible [.posttable.t column cget date -visible] expected $visible]
        lappend result [expr {[.posttable.t column cget date -visible] == $visible}]
        destroy .postcolumns
    }
    set result
} -cleanup {update; destroy .posttable; catch {destroy .postcolumns}} -result {1 1 1 1}
tcltest::test context-media-float {media can float and dock through its action while grouped with tree} -setup {
    ::scidb::test::actions::ready
    ::application::openPane media
    update
    set twm [::application::twm board]
} -body {
    set states {}
    foreach expected {1 0 1 0} {
        set object [dict create paneUid media twm $twm frame [$twm leaf media]]
        set reply [::action::run c9.float [dict create object $object]]
        update
        puts [list MEDIA_FLOAT expected $expected floating [::menu::PaneFloating media $twm] reply $reply]
        lappend states [expr {![string match error:* $reply] && [::menu::PaneFloating media $twm] == $expected}]
    }
    set states
} -cleanup {
    if {[::menu::PaneFloating media $twm]} {::application::assistant::DoPane dock media}
    ::menu::TogglePaneId media
    update
} -result {1 1 1 1}
::tcltest::cleanupTests
