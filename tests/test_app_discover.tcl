package require tcltest 2.5

# App-backed regressions for the database-discovery dialog.  The scanner
# logic itself is covered headlessly by tests/test_database_discover.tcl.

tcltest::test discover-runtime {the discovery module is loaded with default roots} -body {
    list \
        [namespace exists ::application::database::discover] \
        [expr {[llength [::application::database::discover::defaultRoots]] > 0}]
} -result {1 1}

tcltest::testConstraint haveCbm168 [file exists /media/michael-g-thomas/sas_mirror/fixt/cbm168/168Strategy.cbh]

tcltest::test discover-classify-real {a real ChessBase database is classified with its game count} -constraints haveCbm168 -body {
    set entry [::application::database::discover::classify \
        /media/michael-g-thomas/sas_mirror/fixt/cbm168/168Strategy.cbh 1]
    list [lindex $entry 0] [lindex $entry 1] [expr {[lindex $entry 4] > 0}]
} -result {cbh {ChessBase database} 1}

tcltest::test discover-dialog {the dialog opens and closes cleanly} -body {
    ::application::database::discover::open .application
    set dlg .application.__discover__
    update idletasks
    set opened [winfo exists $dlg]
    set rows [llength [$dlg.top.roots.list get 0 end]]
    ::application::database::discover::Close
    update idletasks
    list $opened [expr {$rows > 0}] [winfo exists $dlg]
} -result {1 1 0}

# Regression: dialogButtons defaulted -default to the whole first entry
# ("ok {} {}") instead of its type, so focusing Cancel ran
# ".application.__discover__.ok {} {} configure -default normal".
tcltest::test discover-cancel-focus {focusing Cancel moves the default ring off OK} -body {
    ::application::database::discover::open .application
    set dlg .application.__discover__
    update idletasks
    foreach event {FocusIn FocusOut} {
        eval [string map [list %W $dlg.cancel] [bind $dlg.cancel <$event>]]
    }
    set state [list [$dlg.ok cget -default] [$dlg.cancel cget -default]]
    ::application::database::discover::Close
    update idletasks
    set state
} -result {active normal}

tcltest::test discover-menu-entry {the main drop-down offers Discover Databases} -body {
    # Decision 003/PROPOSAL section 6: Discover Databases has one home,
    # Database in the drop-down, addressed by its action id.
    catch { destroy .testmenu }
    menu .testmenu
    ::menu::BuildDropdown .testmenu
    set rec [::action::get menu.db.discover]
    set result [list \
        [expr {[dict get $rec label] eq [::menu::MC DiscoverDatabases]}] \
        [expr {[dict get $rec dropdown] ne ""}] \
        [expr {[lindex [split [dict get $rec dropdown] .] 0] eq "04"}]]
    destroy .testmenu
    set result
} -result {1 1 1}

tcltest::cleanupTests
