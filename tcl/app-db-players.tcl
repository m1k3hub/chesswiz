# ======================================================================
# Author : $Author$
# Version: $Revision: 1519 $
# Date   : $Date: 2018-09-11 07:41:52 -0400 (Tue, 11 Sep 2018) $
# Url    : $URL$
# ======================================================================

# ======================================================================
#    _/|            __
#   // o\         /    )           ,        /    /
#   || ._)    ----\---------__----------__-/----/__-
#   //__\          \      /   '  /    /   /    /   )
#   )___(     _(____/____(___ __/____(___/____(___/_
# ======================================================================

# ======================================================================
# Copyright: (C) 2009-2018 Gregor Cramer
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

::util::source player-list

namespace eval application {
namespace eval database {
namespace eval player {
namespace eval mc {

set EditPlayer	"Edit Player"
set Score		"Score"
set ShowPrepReport "Show Prep Report..."
set PrepReportTitle "Prep Report for %s"
set PrepSummary "Summary"
set PrepRecentGames "Recent Games"
set PrepWhiteOpenings "Top Openings as White"
set PrepBlackOpenings "Top Openings as Black"
set PrepPlayer "Player"
set PrepGames "Games"
set PrepDateRange "Date Range"
set PrepEloRange "Elo Range"
set PrepTotalScore "Overall"
set PrepWhiteScore "As White"
set PrepBlackScore "As Black"
set PrepCount "Count"
set PrepLine "Line"
set PrepRefresh "Refresh"
set PrepNoOpenings "No openings found"
set PrepUnknown "Unknown"
set PrepRepertoires "Open Repertoires"
set PrepNoRepertoires "No opening databases are open"
set PrepOpenRepertoire "Repertoire Report"
set PrepOpenRepertoirePrep "Opening Prep"
set PrepOpenRepertoireSearch "Advanced Search"
set PrepRepertoireType "Type"
set PrepOpenInSwitcher "Open In Switcher"
set PrepOpenSelectedGame "Open Selected Game"
set PrepPrepSelectedOpponent "Prep Selected Opponent"
set PrepOpenSelectedOpponentDossier "Open Opponent Dossier"
set PrepRepertoireName "Database"
set PrepRepertoireWhiteMatch "White Match"
set PrepRepertoireBlackMatch "Black Match"
set PrepRepertoireFocus "Focus"
set PrepRepertoireGap "Top Gaps"
set PrepRepertoireFocusWhite "Use against player's Black openings"
set PrepRepertoireFocusBlack "Use against player's White openings"
set PrepRepertoireFocusBoth "Covers both sides"
set PrepRepertoireNoGap "covered"
set PrepOpenFirstGap "Open First Gap"
set PrepOpenGapInSwitcher "Open First Gap In Switcher"
set PrepSaveGapWorkingSet "Save First Gap Working Set..."
set PrepNoGapAvailable "The selected repertoire already covers the tracked top openings."
set PrepOpenSelectedOpening "Open Selected Opening"
set PrepClearOpeningFilter "Clear Opening Filter"
set PrepFilterNone "All games"
set PrepFilterEco "ECO %s"
set PrepNoOpeningSelection "Select an opening row first."
set PrepNoRecentSelection "Select a recent game row first."
set AnalyzeFromReport "Analyze this position"
set OpponentDossierTitle "Opponent Dossier: %s"
set DossierWhiteRepertoire "White Repertoire"
set DossierBlackRepertoire "Black Repertoire"
set DossierRecentGames "Recent Games"
set DossierSummary "Summary"
set DossierScore "Score"
set DossierDate "Date"
set DossierEvent "Event"
set DossierOpponent "Opponent"
set DossierResult "Result"
set DossierRating "Rating"
set DossierNoRecentGames "No recent games"
set OpponentDossier "Opponent Dossier"
set DossierColor "Color"
set DossierRefresh "Refresh"
set DossierOpenInPrep "Open In Prep Report"
set DossierOpenInSwitcher "Open In Switcher"
set DossierSaveWorkingSet "Save Working Set..."
set DossierOpenGame "Open Selected Game"
set DossierOpenOpponentPrep "Prep Selected Opponent"
set DossierOpenOpponentDossier "Open Opponent Dossier"
set DossierSaveOpponentWorkingSet "Save Opponent Working Set..."
set DossierNoRecentSelection "Select a recent game row first."

} ;# namespace mc


array set Defaults {
	sort:players	{}
	sort:events		{}
}

array set Prios { player 300 games 200 event 100 }

array set FrameOptions {
	player { -width 400 -height 100% -minwidth 200 -minheight 4u -expand both }
	games	 { -width 600 -height  66% -minwidth 200 -minheight 4u -expand both }
	event	 { -width 600 -height  34% -minwidth 200 -minheight 4u -expand both }
}

variable Layout {
	root { -shrink none -grow none } {
		panedwindow { -orient horz } {
			frame player %player%
			panedwindow { -orient vert } {
				frame games %games%
				frame event %event%
			}
		}
	}
}

variable Tables {}
variable PrepReportData
variable DossierData


proc build {parent} {
	variable Tables
	variable Layout
	variable FrameOptions

	set twm $parent.twm
	namespace eval [namespace current]::$twm {}
	variable ${twm}::Vars

	if {$twm ni $Tables} { lappend Tables $twm }
	set Vars(after:games) {}
	set Vars(after:events) {}
	set Vars(after:players) {}
	set Vars(active) 0
	set Vars(base) ""

	::application::twm::make $twm player \
		[namespace current]::Prios \
		[array get FrameOptions] \
		$Layout \
		-makepane [namespace current]::MakeFrame \
		-buildpane [namespace current]::BuildFrame \
		-adjustcmd [namespace parent]::event::adjustFrame \
		;
	::application::twm::load $twm
	return $twm
}


proc activate {w flag} {
	set path $w.twm
	variable ${path}::Vars

	set Vars(active) $flag
	set base [::scidb::db::get name]
	set variant [::scidb::app::variant]
	set Vars($base:$variant:update:players) 1
	player::DoUpdate $path $base $variant

	if {[winfo toplevel $w] ne $w} {
		::toolbar::activate $Vars(frame:player) $flag
	}
}


proc overhang {parent} {
	set path $parent.twm
	variable ${path}::Vars

	return [::playertable::overhang $Vars(frame:player)]
}


proc linespace {parent} {
	set path $parent.twm
	variable ${path}::Vars

	return [::playertable::linespace $Vars(frame:player)]
}


proc setActive {flag} {
	# no action
}


proc select {parent base variant index} {
	set path $parent.twm
	variable ${path}::Vars

	if {$Vars(active)} {
		Select $path $base $variant $index
	} else {
		set Vars($base:$variant:select) $index
	}
}


proc MakeFrame {twm parent type uid} {
	variable Prios

	set frame [tk::frame $parent.$uid -borderwidth 0 -takefocus 1]
	set nameVar ::application::twm::mc::Pane($uid)
	return [list $frame $nameVar $Prios($uid) no [expr {$uid ne "player"}] yes yes]
}


proc BuildFrame {twm frame uid width height} {
	variable ${twm}::Vars
	set Vars(frame:$uid) $frame
	set id [::application::twm::getId $twm]

	switch $uid {
		player {
			set columns {lastName firstName type sex rating1 federation title frequency}
			::playertable::build $frame [namespace code [list View $twm]] $columns \
				-selectcmd [list [namespace current]::player::Search $twm] \
				-id db:players:$id:$uid \
				-usefind 1 \
				;
			::scidb::db::subscribe playerList \
				[list [namespace current]::player::Update $twm] \
				[list [namespace current]::Close $twm] \
				;
		}
		games {
			set columns {white whiteElo black blackElo event result date length}
			::gamestable::build $frame [namespace code [list View $twm]] $columns -id db:players:$id:$uid
			::scidb::db::subscribe gameList [list [namespace current]::games::Update $twm]
		}
		event {
			set columns {event eventType eventDate eventMode timeMode eventCountry site}
			::eventtable::build $frame [namespace code [list View $twm]] $columns \
				-selectcmd [namespace code [list SelectEvent $twm]] \
				-id db:players:$id:$uid \
				;
			::scidb::db::subscribe eventList [list [namespace current]::event::Update $twm]
		}
	}
}


proc Select {path base variant index} {
	variable ${path}::Vars

	set position [::scidb::db::get lookupPlayer $index $Vars($base:$variant:view) $base $variant]
	::playertable::see $Vars(frame:player) $position
	update idletasks
	set row [::playertable::indexToRow $Vars(frame:player) $position]
	::playertable::setSelection $Vars(frame:player) $row
}


proc View {path base variant} {
	variable ${path}::Vars

	if {[string length $base] == 0} { return 0 }
	return $Vars($base:$variant:view)
}


proc Close {path base variant} {
	variable ${path}::Vars

	array unset Vars $base:$variant:*
	::playertable::forget $Vars(frame:player) $base $variant
	::eventtable::forget $Vars(frame:event) $base $variant
	::gamestable::forget $Vars(frame:games) $base $variant

	if {$Vars(base) eq "$base:$variant"} {
		::playertable::clear $Vars(frame:player)
		::eventtable::clear $Vars(frame:event)
		::gamestable::clear $Vars(frame:games)
	}
}


proc InitBase {path base variant} {
	variable ${path}::Vars
	variable Defaults

	if {[info exists Vars($base:$variant:initializing)]} { return }

	if {![info exists Vars($base:$variant:view)]} {
		set Vars($base:$variant:initializing) 1
		set Vars($base:$variant:view) \
			[::scidb::view::new $base $variant master slave slave slave slave slave]
		set Vars($base:$variant:update:players) 1
		set Vars($base:$variant:sort:players) $Defaults(sort:players)
		set Vars($base:$variant:sort:events) $Defaults(sort:events)
		set Vars($base:$variant:lastChange) [::scidb::db::get lastChange $base $variant]
		set Vars($base:$variant:players:lastId) -1
		set Vars($base:$variant:games:lastId) -1
		set Vars($base:$variant:events:lastId) -1
		set Vars($base:$variant:select) -1
		set Vars($base:$variant:selected:key) {}
		::playertable::init $Vars(frame:player) $base $variant
		::gamestable::init $Vars(frame:games) $base $variant
		::eventtable::init $Vars(frame:event) $base $variant
		::scidb::view::search $base $variant $Vars($base:$variant:view) null events
	}
}


proc SelectEvent {path base variant view} {
	variable ${path}::Vars

	set index [::eventtable::selectedEvent $Vars(frame:event) $base $variant]
	[namespace parent]::selectEvent $base $variant $index
}


namespace eval games {

proc Update {path id base variant {view -1} {index -1}} {
	variable [namespace parent]::${path}::Vars

	[namespace parent]::InitBase $path $base $variant

	if {$view == $Vars($base:$variant:view)} {
		after cancel $Vars(after:games)
		set Vars(after:games) [after idle [namespace code [list Update2 $id $path $base $variant]]]
	}
}


proc Update2 {id path base variant} {
	variable [namespace parent]::${path}::Vars

	if {$id <= $Vars($base:$variant:games:lastId)} { return }
	set Vars($base:$variant:games:lastId) $id
	set lastChange $Vars($base:$variant:lastChange)
	set Vars($base:$variant:lastChange) [::scidb::db::get lastChange $base $variant]
	set selected [::playertable::selectedPlayer $Vars(frame:player) $base $variant]
	set view $Vars($base:$variant:view)

	if {$selected >= 0 && $lastChange < $Vars($base:$variant:lastChange)} {
		if {[llength $Vars($base:$variant:selected:key)]} {
			set index [::scidb::db::find player $base $variant $Vars($base:$variant:selected:key)]
			if {$index >= 0} {
				set row [::scidb::db::get lookupPlayer $index $view $base $variant]
				if {$row >= 0} {
					::playertable::setSelection $Vars(frame:player) \
						[::playertable::indexToRow $Vars(frame:player) $row]
				}
				[namespace parent]::player::Search $path $base $variant $view $index
			} else {
				[namespace parent]::player::Reset $path $base $variant
			}
		}
	} else {
		set Vars($base:$variant:lastChange) $lastChange

		set n [::scidb::view::count games $base $variant $view]
		after idle [list ::gamestable::update $Vars(frame:games) $base $variant $n]

		set n [::scidb::view::count events $base $variant $view]
		after idle [list ::eventtable::update $Vars(frame:event) $base $variant $n]
		set Vars($base:$variant:events:lastId) $id
	}
}

} ;# namespace games


namespace eval player {

proc Reset {path base variant} {
	variable [namespace parent]::${path}::Vars

	::eventtable::clear $Vars(frame:event)
	::gamestable::clear $Vars(frame:games)
	::playertable::select $Vars(frame:player) none
	::playertable::activate $Vars(frame:player) none
	set Vars($base:$variant:selected:key) {}
}


proc Search {path base variant view {selected -1}} {
	variable [namespace parent]::${path}::Vars

	::widget::busyCursor on
	::gamestable::activate $Vars(frame:games) none
	::gamestable::select $Vars(frame:games) none
	::eventtable::activate $Vars(frame:event) none
	::eventtable::select $Vars(frame:event) none

	if {$selected == -1} {
		set selected [::playertable::selectedPlayer $Vars(frame:player) $base $variant]
		if {$selected >= 0} {
			set index $selected
			set Vars($base:$variant:selected:key) [scidb::db::get playerKey $base $variant $index]
		}
	}

	if {$selected >= 0} {
		# TODO: we do an exact search, but probably we like to seach only for player name!
		set Vars($base:$variant:lastChange) [::scidb::db::get lastChange $base $variant]
		::scidb::view::search $base $variant $view null events [list player $selected]
		::eventtable::scroll $Vars(frame:event) home
		::gamestable::scroll $Vars(frame:games) home
	} else {
		Reset $path $base $variant
	}

	::widget::busyCursor off
}


proc Update {path id base variant {view -1} {index -1}} {
	variable ::scidb::clipbaseName
	variable [namespace parent]::${path}::Vars

	if {$base ne $clipbaseName && [string length [file extension $base]] == 0} { return }

	set Vars(base) "$base:$variant"
	after cancel $Vars(after:players)
	set Vars(after:players) [after idle [namespace code [list Update2 $id $path $base $variant]]]
}


proc Update2 {id path base variant} {
	variable [namespace parent]::${path}::Vars

	[namespace parent]::InitBase $path $base $variant
	if {$id <= $Vars($base:$variant:players:lastId)} { return }
	set Vars($base:$variant:players:lastId) $id
	set Vars($base:$variant:update:players) 1
	DoUpdate $path $base $variant
}


proc DoUpdate {path base variant} {
	variable [namespace parent]::${path}::Vars

	if {$Vars(active)} {
		if {[llength $Vars($base:$variant:sort:players)]} {
			::widget::busyCursor on
			set view $Vars($base:$variant:view)
			::scidb::db::sort player $base $variant $Vars($base:$variant:sort:players) $view
			::widget::busyCursor off
			set Vars($base:$variant:sort:players) {}
		}
		if {$Vars($base:$variant:update:players)} {
			set n [::scidb::db::count players $base $variant]
			after idle [list ::playertable::update $Vars(frame:player) $base $variant $n]
			after idle [namespace code [list [namespace parent]::games::Update2 \
				$Vars($base:$variant:players:lastId) $path $base $variant]]
			set Vars($base:$variant:update:players) 0
			if {$Vars($base:$variant:select) >= 0} {
				after idle \
					[list [namespace parent]::Select $path $base $variant $Vars($base:$variant:select)]
				set Vars($base:$variant:select) -1
			} elseif {[llength $Vars($base:$variant:selected:key)]} {
				set index [::scidb::db::find player $base $variant $Vars($base:$variant:selected:key)]
				if {$index >= 0} {
					after idle [list [namespace parent]::Select $path $base $variant $index]
				}
			}
		}
	}
}


} ;# namespace player

namespace eval event {

proc Update {path id base variant {view -1} {index -1}} {
	variable [namespace parent]::${path}::Vars

	after cancel $Vars(after:events)
	set Vars(after:events) [after idle [namespace code [list Update2 $id $path $base $variant]]]
}


proc Update2 {id path base variant} {
	variable [namespace parent]::${path}::Vars

	[namespace parent]::InitBase $path $base $variant
	if {$id <= $Vars($base:$variant:events:lastId)} { return }
	set Vars($base:$variant:events:lastId) $id
	set Vars($base:$variant:update:events) 1
	DoUpdate $path $base $variant
}


proc DoUpdate {path base variant} {
	variable [namespace parent]::${path}::Vars

	if {$Vars(active)} {
		if {[llength $Vars($base:$variant:sort:events)]} {
			::widget::busyCursor on
			set view $Vars($base:$variant:view)
			::scidb::db::sort event $base $variant $Vars($base:$variant:sort:events) $view
			::widget::busyCursor off
			set Vars($base:$variant:sort:events) {}
		}
		if {$Vars($base:$variant:update:events)} {
			set n [::scidb::view::count events $base $variant $Vars($base:$variant:view)]
			after idle [list ::eventtable::update $Vars(frame:event) $base $variant $n]
			set Vars($base:$variant:update:events) 0
		}
	}
}

} ;# namespace event


proc WriteTableOptions {chan variant {id "player"}} {
	variable TableOptions
	variable Tables

	if {$id ne "player"} { return }

	foreach table $Tables {
		set id [::application::twm::getId $table]
		foreach uid {player games event} {
			if {[info exists TableOptions($variant:$id:$uid)]} {
				puts $chan "::scrolledtable::setOptions db:players:$id:$uid {"
				::options::writeArray $chan $TableOptions($variant:$id:$uid)
				puts $chan "}"
			}
		}
	}
}
::options::hookTableWriter [namespace current]::WriteTableOptions


proc SaveOptions {twm variant} {
	variable TableOptions

	set id [::application::twm::getId $twm]
	foreach uid {player games event} {
		set TableOptions($variant:$id:$uid) [::scrolledtable::getOptions db:players:$id:$uid]
	}
}


proc RestoreOptions {twm variant} {
	variable TableOptions

	set id [::application::twm::getId $twm]
	foreach uid {player games event} {
		::scrolledtable::setOptions db:players:$id:$uid $TableOptions($variant:$id:$uid)
	}
}


proc CompareOptions {twm variant} {
	variable TableOptions

	set id [::application::twm::getId $twm]
	foreach uid {player games event} {
		if {[::scrolledtable::countOptions db:players:$id:$uid] > 0} {
			set lhs $TableOptions($variant:$id:$uid)
			set rhs [::scrolledtable::getOptions db:players:$id:$uid]
			if {![::table::equal $lhs $rhs]} { return false }
		}
	}
	return true
}


::options::hookSaveOptions \
	[namespace current]::SaveOptions \
	[namespace current]::RestoreOptions \
	[namespace current]::CompareOptions \
	;


proc PrepReportDialogName {base variant playerIndex} {
	set label [file tail $base]
	set label [string map {: _ / _ \\ _ " " _ . _} $label]
	set label [regsub -all {[^A-Za-z0-9_-]} $label _]
	set label [regsub -all {_+} $label _]
	if {![string length $label]} { set label db }
	set checksum [::scidb::misc::crc32 [file normalize $base]]
	return .playerprep_${label}_${checksum}_${variant}_$playerIndex
}


proc OpponentDossierDialogName {base variant playerIndex} {
	set label [file tail $base]
	set label [string map {: _ / _ \\ _ " " _ . _} $label]
	set label [regsub -all {[^A-Za-z0-9_-]} $label _]
	set label [regsub -all {_+} $label _]
	if {![string length $label]} { set label db }
	set checksum [::scidb::misc::crc32 [file normalize $base]]
	return .opponentdossier_${label}_${checksum}_${variant}_$playerIndex
}


proc PrepReportView {dlg base variant} {
	variable PrepReportData

	if {![info exists PrepReportData($dlg,view)]} { return 0 }
	return $PrepReportData($dlg,view)
}


proc PrepReportPlayerIndex {dlg} {
	variable PrepReportData

	if {![info exists PrepReportData($dlg,file)] || ![info exists PrepReportData($dlg,variant)]} {
		return -1
	}

	if {[info exists PrepReportData($dlg,playerKey)] && [llength $PrepReportData($dlg,playerKey)]} {
		set playerIndex [::scidb::db::find \
			player \
			$PrepReportData($dlg,file) \
			$PrepReportData($dlg,variant) \
			$PrepReportData($dlg,playerKey)]
		if {$playerIndex >= 0} {
			set PrepReportData($dlg,playerIndex) $playerIndex
		}
		return $playerIndex
	}

	if {[info exists PrepReportData($dlg,playerIndex)]} {
		return $PrepReportData($dlg,playerIndex)
	}

	return -1
}


proc PrepReportPercent {value} {
	return [format %.1f [expr {$value / 10.0}]]
}


proc PrepReportScoreText {stats} {
	lassign $stats wins losses draws pct
	return [format "%d-%d-%d (%s%%)" $wins $losses $draws [PrepReportPercent $pct]]
}


proc PrepReportRangeText {first last} {
	variable mc

	if {![string length $first] || $first eq "?"} { set first $mc::PrepUnknown }
	if {![string length $last] || $last eq "?"} { set last $mc::PrepUnknown }
	return "$first - $last"
}


proc PrepReportRatingText {minRating maxRating} {
	variable mc

	if {$minRating <= 0 && $maxRating <= 0} {
		return $mc::PrepUnknown
	}
	if {$minRating <= 0} { return $maxRating }
	if {$maxRating <= 0 || $minRating == $maxRating} { return $minRating }
	return "$minRating - $maxRating"
}


proc UnpackPlayerStats {stats} {
	set whiteRows {}
	set blackRows {}
	if {[llength $stats] > 6} {
		lassign [lindex $stats 6] whiteRows blackRows
	}

	return [list \
		[lindex $stats 0] \
		[lindex $stats 1] \
		[lindex $stats 2] \
		[lindex $stats 3] \
		[lindex $stats 4] \
		[lindex $stats 5] \
		$whiteRows \
		$blackRows]
}


proc PopulatePrepOpenings {tree rows} {
	variable mc

	$tree delete [$tree children {}]
	if {![llength $rows]} {
		$tree insert {} end -values [list 0 {} $mc::PrepNoOpenings]
		return
	}

	foreach row $rows {
		lassign $row count eco line
		$tree insert {} end -values [list $count $eco $line]
	}
}


proc SetActivePrepOpeningTree {dlg treeName} {
	variable PrepReportData

	set PrepReportData($dlg,activeOpeningTree) $treeName
}


proc SelectedPrepOpening {dlg {warn 1}} {
	variable PrepReportData
	variable mc

	set treeNames {whiteTree blackTree}
	if {[info exists PrepReportData($dlg,activeOpeningTree)]} {
		set activeTree $PrepReportData($dlg,activeOpeningTree)
		set index [lsearch -exact $treeNames $activeTree]
		if {$index >= 0} {
			set treeNames [linsert [lreplace $treeNames $index $index] 0 $activeTree]
		}
	}

	foreach treeName $treeNames {
		set tree $PrepReportData($dlg,$treeName)
		set sel [$tree selection]
		if {[llength $sel]} {
			set values [$tree item [lindex $sel 0] -values]
			set eco [lindex $values 1]
			set line [lindex $values 2]
			if {[string length $eco] && [string length $line] && $line ne $mc::PrepNoOpenings} {
				return $eco
			}
		}
	}

	if {$warn} {
		::dialog::info -parent $dlg -message $mc::PrepNoOpeningSelection
	}
	return {}
}


proc FilterPrepReportByOpening {dlg {eco {}}} {
	variable PrepReportData
	variable mc

	if {![PrepReportReady? $dlg]} { return }

	set base $PrepReportData($dlg,file)
	set variant $PrepReportData($dlg,variant)
	set playerIndex [PrepReportPlayerIndex $dlg]
	set view $PrepReportData($dlg,view)
	set scrolledTable $PrepReportData($dlg,scrolledTable)
	if {$playerIndex < 0} { return }

	::widget::busyCursor on
	if {[string length $eco]} {
		::scidb::view::search $base $variant $view null none [list AND [list player $playerIndex] [list eco $eco]]
		set PrepReportData($dlg,filterSummary) [format $mc::PrepFilterEco $eco]
	} else {
		::scidb::view::search $base $variant $view null none [list player $playerIndex]
		set PrepReportData($dlg,filterSummary) $mc::PrepFilterNone
	}
	::scidb::db::sort gameInfo \
		$base \
		$variant \
		[::scrolledtable::columnNo $scrolledTable date] \
		$view \
		-descending \
		-ratings {Any Any}
	set count [::scidb::view::count games $base $variant $view]
	if {![winfo exists $dlg] || ![winfo exists $scrolledTable]} {
		::widget::busyCursor off
		return
	}
	::gamestable::scroll $scrolledTable home
	::gamestable::update $scrolledTable $base $variant $count
	::widget::busyCursor off

	set PrepReportData($dlg,recentStatus) \
		"$count $mc::PrepGames - $PrepReportData($dlg,filterSummary)"
}


proc OpenSelectedPrepOpening {dlg} {
	set eco [SelectedPrepOpening $dlg]
	if {![string length $eco]} { return }
	FilterPrepReportByOpening $dlg $eco
}


proc PrepRepertoireTypeLabel {type} {
	variable mc

	switch -- $type {
		OpeningsWhite { return $::application::database::mc::RepertoireWhite }
		OpeningsBlack { return $::application::database::mc::RepertoireBlack }
		default { return $::application::database::mc::RepertoireBoth }
	}
}


proc PopulatePrepRepertoires {dlg} {
	variable PrepReportData
	variable mc

	set tree $PrepReportData($dlg,repertoireTree)
	set variant $PrepReportData($dlg,variant)
	$tree delete [$tree children {}]

	set bases [::application::database::repertoireBases 0 $variant]
	if {![llength $bases]} {
		$tree insert {} end -values [list $mc::PrepNoRepertoires {} {} {}]
		return
	}

	set whiteCodes {}
	foreach row $PrepReportData($dlg,whiteRows) {
		lappend whiteCodes [lindex $row 1]
	}
	set blackCodes {}
	foreach row $PrepReportData($dlg,blackRows) {
		lappend blackCodes [lindex $row 1]
	}

	foreach base $bases {
		set type [::scidb::db::get type $base]
		set ecoRows [::scidb::db::ecoStats $base $variant]
		set ecoSet {}
		foreach ecoRow $ecoRows {
			dict set ecoSet [lindex $ecoRow 0] 1
		}
		set whiteMatches 0
		foreach eco $whiteCodes {
			if {[string length $eco] && [dict exists $ecoSet $eco]} {
				incr whiteMatches
			}
		}
		set blackMatches 0
		foreach eco $blackCodes {
			if {[string length $eco] && [dict exists $ecoSet $eco]} {
				incr blackMatches
			}
		}
		set focus $mc::PrepRepertoireFocusBoth
		set gaps {}
		switch -- $type {
			OpeningsWhite {
				set focus $mc::PrepRepertoireFocusWhite
				foreach eco $blackCodes {
					if {[string length $eco] && ![dict exists $ecoSet $eco] && $eco ni $gaps} {
						lappend gaps $eco
					}
				}
			}
			OpeningsBlack {
				set focus $mc::PrepRepertoireFocusBlack
				foreach eco $whiteCodes {
					if {[string length $eco] && ![dict exists $ecoSet $eco] && $eco ni $gaps} {
						lappend gaps $eco
					}
				}
			}
			default {
				foreach eco [concat $whiteCodes $blackCodes] {
					if {[string length $eco] && ![dict exists $ecoSet $eco] && $eco ni $gaps} {
						lappend gaps $eco
					}
				}
			}
		}
		if {[llength $gaps]} {
			set firstGap [lindex $gaps 0]
			set gapSummary [join [lrange $gaps 0 2] {, }]
		} else {
			set firstGap {}
			set gapSummary $mc::PrepRepertoireNoGap
		}
		$tree insert {} end -values [list \
			[::util::databaseName $base] \
			[PrepRepertoireTypeLabel $type] \
			"$whiteMatches/[llength $whiteCodes]" \
			"$blackMatches/[llength $blackCodes]" \
			$focus \
			$gapSummary \
			$firstGap \
			$base]
	}
}


proc SelectedPrepRepertoire {dlg {warn 1}} {
	variable PrepReportData

	set tree $PrepReportData($dlg,repertoireTree)
	set sel [$tree selection]
	if {[llength $sel] == 0} {
		if {$warn} {
			::dialog::info -parent $dlg -message $::gamebar::mc::NoRepertoireBases
		}
		return {}
	}

	set base [lindex [$tree item [lindex $sel 0] -values] 7]
	if {[string length $base]} { return $base }

	if {$warn} {
		::dialog::info -parent $dlg -message $::gamebar::mc::NoRepertoireBases
	}
	return {}
}


proc OpenSelectedPrepRepertoireReport {dlg} {
	variable PrepReportData

	set base [SelectedPrepRepertoire $dlg]
	if {![string length $base]} { return }
	::application::database::OpenRepertoireReport $dlg $base $PrepReportData($dlg,variant)
}


proc OpenSelectedPrepRepertoirePrep {dlg} {
	variable PrepReportData

	set base [SelectedPrepRepertoire $dlg]
	if {![string length $base]} { return }
	::application::database::OpenOpeningPrepReport $dlg $base $PrepReportData($dlg,variant)
}


proc OpenSelectedPrepRepertoireSearch {dlg} {
	variable PrepReportData

	set base [SelectedPrepRepertoire $dlg]
	if {![string length $base]} { return }
	::application::database::OpenAdvancedSearch $dlg $base $PrepReportData($dlg,variant)
}


proc OpenSelectedPrepRepertoireGap {dlg} {
	set firstGap [SelectedPrepRepertoireGap $dlg]
	if {$firstGap eq {}} { return }
	FilterPrepReportByOpening $dlg $firstGap
}


proc SelectedPrepRepertoireGap {dlg} {
	variable PrepReportData
	variable mc

	set tree $PrepReportData($dlg,repertoireTree)
	set sel [$tree selection]
	if {[llength $sel] == 0} {
		::dialog::info -parent $dlg -message $::gamebar::mc::NoRepertoireBases
		return {}
	}

	set firstGap [lindex [$tree item [lindex $sel 0] -values] 6]
	if {![string length $firstGap]} {
		::dialog::info -parent $dlg -message $mc::PrepNoGapAvailable
		return {}
	}

	return $firstGap
}


proc OpenSelectedPrepGapInSwitcher {dlg} {
	variable PrepReportData

	set eco [SelectedPrepRepertoireGap $dlg]
	if {$eco eq {}} { return 0 }
	set playerIndex [PrepReportPlayerIndex $dlg]
	if {$playerIndex < 0} { return 0 }

	set view [::scidb::view::new \
		$PrepReportData($dlg,file) \
		$PrepReportData($dlg,variant) \
		unused unused unused unused master slave]

	set rc [catch {
		::scidb::view::search \
			$PrepReportData($dlg,file) \
			$PrepReportData($dlg,variant) \
			$view \
			null \
			none \
			[list AND [list player $playerIndex] [list eco $eco]]
		::application::database::OpenFilteredViewInSwitcher \
			$dlg \
			$PrepReportData($dlg,file) \
			$PrepReportData($dlg,variant) \
			$view \
			player-prep-gap \
			"gap-$eco"
	} result options]
	catch { ::scidb::view::close $PrepReportData($dlg,file) $PrepReportData($dlg,variant) $view }
	return -options $options $result
}


proc SaveSelectedPrepGapWorkingSet {dlg} {
	variable PrepReportData

	set eco [SelectedPrepRepertoireGap $dlg]
	if {$eco eq {}} { return 0 }
	set playerIndex [PrepReportPlayerIndex $dlg]
	if {$playerIndex < 0} { return 0 }

	set view [::scidb::view::new \
		$PrepReportData($dlg,file) \
		$PrepReportData($dlg,variant) \
		unused unused unused unused master slave]

	set rc [catch {
		::scidb::view::search \
			$PrepReportData($dlg,file) \
			$PrepReportData($dlg,variant) \
			$view \
			null \
			none \
			[list AND [list player $playerIndex] [list eco $eco]]
		::application::database::SaveFilteredViewAsWorkingSet \
			$dlg \
			$PrepReportData($dlg,file) \
			$PrepReportData($dlg,variant) \
			$view \
			player-prep-gap \
			"gap-$eco"
	} result options]
	catch { ::scidb::view::close $PrepReportData($dlg,file) $PrepReportData($dlg,variant) $view }
	return -options $options $result
}


proc OpenPrepResultsInSwitcher {dlg} {
	variable PrepReportData

	set rc [::application::database::OpenFilteredViewInSwitcher \
		$dlg \
		$PrepReportData($dlg,file) \
		$PrepReportData($dlg,variant) \
		$PrepReportData($dlg,view) \
		player-prep]
	if {$rc ne 0 && [winfo exists $dlg]} {
		destroy $dlg
	}
	return $rc
}


proc SelectedPrepGameNumber {dlg {warn 1}} {
	variable PrepReportData
	variable mc

	if {![info exists PrepReportData($dlg,table)] || ![info exists PrepReportData($dlg,view)]} {
		return -1
	}

	set table $PrepReportData($dlg,table)
	set index [::scrolledtable::index $table]
	if {$index < 0} {
		if {$warn} {
			::dialog::info -parent $dlg -message $mc::PrepNoRecentSelection
		}
		return -1
	}

	set info [::scidb::db::get gameInfo \
		$index \
		$PrepReportData($dlg,view) \
		$PrepReportData($dlg,file) \
		$PrepReportData($dlg,variant)]
	return [expr {[::gamestable::column $info number] - 1}]
}


proc SelectedPrepOpponentIndex {dlg {warn 1}} {
	variable PrepReportData
	variable mc

	set number [SelectedPrepGameNumber $dlg $warn]
	if {$number < 0} { return -1 }

	set base $PrepReportData($dlg,file)
	set variant $PrepReportData($dlg,variant)
	set playerKey $PrepReportData($dlg,playerKey)
	set whiteKey [::scidb::db::get playerKey $base $variant $number white]
	set blackKey [::scidb::db::get playerKey $base $variant $number black]

	if {$whiteKey eq $playerKey} {
		set opponentKey $blackKey
	} elseif {$blackKey eq $playerKey} {
		set opponentKey $whiteKey
	} else {
		if {$warn} {
			::dialog::info -parent $dlg -message $mc::PrepNoRecentSelection
		}
		return -1
	}

	return [::scidb::db::find player $base $variant $opponentKey]
}


proc OpenSelectedPrepGame {dlg} {
	variable PrepReportData

	set number [SelectedPrepGameNumber $dlg]
	if {$number < 0} { return }

	::game::new \
		$PrepReportData($dlg,table) \
		-base $PrepReportData($dlg,file) \
		-variant $PrepReportData($dlg,variant) \
		-view $PrepReportData($dlg,view) \
		-number $number
}


proc OpenSelectedPrepOpponent {dlg} {
	variable PrepReportData

	set opponentIndex [SelectedPrepOpponentIndex $dlg]
	if {$opponentIndex < 0} { return }

	OpenPrepReport $dlg $PrepReportData($dlg,file) $PrepReportData($dlg,variant) $opponentIndex
}


proc OpenSelectedPrepOpponentDossier {dlg} {
	variable PrepReportData

	set opponentIndex [SelectedPrepOpponentIndex $dlg]
	if {$opponentIndex < 0} { return }

	BuildOpponentDossier $dlg $PrepReportData($dlg,file) $PrepReportData($dlg,variant) $opponentIndex
}


proc PopupPrepRecentMenu {dlg x y} {
	variable mc

	if {![winfo exists $dlg]} { return }

	set menu $dlg.prepRecentMenu
	if {![winfo exists $menu]} {
		menu $menu -tearoff 0
		$menu add command \
			-label $mc::PrepOpenSelectedGame \
			-command [namespace code [list OpenSelectedPrepGame $dlg]]
		$menu add command \
			-label $mc::PrepPrepSelectedOpponent \
			-command [namespace code [list OpenSelectedPrepOpponent $dlg]]
		$menu add command \
			-label $mc::PrepOpenSelectedOpponentDossier \
			-command [namespace code [list OpenSelectedPrepOpponentDossier $dlg]]
	}

	tk_popup $menu $x $y
}


proc SavePrepWorkingSet {dlg} {
	variable PrepReportData

	set defaultName player-prep
	if {[info exists PrepReportData($dlg,filterSummary)]} {
		set summary $PrepReportData($dlg,filterSummary)
		if {$summary ne $mc::PrepFilterNone} {
			set defaultName $summary
		}
	}

	return [::application::database::SaveFilteredViewAsWorkingSet \
		$dlg \
		$PrepReportData($dlg,file) \
		$PrepReportData($dlg,variant) \
		$PrepReportData($dlg,view) \
		player-prep \
		$defaultName]
}


proc ClosePrepReport {dlg} {
	variable PrepReportData

	if {$dlg eq "" || ![info exists PrepReportData($dlg,file)]} { return }

	if {[info exists PrepReportData($dlg,view)]} {
		catch {
			::scidb::view::close \
				$PrepReportData($dlg,file) \
				$PrepReportData($dlg,variant) \
				$PrepReportData($dlg,view)
		}
	}

	foreach key [array names PrepReportData $dlg,*] {
		unset PrepReportData($key)
	}
}


proc HandlePrepReportDestroy {dlg widget} {
	if {$widget ne $dlg} { return }
	ClosePrepReport $dlg
}


proc PrepReportReady? {dlg} {
	variable PrepReportData

	return [expr {
		[winfo exists $dlg]
		&& [info exists PrepReportData($dlg,view)]
		&& [info exists PrepReportData($dlg,scrolledTable)]
		&& [info exists PrepReportData($dlg,table)]
		&& [info exists PrepReportData($dlg,whiteTree)]
		&& [info exists PrepReportData($dlg,blackTree)]
	}]
}


proc RefreshPrepReport {dlg} {
	variable PrepReportData
	variable mc

	if {![winfo exists $dlg]} { return }
	foreach key {file variant playerIndex view scrolledTable whiteTree blackTree} {
		if {![info exists PrepReportData($dlg,$key)]} { return }
	}

	set base $PrepReportData($dlg,file)
	set variant $PrepReportData($dlg,variant)
	set playerIndex [PrepReportPlayerIndex $dlg]
	set view $PrepReportData($dlg,view)
	set scrolledTable $PrepReportData($dlg,scrolledTable)
	set whiteTree $PrepReportData($dlg,whiteTree)
	set blackTree $PrepReportData($dlg,blackTree)
	if {$playerIndex < 0} { return }

	set playerKey [::scidb::db::get playerKey $base $variant $playerIndex]
	set playerName [lindex $playerKey 0]
	set PrepReportData($dlg,playerKey) $playerKey
	set stats [::scidb::db::get playerStats $base $variant $playerIndex]

	::widget::busyCursor on
	::scidb::view::search $base $variant $view null none [list player $playerIndex]
	::scidb::db::sort gameInfo \
		$base \
		$variant \
		[::scrolledtable::columnNo $scrolledTable date] \
		$view \
		-descending \
		-ratings {Any Any}
	set count [::scidb::view::count games $base $variant $view]
	if {![winfo exists $dlg] || ![winfo exists $scrolledTable]} {
		::widget::busyCursor off
		return
	}
	::gamestable::scroll $scrolledTable home
	::gamestable::update $scrolledTable $base $variant $count
	::widget::busyCursor off

	if {![PrepReportReady? $dlg] || ![winfo exists $whiteTree] || ![winfo exists $blackTree]} { return }

	lassign [UnpackPlayerStats $stats] \
		dateStats ratingStats gameCount whiteStats blackStats totalStats whiteRows blackRows
	lassign $dateStats firstDate lastDate
	lassign $ratingStats minRating maxRating
	set PrepReportData($dlg,playerName) $playerName
	set PrepReportData($dlg,games) $gameCount
	set PrepReportData($dlg,dateRange) [PrepReportRangeText $firstDate $lastDate]
	set PrepReportData($dlg,eloRange) [PrepReportRatingText $minRating $maxRating]
	set PrepReportData($dlg,totalScore) [PrepReportScoreText $totalStats]
	set PrepReportData($dlg,whiteScore) [PrepReportScoreText $whiteStats]
	set PrepReportData($dlg,blackScore) [PrepReportScoreText $blackStats]
	set PrepReportData($dlg,recentStatus) [format "%d %s" $count $mc::PrepGames]
	set PrepReportData($dlg,filterSummary) $mc::PrepFilterNone

	set PrepReportData($dlg,whiteRows) $whiteRows
	set PrepReportData($dlg,blackRows) $blackRows
	PopulatePrepOpenings $whiteTree $whiteRows
	PopulatePrepOpenings $blackTree $blackRows
	PopulatePrepRepertoires $dlg
	FilterPrepReportByOpening $dlg

	wm title $dlg [format $mc::PrepReportTitle $playerName]
}


proc addPrepReportMenuEntry {menu parent base variant playerIndex} {
	if {$playerIndex < 0} { return }

	$menu add command \
		-label " $::playertable::mc::ShowPrepReport" \
		-command [list [namespace current]::OpenPrepReport $parent $base $variant $playerIndex] \
		;
}


proc OpenPrepReport {parent base variant playerIndex} {
	variable PrepReportData
	variable mc

	if {![::application::database::RecommendSciWorkflow \
		$parent $base $variant "player prep reports" prep-report]} {
		return
	}

	set playerKey [::scidb::db::get playerKey $base $variant $playerIndex]
	set dlg [PrepReportDialogName $base $variant $playerIndex]

	if {[winfo exists $dlg] && ![PrepReportReady? $dlg]} {
		catch { destroy $dlg }
		ClosePrepReport $dlg
	}

	if {[winfo exists $dlg]
		&& [info exists PrepReportData($dlg,playerKey)]
		&& $PrepReportData($dlg,playerKey) ne $playerKey} {
		catch { destroy $dlg }
		ClosePrepReport $dlg
	}

	set PrepReportData($dlg,file) $base
	set PrepReportData($dlg,variant) $variant
	set PrepReportData($dlg,playerIndex) $playerIndex
	set PrepReportData($dlg,playerKey) $playerKey

	if {![winfo exists $dlg]} {
		set PrepReportData($dlg,playerName) {}
		set PrepReportData($dlg,games) 0
		set PrepReportData($dlg,dateRange) $mc::PrepUnknown
		set PrepReportData($dlg,eloRange) $mc::PrepUnknown
		set PrepReportData($dlg,totalScore) {}
		set PrepReportData($dlg,whiteScore) {}
		set PrepReportData($dlg,blackScore) {}
		set PrepReportData($dlg,recentStatus) {}
		set PrepReportData($dlg,activeOpeningTree) whiteTree
		set PrepReportData($dlg,view) \
			[::scidb::view::new $base $variant unused unused unused unused master slave]

		toplevel $dlg -class Scidb
		wm transient $dlg [winfo toplevel $parent]
		wm protocol $dlg WM_DELETE_WINDOW [list destroy $dlg]
		wm resizable $dlg true true
		wm withdraw $dlg

		ttk::frame $dlg.controls
		ttk::frame $dlg.summary
		ttk::frame $dlg.openings
		ttk::labelframe $dlg.repertoires -text $mc::PrepRepertoires
		ttk::labelframe $dlg.games -text $mc::PrepRecentGames
		pack $dlg.controls -side top -fill x
		pack $dlg.summary -side top -fill x -padx 6 -pady 6
		pack $dlg.openings -side top -fill both -padx 6
		pack $dlg.repertoires -side top -fill both -padx 6 -pady {6 0}
		pack $dlg.games -side top -fill both -expand yes -padx 6 -pady 6

		ttk::button $dlg.controls.refresh \
			-text $mc::PrepRefresh \
			-command [namespace code [list RefreshPrepReport $dlg]]
		ttk::button $dlg.controls.opening \
			-text $mc::PrepOpenSelectedOpening \
			-command [namespace code [list OpenSelectedPrepOpening $dlg]]
		ttk::button $dlg.controls.clearOpening \
			-text $mc::PrepClearOpeningFilter \
			-command [namespace code [list FilterPrepReportByOpening $dlg]]
		ttk::button $dlg.controls.switcher \
			-text $mc::PrepOpenInSwitcher \
			-command [namespace code [list OpenPrepResultsInSwitcher $dlg]]
		ttk::button $dlg.controls.openGame \
			-text $mc::PrepOpenSelectedGame \
			-command [namespace code [list OpenSelectedPrepGame $dlg]]
		ttk::button $dlg.controls.opponent \
			-text $mc::PrepPrepSelectedOpponent \
			-command [namespace code [list OpenSelectedPrepOpponent $dlg]]
		ttk::button $dlg.controls.dossier \
			-text $mc::PrepOpenSelectedOpponentDossier \
			-command [namespace code [list OpenSelectedPrepOpponentDossier $dlg]]
		ttk::button $dlg.controls.savews \
			-text $::application::database::mc::SaveWorkingSet \
			-command [namespace code [list SavePrepWorkingSet $dlg]]
		ttk::button $dlg.controls.close \
			-text $::mc::Close \
			-command [list destroy $dlg]
		pack $dlg.controls.close -side right
		pack $dlg.controls.savews -side right -padx {0 6}
		pack $dlg.controls.dossier -side right -padx {0 6}
		pack $dlg.controls.opponent -side right -padx {0 6}
		pack $dlg.controls.openGame -side right -padx {0 6}
		pack $dlg.controls.switcher -side right -padx {0 6}
		pack $dlg.controls.clearOpening -side right -padx {0 6}
		pack $dlg.controls.opening -side right -padx {0 6}
		pack $dlg.controls.refresh -side right -padx {0 6}

		ttk::label $dlg.summary.playerLabel -text $mc::PrepPlayer
		ttk::label $dlg.summary.playerValue \
			-textvariable [namespace current]::PrepReportData($dlg,playerName)
		ttk::label $dlg.summary.gamesLabel -text $mc::PrepGames
		ttk::label $dlg.summary.gamesValue \
			-textvariable [namespace current]::PrepReportData($dlg,games)
		ttk::label $dlg.summary.dateLabel -text $mc::PrepDateRange
		ttk::label $dlg.summary.dateValue \
			-textvariable [namespace current]::PrepReportData($dlg,dateRange)
		ttk::label $dlg.summary.eloLabel -text $mc::PrepEloRange
		ttk::label $dlg.summary.eloValue \
			-textvariable [namespace current]::PrepReportData($dlg,eloRange)
		ttk::label $dlg.summary.totalLabel -text $mc::PrepTotalScore
		ttk::label $dlg.summary.totalValue \
			-textvariable [namespace current]::PrepReportData($dlg,totalScore)
		ttk::label $dlg.summary.whiteLabel -text $mc::PrepWhiteScore
		ttk::label $dlg.summary.whiteValue \
			-textvariable [namespace current]::PrepReportData($dlg,whiteScore)
		ttk::label $dlg.summary.blackLabel -text $mc::PrepBlackScore
		ttk::label $dlg.summary.blackValue \
			-textvariable [namespace current]::PrepReportData($dlg,blackScore)

		grid $dlg.summary.playerLabel -row 0 -column 0 -sticky w
		grid $dlg.summary.playerValue -row 0 -column 1 -sticky w -padx {6 18}
		grid $dlg.summary.gamesLabel -row 0 -column 2 -sticky w
		grid $dlg.summary.gamesValue -row 0 -column 3 -sticky w -padx {6 18}
		grid $dlg.summary.dateLabel -row 1 -column 0 -sticky w
		grid $dlg.summary.dateValue -row 1 -column 1 -sticky w -padx {6 18}
		grid $dlg.summary.eloLabel -row 1 -column 2 -sticky w
		grid $dlg.summary.eloValue -row 1 -column 3 -sticky w -padx {6 18}
		grid $dlg.summary.totalLabel -row 2 -column 0 -sticky w
		grid $dlg.summary.totalValue -row 2 -column 1 -sticky w -padx {6 18}
		grid $dlg.summary.whiteLabel -row 2 -column 2 -sticky w
		grid $dlg.summary.whiteValue -row 2 -column 3 -sticky w -padx {6 18}
		grid $dlg.summary.blackLabel -row 3 -column 0 -sticky w
		grid $dlg.summary.blackValue -row 3 -column 1 -sticky w -padx {6 18}

		ttk::labelframe $dlg.openings.white -text $mc::PrepWhiteOpenings
		ttk::labelframe $dlg.openings.black -text $mc::PrepBlackOpenings
		pack $dlg.openings.white -side left -fill both -expand yes -padx {0 3}
		pack $dlg.openings.black -side left -fill both -expand yes -padx {3 0}

		foreach side {white black} {
			set tree [ttk::treeview $dlg.openings.$side.tree \
				-columns {count eco line} \
				-show headings \
				-height 6]
			$tree heading count -text $mc::PrepCount
			$tree heading eco -text ECO
			$tree heading line -text $mc::PrepLine
			$tree column count -anchor e -width 60 -stretch 0
			$tree column eco -anchor w -width 55 -stretch 0
			$tree column line -anchor w -width 420 -stretch 1
			pack $tree -fill both -expand yes
			bind $tree <<TreeviewSelect>> [namespace code [list SetActivePrepOpeningTree $dlg ${side}Tree]]
			bind $tree <Double-1> [namespace code [list OpenSelectedPrepOpening $dlg]]
			set PrepReportData($dlg,${side}Tree) $tree
		}

		ttk::frame $dlg.repertoires.controls
		pack $dlg.repertoires.controls -side top -fill x
		ttk::button $dlg.repertoires.controls.report \
			-text $mc::PrepOpenRepertoire \
			-command [namespace code [list OpenSelectedPrepRepertoireReport $dlg]]
		ttk::button $dlg.repertoires.controls.prep \
			-text $mc::PrepOpenRepertoirePrep \
			-command [namespace code [list OpenSelectedPrepRepertoirePrep $dlg]]
		ttk::button $dlg.repertoires.controls.search \
			-text $mc::PrepOpenRepertoireSearch \
			-command [namespace code [list OpenSelectedPrepRepertoireSearch $dlg]]
		ttk::button $dlg.repertoires.controls.gap \
			-text $mc::PrepOpenFirstGap \
			-command [namespace code [list OpenSelectedPrepRepertoireGap $dlg]]
		ttk::button $dlg.repertoires.controls.gapSwitcher \
			-text $mc::PrepOpenGapInSwitcher \
			-command [namespace code [list OpenSelectedPrepGapInSwitcher $dlg]]
		ttk::button $dlg.repertoires.controls.gapSave \
			-text $mc::PrepSaveGapWorkingSet \
			-command [namespace code [list SaveSelectedPrepGapWorkingSet $dlg]]
		pack $dlg.repertoires.controls.search -side right
		pack $dlg.repertoires.controls.gapSave -side right -padx {0 6}
		pack $dlg.repertoires.controls.gapSwitcher -side right -padx {0 6}
		pack $dlg.repertoires.controls.gap -side right -padx {0 6}
		pack $dlg.repertoires.controls.prep -side right -padx {0 6}
		ttk::button $dlg.repertoires.controls.analyze \
			-text $mc::AnalyzeFromReport \
			-command [namespace code [list AnalyzePrepReportPosition $dlg]]
		pack $dlg.repertoires.controls.analyze -side right -padx {0 6}
		pack $dlg.repertoires.controls.report -side right -padx {0 6}
		ttk::button $dlg.repertoires.controls.dossier \
			-text $mc::OpponentDossier \
			-command [namespace code [list OpenOpponentDossier $dlg]]
		pack $dlg.repertoires.controls.dossier -side right -padx {0 6}

		set repTree [ttk::treeview $dlg.repertoires.tree \
			-columns {name type whiteMatch blackMatch focus gap firstGap base} \
			-show headings \
			-height 4]
		$repTree heading name -text $mc::PrepRepertoireName
		$repTree heading type -text $mc::PrepRepertoireType
		$repTree heading whiteMatch -text $mc::PrepRepertoireWhiteMatch
		$repTree heading blackMatch -text $mc::PrepRepertoireBlackMatch
		$repTree heading focus -text $mc::PrepRepertoireFocus
		$repTree heading gap -text $mc::PrepRepertoireGap
		$repTree column name -anchor w -width 340 -stretch 1
		$repTree column type -anchor w -width 180 -stretch 0
		$repTree column whiteMatch -anchor e -width 90 -stretch 0
		$repTree column blackMatch -anchor e -width 90 -stretch 0
		$repTree column focus -anchor w -width 220 -stretch 0
		$repTree column gap -anchor w -width 170 -stretch 1
		$repTree column firstGap -width 0 -stretch 0
		$repTree column base -width 0 -stretch 0
		pack $repTree -side top -fill both -expand yes -pady {6 0}
		bind $repTree <Double-1> [namespace code [list OpenSelectedPrepRepertoireReport $dlg]]
		set PrepReportData($dlg,repertoireTree) $repTree

		ttk::label $dlg.games.status \
			-textvariable [namespace current]::PrepReportData($dlg,recentStatus)
		pack $dlg.games.status -side top -anchor w

		set PrepReportData($dlg,scrolledTable) $dlg.games.table
		set PrepReportData($dlg,table) [::gamestable::build \
			$PrepReportData($dlg,scrolledTable) \
			[namespace code [list PrepReportView $dlg]] \
			{number white black result event date eco material} \
			-id db:player-prep:[string map {. _} $dlg] \
			-mode list]
		bind $PrepReportData($dlg,scrolledTable) <Double-1> \
			[namespace code [list OpenSelectedPrepGame $dlg]]
		bind $PrepReportData($dlg,scrolledTable) <ButtonPress-3> \
			[namespace code [list PopupPrepRecentMenu $dlg %X %Y]]

		bind $dlg <Destroy> [namespace code [list HandlePrepReportDestroy $dlg %W]]

		wm minsize $dlg 880 540
		::util::place $dlg -parent [winfo toplevel $parent] -position center
		wm deiconify $dlg
	}

	wm deiconify $dlg
	raise $dlg
	focus $dlg
	RefreshPrepReport $dlg
}


proc AnalyzePrepReportPosition {dlg} {
	# Get current position from prep report
	variable PrepReportData

	set base $PrepReportData($dlg,file)
	set variant $PrepReportData($dlg,variant)
	set playerIndex $PrepReportData($dlg,playerIndex)

	# Load the player position for analysis
	if {![::scidb::game::load $base $variant 0]} {
		::ui::message "Failed to load position for analysis"
		return
	}

	# Start or activate analysis panel
	if {[::application::analysis::active?]} {
		::application::analysis::restartAnalysis 1
	} else {
		::application::analysis::newAnalysisPane 1
		::application::analysis::startAnalysis 1
	}
}
} ;# namespace player
} ;# namespace database
} ;# namespace application

# vi:set ts=3 sw=3:

# ======================================================================
# Opponent Dossier - Player Tendency Analysis
# ======================================================================

proc RefreshOpponentDossier {dlg} {
	variable DossierData

	foreach key {file variant playerIndex whiteTree blackTree recentTree summaryText} {
		if {![info exists DossierData($dlg,$key)]} { return }
	}
	if {![winfo exists $dlg]} { return }

	PopulateOpponentDossier \
		$dlg \
		$DossierData($dlg,file) \
		$DossierData($dlg,variant) \
		$DossierData($dlg,playerIndex) \
		$DossierData($dlg,whiteTree) \
		$DossierData($dlg,blackTree) \
		$DossierData($dlg,recentTree) \
		$DossierData($dlg,summaryText)
}


proc SelectedDossierOpening {dlg {warn 1}} {
	variable DossierData
	variable mc

	foreach treeName {whiteTree blackTree} {
		if {![info exists DossierData($dlg,$treeName)]} {
			continue
		}

		set tree $DossierData($dlg,$treeName)
		set sel [$tree selection]
		if {![llength $sel]} {
			continue
		}

		set values [$tree item [lindex $sel 0] -values]
		set eco [lindex $values 1]
		set line [lindex $values 2]
		if {[string length $eco] && [string length $line] && $line ne $mc::PrepNoOpenings} {
			return $eco
		}
	}

	if {$warn} {
		::dialog::info -parent $dlg -message $mc::PrepNoOpeningSelection
	}
	return {}
}


proc OpenDossierOpeningInPrepReport {dlg} {
	variable DossierData

	set eco [SelectedDossierOpening $dlg]
	if {$eco eq {}} { return }

	set base $DossierData($dlg,file)
	set variant $DossierData($dlg,variant)
	set playerIndex $DossierData($dlg,playerIndex)

	OpenPrepReport $dlg $base $variant $playerIndex
	set prepDlg [PrepReportDialogName $base $variant $playerIndex]
	if {[PrepReportReady? $prepDlg]} {
		FilterPrepReportByOpening $prepDlg $eco
	}
}


proc OpenDossierOpeningInSwitcher {dlg} {
	variable DossierData

	set eco [SelectedDossierOpening $dlg]
	if {$eco eq {}} { return 0 }

	set base $DossierData($dlg,file)
	set variant $DossierData($dlg,variant)
	set playerIndex $DossierData($dlg,playerIndex)
	set playerName [lindex $DossierData($dlg,playerKey) 0]
	set view [::scidb::view::new $base $variant unused unused unused unused master slave]
	set label [string trim "$playerName $eco"]

	set rc [catch {
		::scidb::view::search $base $variant $view null none [list AND [list player $playerIndex] [list eco $eco]]
		::application::database::OpenFilteredViewInSwitcher $dlg $base $variant $view dossier-opening $label
	} result options]
	catch { ::scidb::view::close $base $variant $view }
	return -options $options $result
}


proc SaveDossierOpeningWorkingSet {dlg} {
	variable DossierData

	set eco [SelectedDossierOpening $dlg]
	if {$eco eq {}} { return 0 }

	set base $DossierData($dlg,file)
	set variant $DossierData($dlg,variant)
	set playerIndex $DossierData($dlg,playerIndex)
	set view [::scidb::view::new $base $variant unused unused unused unused master slave]

	set rc [catch {
		::scidb::view::search $base $variant $view null none [list AND [list player $playerIndex] [list eco $eco]]
		::application::database::SaveFilteredViewAsWorkingSet $dlg $base $variant $view dossier-opening $eco
	} result options]
	catch { ::scidb::view::close $base $variant $view }
	return -options $options $result
}


proc SelectDossierOpeningAt {dlg tree y} {
	if {![winfo exists $tree]} { return 0 }

	set item [$tree identify row $y]
	if {$item eq {}} { return 0 }

	$tree selection set $item
	$tree focus $item

	variable DossierData
	foreach treeName {whiteTree blackTree} {
		if {![info exists DossierData($dlg,$treeName)]} {
			continue
		}
		set otherTree $DossierData($dlg,$treeName)
		if {$otherTree ne $tree && [winfo exists $otherTree]} {
			$otherTree selection remove [$otherTree selection]
		}
	}
	return 1
}


proc PopupDossierOpeningMenu {dlg tree x y Y} {
	variable mc

	if {![SelectDossierOpeningAt $dlg $tree $y]} { return }

	set menu $dlg.dossierOpeningMenu
	if {![winfo exists $menu]} {
		menu $menu -tearoff 0
		$menu add command \
			-label $mc::DossierOpenInPrep \
			-command [namespace code [list OpenDossierOpeningInPrepReport $dlg]]
		$menu add command \
			-label $mc::DossierOpenInSwitcher \
			-command [namespace code [list OpenDossierOpeningInSwitcher $dlg]]
		$menu add command \
			-label $mc::DossierSaveWorkingSet \
			-command [namespace code [list SaveDossierOpeningWorkingSet $dlg]]
	}

	tk_popup $menu $x $Y
}


proc SelectedDossierRecentGameNumber {dlg {warn 1}} {
	variable DossierData
	variable mc

	if {![info exists DossierData($dlg,recentTree)]} {
		return -1
	}

	set tree $DossierData($dlg,recentTree)
	set sel [$tree selection]
	if {![llength $sel]} {
		if {$warn} {
			::dialog::info -parent $dlg -message $mc::DossierNoRecentSelection
		}
		return -1
	}

	set values [$tree item [lindex $sel 0] -values]
	set number [lindex $values 6]
	if {![string is integer -strict $number] || $number < 0} {
		if {$warn} {
			::dialog::info -parent $dlg -message $mc::DossierNoRecentGames
		}
		return -1
	}

	return $number
}


proc SelectDossierRecentGameAt {dlg y} {
	variable DossierData

	if {![info exists DossierData($dlg,recentTree)]} {
		return 0
	}

	set tree $DossierData($dlg,recentTree)
	if {![winfo exists $tree]} { return 0 }

	set item [$tree identify row $y]
	if {$item eq {}} { return 0 }

	$tree selection set $item
	$tree focus $item
	return 1
}


proc PopupDossierRecentMenu {dlg x y Y} {
	variable mc

	if {![SelectDossierRecentGameAt $dlg $y]} { return }

	set menu $dlg.dossierRecentMenu
	if {![winfo exists $menu]} {
		menu $menu -tearoff 0
		$menu add command \
			-label $mc::DossierOpenGame \
			-command [namespace code [list OpenSelectedDossierRecentGame $dlg]]
		$menu add command \
			-label $mc::DossierOpenOpponentPrep \
			-command [namespace code [list OpenSelectedDossierOpponentPrep $dlg]]
		$menu add command \
			-label $mc::DossierOpenOpponentDossier \
			-command [namespace code [list OpenSelectedDossierOpponentDossier $dlg]]
		$menu add command \
			-label $mc::DossierSaveOpponentWorkingSet \
			-command [namespace code [list SaveSelectedDossierOpponentWorkingSet $dlg]]
	}

	tk_popup $menu $x $Y
}


proc SelectedDossierOpponentIndex {dlg {warn 1}} {
	variable DossierData
	variable mc

	set number [SelectedDossierRecentGameNumber $dlg $warn]
	if {$number < 0} { return -1 }

	set base $DossierData($dlg,file)
	set variant $DossierData($dlg,variant)
	set playerKey $DossierData($dlg,playerKey)
	set whiteKey [::scidb::db::get playerKey $base $variant $number white]
	set blackKey [::scidb::db::get playerKey $base $variant $number black]

	if {$whiteKey eq $playerKey} {
		set opponentKey $blackKey
	} elseif {$blackKey eq $playerKey} {
		set opponentKey $whiteKey
	} else {
		if {$warn} {
			::dialog::info -parent $dlg -message $mc::DossierNoRecentGames
		}
		return -1
	}

	return [::scidb::db::find player $base $variant $opponentKey]
}


proc OpenSelectedDossierRecentGame {dlg} {
	variable DossierData

	set number [SelectedDossierRecentGameNumber $dlg]
	if {$number < 0} { return }

	::game::new \
		$DossierData($dlg,recentTree) \
		-base $DossierData($dlg,file) \
		-variant $DossierData($dlg,variant) \
		-number $number
}


proc OpenSelectedDossierOpponentPrep {dlg} {
	variable DossierData

	set opponentIndex [SelectedDossierOpponentIndex $dlg]
	if {$opponentIndex < 0} { return }

	OpenPrepReport $dlg $DossierData($dlg,file) $DossierData($dlg,variant) $opponentIndex
}


proc OpenSelectedDossierOpponentDossier {dlg} {
	variable DossierData

	set opponentIndex [SelectedDossierOpponentIndex $dlg]
	if {$opponentIndex < 0} { return }

	BuildOpponentDossier $dlg $DossierData($dlg,file) $DossierData($dlg,variant) $opponentIndex
}


proc SaveSelectedDossierOpponentWorkingSet {dlg} {
	variable DossierData

	set opponentIndex [SelectedDossierOpponentIndex $dlg]
	if {$opponentIndex < 0} { return 0 }

	set base $DossierData($dlg,file)
	set variant $DossierData($dlg,variant)
	set playerKey [::scidb::db::get playerKey $base $variant $opponentIndex]
	set defaultName [lindex $playerKey 0]
	set view [::scidb::view::new $base $variant unused unused unused unused master slave]

	set rc [catch {
		::scidb::view::search $base $variant $view null none [list player $opponentIndex]
		::application::database::SaveFilteredViewAsWorkingSet \
			$dlg \
			$base \
			$variant \
			$view \
			dossier-opponent \
			$defaultName
	} result options]
	catch { ::scidb::view::close $base $variant $view }
	return -options $options $result
}

proc BuildOpponentDossier {parent base variant playerIndex} {
	variable mc
	variable PrepReportData
	variable DossierData

	set playerKey [::scidb::db::get playerKey $base $variant $playerIndex]
	lassign $playerKey playerName playerId

	set dlg [OpponentDossierDialogName $base $variant $playerIndex]
	set DossierData($dlg,file) $base
	set DossierData($dlg,variant) $variant
	set DossierData($dlg,playerIndex) $playerIndex
	set DossierData($dlg,playerKey) $playerKey
	if {![info exists DossierData($dlg,view)]} {
		set DossierData($dlg,view) \
			[::scidb::view::new $base $variant unused unused unused unused master slave]
	}

	if {[winfo exists $dlg]} {
		wm deiconify $dlg
		raise $dlg
		focus $dlg
		RefreshOpponentDossier $dlg
		return $dlg
	}

	tk::toplevel $dlg -class Scidb
	wm withdraw $dlg
	wm title $dlg [format $mc::OpponentDossierTitle $playerName]
	wm protocol $dlg WM_DELETE_WINDOW [list destroy $dlg]

	ttk::frame $dlg.controls
	pack $dlg.controls -side top -fill x
	ttk::button $dlg.controls.refresh \
		-text $mc::DossierRefresh \
		-command [namespace code [list RefreshOpponentDossier $dlg]]
	ttk::button $dlg.controls.prep \
		-text $mc::DossierOpenInPrep \
		-command [namespace code [list OpenDossierOpeningInPrepReport $dlg]]
	ttk::button $dlg.controls.switcher \
		-text $mc::DossierOpenInSwitcher \
		-command [namespace code [list OpenDossierOpeningInSwitcher $dlg]]
	ttk::button $dlg.controls.save \
		-text $mc::DossierSaveWorkingSet \
		-command [namespace code [list SaveDossierOpeningWorkingSet $dlg]]
	ttk::button $dlg.controls.openGame \
		-text $mc::DossierOpenGame \
		-command [namespace code [list OpenSelectedDossierRecentGame $dlg]]
	ttk::button $dlg.controls.opponentPrep \
		-text $mc::DossierOpenOpponentPrep \
		-command [namespace code [list OpenSelectedDossierOpponentPrep $dlg]]
	ttk::button $dlg.controls.close \
		-text $::mc::Close \
		-command [list destroy $dlg]
	pack $dlg.controls.close -side right
	pack $dlg.controls.opponentPrep -side right -padx {0 6}
	pack $dlg.controls.openGame -side right -padx {0 6}
	pack $dlg.controls.save -side right -padx {0 6}
	pack $dlg.controls.switcher -side right -padx {0 6}
	pack $dlg.controls.prep -side right -padx {0 6}
	pack $dlg.controls.refresh -side right -padx {0 6}

	# Create notebook for multiple tabs
	ttk::notebook $dlg.nb
	pack $dlg.nb -fill both -expand yes

	# Tab 1: Opening Tendencies
	set tabWhite [ttk::frame $dlg.nb.white]
	set tabBlack [ttk::frame $dlg.nb.black]
	set tabRecent [ttk::frame $dlg.nb.recent]
	set tabSummary [ttk::frame $dlg.nb.summary]

	$dlg.nb add $tabWhite -text $mc::DossierWhiteRepertoire
	$dlg.nb add $tabBlack -text $mc::DossierBlackRepertoire
	$dlg.nb add $tabRecent -text $mc::DossierRecentGames
	$dlg.nb add $tabSummary -text $mc::DossierSummary

	# Build white repertoire tree
	set whiteTree [ttk::treeview $tabWhite.tree \
		-columns {count eco line score} \
		-show headings \
		-height 20]
	$whiteTree heading count -text $mc::PrepCount
	$whiteTree heading eco -text ECO
	$whiteTree heading line -text $mc::PrepLine
	$whiteTree heading score -text $mc::DossierScore
	$whiteTree column count -anchor e -width 50 -stretch 0
	$whiteTree column eco -anchor w -width 55 -stretch 0
	$whiteTree column line -anchor w -width 300 -stretch 1
	$whiteTree column score -anchor e -width 80 -stretch 0
	pack $whiteTree -fill both -expand yes

	# Build black repertoire tree
	set blackTree [ttk::treeview $tabBlack.tree \
		-columns {count eco line score} \
		-show headings \
		-height 20]
	$blackTree heading count -text $mc::PrepCount
	$blackTree heading eco -text ECO
	$blackTree heading line -text $mc::PrepLine
	$blackTree heading score -text $mc::DossierScore
	$blackTree column count -anchor e -width 50 -stretch 0
	$blackTree column eco -anchor w -width 55 -stretch 0
	$blackTree column line -anchor w -width 300 -stretch 1
	$blackTree column score -anchor e -width 80 -stretch 0
	pack $blackTree -fill both -expand yes

	# Recent games listbox
	set recentList [ttk::treeview $tabRecent.tree \
		-columns {date event opponent color result rating number} \
		-show headings \
		-height 20]
	$recentList heading date -text $mc::DossierDate
	$recentList heading event -text $mc::DossierEvent
	$recentList heading opponent -text $mc::DossierOpponent
	$recentList heading color -text $mc::DossierColor
	$recentList heading result -text $mc::DossierResult
	$recentList heading rating -text $mc::DossierRating
	$recentList column date -anchor w -width 80 -stretch 0
	$recentList column event -anchor w -width 150 -stretch 1
	$recentList column opponent -anchor w -width 150 -stretch 1
	$recentList column color -anchor center -width 55 -stretch 0
	$recentList column result -anchor e -width 50 -stretch 0
	$recentList column rating -anchor e -width 60 -stretch 0
	$recentList column number -width 0 -stretch 0
	pack $recentList -fill both -expand yes

	# Summary text widget
	set summaryText [tk::text $tabSummary.text -wrap word -height 30]
	ttk::scrollbar $tabSummary.sb -command [list $summaryText yview]
	$summaryText configure -yscrollcommand [list $tabSummary.sb set]
	pack $tabSummary.sb -side right -fill y
	pack $summaryText -fill both -expand yes

	set DossierData($dlg,whiteTree) $whiteTree
	set DossierData($dlg,blackTree) $blackTree
	set DossierData($dlg,recentTree) $recentList
	set DossierData($dlg,summaryText) $summaryText

	# Populate data
	PopulateOpponentDossier $dlg $base $variant $playerIndex $whiteTree $blackTree $recentList $summaryText

	# Bind double-click to open games
	bind $whiteTree <Double-1> [namespace code [list OpenDossierOpening $dlg $base $variant $playerIndex $whiteTree white]]
	bind $blackTree <Double-1> [namespace code [list OpenDossierOpening $dlg $base $variant $playerIndex $blackTree black]]
	bind $whiteTree <ButtonPress-3> [namespace code [list PopupDossierOpeningMenu $dlg $whiteTree %X %x %Y]]
	bind $blackTree <ButtonPress-3> [namespace code [list PopupDossierOpeningMenu $dlg $blackTree %X %x %Y]]
	bind $recentList <Double-1> [namespace code [list OpenDossierRecentGame $dlg $base $variant $playerIndex $recentList]]
	bind $recentList <ButtonPress-3> [namespace code [list PopupDossierRecentMenu $dlg %X %y %Y]]
	bind $dlg <Destroy> [namespace code [list HandleOpponentDossierDestroy $dlg %W]]

	wm minsize $dlg 700 500
	::util::place $dlg -parent [winfo toplevel $parent] -position center
	wm deiconify $dlg
	raise $dlg
	focus $dlg

	return $dlg
}


