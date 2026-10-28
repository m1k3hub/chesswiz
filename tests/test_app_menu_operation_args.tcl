# Real native operations through menu ids: supplied input bypasses choosers.
package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
namespace eval ::scidb::test::menuops {
    variable dir [file join [file dirname [info script]] tmp-app menuops-[pid]]
    proc call {id args} {
        set result [::action::run $id $args]
        if {[string match error:* $result]} { error $result }
        return $result
    }
}
tcltest::test menu-operation-native-files {create, import, search and export act on native data without a chooser} -setup {
    ::scidb::test::actions::ready
    ::knowledge::Ensure
    file mkdir $::scidb::test::menuops::dir
    set base [file join $::scidb::test::menuops::dir new.sci]
    set pgn [::scidb::test::actions::fixture]
    set out [file join $::scidb::test::menuops::dir exported.pgn]
    set html [file join $::scidb::test::menuops::dir exported.html]
} -body {
    ::scidb::test::menuops::call menu.file.new.normal filename $base
    set created [expr {[::scidb::db::get name] eq [file normalize $base]}]
    ::scidb::test::menuops::call menu.file.import.pgn filename $pgn
    set imported [::scidb::db::count games $base Normal]
    ::scidb::test::menuops::call menu.db.search.plain player {Generated White}
    set count [::scidb::view::count games $base Normal 0]
    ::scidb::test::menuops::call menu.file.export.pgn filename $out
    set ch [open $out];set text [read $ch];close $ch
    ::scidb::test::menuops::call menu.file.export.html filename $html
    set ch [open $html];set page [read $ch];close $ch
    set duplicate [::action::run menu.file.export.pgn [list filename $out]]
    list $created $imported $count [string match {*Generated White*} $text] \
        [string match {*Generated White*} $page] [string match {error:*file exists*} $duplicate]
} -cleanup {
    catch {::application::database::closeBase .application $base}
    catch {file delete -force $::scidb::test::menuops::dir}
} -result {1 1 1 1 1 1}


tcltest::test menu-operation-canonical-and-context {canonical export accepts arguments and context export respects its selected database} -setup {
    ::scidb::test::actions::ready
    ::knowledge::Ensure
    file mkdir $::scidb::test::menuops::dir
    set base [file join $::scidb::test::menuops::dir selected.sci]
    set empty [file join $::scidb::test::menuops::dir other.sci]
    ::scidb::test::menuops::call menu.file.new.normal filename $base
    ::scidb::test::menuops::call menu.file.import.pgn filename [::scidb::test::actions::fixture]
} -body {
    set out [file join $::scidb::test::menuops::dir canonical.pgn]
    set reply [::application::assistant::runTool export_database [list filename $out format pgn]]
    if {[string match error:* $reply]} {error $reply}
    ::scidb::test::menuops::call menu.file.new.normal filename $empty
    set selected [file join $::scidb::test::menuops::dir selected.pgn]
    ::scidb::test::menuops::call c4.export.pgn filename $selected object [dict create base $base]
    set ch [open $selected];set text [read $ch];close $ch
    list [expr {[file size $out] > 0}] [string match {*Generated White*} $text] \
        [expr {[::scidb::db::get name] eq [file normalize $empty]}]
} -cleanup {
    catch {::application::database::closeBase .application $empty}
    catch {::application::database::closeBase .application $base}
    catch {file delete -force $::scidb::test::menuops::dir}
} -result {1 1 1}

tcltest::test menu-operation-schemas {menu and context aliases expose typed filename arguments} -body {
    set bad {}
    foreach id {menu.file.new.normal menu.file.new.three menu.file.new.crazy menu.file.new.variants menu.file.open menu.file.import.pgn menu.file.import.db menu.file.export.pgn menu.file.export.html c4.new.scid c4.new.pgn c4.open_database c4.import.pgn c4.export.pgn} {
        set schema [::action::schemaOf $id]
        if {![dict exists $schema properties filename type] || [dict get $schema properties filename type] ne {string}} {lappend bad $id}
        if {[lindex [::action::validateArgs $id {filename /tmp/example.pgn}] 0] ne {ok}} {lappend bad $id}
    }
    set bad
} -result {}
tcltest::cleanupTests
