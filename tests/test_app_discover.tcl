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

tcltest::test discover-menu-entry {the main menu offers Discover Databases} -body {
    catch { destroy .testmenu }
    menu .testmenu
    ::menu::build .testmenu
    set found 0
    set n [.testmenu index end]
    for {set i 0} {$i <= $n} {incr i} {
        if {[.testmenu type $i] eq "cascade" && [string match "*Extras*" [.testmenu entrycget $i -label]]} {
            set em [.testmenu entrycget $i -menu]
            set en [$em index end]
            for {set k 0} {$k <= $en} {incr k} {
                if {[catch { set label [$em entrycget $k -label] }]} { continue }
                if {[string match "*Discover*" $label]} { set found 1 }
            }
        }
    }
    destroy .testmenu
    set found
} -result 1

tcltest::cleanupTests
