# ======================================================================
# Scidb App Test — the players prep report's selected-game lookup
# ======================================================================
# Found by driving the report: SelectedPrepGameNumber gave the inner table
# path to ::scrolledtable::index, which wants the scrolled table's own path,
# so 'Open selected game', 'Prep selected opponent' and 'Dossier' all raised
# "parent namespace doesn't exist" before doing anything.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::prep {
	variable Asked {}
}

proc ::scidb::test::prep::index {path} {
	set ::scidb::test::prep::Asked $path
	return -1
}

tcltest::test prepreport-selected-game-path {the selected-game lookup asks the scrolled table, not its inner table} -setup {
	set d ::application::database::player::PrepReportData
	set dlg .playerprep_test
	set ${d}($dlg,scrolledTable) $dlg.games.table
	set ${d}($dlg,table) $dlg.games.table.top.table
	set ${d}($dlg,view) 0
	rename ::scrolledtable::index ::scidb::test::prep::realIndex
	rename ::scidb::test::prep::index ::scrolledtable::index
	set ::scidb::test::prep::Asked {}
} -body {
	set n [::application::database::player::SelectedPrepGameNumber $dlg 0]
	list $n $::scidb::test::prep::Asked
} -cleanup {
	rename ::scrolledtable::index ::scidb::test::prep::index
	rename ::scidb::test::prep::realIndex ::scrolledtable::index
	unset -nocomplain ${d}($dlg,scrolledTable) ${d}($dlg,table) ${d}($dlg,view)
} -result {-1 .playerprep_test.games.table}

::tcltest::cleanupTests
return
