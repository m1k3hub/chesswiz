# ======================================================================
# Scidb App Test Suite - Database UI Regressions
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::appdb {

variable testDir [file dirname [file normalize [info script]]]
variable tmpDir [file join $testDir tmp-app]
variable mockSerial 0
variable busyCalls {}

proc setup {} {
    variable tmpDir
    file mkdir $tmpDir
}

proc cleanup {} {
    foreach w [winfo children .] {
        if {$w ne ".application"} {
            catch { destroy $w }
        }
    }
}

proc tempPath {stem ext} {
    variable tmpDir
    return [file normalize [file join $tmpDir "${stem}_[pid]_[clock microseconds].${ext}"]]
}

proc makeDialog {name} {
    set dlg .$name
    catch { destroy $dlg }
    toplevel $dlg
    frame $dlg.table
    pack $dlg.table
    return $dlg
}

proc createDatabase {stem} {
    set base [tempPath $stem sci]
    ::application::database::newBase .application Normal $base
    update idletasks
    return $base
}

proc installMock {name arglist body} {
    variable mockSerial
    set backup ""
    if {[info commands $name] ne ""} {
        set backup ::scidb::test::appdb::mock_[incr mockSerial]
        rename $name $backup
    }
    proc $name $arglist $body
    return $backup
}

proc restoreMock {name backup} {
    catch { rename $name {} }
    if {$backup ne ""} {
        rename $backup $name
    }
}

proc withBusyRecorder {body} {
    variable busyCalls
    set busyCalls {}
    set backup [installMock ::widget::busyCursor {args} {
        lappend ::scidb::test::appdb::busyCalls $args
    }]
    set rc [catch {uplevel 1 $body} result options]
    restoreMock ::widget::busyCursor $backup
    if {$rc} {
        return -options $options $result
    }
    return $result
}

proc maintenanceLabels {menu} {
    set labels {}
    for {set i 0} {$i <= [$menu index end]} {incr i} {
        if {[$menu type $i] ne "command"} { continue }
        lappend labels [string trim [$menu entrycget $i -label]]
    }
    return $labels
}

setup

tcltest::test app-db-popup-01 {Repertoire report stays hidden for non-repertoire databases} -body {
    set base [createDatabase popup]
    set parent .application.nb.database.main.switcher.content
    ::application::database::PopupMenu $parent 0 0 $base
    set labels [maintenanceLabels ${parent}.__menu__.maintenance]
    expr {[lsearch -exact $labels "Repertoire Report..."] == -1}
} -cleanup {
    set parent .application.nb.database.main.switcher.content
    catch { destroy ${parent}.__menu__ }
    cleanup
} -result 1

tcltest::test app-db-filter-02 {Repertoire filter releases busy cursor on search error} -body {
    set base [createDatabase rep_search]
    set dlg [makeDialog test_rep_search]
    set ::application::database::RepertoireReportData($dlg,file) $base
    set ::application::database::RepertoireReportData($dlg,variant) Normal
    set ::application::database::RepertoireReportData($dlg,view) 7
    set ::application::database::RepertoireReportData($dlg,scrolledTable) $dlg.table
    set searchBackup [installMock ::scidb::view::search {args} { error "search failed" }]
    set sortBackup [installMock ::scidb::db::sort {args} { error "sort should not run" }]
    set rc [catch {
        withBusyRecorder {
            ::application::database::FilterRepertoireByEco $dlg C20
        }
    }]
    restoreMock ::scidb::db::sort $sortBackup
    restoreMock ::scidb::view::search $searchBackup
    expr {$rc == 1 && $::scidb::test::appdb::busyCalls eq {on off}}
} -cleanup {
    cleanup
} -result 1

tcltest::test app-db-filter-03 {Repertoire filter releases busy cursor on sort error} -body {
    set base [createDatabase rep_sort]
    set dlg [makeDialog test_rep_sort]
    set ::application::database::RepertoireReportData($dlg,file) $base
    set ::application::database::RepertoireReportData($dlg,variant) Normal
    set ::application::database::RepertoireReportData($dlg,view) 7
    set ::application::database::RepertoireReportData($dlg,scrolledTable) $dlg.table
    set searchBackup [installMock ::scidb::view::search {args} {}]
    set sortBackup [installMock ::scidb::db::sort {args} { error "sort failed" }]
    set columnBackup [installMock ::scrolledtable::columnNo {args} { return 0 }]
    set rc [catch {
        withBusyRecorder {
            ::application::database::FilterRepertoireByEco $dlg C20
        }
    }]
    restoreMock ::scrolledtable::columnNo $columnBackup
    restoreMock ::scidb::db::sort $sortBackup
    restoreMock ::scidb::view::search $searchBackup
    expr {$rc == 1 && $::scidb::test::appdb::busyCalls eq {on off}}
} -cleanup {
    cleanup
} -result 1

tcltest::test app-db-search-04 {Material search releases busy cursor on backend error} -body {
    set base [createDatabase material]
    set dlg [makeDialog test_material]
    set ::application::database::MaterialSearchData($dlg,mode) exact
    set ::application::database::MaterialSearchData($dlg,white) q
    set ::application::database::MaterialSearchData($dlg,black) q
    set ::application::database::MaterialSearchData($dlg,file) $base
    set ::application::database::MaterialSearchData($dlg,variant) Normal
    set ::application::database::MaterialSearchData($dlg,view) 1
    set ::application::database::MaterialSearchData($dlg,scrolledTable) $dlg.table
    set searchBackup [installMock ::scidb::view::search {args} { error "search failed" }]
    set rc [catch {
        withBusyRecorder {
            ::application::database::RunMaterialSearch $dlg
        }
    }]
    restoreMock ::scidb::view::search $searchBackup
    expr {$rc == 1 && $::scidb::test::appdb::busyCalls eq {on off}}
} -cleanup {
    cleanup
} -result 1

tcltest::test app-db-search-05 {Rating search releases busy cursor on backend error} -body {
    set base [createDatabase rating]
    set dlg [makeDialog test_rating]
    set ::application::database::RatingSearchData($dlg,mode) white
    set ::application::database::RatingSearchData($dlg,rangeA) 2400-2600
    set ::application::database::RatingSearchData($dlg,type) Elo
    set ::application::database::RatingSearchData($dlg,file) $base
    set ::application::database::RatingSearchData($dlg,variant) Normal
    set ::application::database::RatingSearchData($dlg,view) 1
    set ::application::database::RatingSearchData($dlg,scrolledTable) $dlg.table
    set searchBackup [installMock ::scidb::view::search {args} { error "search failed" }]
    set rc [catch {
        withBusyRecorder {
            ::application::database::RunRatingSearch $dlg
        }
    }]
    restoreMock ::scidb::view::search $searchBackup
    expr {$rc == 1 && $::scidb::test::appdb::busyCalls eq {on off}}
} -cleanup {
    cleanup
} -result 1

tcltest::test app-db-search-06 {Advanced search releases busy cursor on backend error} -body {
    set base [createDatabase advanced]
    set dlg [makeDialog test_advanced]
    set ::application::database::AdvancedSearchData($dlg,file) $base
    set ::application::database::AdvancedSearchData($dlg,variant) Normal
    set ::application::database::AdvancedSearchData($dlg,view) 1
    set ::application::database::AdvancedSearchData($dlg,scrolledTable) $dlg.table
    set buildBackup [installMock ::application::database::BuildAdvancedSearchQuery {dlg} {
        return [list [list eco C20] "ECO C20"]
    }]
    set searchBackup [installMock ::scidb::view::search {args} { error "search failed" }]
    set rc [catch {
        withBusyRecorder {
            ::application::database::RunAdvancedSearch $dlg
        }
    }]
    restoreMock ::scidb::view::search $searchBackup
    restoreMock ::application::database::BuildAdvancedSearchQuery $buildBackup
    expr {$rc == 1 && $::scidb::test::appdb::busyCalls eq {on off}}
} -cleanup {
    cleanup
} -result 1

cleanup
tcltest::cleanupTests

} ;# namespace ::scidb::test::appdb