proc PopulateOpponentDossier {dlg base variant playerIndex whiteTree blackTree recentList summaryText} {
	variable mc
	variable DossierData

	# Get player stats
	set stats [::scidb::db::get playerStats $base $variant $playerIndex]
	lassign [UnpackPlayerStats $stats] \
		dateStats ratingStats gameCount whiteStats blackStats totalStats whiteRows blackRows

	# Populate white openings
	PopulateDossierOpenings $whiteTree $whiteRows $base $variant

	# Populate black openings
	PopulateDossierOpenings $blackTree $blackRows $base $variant

	# Get recent games from a dedicated player-specific view.
	set view $DossierData($dlg,view)
	::scidb::view::search $base $variant $view null none [list player $playerIndex]
	::scidb::db::sort gameInfo \
		$base \
		$variant \
		[::gamestable::columnIndex date] \
		$view \
		-descending \
		-ratings {Any Any}
	set recentCount [::scidb::view::count games $base $variant $view]
	PopulateDossierRecentGames $dlg $recentList $base $variant $view [expr {min(20, $recentCount)}]

	# Build summary
	BuildDossierSummary $summaryText $playerIndex $stats $base $variant
}


proc PopulateDossierOpenings {tree rows base variant} {
	variable mc

	$tree delete [$tree children {}]
	if {![llength $rows]} {
		$tree insert {} end -values [list 0 {} $mc::PrepNoOpenings]
		return
	}

	foreach row $rows {
		lassign $row count eco line
		$tree insert {} end -values [list $count $eco $line]
	}
}


proc PopulateDossierRecentGames {dlg tree base variant view recentCount} {
	variable mc
	variable DossierData

	$tree delete [$tree children {}]
	if {$recentCount <= 0} {
		$tree insert {} end -values [list {} {} $mc::DossierNoRecentGames {} {} {} -1]
		return
	}

	set playerKey $DossierData($dlg,playerKey)
	for {set index 0} {$index < $recentCount} {incr index} {
		set info [::scidb::db::get gameInfo $index $view $base $variant]
		set number [expr {[::gamestable::column $info number] - 1}]
		set whiteKey [::scidb::db::get playerKey $base $variant $number white]
		set blackKey [::scidb::db::get playerKey $base $variant $number black]
		if {$whiteKey eq $playerKey} {
			set color White
			set opponent [::gamestable::column $info black]
			set rating [::gamestable::column $info blackRating1]
			set resultText [DossierPlayerResult [::gamestable::column $info result] white]
		} elseif {$blackKey eq $playerKey} {
			set color Black
			set opponent [::gamestable::column $info white]
			set rating [::gamestable::column $info whiteRating1]
			set resultText [DossierPlayerResult [::gamestable::column $info result] black]
		} else {
			set color {}
			set opponent [format "%s - %s" \
				[::gamestable::column $info white] \
				[::gamestable::column $info black]]
			set rating {}
			set resultText [::gamestable::column $info result]
		}
		$tree insert {} end -values [list \
			[::gamestable::column $info date] \
			[::gamestable::column $info event] \
			$opponent \
			$color \
			$resultText \
			$rating \
			$number]
	}
}


proc BuildDossierSummary {textWidget playerIndex stats base variant} {
	variable mc

	$textWidget configure -state normal
	$textWidget delete 1.0 end
	$textWidget tag configure heading -font {Helvetica 14 bold}
	$textWidget tag configure subheading -font {Helvetica 12 bold}
	$textWidget tag configure normal -font {Helvetica 11}

	lassign [UnpackPlayerStats $stats] \
		dateStats ratingStats gameCount whiteStats blackStats totalStats whiteRows blackRows
	lassign $dateStats firstDate lastDate

	# Overall stats
	$textWidget insert end "Overall Statistics\n" heading
	lassign $totalStats wins losses draws pct
	if {$gameCount > 0} {
		$textWidget insert end "Games: $gameCount  Score: [format %.1f $pct]%  " normal
		$textWidget insert end "($wins-$losses-$draws)\n\n" normal
	}
	$textWidget insert end "Date Range: [PrepReportRangeText $firstDate $lastDate]\n\n" normal

	# White performance
	$textWidget insert end "With White\n" subheading
	lassign $whiteStats wWins wLosses wDraws wPct
	set whiteGames [expr {$wWins + $wLosses + $wDraws}]
	if {$whiteGames > 0} {
		$textWidget insert end "Games: $whiteGames  Score: [format %.1f $wPct]%\n" normal
	}
	set topWhite [DossierTopOpeningText $whiteRows]
	if {[string length $topWhite]} {
		$textWidget insert end "Top Opening: $topWhite\n\n" normal
	}

	# Black performance
	$textWidget insert end "With Black\n" subheading
	lassign $blackStats bWins bLosses bDraws bPct
	set blackGames [expr {$bWins + $bLosses + $bDraws}]
	if {$blackGames > 0} {
		$textWidget insert end "Games: $blackGames  Score: [format %.1f $bPct]%\n" normal
	}
	set topBlack [DossierTopOpeningText $blackRows]
	if {[string length $topBlack]} {
		$textWidget insert end "Top Opening: $topBlack\n\n" normal
	}

	# Rating info
	lassign $ratingStats minRating maxRating
	if {$maxRating > 0} {
		$textWidget insert end "Rating Range\n" subheading
		$textWidget insert end [PrepReportRatingText $minRating $maxRating]
		$textWidget insert end "\n\n" normal
	}

	$textWidget configure -state disabled
}


proc DossierTopOpeningText {rows} {
	if {![llength $rows]} { return {} }

	lassign [lindex $rows 0] count eco line
	if {![string length $eco] || ![string length $line]} { return {} }

	return "$eco $line ($count)"
}


proc OpenDossierOpening {dlg base variant playerIndex tree color} {
	variable DossierData

	set sel [$tree selection]
	if {![llength $sel]} { return }

	set values [$tree item [lindex $sel 0] -values]
	set eco [lindex $values 1]
	if {![string length $eco]} { return }

	set view [::scidb::view::new $base $variant unused unused unused unused master slave]
	set playerName [lindex $DossierData($dlg,playerKey) 0]
	set label [string trim "$playerName $eco"]
	set result [catch {
		::scidb::view::search $base $variant $view null none [list AND [list player $playerIndex] [list eco $eco]]
		::application::database::OpenFilteredViewInSwitcher $dlg $base $variant $view dossier-opening $label
	} rc options]
	catch { ::scidb::view::close $base $variant $view }
	return -options $options $rc
}


proc OpenDossierRecentGame {dlg base variant playerIndex tree} {
	set sel [$tree selection]
	if {![llength $sel]} { return }

	set values [$tree item [lindex $sel 0] -values]
	set number [lindex $values 6]
	if {![string is integer -strict $number] || $number < 0} { return }
	::game::new $tree -base $base -variant $variant -number $number
}


proc DossierPlayerResult {result side} {
	switch -- $result {
		"1-0" { return [expr {$side eq "white" ? "W" : "L"}] }
		"0-1" { return [expr {$side eq "black" ? "W" : "L"}] }
		"1/2-1/2" { return "D" }
		default { return $result }
	}
}


proc CloseOpponentDossier {dlg} {
	variable DossierData

	if {$dlg eq "" || ![info exists DossierData($dlg,file)]} { return }
	if {[info exists DossierData($dlg,view)]} {
		catch {
			::scidb::view::close \
				$DossierData($dlg,file) \
				$DossierData($dlg,variant) \
				$DossierData($dlg,view)
		}
	}

	foreach key [array names DossierData $dlg,*] {
		unset DossierData($key)
	}
}


proc HandleOpponentDossierDestroy {dlg widget} {
	if {$widget ne $dlg} { return }
	CloseOpponentDossier $dlg
}



proc OpenOpponentDossier {dlg} {
	variable PrepReportData

	set base $PrepReportData($dlg,file)
	set variant $PrepReportData($dlg,variant)
	set playerIndex [PrepReportPlayerIndex $dlg]

	BuildOpponentDossier $dlg $base $variant $playerIndex
}
