# ======================================================================
# Author : $Author$
# Version: $Revision$
# Date   : $Date$
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

::util::source database-repertoire

namespace eval application {
namespace eval database {
namespace eval mc {

set AddToRepertoire					"Add Current Game to Repertoire"
set AddToRepertoireBase					"Add Current Game to %s"
set AddLineToRepertoire					"Add Current Line to Repertoire"
set AddLineToRepertoireBase				"Add Current Line to %s"
set NoRepertoireBases					"No writable opening databases are open."
set NoRepertoireBasesDetail			"Create or retag a database as Openings, Openings White, or Openings Black, then reopen this menu."
set NoTemporarySlot					"No temporary game slot is available."
set NoTemporarySlotDetail			"Release one auxiliary game or browser slot and try again."
set RepertoireBoth					"Openings"
set RepertoireWhite					"Openings White"
set RepertoireBlack					"Openings Black"
set RepertoireReport				"Repertoire Report"
set RepertoireReportTitle			"Repertoire Report for '%s'"
set RepertoireType					"Type"
set RepertoireGames					"Games"
set RepertoireDeleted				"Deleted"
set RepertoireStatus				"Storage"
set RepertoireTopOpening			"Top ECO"
set RepertoireCoverage			"Coverage"
set RepertoireStatusCompact		"Compaction recommended"
set RepertoireStatusClean			"No compaction needed"
set RepertoireNoOpenings			"No openings found"
set RepertoireTopOpenings			"Top Openings"
set RepertoireRecentGames			"Recent Games"
set RepertoireRefresh				"Refresh"
set RepertoireOpenPrep				"Opening Prep"
set RepertoireOpenSearch			"Advanced Search"
set RepertoireOpenInSwitcher		"Open In Switcher"
set RepertoireOpenSelectedEco		"Open Selected ECO"
set RepertoireClearEcoFilter		"Clear ECO Filter"
set RepertoireNoEcoSelection		"Select an ECO row first."
set RepertoireFilterNone			"All repertoire games"
set RepertoireFilterEco			"Filtered to ECO %s"
set RepertoireGamesShown			"%s recent games shown"

} ;# namespace mc

proc RepertoireReportDialogName {file variant} {
	return .repertoire_[string map {: _ . _ / _} $file]_${variant}
}


proc RepertoireTypeLabel {type} {
	variable mc

	switch -- $type {
		OpeningsWhite { return $mc::RepertoireWhite }
		OpeningsBlack { return $mc::RepertoireBlack }
		default { return $mc::RepertoireBoth }
	}
}


proc RepertoireReportView {dlg base variant} {
	variable RepertoireReportData

	if {![info exists RepertoireReportData($dlg,view)]} { return 0 }
	return $RepertoireReportData($dlg,view)
}


proc CloseRepertoireReport {dlg} {
	variable RepertoireReportData

	if {![string match .repertoire_* $dlg]} { return }
	if {[info exists RepertoireReportData($dlg,view)]} {
		catch {
			::scidb::view::close \
				$RepertoireReportData($dlg,file) \
				$RepertoireReportData($dlg,variant) \
				$RepertoireReportData($dlg,view)
		}
	}
	foreach key [array names RepertoireReportData $dlg,*] {
		unset RepertoireReportData($key)
	}
}


proc PopulateRepertoireOpenings {dlg rows} {
	variable RepertoireReportData
	variable mc

	set tv $RepertoireReportData($dlg,openingsTree)
	$tv delete [$tv children {}]

	if {![llength $rows]} {
		$tv insert {} end -values [list $mc::RepertoireNoOpenings {} {} {}]
		return
	}

	foreach row $rows {
		lassign $row eco count white draw black
		$tv insert {} end -values [list $eco $count $white $draw $black]
	}
}


proc SelectedRepertoireEco {dlg {warn 1}} {
	variable RepertoireReportData
	variable mc

	set tv $RepertoireReportData($dlg,openingsTree)
	set sel [$tv selection]
	if {[llength $sel] == 0} {
		if {$warn} {
			::dialog::info -parent $dlg -message $mc::RepertoireNoEcoSelection
		}
		return {}
	}

	set eco [lindex [$tv item [lindex $sel 0] -values] 0]
	if {![string length $eco] || $eco eq $mc::RepertoireNoOpenings} {
		if {$warn} {
			::dialog::info -parent $dlg -message $mc::RepertoireNoEcoSelection
		}
		return {}
	}

	return $eco
}


proc FilterRepertoireByEco {dlg {eco {}}} {
	variable RepertoireReportData
	variable mc

	if {![winfo exists $dlg]} { return }

	set base $RepertoireReportData($dlg,file)
	set variant $RepertoireReportData($dlg,variant)
	set view $RepertoireReportData($dlg,view)
	set scrolledTable $RepertoireReportData($dlg,scrolledTable)

	::widget::busyCursor on
	set rc [catch {
		if {[string length $eco]} {
			::scidb::view::search $base $variant $view null none [list eco $eco]
			set RepertoireReportData($dlg,filterSummary) [format $mc::RepertoireFilterEco $eco]
		} else {
			::scidb::view::search $base $variant $view null none
			set RepertoireReportData($dlg,filterSummary) $mc::RepertoireFilterNone
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
			return
		}
		::gamestable::scroll $scrolledTable home
		::gamestable::update $scrolledTable $base $variant $count
	} result options]
	::widget::busyCursor off
	if {$rc} {
		return -options $options $result
	}

	if {[winfo exists $dlg]} {
		set RepertoireReportData($dlg,recentStatus) \
			"[format $mc::RepertoireGamesShown [::locale::formatNumber $count]] - $RepertoireReportData($dlg,filterSummary)"
	}
}


proc OpenSelectedRepertoireEco {dlg} {
	set eco [SelectedRepertoireEco $dlg]
	if {![string length $eco]} { return }
	FilterRepertoireByEco $dlg $eco
}


proc OpenRepertoireResultsInSwitcher {dlg} {
	variable RepertoireReportData

	set rc [OpenFilteredViewInSwitcher \
		$dlg \
		$RepertoireReportData($dlg,file) \
		$RepertoireReportData($dlg,variant) \
		$RepertoireReportData($dlg,view) \
		repertoire]
	if {$rc ne 0 && [winfo exists $dlg]} {
		destroy $dlg
	}
	return $rc
}


proc SaveRepertoireWorkingSet {dlg} {
	variable RepertoireReportData

	set defaultName repertoire
	if {[info exists RepertoireReportData($dlg,filterSummary)]} {
		set summary $RepertoireReportData($dlg,filterSummary)
		if {$summary ne $mc::RepertoireFilterNone} {
			set defaultName $summary
		}
	}

	return [SaveFilteredViewAsWorkingSet \
		$dlg \
		$RepertoireReportData($dlg,file) \
		$RepertoireReportData($dlg,variant) \
		$RepertoireReportData($dlg,view) \
		repertoire \
		$defaultName]
}


proc RefreshRepertoireReport {dlg} {
	variable RepertoireReportData

	if {![winfo exists $dlg]} { return }

	set base $RepertoireReportData($dlg,file)
	set variant $RepertoireReportData($dlg,variant)
	set view $RepertoireReportData($dlg,view)
	set scrolledTable $RepertoireReportData($dlg,scrolledTable)

	set type [::scidb::db::get type $base]
	set active [::scidb::db::count games $base $variant]
	set total [::scidb::db::count total $base]
	set deleted [expr {$total - $active}]
	set rows [::scidb::db::ecoStats $base $variant]

	if {![winfo exists $dlg]} { return }

	set RepertoireReportData($dlg,type) [RepertoireTypeLabel $type]
	set RepertoireReportData($dlg,games) [::locale::formatNumber $active]
	set RepertoireReportData($dlg,deleted) [::locale::formatNumber $deleted]
	set RepertoireReportData($dlg,coverage) [::locale::formatNumber [llength $rows]]
	if {[::scidb::db::get compact? $base $variant]} {
		set RepertoireReportData($dlg,status) $::application::database::mc::RepertoireStatusCompact
	} else {
		set RepertoireReportData($dlg,status) $::application::database::mc::RepertoireStatusClean
	}
	if {[llength $rows]} {
		lassign [lindex $rows 0] eco count white draw black
		set RepertoireReportData($dlg,topOpening) "$eco ([::locale::formatNumber $count])"
	} else {
		set RepertoireReportData($dlg,topOpening) $::application::database::mc::RepertoireNoOpenings
	}
	set RepertoireReportData($dlg,filterSummary) $::application::database::mc::RepertoireFilterNone

	PopulateRepertoireOpenings $dlg [lrange $rows 0 11]
	wm title $dlg [format $::application::database::mc::RepertoireReportTitle [::util::databaseName $base]]
	FilterRepertoireByEco $dlg
}


proc OpenRepertoireReport {parent file variant} {
	variable RepertoireReportData
	variable mc

	set dlg [RepertoireReportDialogName $file $variant]

	if {![winfo exists $dlg]} {
		set RepertoireReportData($dlg,file) $file
		set RepertoireReportData($dlg,variant) $variant
		set RepertoireReportData($dlg,type) {}
		set RepertoireReportData($dlg,games) 0
		set RepertoireReportData($dlg,deleted) 0
		set RepertoireReportData($dlg,status) {}
		set RepertoireReportData($dlg,topOpening) {}
		set RepertoireReportData($dlg,coverage) 0
		set RepertoireReportData($dlg,filterSummary) $mc::RepertoireFilterNone
		set RepertoireReportData($dlg,recentStatus) {}
		set RepertoireReportData($dlg,view) \
			[::scidb::view::new $file $variant unused unused unused unused master slave]

		toplevel $dlg -class Scidb
		wm transient $dlg [winfo toplevel $parent]
		wm protocol $dlg WM_DELETE_WINDOW [list destroy $dlg]
		wm resizable $dlg true true
		wm withdraw $dlg

		ttk::frame $dlg.controls
		ttk::frame $dlg.summary
		ttk::labelframe $dlg.openings -text $mc::RepertoireTopOpenings
		ttk::labelframe $dlg.games -text $mc::RepertoireRecentGames
		pack $dlg.controls -side top -fill x
		pack $dlg.summary -side top -fill x -padx 6 -pady 6
		pack $dlg.openings -side top -fill both -padx 6
		pack $dlg.games -side top -fill both -expand yes -padx 6 -pady 6

		ttk::button $dlg.controls.refresh \
			-text $mc::RepertoireRefresh \
			-command [namespace code [list RefreshRepertoireReport $dlg]]
		ttk::button $dlg.controls.prep \
			-text $mc::RepertoireOpenPrep \
			-command [namespace code [list OpenOpeningPrepReport $dlg $file $variant]]
		ttk::button $dlg.controls.search \
			-text $mc::RepertoireOpenSearch \
			-command [namespace code [list OpenAdvancedSearch $dlg $file $variant]]
		ttk::button $dlg.controls.switcher \
			-text $mc::RepertoireOpenInSwitcher \
			-command [namespace code [list OpenRepertoireResultsInSwitcher $dlg]]
		ttk::button $dlg.controls.savews \
			-text $mc::SaveWorkingSet \
			-command [namespace code [list SaveRepertoireWorkingSet $dlg]]
		ttk::button $dlg.controls.openEco \
			-text $mc::RepertoireOpenSelectedEco \
			-command [namespace code [list OpenSelectedRepertoireEco $dlg]]
		ttk::button $dlg.controls.clearEco \
			-text $mc::RepertoireClearEcoFilter \
			-command [namespace code [list FilterRepertoireByEco $dlg]]
		ttk::button $dlg.controls.close \
			-text $mc::Close \
			-command [list destroy $dlg]
		pack $dlg.controls.close -side right
		pack $dlg.controls.savews -side right -padx {0 6}
		pack $dlg.controls.clearEco -side right -padx {0 6}
		pack $dlg.controls.openEco -side right -padx {0 6}
		pack $dlg.controls.switcher -side right -padx {0 6}
		pack $dlg.controls.search -side right -padx {0 6}
		pack $dlg.controls.prep -side right -padx {0 6}
		pack $dlg.controls.refresh -side right -padx {0 6}

		foreach {row col key label} {
			0 0 type $mc::RepertoireType
			0 2 games $mc::RepertoireGames
			1 0 deleted $mc::RepertoireDeleted
			1 2 status $mc::RepertoireStatus
			2 0 topOpening $mc::RepertoireTopOpening
			2 2 coverage $mc::RepertoireCoverage
		} {
			ttk::label $dlg.summary.l_$key -text $label
			ttk::label $dlg.summary.v_$key \
				-textvariable [namespace current]::RepertoireReportData($dlg,$key)
			grid $dlg.summary.l_$key -row $row -column $col -sticky w
			grid $dlg.summary.v_$key -row $row -column [expr {$col + 1}] -sticky w -padx {6 18}
		}

		set tree [ttk::treeview $dlg.openings.tree \
			-columns {eco count white draw black} \
			-show headings \
			-height 8]
		$tree heading eco -text ECO
		$tree heading count -text Count
		$tree heading white -text White
		$tree heading draw -text Draw
		$tree heading black -text Black
		$tree column eco -anchor w -width 70 -stretch 0
		$tree column count -anchor e -width 80 -stretch 0
		$tree column white -anchor e -width 70 -stretch 0
		$tree column draw -anchor e -width 70 -stretch 0
		$tree column black -anchor e -width 70 -stretch 0
		pack $tree -fill both -expand yes
		set RepertoireReportData($dlg,openingsTree) $tree
		bind $tree <Double-1> [namespace code [list OpenSelectedRepertoireEco $dlg]]

		ttk::label $dlg.games.status \
			-textvariable [namespace current]::RepertoireReportData($dlg,recentStatus)
		pack $dlg.games.status -side top -anchor w

		set RepertoireReportData($dlg,scrolledTable) $dlg.games.table
		set RepertoireReportData($dlg,table) [::gamestable::build \
			$RepertoireReportData($dlg,scrolledTable) \
			[namespace code [list RepertoireReportView $dlg]] \
			{number white black result event date eco material} \
			-id db:repertoire-report:[string map {. _} $dlg] \
			-mode list]

		bind $dlg <Destroy> [namespace code [list CloseRepertoireReport %W]]

		wm minsize $dlg 900 560
		::util::place $dlg -parent [winfo toplevel $parent] -position center
		wm deiconify $dlg
	} else {
		raise $dlg
	}

	wm deiconify $dlg
	raise $dlg
	focus $dlg
	RefreshRepertoireReport $dlg
}


proc repertoireBases {{discardActualBase 0} {variant {}}} {
	variable ::scidb::clipbaseName

	set actual [::scidb::db::get name]
	if {$variant eq {}} {
		set variant [::scidb::game::query Variant?]
	}
	set result {}

	foreach base [::scidb::tree::list] {
		if {$discardActualBase && $base eq $actual} { continue }
		if {[::scidb::db::get readonly? $base]} { continue }
		if {$variant ni [::scidb::db::get variants $base]} { continue }

		set type [::scidb::db::get type $base]
		if {$type ni {Openings OpeningsWhite OpeningsBlack}} { continue }

		lappend result $base
	}

	return [lsort -dictionary $result]
}


proc showNoRepertoireBases {parent} {
	variable mc

	::dialog::info \
		-parent $parent \
		-message $mc::NoRepertoireBases \
		-detail $mc::NoRepertoireBasesDetail
}



proc addRepertoireDestinationsForSaveToMenu {parent m {discardActualBase 0} {variant {}}} {
	set result [repertoireBases $discardActualBase $variant]

	foreach base $result {
		$m add command \
			-label [::util::databaseName $base] \
			-command [list ::application::pgn::saveGame add $base]
	}

	if {[llength $result] == 0} {
		$m add command \
			-label " $::gamebar::mc::NoRepertoireBases" \
			-command [namespace code [list showNoRepertoireBases $parent]] \
			-state normal
	}

	return [llength $result]
}


proc findTemporaryPosition {} {
	set first [expr {$::game::MaxPosition + 1}]
	set last [expr {$first + 15}]

	for {set pos $first} {$pos <= $last} {incr pos} {
		if {![::scidb::game::query $pos open?]} {
			return $pos
		}
	}

	return -1
}


proc saveCurrentLineToRepertoire {parent base} {

	set position [::scidb::game::current]
	set temp [findTemporaryPosition]

	if {$temp < 0} {
		::dialog::info \
			-parent $parent \
			-message $mc::NoTemporarySlot \
			-detail $mc::NoTemporarySlotDetail
		return
	}

	set rc [catch {
		::scidb::tree::freeze 1
		::scidb::game::duplicate $temp $position modified
		::scidb::game::switch $temp
		::scidb::game::strip truncate
		::application::pgn::saveGame add $base
	} result options]

	catch {
		if {[::scidb::game::query $temp open?]} {
			::scidb::game::release $temp
		}
	}
	catch { ::scidb::game::switch $position }
	catch { ::scidb::tree::freeze 0 }

	if {$rc} {
		return -options $options $result
	}
}


proc addRepertoireLineDestinationsForSaveToMenu {parent m {discardActualBase 0} {variant {}}} {
	set result [repertoireBases $discardActualBase $variant]

	foreach base $result {
		$m add command \
			-label [::util::databaseName $base] \
			-command [namespace code [list ::widget::busyOperation [list saveCurrentLineToRepertoire $parent $base]]]
	}

	if {[llength $result] == 0} {
		$m add command \
			-label " $::gamebar::mc::NoRepertoireBases" \
			-command [namespace code [list showNoRepertoireBases $parent]] \
			-state normal
	}

	return [llength $result]
}


proc addRepertoireGameEntry {parent m {discardActualBase 0} {variant {}}} {
	variable mc

	set bases [repertoireBases $discardActualBase $variant]

	if {[llength $bases] == 1} {
		set base [lindex $bases 0]
		$m add command \
			-label " [format $mc::AddToRepertoireBase [::util::databaseName $base]]" \
			-image $::icon::16x16::saveAs \
			-compound left \
			-command [list ::application::pgn::saveGame add $base]
		return 1
	}

	menu $m.repertoire
	addRepertoireDestinationsForSaveToMenu $parent $m.repertoire $discardActualBase $variant
	$m add cascade \
		-menu $m.repertoire \
		-label " $mc::AddToRepertoire" \
		-image $::icon::16x16::saveAs \
		-compound left \
		-state normal
	return [llength $bases]
}


proc addRepertoireLineEntry {parent m {discardActualBase 0} {variant {}}} {
	variable mc

	set bases [repertoireBases $discardActualBase $variant]

	if {[llength $bases] == 1} {
		set base [lindex $bases 0]
		$m add command \
			-label " [format $mc::AddLineToRepertoireBase [::util::databaseName $base]]" \
			-image $::icon::16x16::saveAs \
			-compound left \
			-command [namespace code [list ::widget::busyOperation [list saveCurrentLineToRepertoire $parent $base]]]
		return 1
	}

	menu $m.repertoireLine
	addRepertoireLineDestinationsForSaveToMenu $parent $m.repertoireLine $discardActualBase $variant
	$m add cascade \
		-menu $m.repertoireLine \
		-label " $mc::AddLineToRepertoire" \
		-image $::icon::16x16::saveAs \
		-compound left \
		-state normal
	return [llength $bases]
}



} ;# namespace database
} ;# namespace application

# vi:set ts=3 sw=3:
