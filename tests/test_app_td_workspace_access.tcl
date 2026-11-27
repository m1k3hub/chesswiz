# The Tournament Director workspace offers TRF import, the audit log,
# FIDE lookup and prizes, and its labels come from the translation tables.
package require tcltest 2.5

tcltest::test td-workspace-new-controls {import, audit, FIDE lookup and prizes have buttons} -body {
	set dlg [::td::ui::Open {}]
	set nb $::td::ui::Notebook
	set out {}
	foreach w [list $nb.event.buttons.import $nb.event.buttons.audit $nb.players.fide.find $nb.standings.btns.prize] {
		lappend out [winfo exists $w]
	}
	::td::ui::Close
	set out
} -result {1 1 1 1}

tcltest::test td-workspace-labels-translated {labels follow ::td::ui::mc} -body {
	set saved $::td::ui::mc::Tab_players
	set ::td::ui::mc::Tab_players "Spieler"
	set dlg [::td::ui::Open {}]
	set nb $::td::ui::Notebook
	set text [$nb tab $nb.players -text]
	::td::ui::Close
	set ::td::ui::mc::Tab_players $saved
	set text
} -result Spieler

tcltest::test td-safe-returns-result {Safe returns the command's result and reports errors} -body {
	list [::td::ui::Safe {expr {1 + 1}}] [::td::ui::Safe {error boom}]
} -cleanup {
	foreach w [winfo children .application] { if {[string match *dialog* [string tolower [winfo class $w]]]} { catch { destroy $w } } }
} -result {2 {}}

tcltest::cleanupTests
