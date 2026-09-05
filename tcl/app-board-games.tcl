# ======================================================================
# Full-database games list pane for the Board tab.
# ======================================================================
# UX modeled on Scid vs PC's game list window (tcl/windows/gamelist.tcl
# in the scidvspc sources): a sortable game grid that is reachable from
# the board without switching to the Database tab.  Feeds from the same
# lazy-loading grid (::gamestable) as the Database tab's games browser;
# the view callback returns 0 (the base's main view = all games).
#
# Selecting a row loads the game on the board (gamestable's default
# ::game::new dispatch; no -selectcmd override).
# ======================================================================

namespace eval application::boardgames {
variable Columns {
	number white whiteElo black blackElo event result date round length eco deleted hasMedia
}
variable current {}

proc build {parent {width 0} {height 0}} {
	variable Tables
	variable Columns

	set id [::application::twm::getId $parent]
	set table $parent.table
	namespace eval [namespace current]::$table {}
	variable ${table}::Priv

	set Priv(base) {}
	set Priv(variant) {}

	::gamestable::build $table [namespace code [list View]] $Columns \
		-id db:board:games:$id \
		-takefocus 0 \
		-mode list \
		;

	::scidb::db::subscribe gameList \
		[list [namespace current]::TableUpdate $table] \
		[list [namespace current]::Close $table] \
		;
	::scidb::db::subscribe databaseSwitch \
		[list [namespace current]::DatabaseSwitched] \
		;

	return $table
}


# View callback for ::gamestable: 0 selects the base's main view (all
# games; no filter).
proc View {} {
	return 0
}


# databaseSwitch: rebind the grid to the newly active base.
proc DatabaseSwitched {base variant} {
	TableUpdate "*" "*" $base $variant
}


# gameList event: refresh the visible rows after an insert/delete/change.
proc TableUpdate {table id base variant {view -1} {index -1}} {
	if {[::scidb::db::get name] ne $base} { return }

	set n [::scidb::db::count games $base $variant]
	::gamestable::update $table $base $variant $n
}


proc Close {table base variant} {
	::gamestable::forget $table $base $variant
}

} ;# namespace application::boardgames

# vi:set ts=3 sw=3:
