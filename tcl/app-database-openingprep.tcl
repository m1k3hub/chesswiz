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
# Copyright: (C) 2026 Michael Thomas (Chesswiz)
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

::util::source database-openingprep

namespace eval application {
namespace eval database {
namespace eval mc {
set PreferScidbTitle				"Convert '%s' to .sci?"
set PreferScidbMessage				"This workflow is optimized for Scidb databases (.sci)."
set PreferScidbDetail				"For best speed on large databases, convert '%s' to .sci before using %s. You can continue with the current format, but it may be slow."
set ContinueAnyway					"Continue"
set ConvertNow						"Convert Now"

set OpeningPrepTitle				"Opening Prep for '%s'"
set OpeningPrepSearching			"Searching reference moves for the current position..."
set OpeningPrepNoMoves				"No moves found for the current position."
set OpeningPrepUnsupported			"Opening prep is currently available only for the normal chess variant."
set OpeningPrepRefresh				"Refresh"
set OpeningPrepPlayMove				"Play Selected Move"
set OpeningPrepLoadGame				"Load First Game"
set OpeningPrepOpenEco				"ECO Stats"
set OpeningPrepOpenInSwitcher		"Open Selected ECO Games In Switcher"
set OpeningPrepSaveWorkingSet		"Save Selected ECO Games Working Set..."
set OpeningPrepMethod				"Method"
set OpeningPrepRareOnly				"Low-frequency moves only"
set OpeningPrepRareLimit			"Max games"
set OpeningPrepRareNoMoves			"No low-frequency moves found for the current position."
set OpeningPrepRareSummary			"Low-frequency moves: %s candidate moves, %s games, top move %s"
set OpeningPrepRareStatus			"Showing moves with %s games or fewer."
set OpeningPrepNarrate			"Narrate"
set OpeningPrepSummaryNone			"Current position: no move statistics loaded"
set OpeningPrepSummary				"Current position: %s candidate moves, %s games, top move %s"
set OpeningPrepRefBase				"Reference database"
set OpeningPrepPosition				"Position"
set OpeningPrepStatus				"Status"
set OpeningPrepColMove				"Move"
set OpeningPrepColEco				"ECO"
set OpeningPrepColFreq			"Games"
set OpeningPrepColScore				"Score"
set OpeningPrepColDraws			"Draw %"
set OpeningPrepColResult			"Result"
set OpeningPrepColAvgRating		"Avg %s"
set OpeningPrepColLastYear			"Last"
set OpeningPrepColBestPlayer		"Best Player"
set OpeningPrepNoSelection			"No move is selected."

} ;# namespace mc

array set NonSciWorkflowAdvice {}

proc IsSciWorkingFormat {file} {
	return [expr {[file extension $file] eq ".sci" || $file eq $::scidb::clipbaseName}]
}


proc ConvertDatabaseToScidb {parent file variant} {
	set name [::util::databaseName $file]
	::export::open $parent \
		-base $file \
		-variant $variant \
		-extension [string trimleft [file extension $file] .] \
		-name $name \
		-view 0 \
		-type scidb
}


proc RecommendSciWorkflow {parent file variant featureLabel featureKey} {
	variable NonSciWorkflowAdvice
	variable mc

	if {[IsSciWorkingFormat $file]} { return 1 }

	set key "$file:$variant:$featureKey"
	if {[info exists NonSciWorkflowAdvice($key)]} { return 1 }

	set name [::util::databaseName $file]
	set reply [::dialog::question \
		-parent $parent \
		-title [format $mc::PreferScidbTitle $name] \
		-message $mc::PreferScidbMessage \
		-detail [format $mc::PreferScidbDetail $name $featureLabel] \
		-buttons [list [list convert $mc::ConvertNow] [list continue $mc::ContinueAnyway] cancel] \
		-default continue]

	switch $reply {
		convert {
			ConvertDatabaseToScidb $parent $file $variant
			return 0
		}
		continue {
			set NonSciWorkflowAdvice($key) 1
			return 1
		}
		default {
			return 0
		}
	}
}


proc OpeningPrepDialogName {file variant} {
	return .openingprep_[string map {: _ . _ / _ " " _} $file]_${variant}
}


proc OpeningPrepMethodLabel {mode} {
	switch -- $mode {
		fast { return $::application::tree::mc::UseFastMode }
		quick { return $::application::tree::mc::UseQuickMode }
		default { return $::application::tree::mc::UseExactMode }
	}
}


proc OpeningPrepMethodFromLabel {label} {
	switch -- $label {
		$::application::tree::mc::UseFastMode { return fast }
		$::application::tree::mc::UseQuickMode { return quick }
		default { return exact }
	}
}


proc OpeningPrepSortValue {value kind} {
	switch -- $kind {
		int {
			if {[string is integer -strict $value]} { return $value }
			return -1
		}
		default {
			return [string tolower $value]
		}
	}
}


proc PopulateOpeningPrepTable {dlg rows} {
	variable OpeningPrepData

	set tv $OpeningPrepData($dlg,tv)
	$tv delete [$tv children {}]

	foreach row $rows {
		set sourceRow [dict get $row row]
		set move [dict get $row move]
		set eco [dict get $row eco]
		set frequency [dict get $row frequency]
		set score [dict get $row score]
		set draws [dict get $row draws]
		set result [dict get $row result]
		set averageRating [dict get $row averageRating]
		set lastYear [dict get $row lastYear]
		set bestPlayerName [dict get $row bestPlayer]
		set identity [dict get $row identity]

		$tv insert {} end -id row$sourceRow -values [list \
			$sourceRow \
			$identity \
			$move \
			$eco \
			$frequency \
			[format %.1f [expr {$score/10.0}]] \
			[format %.1f [expr {$draws/10.0}]] \
			$result \
			$averageRating \
			$lastYear \
			$bestPlayerName]
	}
}


proc OpeningPrepRareLimitValue {dlg} {
	variable OpeningPrepData

	set limit [string trim $OpeningPrepData($dlg,rareLimit)]
	if {![string is integer -strict $limit] || $limit < 1} {
		set limit 3
	}
	if {$limit > 9999} {
		set limit 9999
	}
	set OpeningPrepData($dlg,rareLimit) $limit
	return $limit
}


proc OpeningPrepFilteredRows {dlg rows} {
	variable OpeningPrepData

	if {!$OpeningPrepData($dlg,rareOnly)} {
		return $rows
	}

	set limit [OpeningPrepRareLimitValue $dlg]
	set filtered {}
	foreach row $rows {
		if {[dict get $row frequency] <= $limit} {
			lappend filtered $row
		}
	}
	return $filtered
}


proc UpdateOpeningPrepDisplay {dlg} {
	variable OpeningPrepData
	variable mc

	if {![winfo exists $dlg]} { return }

	if {![info exists OpeningPrepData($dlg,data)] || [llength $OpeningPrepData($dlg,data)] == 0} {
		set OpeningPrepData($dlg,summary) $mc::OpeningPrepSummaryNone
		PopulateOpeningPrepTable $dlg {}
		return
	}

	set rows [OpeningPrepFilteredRows $dlg $OpeningPrepData($dlg,data)]
	if {[llength $rows] == 0} {
		if {$OpeningPrepData($dlg,rareOnly)} {
			set OpeningPrepData($dlg,summary) $mc::OpeningPrepRareNoMoves
			set OpeningPrepData($dlg,status) [format $mc::OpeningPrepRareStatus [OpeningPrepRareLimitValue $dlg]]
		} else {
			set OpeningPrepData($dlg,summary) $mc::OpeningPrepSummaryNone
			set OpeningPrepData($dlg,status) $mc::OpeningPrepNoMoves
		}
		PopulateOpeningPrepTable $dlg {}
		return
	}

	set totalGames 0
	foreach row $rows {
		incr totalGames [dict get $row frequency]
	}
	set topMove [dict get [lindex $rows 0] move]
	if {$OpeningPrepData($dlg,rareOnly)} {
		set OpeningPrepData($dlg,summary) [format \
			$mc::OpeningPrepRareSummary \
			[::locale::formatNumber [llength $rows]] \
			[::locale::formatNumber $totalGames] \
			$topMove]
		set OpeningPrepData($dlg,status) [format $mc::OpeningPrepRareStatus [OpeningPrepRareLimitValue $dlg]]
	} else {
		set OpeningPrepData($dlg,summary) [format \
			$mc::OpeningPrepSummary \
			[::locale::formatNumber [llength $rows]] \
			[::locale::formatNumber $totalGames] \
			$topMove]
		set OpeningPrepData($dlg,status) ""
	}
	PopulateOpeningPrepTable $dlg $rows
}


# Audit B3: the table as a grounded, read-only narrative (ai-openingprep).
proc OpeningPrepNarrate {dlg} {
	variable OpeningPrepData

	if {![winfo exists $dlg] || [llength [info commands ::ai::openingprep::narrate]] == 0} { return }
	if {![info exists OpeningPrepData($dlg,data)] || [llength $OpeningPrepData($dlg,data)] == 0} { return }

	set rows [OpeningPrepFilteredRows $dlg $OpeningPrepData($dlg,data)]
	set facts [::ai::openingprep::facts $OpeningPrepData($dlg,positionText) $rows]
	::ai::openingprep::narrate $dlg $facts
}


proc FinishOpeningPrepReport {dlg} {
	variable OpeningPrepData
	variable mc

	if {![winfo exists $dlg]} { return }

	set method [OpeningPrepMethodFromLabel $OpeningPrepData($dlg,methodLabel)]
	set state [::scidb::tree::finish $OpeningPrepData($dlg,ratingType) $method 0 -sort 2]
	if {$state eq "null"} {
		return 0
	}

	set data [::scidb::tree::describe]
	set OpeningPrepData($dlg,data) $data
	set fen [::scidb::tree::position]
	set OpeningPrepData($dlg,positionText) $fen

	if {[llength $data] == 0} {
		set OpeningPrepData($dlg,summary) $mc::OpeningPrepSummaryNone
		set OpeningPrepData($dlg,status) $mc::OpeningPrepNoMoves
		PopulateOpeningPrepTable $dlg {}
		return 1
	}

	UpdateOpeningPrepDisplay $dlg
	return 1
}


proc PollOpeningPrepReport {dlg} {
	variable OpeningPrepData

	if {![winfo exists $dlg]} { return }

	::scidb::tree::set $OpeningPrepData($dlg,file)
	if {[::scidb::tree::update \
			$OpeningPrepData($dlg,ratingType) \
			[OpeningPrepMethodFromLabel $OpeningPrepData($dlg,methodLabel)] \
			0]} {
		FinishOpeningPrepReport $dlg
		return
	}

	set OpeningPrepData($dlg,poll) [after 250 [namespace code [list PollOpeningPrepReport $dlg]]]
}


proc RefreshOpeningPrepReport {dlg} {
	variable OpeningPrepData
	variable mc

	if {![winfo exists $dlg]} { return }

	if {[::scidb::game::query mainvariant?] ne "Normal"} {
		set OpeningPrepData($dlg,status) $mc::OpeningPrepUnsupported
		return
	}

	catch { after cancel $OpeningPrepData($dlg,poll) }
	::scidb::tree::set $OpeningPrepData($dlg,file)
	set OpeningPrepData($dlg,status) $mc::OpeningPrepSearching
	set OpeningPrepData($dlg,positionText) [::scidb::tree::position]
	$OpeningPrepData($dlg,tv) heading averageRating -text [format $mc::OpeningPrepColAvgRating $OpeningPrepData($dlg,ratingType)]

	if {[::scidb::tree::update \
			$OpeningPrepData($dlg,ratingType) \
			[OpeningPrepMethodFromLabel $OpeningPrepData($dlg,methodLabel)] \
			0]} {
		FinishOpeningPrepReport $dlg
	} else {
		set OpeningPrepData($dlg,poll) [after 250 [namespace code [list PollOpeningPrepReport $dlg]]]
	}
}


proc OpeningPrepSelectedRow {dlg} {
	variable OpeningPrepData
	variable mc

	set sel [$OpeningPrepData($dlg,tv) selection]
	if {[llength $sel] == 0} {
		::dialog::info -parent $dlg -message $mc::OpeningPrepNoSelection
		return -1
	}
	return [lindex [$OpeningPrepData($dlg,tv) item [lindex $sel 0] -values] 0]
}


proc OpeningPrepSelectedIdentity {dlg} {
	variable OpeningPrepData

	set row [OpeningPrepSelectedRow $dlg]
	if {$row < 0} { return {} }

	return [lindex [$OpeningPrepData($dlg,tv) item row$row -values] 1]
}


proc OpeningPrepSelectedEco {dlg} {
	variable OpeningPrepData

	set row [OpeningPrepSelectedRow $dlg]
	if {$row < 0} { return {} }

	set values [$OpeningPrepData($dlg,tv) item row$row -values]
	if {[llength $values] < 4} { return {} }
	return [lindex $values 3]
}


proc OpeningPrepSourceView {dlg} {
	variable OpeningPrepData

	set treeView [::scidb::tree::view]
	if {$treeView >= 0
		&& [::scidb::tree::isRefBase? $OpeningPrepData($dlg,file)]} {
		return $treeView
	}

	return 0
}


proc ApplyOpeningPrepTreeFilter {dlg view row identity eco} {
	variable OpeningPrepData

	if {$identity ne {}} {
		set rc [catch {
			::scidb::view::setTreeFilter \
				$OpeningPrepData($dlg,file) \
				$OpeningPrepData($dlg,variant) \
				$view \
				-identity $identity
		} result options]
		if {$rc == 0} {
			return $result
		}
	}

	if {$eco ne {}} {
		return [::scidb::view::search \
			$OpeningPrepData($dlg,file) \
			$OpeningPrepData($dlg,variant) \
			$view \
			null \
			none \
			[list eco $eco]]
	}

	return -code error "unable to apply opening prep selection to view $view"
}


proc OpenOpeningPrepEcoInSwitcher {dlg} {
	variable OpeningPrepData

	set eco [OpeningPrepSelectedEco $dlg]
	set identity [OpeningPrepSelectedIdentity $dlg]
	if {$eco eq {} && $identity eq {}} { return 0 }
	set row [OpeningPrepSelectedRow $dlg]
	if {$row < 0} { return 0 }

	set sourceView [OpeningPrepSourceView $dlg]
	set view [::scidb::view::new \
		$OpeningPrepData($dlg,file) \
		$OpeningPrepData($dlg,variant) \
		unused unused unused unused master slave]

	set rc [catch {
		if {$sourceView == [::scidb::tree::view]
			&& [::scidb::tree::isRefBase? $OpeningPrepData($dlg,file)]} {
			ApplyOpeningPrepTreeFilter $dlg $view $row $identity $eco
		} else {
			::scidb::view::copy \
				$OpeningPrepData($dlg,file) \
				$OpeningPrepData($dlg,variant) \
				$sourceView \
				$view
			if {$identity ne {}} {
				ApplyOpeningPrepTreeFilter $dlg $view $row $identity $eco
			} else {
				::scidb::view::search $OpeningPrepData($dlg,file) $OpeningPrepData($dlg,variant) $view null none [list eco $eco]
			}
		}
		OpenFilteredViewInSwitcher \
			$dlg \
			$OpeningPrepData($dlg,file) \
			$OpeningPrepData($dlg,variant) \
			$view \
			opening-prep \
			[expr {$identity ne {} ? "row-$row" : "eco-$eco"}]
	} result options]
	catch { ::scidb::view::close $OpeningPrepData($dlg,file) $OpeningPrepData($dlg,variant) $view }
	return -options $options $result
}


proc SaveOpeningPrepEcoWorkingSet {dlg} {
	variable OpeningPrepData

	set eco [OpeningPrepSelectedEco $dlg]
	set identity [OpeningPrepSelectedIdentity $dlg]
	if {$eco eq {} && $identity eq {}} { return 0 }
	set row [OpeningPrepSelectedRow $dlg]
	if {$row < 0} { return 0 }

	set sourceView [OpeningPrepSourceView $dlg]
	set view [::scidb::view::new \
		$OpeningPrepData($dlg,file) \
		$OpeningPrepData($dlg,variant) \
		unused unused unused unused master slave]

	set rc [catch {
		if {$sourceView == [::scidb::tree::view]
			&& [::scidb::tree::isRefBase? $OpeningPrepData($dlg,file)]} {
			ApplyOpeningPrepTreeFilter $dlg $view $row $identity $eco
		} else {
			::scidb::view::copy \
				$OpeningPrepData($dlg,file) \
				$OpeningPrepData($dlg,variant) \
				$sourceView \
				$view
			if {$identity ne {}} {
				ApplyOpeningPrepTreeFilter $dlg $view $row $identity $eco
			} else {
				::scidb::view::search $OpeningPrepData($dlg,file) $OpeningPrepData($dlg,variant) $view null none [list eco $eco]
			}
		}
		SaveFilteredViewAsWorkingSet \
			$dlg \
			$OpeningPrepData($dlg,file) \
			$OpeningPrepData($dlg,variant) \
			$view \
			opening-prep \
			[expr {$identity ne {} ? "row-$row" : "eco-$eco"}]
	} result options]
	catch { ::scidb::view::close $OpeningPrepData($dlg,file) $OpeningPrepData($dlg,variant) $view }
	return -options $options $result
}


proc OpeningPrepPlaySelectedMove {dlg} {
	set row [OpeningPrepSelectedRow $dlg]
	if {$row < 0} { return }
	set move [::scidb::tree::move $row]
	if {[string length $move]} {
		set action append
		if {![::scidb::game::position atEnd?]} {
			set action variation
		}
		::move::doAction $action $move
	}
}


# Report row numbers belong to the report's captured tree position.
proc OpeningPrepAnalyzeSelectedMove {dlg} {
	variable OpeningPrepData
	set row [OpeningPrepSelectedRow $dlg]
	if {$row < 0} { return }
	if {$OpeningPrepData($dlg,positionText) ne [::scidb::pos::fen]} {
		::dialog::info -parent $dlg -message "The board position changed. Refresh the opening report first."
		return
	}
	# Use the captured move, rather than a row index in a possibly re-sorted tree.
	set values [$OpeningPrepData($dlg,tv) item row$row -values]
	set move [lindex $values 2]
	if {$move eq "" || ![::scidb::game::valid? $move]} { return }
	::move::addMove menu $move
	::application::analysis::AnalyzeCurrentPosition
}


proc OpeningPrepLoadSelectedGame {dlg} {
	variable OpeningPrepData

	set row [OpeningPrepSelectedRow $dlg]
	if {$row < 0} { return }
	set move [::scidb::tree::move $row]
	if {![string length $move]} { return }
	set index [::scidb::tree::gameIndex $row]
	set fen [::scidb::tree::position $move]
	::game::new $dlg \
		-base $OpeningPrepData($dlg,file) \
		-variant $OpeningPrepData($dlg,variant) \
		-view [::scidb::tree::view] \
		-number $index \
		-fen $fen
}


proc CloseOpeningPrepReport {dlg} {
	variable OpeningPrepData

	if {![string match .openingprep_* $dlg]} { return }
	catch { after cancel $OpeningPrepData($dlg,poll) }
	if {[info exists OpeningPrepData($dlg,restoreBase)]} {
		catch { ::scidb::tree::set $OpeningPrepData($dlg,restoreBase) }
	}
	foreach key [array names OpeningPrepData $dlg,*] {
		unset OpeningPrepData($key)
	}
}


proc OpenOpeningPrepReport {parent file variant} {
	variable OpeningPrepData
	variable mc

	if {![RecommendSciWorkflow $parent $file $variant $mc::EcoStats openingprep]} {
		return
	}

	set dlg [OpeningPrepDialogName $file $variant]

	if {![winfo exists $dlg]} {
		set OpeningPrepData($dlg,file) $file
		set OpeningPrepData($dlg,fileLabel) [::util::databaseName $file]
		set OpeningPrepData($dlg,variant) $variant
		set OpeningPrepData($dlg,restoreBase) [::scidb::tree::get]
		set OpeningPrepData($dlg,methodLabel) [OpeningPrepMethodLabel exact]
		set OpeningPrepData($dlg,ratingType) Elo
		set OpeningPrepData($dlg,rareOnly) 0
		set OpeningPrepData($dlg,rareLimit) 3
		set OpeningPrepData($dlg,summary) $mc::OpeningPrepSummaryNone
		set OpeningPrepData($dlg,status) {}
		set OpeningPrepData($dlg,positionText) {}
		set OpeningPrepData($dlg,poll) {}
		set OpeningPrepData($dlg,data) {}

		toplevel $dlg -class Scidb
		wm transient $dlg [winfo toplevel $parent]
		wm protocol $dlg WM_DELETE_WINDOW [list destroy $dlg]
		wm title $dlg [format $mc::OpeningPrepTitle [::util::databaseName $file]]
		wm resizable $dlg true true

		set controls [ttk::frame $dlg.controls]
		set info [ttk::frame $dlg.info]
		set body [ttk::frame $dlg.body]
		pack $controls -side top -fill x -padx 6 -pady {6 2}
		pack $info -side top -fill x -padx 6 -pady {0 4}
		pack $body -side top -fill both -expand yes -padx 6 -pady {0 6}

		ttk::label $controls.methodLabel -text $mc::OpeningPrepMethod
		ttk::combobox $controls.method \
			-state readonly \
			-textvariable [namespace current]::OpeningPrepData($dlg,methodLabel) \
			-values [list \
				[OpeningPrepMethodLabel exact] \
				[OpeningPrepMethodLabel fast] \
				[OpeningPrepMethodLabel quick]] \
			-width 22
		ttk::label $controls.ratingLabel -text $mc::RatingType
		ttk::combobox $controls.rating \
			-state readonly \
			-textvariable [namespace current]::OpeningPrepData($dlg,ratingType) \
			-values $::ratingbox::ratings(all) \
			-width 10
		ttk::checkbutton $controls.rareOnly \
			-text $mc::OpeningPrepRareOnly \
			-variable [namespace current]::OpeningPrepData($dlg,rareOnly) \
			-command [namespace code [list UpdateOpeningPrepDisplay $dlg]]
		ttk::label $controls.rareLimitLabel -text $mc::OpeningPrepRareLimit
		ttk::spinbox $controls.rareLimit \
			-from 1 \
			-to 9999 \
			-width 5 \
			-textvariable [namespace current]::OpeningPrepData($dlg,rareLimit) \
			-command [namespace code [list UpdateOpeningPrepDisplay $dlg]]
		ttk::button $controls.refresh -text $mc::OpeningPrepRefresh \
			-command [namespace code [list RefreshOpeningPrepReport $dlg]]
		ttk::button $controls.play -text $mc::OpeningPrepPlayMove \
			-command [namespace code [list OpeningPrepPlaySelectedMove $dlg]]
		ttk::button $controls.analyze -text "Analyze this line" \
			-command [namespace code [list OpeningPrepAnalyzeSelectedMove $dlg]]
		ttk::button $controls.load -text $mc::OpeningPrepLoadGame \
			-command [namespace code [list OpeningPrepLoadSelectedGame $dlg]]
		ttk::button $controls.eco -text $mc::OpeningPrepOpenEco \
			-command [namespace code [list OpenMaintenanceReport $dlg $file $variant openings]]
		ttk::button $controls.switcher -text $mc::OpeningPrepOpenInSwitcher \
			-command [namespace code [list OpenOpeningPrepEcoInSwitcher $dlg]]
		ttk::button $controls.savews -text $mc::OpeningPrepSaveWorkingSet \
			-command [namespace code [list SaveOpeningPrepEcoWorkingSet $dlg]]
		ttk::button $controls.narrate -text $mc::OpeningPrepNarrate \
			-command [namespace code [list OpeningPrepNarrate $dlg]]
		ttk::button $controls.close -text $mc::Close -command [list destroy $dlg]

		grid $controls.methodLabel -row 0 -column 0 -sticky w
		grid $controls.method -row 0 -column 1 -sticky ew
		grid $controls.ratingLabel -row 0 -column 2 -sticky w -padx {8 0}
		grid $controls.rating -row 0 -column 3 -sticky ew
		grid $controls.rareOnly -row 0 -column 4 -sticky w -padx {8 0}
		grid $controls.rareLimitLabel -row 0 -column 5 -sticky w -padx {4 0}
		grid $controls.rareLimit -row 0 -column 6 -sticky ew
		grid $controls.refresh -row 0 -column 7 -sticky ew -padx {8 0}
		grid $controls.analyze -row 1 -column 8 -columnspan 2 -sticky ew -pady {4 0}
		grid $controls.play -row 0 -column 8 -sticky ew -padx {4 0}
		grid $controls.load -row 0 -column 9 -sticky ew -padx {4 0}
		grid $controls.eco -row 0 -column 10 -sticky ew -padx {4 0}
		grid $controls.switcher -row 0 -column 11 -sticky ew -padx {4 0}
		grid $controls.savews -row 0 -column 12 -sticky ew -padx {4 0}
		grid $controls.narrate -row 0 -column 13 -sticky ew -padx {4 0}
		grid $controls.close -row 0 -column 14 -sticky e -padx {4 0}
		grid columnconfigure $controls 1 -weight 1
		grid columnconfigure $controls 3 -weight 1
		grid columnconfigure $controls 6 -weight 1

		foreach {key label row} [list \
			refBase $mc::OpeningPrepRefBase 0 \
			position $mc::OpeningPrepPosition 1 \
			summary $mc::OpeningPrepSummaryNone 2 \
			status $mc::OpeningPrepStatus 3] {
			if {$key eq "summary"} {
				ttk::label $info.$key -textvariable [namespace current]::OpeningPrepData($dlg,summary) -anchor w
				grid $info.$key -row $row -column 0 -columnspan 2 -sticky ew -pady 1
			} else {
				ttk::label $info.l_$key -text $label
				set varName [expr {$key eq "refBase" ? "fileLabel" : ($key eq "position" ? "positionText" : "status")}]
				ttk::label $info.v_$key -textvariable [namespace current]::OpeningPrepData($dlg,$varName) -anchor w
				grid $info.l_$key -row $row -column 0 -sticky nw -padx {0 6} -pady 1
				grid $info.v_$key -row $row -column 1 -sticky ew -pady 1
			}
		}
		grid columnconfigure $info 1 -weight 1

		set tv [ttk::treeview $body.tv \
			-columns {row identity move eco frequency score draws result averageRating lastYear bestPlayer} \
			-displaycolumns {move eco frequency score draws result averageRating lastYear bestPlayer} \
			-show headings \
			-selectmode browse \
			-yscrollcommand [list $body.vsb set]]
		set OpeningPrepData($dlg,tv) $tv
		foreach {col label anchor width} [list \
			move $mc::OpeningPrepColMove w 90 \
			eco $mc::OpeningPrepColEco w 70 \
			frequency $mc::OpeningPrepColFreq e 80 \
			score $mc::OpeningPrepColScore e 70 \
			draws $mc::OpeningPrepColDraws e 70 \
			result $mc::OpeningPrepColResult w 120 \
			averageRating [format $mc::OpeningPrepColAvgRating Elo] e 90 \
			lastYear $mc::OpeningPrepColLastYear e 70 \
			bestPlayer $mc::OpeningPrepColBestPlayer w 180] {
			$tv heading $col -text $label
			$tv column $col -anchor $anchor -width $width
		}
		$tv column row -width 0 -stretch 0
		$tv column identity -width 0 -stretch 0
		ttk::scrollbar $body.vsb -orient vertical -command [list $tv yview]
		grid $tv -row 0 -column 0 -sticky nsew
		grid $body.vsb -row 0 -column 1 -sticky ns
		grid rowconfigure $body 0 -weight 1
		grid columnconfigure $body 0 -weight 1

		bind $controls.method <<ComboboxSelected>> [namespace code [list RefreshOpeningPrepReport $dlg]]
		bind $controls.rating <<ComboboxSelected>> [namespace code [list RefreshOpeningPrepReport $dlg]]
		bind $controls.rareLimit <Return> [namespace code [list UpdateOpeningPrepDisplay $dlg]]
		bind $controls.rareLimit <FocusOut> [namespace code [list UpdateOpeningPrepDisplay $dlg]]
		bind $tv <Double-1> [namespace code [list OpeningPrepLoadSelectedGame $dlg]]
		bind $dlg <Destroy> [namespace code [list CloseOpeningPrepReport %W]]
		wm minsize $dlg 880 380
		::util::place $dlg -parent [winfo toplevel $parent] -position center
	}

	raise $dlg
	focus $OpeningPrepData($dlg,tv)
	RefreshOpeningPrepReport $dlg
}


} ;# namespace database
} ;# namespace application

# vi:set ts=3 sw=3:
