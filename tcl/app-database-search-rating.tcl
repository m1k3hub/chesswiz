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

::util::source database-search-rating

namespace eval application {
namespace eval database {
array set RatingSearchPresets {}

proc RatingModeLabel {mode} {
	variable mc

	switch -- $mode {
		black { return $mc::RatingModeBlack }
		average { return $mc::RatingModeAverage }
		both { return $mc::RatingModeBoth }
		default { return $mc::RatingModeWhite }
	}
}


proc RatingModeFromLabel {label} {
	variable mc

	switch -- $label {
		$mc::RatingModeBlack { return black }
		$mc::RatingModeAverage { return average }
		$mc::RatingModeBoth { return both }
		default { return white }
	}
}


proc UpdateRatingSearchHelp {dlg} {
	variable RatingSearchData
	variable mc

	switch -- $RatingSearchData($dlg,mode) {
		average { set RatingSearchData($dlg,help) $mc::RatingExampleAverage }
		both { set RatingSearchData($dlg,help) $mc::RatingExampleBoth }
		default { set RatingSearchData($dlg,help) $mc::RatingExample }
	}
}


proc SetRatingSearchMode {dlg mode} {
	variable RatingSearchData

	if {![info exists RatingSearchData($dlg,mode)]} { return }
	set RatingSearchData($dlg,mode) $mode
	set RatingSearchData($dlg,modeLabel) [RatingModeLabel $mode]
	UpdateRatingSearchHelp $dlg
}


proc SelectRatingSearchMode {dlg} {
	variable RatingSearchData

	SetRatingSearchMode $dlg [RatingModeFromLabel $RatingSearchData($dlg,modeLabel)]
}


proc RatingSearchView {dlg base variant} {
	variable RatingSearchData

	if {![info exists RatingSearchData($dlg,view)]} { return 0 }
	if {$base ne $RatingSearchData($dlg,file)} { return 0 }
	if {$variant ne $RatingSearchData($dlg,variant)} { return 0 }
	return $RatingSearchData($dlg,view)
}


proc RatingSessionKey {file variant} {
	return "$file:$variant"
}


proc SaveRatingSearchState {dlg {success {}}} {
	variable RatingSearchData
	variable RatingSearchState

	if {![info exists RatingSearchData($dlg,file)] || ![info exists RatingSearchData($dlg,variant)]} {
		return
	}

	set key [RatingSessionKey $RatingSearchData($dlg,file) $RatingSearchData($dlg,variant)]
	if {$success eq {}} {
		if {[info exists RatingSearchData($dlg,lastSuccess)]} {
			set success $RatingSearchData($dlg,lastSuccess)
		} else {
			set success 0
		}
	}

	set RatingSearchState($key) [dict create \
		mode $RatingSearchData($dlg,mode) \
		type $RatingSearchData($dlg,type) \
		rangeA $RatingSearchData($dlg,rangeA) \
		rangeB $RatingSearchData($dlg,rangeB) \
		querySummary $RatingSearchData($dlg,querySummary) \
		status $RatingSearchData($dlg,status) \
		lastSuccess $success]
}


proc RestoreRatingSearchState {dlg} {
	variable RatingSearchData
	variable RatingSearchState

	set key [RatingSessionKey $RatingSearchData($dlg,file) $RatingSearchData($dlg,variant)]
	if {![info exists RatingSearchState($key)]} {
		set RatingSearchData($dlg,lastSuccess) 0
		UpdateRatingSearchQuerySummary $dlg
		return 0
	}

	set state $RatingSearchState($key)
	set RatingSearchData($dlg,type) [dict get $state type]
	set RatingSearchData($dlg,rangeA) [dict get $state rangeA]
	set RatingSearchData($dlg,rangeB) [dict get $state rangeB]
	set RatingSearchData($dlg,status) [dict get $state status]
	set RatingSearchData($dlg,lastSuccess) [dict get $state lastSuccess]
	SetRatingSearchMode $dlg [dict get $state mode]
	UpdateRatingSearchQuerySummary $dlg
	return [dict get $state lastSuccess]
}


proc NormalizeRatingRange {value} {
	set value [string trim $value]
	if {![string length $value]} { error invalid }

	if {[string first - $value] < 0} {
		if {![string is integer -strict $value] || $value < 0 || $value > 4000} { error invalid }
		return $value
	}

	lassign [split $value -] low high
	if {![string length $low] || ![string length $high]} { error invalid }
	if {![string is integer -strict $low] || ![string is integer -strict $high]} { error invalid }
	if {$low < 0 || $high < 0 || $low > $high || $high > 4000} { error invalid }
	return "${low}-${high}"
}


proc UpdateRatingSearchStatus {dlg count} {
	variable RatingSearchData
	variable mc

	if {$count > 0} {
		set RatingSearchData($dlg,status) [format $mc::RatingResults [::locale::formatNumber $count]]
	} else {
		set RatingSearchData($dlg,status) $mc::RatingNoResults
	}
	SaveRatingSearchState $dlg
}


proc UpdateRatingSearchQuerySummary {dlg {rangeA {}} {rangeB {}}} {
	variable RatingSearchData
	variable mc

	if {![winfo exists $dlg]} { return }

	if {![string length $rangeA]} {
		set RatingSearchData($dlg,querySummary) $mc::RatingFilterNone
		wm title $dlg [format $mc::RatingSearchTitle [::util::databaseName $RatingSearchData($dlg,file)]]
		return
	}

	set type $RatingSearchData($dlg,type)
	switch -- $RatingSearchData($dlg,mode) {
		black {
			set summary [format $mc::RatingFilterBlack $type $rangeA]
		}
		average {
			set summary [format $mc::RatingFilterAverage $type $rangeA]
		}
		both {
			set summary [format $mc::RatingFilterBoth $type $rangeA $rangeB]
		}
		default {
			set summary [format $mc::RatingFilterWhite $type $rangeA]
		}
	}

	set RatingSearchData($dlg,querySummary) $summary
	wm title $dlg [format $mc::RatingSearchTitleActive [::util::databaseName $RatingSearchData($dlg,file)] $summary]
}


proc ResetRatingSearch {dlg} {
	variable RatingSearchData

	if {![winfo exists $dlg]} { return }
	set RatingSearchData($dlg,rangeA) {}
	set RatingSearchData($dlg,rangeB) {}
	set RatingSearchData($dlg,type) Elo
	SetRatingSearchMode $dlg white
	catch {
		::scidb::view::close \
			$RatingSearchData($dlg,file) \
			$RatingSearchData($dlg,variant) \
			$RatingSearchData($dlg,view)
	}
	set RatingSearchData($dlg,view) \
		[::scidb::view::new \
			$RatingSearchData($dlg,file) \
			$RatingSearchData($dlg,variant) \
			unused unused unused unused master slave]
	::gamestable::scroll $RatingSearchData($dlg,scrolledTable) home
	::gamestable::update \
		$RatingSearchData($dlg,scrolledTable) \
		$RatingSearchData($dlg,file) \
		$RatingSearchData($dlg,variant) \
		0
	UpdateRatingSearchQuerySummary $dlg
	UpdateRatingSearchStatus $dlg 0
	set RatingSearchData($dlg,lastSuccess) 0
	SaveRatingSearchState $dlg 0
	focus $dlg.controls.rangeA
}


proc RunRatingSearch {dlg} {
	variable RatingSearchData
	variable mc

	if {![winfo exists $dlg]} { return }

	set mode $RatingSearchData($dlg,mode)
	if {[catch {
		set rangeA [NormalizeRatingRange $RatingSearchData($dlg,rangeA)]
		if {$mode eq "both"} {
			set rangeB [NormalizeRatingRange $RatingSearchData($dlg,rangeB)]
			set query [list rating $RatingSearchData($dlg,type) both $rangeA $rangeB]
		} else {
			set rangeB {}
			set query [list rating $RatingSearchData($dlg,type) $mode $rangeA]
		}
	}]} {
		return [::dialog::error -parent $dlg -message $mc::RatingInvalid]
	}

	::widget::busyCursor on
	set rc [catch {
		::scidb::view::search \
			$RatingSearchData($dlg,file) \
			$RatingSearchData($dlg,variant) \
			$RatingSearchData($dlg,view) \
			null \
			none \
			$query
		set count [::scidb::view::count games \
			$RatingSearchData($dlg,file) \
			$RatingSearchData($dlg,variant) \
			$RatingSearchData($dlg,view)]
		::gamestable::scroll $RatingSearchData($dlg,scrolledTable) home
		::gamestable::update \
			$RatingSearchData($dlg,scrolledTable) \
			$RatingSearchData($dlg,file) \
			$RatingSearchData($dlg,variant) \
			$count
		UpdateRatingSearchQuerySummary $dlg $rangeA $rangeB
		UpdateRatingSearchStatus $dlg $count
		set RatingSearchData($dlg,lastSuccess) 1
		SaveRatingSearchState $dlg 1
	} result options]
	::widget::busyCursor off
	if {$rc} {
		return -options $options $result
	}
}


proc OpenRatingResultsInSwitcher {dlg} {
	variable RatingSearchData

	set rc [OpenFilteredViewInSwitcher \
		$dlg \
		$RatingSearchData($dlg,file) \
		$RatingSearchData($dlg,variant) \
		$RatingSearchData($dlg,view) \
		rating]
	if {$rc ne 0 && [winfo exists $dlg]} {
		destroy $dlg
	}
	return $rc
}


proc SaveRatingWorkingSet {dlg} {
	variable RatingSearchData

	set defaultName rating
	if {[info exists RatingSearchData($dlg,querySummary)]} {
		set summary $RatingSearchData($dlg,querySummary)
		if {$summary ne $mc::RatingFilterNone} {
			set defaultName $summary
		}
	}

	return [SaveFilteredViewAsWorkingSet \
		$dlg \
		$RatingSearchData($dlg,file) \
		$RatingSearchData($dlg,variant) \
		$RatingSearchData($dlg,view) \
		rating \
		$defaultName]
}


proc RatingPresetState {dlg} {
	variable RatingSearchData

	return [dict create \
		mode $RatingSearchData($dlg,mode) \
		type $RatingSearchData($dlg,type) \
		rangeA $RatingSearchData($dlg,rangeA) \
		rangeB $RatingSearchData($dlg,rangeB)]
}


proc ApplyRatingPresetState {dlg state} {
	variable RatingSearchData

	set RatingSearchData($dlg,type) [dict get $state type]
	set RatingSearchData($dlg,rangeA) [dict get $state rangeA]
	set RatingSearchData($dlg,rangeB) [dict get $state rangeB]
	SetRatingSearchMode $dlg [dict get $state mode]
	UpdateRatingSearchQuerySummary $dlg
}


proc SaveRatingPreset {dlg} {
	variable RatingSearchData
	variable mc

	set defaultName rating
	if {[info exists RatingSearchData($dlg,querySummary)]} {
		set summary $RatingSearchData($dlg,querySummary)
		if {$summary ne $mc::RatingFilterNone} {
			set defaultName $summary
		}
	}

	set name [SaveSearchPresetState \
		$dlg \
		[namespace current]::RatingSearchPresets \
		$defaultName \
		[RatingPresetState $dlg]]
	if {![string length $name]} { return 0 }
	set RatingSearchData($dlg,presetName) $name
	UpdateSearchPresetSelector \
		$dlg.controls.preset \
		[namespace current]::RatingSearchData($dlg,presetName) \
		[namespace current]::RatingSearchPresets
	return 1
}


proc LoadRatingPreset {dlg} {
	variable RatingSearchData
	variable RatingSearchPresets
	variable mc

	set name [string trim $RatingSearchData($dlg,presetName)]
	if {![string length $name] || ![info exists RatingSearchPresets($name)]} {
		return [::dialog::info -parent $dlg -message $mc::SearchPresetMissing]
	}

	ApplyRatingPresetState $dlg $RatingSearchPresets($name)
	RunRatingSearch $dlg
}


proc DeleteRatingPreset {dlg} {
	variable RatingSearchData

	set name [string trim $RatingSearchData($dlg,presetName)]
	if {![DeleteSearchPresetState $dlg [namespace current]::RatingSearchPresets $name]} {
		return 0
	}

	set RatingSearchData($dlg,presetName) {}
	UpdateSearchPresetSelector \
		$dlg.controls.preset \
		[namespace current]::RatingSearchData($dlg,presetName) \
		[namespace current]::RatingSearchPresets
	return 1
}


proc CloseRatingSearch {dlg} {
	variable RatingSearchData

	if {![string match .rating_* $dlg]} { return }
	if {[info exists RatingSearchData($dlg,view)]} {
		catch {
			::scidb::view::close \
				$RatingSearchData($dlg,file) \
				$RatingSearchData($dlg,variant) \
				$RatingSearchData($dlg,view)
		}
	}
	SaveRatingSearchState $dlg
	foreach key [array names RatingSearchData $dlg,*] {
		unset RatingSearchData($key)
	}
}


proc OpenRatingSearch {parent file variant} {
	variable RatingSearchData
	variable mc

	set dlg [RatingDialogName $file $variant]

	if {![winfo exists $dlg]} {
		set RatingSearchData($dlg,file) $file
		set RatingSearchData($dlg,variant) $variant
		set RatingSearchData($dlg,presetName) {}
		set RatingSearchData($dlg,mode) white
		set RatingSearchData($dlg,modeLabel) [RatingModeLabel white]
		set RatingSearchData($dlg,type) Elo
		set RatingSearchData($dlg,rangeA) {}
		set RatingSearchData($dlg,rangeB) {}
		set RatingSearchData($dlg,help) $mc::RatingExample
		set RatingSearchData($dlg,querySummary) $mc::RatingFilterNone
		set RatingSearchData($dlg,status) $mc::RatingNoResults
		set RatingSearchData($dlg,lastSuccess) 0
		set RatingSearchData($dlg,view) \
			[::scidb::view::new $file $variant unused unused unused unused master slave]

		tk::toplevel $dlg -class Scidb
		ttk::frame $dlg.controls
		ttk::frame $dlg.results
		pack $dlg.controls -side top -fill x
		pack $dlg.results -side top -fill both -expand yes

		ttk::label $dlg.controls.presetLabel -text $mc::SearchPreset
		ttk::combobox $dlg.controls.preset \
			-state readonly \
			-textvariable [namespace current]::RatingSearchData($dlg,presetName) \
			-values [SearchPresetNames [namespace current]::RatingSearchPresets] \
			-width 20
		ttk::label $dlg.controls.typeLabel -text $mc::RatingType
		ttk::combobox $dlg.controls.type \
			-state readonly \
			-textvariable [namespace current]::RatingSearchData($dlg,type) \
			-values $::ratingbox::ratings(all) \
			-width 10
		ttk::label $dlg.controls.modeLabel -text $mc::RatingMode
		ttk::combobox $dlg.controls.mode \
			-state readonly \
			-textvariable [namespace current]::RatingSearchData($dlg,modeLabel) \
			-values [list $mc::RatingModeWhite $mc::RatingModeBlack $mc::RatingModeAverage $mc::RatingModeBoth] \
			-width 16
		ttk::label $dlg.controls.rangeALabel -text $mc::RatingRangeA
		ttk::entry $dlg.controls.rangeA \
			-textvariable [namespace current]::RatingSearchData($dlg,rangeA) \
			-width 14
		ttk::label $dlg.controls.rangeBLabel -text $mc::RatingRangeB
		ttk::entry $dlg.controls.rangeB \
			-textvariable [namespace current]::RatingSearchData($dlg,rangeB) \
			-width 14
		ttk::button $dlg.controls.search \
			-text $mc::RatingSearchAction \
			-command [namespace code [list RunRatingSearch $dlg]]
		ttk::button $dlg.controls.savePreset \
			-text $mc::SaveSearchPreset \
			-command [namespace code [list SaveRatingPreset $dlg]]
		ttk::button $dlg.controls.loadPreset \
			-text $mc::LoadSearchPreset \
			-command [namespace code [list LoadRatingPreset $dlg]]
		ttk::button $dlg.controls.deletePreset \
			-text $mc::DeleteSearchPreset \
			-command [namespace code [list DeleteRatingPreset $dlg]]
		ttk::button $dlg.controls.reset \
			-text $mc::RatingReset \
			-command [namespace code [list ResetRatingSearch $dlg]]
		ttk::button $dlg.controls.switcher \
			-text $mc::RatingOpenInSwitcher \
			-command [namespace code [list OpenRatingResultsInSwitcher $dlg]]
		ttk::button $dlg.controls.savews \
			-text $mc::SaveWorkingSet \
			-command [namespace code [list SaveRatingWorkingSet $dlg]]
		ttk::button $dlg.controls.close \
			-text $mc::Close \
			-command [list destroy $dlg]
		ttk::label $dlg.controls.help \
			-textvariable [namespace current]::RatingSearchData($dlg,help)
		ttk::label $dlg.controls.query \
			-textvariable [namespace current]::RatingSearchData($dlg,querySummary)
		ttk::label $dlg.controls.status \
			-textvariable [namespace current]::RatingSearchData($dlg,status)

		grid $dlg.controls.presetLabel -row 0 -column 0 -sticky w
		grid $dlg.controls.preset -row 0 -column 1 -columnspan 2 -sticky ew
		grid $dlg.controls.savePreset -row 0 -column 3 -sticky ew
		grid $dlg.controls.loadPreset -row 0 -column 4 -sticky ew
		grid $dlg.controls.deletePreset -row 0 -column 5 -sticky ew
		grid $dlg.controls.typeLabel -row 1 -column 0 -sticky w
		grid $dlg.controls.type -row 1 -column 1 -sticky ew
		grid $dlg.controls.modeLabel -row 1 -column 2 -sticky w
		grid $dlg.controls.mode -row 1 -column 3 -sticky ew
		grid $dlg.controls.rangeALabel -row 1 -column 4 -sticky w
		grid $dlg.controls.rangeA -row 1 -column 5 -sticky ew
		grid $dlg.controls.rangeBLabel -row 1 -column 6 -sticky w
		grid $dlg.controls.rangeB -row 1 -column 7 -sticky ew
		grid $dlg.controls.search -row 1 -column 8 -sticky ew
		grid $dlg.controls.reset -row 1 -column 9 -sticky ew
		grid $dlg.controls.switcher -row 1 -column 10 -sticky ew
		grid $dlg.controls.savews -row 1 -column 11 -sticky ew
		grid $dlg.controls.close -row 1 -column 12 -sticky ew
		grid $dlg.controls.help -row 2 -column 0 -columnspan 13 -sticky w
		grid $dlg.controls.query -row 3 -column 0 -columnspan 13 -sticky w
		grid $dlg.controls.status -row 4 -column 0 -columnspan 13 -sticky w
		grid columnconfigure $dlg.controls 1 -weight 1
		grid columnconfigure $dlg.controls 2 -weight 1
		grid columnconfigure $dlg.controls 3 -weight 1
		grid columnconfigure $dlg.controls 5 -weight 1
		grid columnconfigure $dlg.controls 7 -weight 1

		set RatingSearchData($dlg,scrolledTable) $dlg.results.table
		set RatingSearchData($dlg,table) [::gamestable::build \
			$RatingSearchData($dlg,scrolledTable) \
			[namespace code [list RatingSearchView $dlg]] \
			{number white whiteElo black blackElo result event date eco} \
			-id db:rating-search:[string map {. _} $dlg] \
			-mode list]

		bind $dlg.controls.mode <<ComboboxSelected>> [namespace code [list SelectRatingSearchMode $dlg]]
		bind $dlg.controls.preset <<ComboboxSelected>> [namespace code [list LoadRatingPreset $dlg]]
		bind $dlg.controls.rangeA <Return> [namespace code [list RunRatingSearch $dlg]]
		bind $dlg.controls.rangeB <Return> [namespace code [list RunRatingSearch $dlg]]
		bind $dlg <Destroy> [namespace code [list CloseRatingSearch %W]]

		wm transient $dlg [winfo toplevel $parent]
		wm withdraw $dlg
		wm minsize $dlg 720 360
		::util::place $dlg -parent [winfo toplevel $parent] -position center
		wm deiconify $dlg
	} else {
		raise $dlg
	}

	UpdateRatingSearchHelp $dlg
	UpdateSearchPresetSelector \
		$dlg.controls.preset \
		[namespace current]::RatingSearchData($dlg,presetName) \
		[namespace current]::RatingSearchPresets
	if {[RestoreRatingSearchState $dlg]} {
		RunRatingSearch $dlg
	} else {
		UpdateRatingSearchQuerySummary $dlg
	}
	focus $dlg.controls.rangeA
}


} ;# namespace database
} ;# namespace application

# vi:set ts=3 sw=3:
