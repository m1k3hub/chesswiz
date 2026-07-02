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

::util::source database-search

namespace eval application {
namespace eval database {
namespace eval mc {
set AdvancedSearch					"Advanced Search"
set AdvancedSearchTitle			"Advanced Search for '%s'"
set AdvancedSearchTitleActive	"Advanced Search for '%s' \[%s\]"
set AdvancedPlayer					"Player"
set AdvancedPlayerMode			"Player side"
set AdvancedPlayerAny				"Any"
set AdvancedEvent					"Event"
set AdvancedSite					"Site"
set AdvancedAnnotator				"Annotator"
set AdvancedPosition				"Position ID"
set AdvancedUseCurrentPosition	"Use Start Position"
set AdvancedSearchHelp			"Combine any of these filters. Leave a field empty to ignore it. Use * and ? in name fields for wildcard matching, or prefix with = for an exact literal name match."
set AdvancedSearchAction			"Search"
set AdvancedReset					"Reset"
set AdvancedOpenInSwitcher		"Open In Switcher"
set SaveWorkingSet				"Save Working Set..."
set WorkingSetName				"Working set name:"
set WorkingSetSaved				"Saved %s filtered games as working set '%s'."
set SearchPreset					"Preset"
set SaveSearchPreset			"Save Preset..."
set LoadSearchPreset			"Load Preset"
set DeleteSearchPreset			"Delete Preset"
set SearchPresetName			"Preset name:"
set SearchPresetMissing			"Select a preset first."
set SearchPresetSaved			"Saved preset '%s'."
set SearchPresetDeleted			"Deleted preset '%s'."
set SearchPresetOverwrite		"Overwrite existing preset '%s'?"
set SearchPresetDelete			"Delete preset '%s'?"
set AdvancedInvalid				"Enter at least one valid search criterion."
set AdvancedResults				"%s matching games"
set AdvancedNoResults				"No matching games"
set AdvancedFilterNone			"Active filter: none"
set MaterialSearchTitle			"Material Search for '%s'"
set MaterialSearchTitleActive	"Material Search for '%s' \[%s\]"
set MaterialWhite					"White"
set MaterialBlack					"Black"
set MaterialExample				"Use Q/R/B/N letters plus pawn count, for example qrbn8 or 0."
set MaterialExampleClass			"Match the same major and minor piece totals as the entered material."
set MaterialExamplePawns			"Enter pawn counts or ranges such as 4, 5-7, or 0."
set MaterialSearchAction			"Search"
set MaterialReset					"Reset"
set MaterialOpenInSwitcher		"Open In Switcher"
set MaterialUseCurrent			"Use Current Game"
set MaterialUseSelected			"Use Selected Result"
set MaterialRefineExact			"Refine To Exact"
set MaterialRefineClass			"Refine To Majors/Minors"
set MaterialRefinePawns			"Refine To Pawn Range"
set MaterialMode					"Mode"
set MaterialModeExact				"Exact"
set MaterialModeClass				"Same majors/minors"
set MaterialModePawns				"Pawn count range"
set MaterialInvalid				"Invalid material signature. Use values such as qrbn8:qrbn8 or qrrb5:qn6."
set MaterialInvalidPawns			"Invalid pawn range. Use a number or a range such as 4-6."
set MaterialResults				"%s matching games"
set MaterialNoResults				"No matching games"
set MaterialFilterNone			"Active filter: none"
set MaterialFilterExact			"Active filter: exact %s:%s"
set MaterialFilterClass			"Active filter: same majors/minors as %s:%s"
set MaterialFilterPawns			"Active filter: pawns %s:%s"
set MaterialNoCurrentGame		"Current game is not linked to a database game with stored material."
set MaterialNoSelectedGame		"No result row is selected."
set RatingSearchTitle				"Rating Search for '%s'"
set RatingSearchTitleActive		"Rating Search for '%s' \[%s\]"
set RatingType						"Rating"
set RatingMode						"Mode"
set RatingRangeA					"Range"
set RatingRangeB					"Second Range"
set RatingModeWhite				"White"
set RatingModeBlack				"Black"
set RatingModeAverage				"Average"
set RatingModeBoth					"White and Black"
set RatingExample					"Enter a rating or range such as 2200 or 2000-2400."
set RatingExampleAverage			"Matches games whose average white/black rating falls in the entered range."
set RatingExampleBoth				"Enter one range for White and one range for Black."
set RatingSearchAction			"Search"
set RatingReset						"Reset"
set RatingOpenInSwitcher			"Open In Switcher"
set RatingInvalid					"Invalid rating range. Use a number or a range such as 2000-2400."
set RatingResults					"%s matching games"
set RatingNoResults				"No matching games"
set RatingFilterNone				"Active filter: none"
set RatingFilterWhite				"Active filter: %s white rating %s"
set RatingFilterBlack				"Active filter: %s black rating %s"
set RatingFilterAverage			"Active filter: %s average rating %s"
set RatingFilterBoth				"Active filter: %s white %s and black %s"
set SearchResultsOpened			"Opened %s filtered games in the switcher."
set SearchResultsEmpty			"No filtered games available to open in the switcher."

} ;# namespace mc

array set MaterialSearchPresets {}
array set RatingSearchPresets {}
array set AdvancedSearchPresets {}

proc MaterialDialogName {file variant} {
	return .material_[string map {: _ . _ / _} $file]_${variant}
}


proc NormalizeMaterialTerm {text} {
	set text [string tolower [string trim $text]]
	if {![string length $text]} { return -code error "empty" }
	if {$text eq "0"} { return $text }
	if {![regexp {^[qrbn0-9]+$} $text]} { return -code error "invalid" }
	return $text
}


proc NormalizePawnRange {text} {
	set text [string trim $text]
	if {![string length $text]} { return -code error "empty" }
	if {![regexp {^[0-9]+(?:-[0-9]+)?$} $text]} { return -code error "invalid" }

	if {[string first - $text] < 0} {
		if {$text > 15} { return -code error "invalid" }
		return $text
	}

	lassign [split $text -] low high
	if {$low > $high || $high > 15} { return -code error "invalid" }
	return $text
}


proc MaterialModeEntries {} {
	return [list \
		exact $mc::MaterialModeExact \
		class $mc::MaterialModeClass \
		pawns $mc::MaterialModePawns]
}


proc MaterialModeLabel {mode} {
	foreach {key label} [MaterialModeEntries] {
		if {$key eq $mode} { return $label }
	}
	return $mode
}


proc MaterialModeFromLabel {label} {
	foreach {key value} [MaterialModeEntries] {
		if {$value eq $label} { return $key }
	}
	return exact
}


proc CoerceMaterialField {text mode} {
	set text [string trim $text]

	if {$mode eq "pawns"} {
		set text [regsub -all {[^0-9-]} $text {}]
		return $text
	}

	if {[string first - $text] >= 0} {
		set text [lindex [split $text -] 0]
	}

	return [string tolower [string trim $text]]
}


proc SetMaterialSearchMode {dlg mode} {
	variable MaterialSearchData

	if {![winfo exists $dlg]} { return }
	if {![info exists MaterialSearchData($dlg,mode)]} { return }

	foreach side {white black} {
		set MaterialSearchData($dlg,$side) [CoerceMaterialField $MaterialSearchData($dlg,$side) $mode]
	}

	set MaterialSearchData($dlg,mode) $mode
	set MaterialSearchData($dlg,modeLabel) [MaterialModeLabel $mode]
	UpdateMaterialSearchHelp $dlg
}


proc SelectMaterialSearchMode {dlg} {
	variable MaterialSearchData

	SetMaterialSearchMode $dlg [MaterialModeFromLabel $MaterialSearchData($dlg,modeLabel)]
}


proc UpdateMaterialSearchHelp {dlg} {
	variable MaterialSearchData

	switch $MaterialSearchData($dlg,mode) {
		class { set MaterialSearchData($dlg,help) $mc::MaterialExampleClass }
		pawns { set MaterialSearchData($dlg,help) $mc::MaterialExamplePawns }
		default { set MaterialSearchData($dlg,help) $mc::MaterialExample }
	}
}


proc MaterialSearchView {dlg base variant} {
	variable MaterialSearchData

	if {![info exists MaterialSearchData($dlg,view)]} { return 0 }
	if {$base ne $MaterialSearchData($dlg,file)} { return 0 }
	if {$variant ne $MaterialSearchData($dlg,variant)} { return 0 }
	return $MaterialSearchData($dlg,view)
}


proc MaterialSessionKey {file variant} {
	return "$file:$variant"
}


proc SaveMaterialSearchState {dlg {success {}}} {
	variable MaterialSearchData
	variable MaterialSearchState

	if {![info exists MaterialSearchData($dlg,file)] || ![info exists MaterialSearchData($dlg,variant)]} {
		return
	}

	set key [MaterialSessionKey $MaterialSearchData($dlg,file) $MaterialSearchData($dlg,variant)]
	if {$success eq {}} {
		if {[info exists MaterialSearchData($dlg,lastSuccess)]} {
			set success $MaterialSearchData($dlg,lastSuccess)
		} else {
			set success 0
		}
	}

	set MaterialSearchState($key) [dict create \
		mode $MaterialSearchData($dlg,mode) \
		white $MaterialSearchData($dlg,white) \
		black $MaterialSearchData($dlg,black) \
		querySummary $MaterialSearchData($dlg,querySummary) \
		status $MaterialSearchData($dlg,status) \
		lastSuccess $success]
}


proc RestoreMaterialSearchState {dlg} {
	variable MaterialSearchData
	variable MaterialSearchState

	set key [MaterialSessionKey $MaterialSearchData($dlg,file) $MaterialSearchData($dlg,variant)]
	if {![info exists MaterialSearchState($key)]} {
		set MaterialSearchData($dlg,lastSuccess) 0
		UpdateMaterialSearchQuerySummary $dlg
		return 0
	}

	set state $MaterialSearchState($key)
	set MaterialSearchData($dlg,white) [dict get $state white]
	set MaterialSearchData($dlg,black) [dict get $state black]
	set MaterialSearchData($dlg,status) [dict get $state status]
	set MaterialSearchData($dlg,lastSuccess) [dict get $state lastSuccess]
	SetMaterialSearchMode $dlg [dict get $state mode]
	UpdateMaterialSearchQuerySummary $dlg
	return [dict get $state lastSuccess]
}


proc UpdateMaterialSearchStatus {dlg count} {
	variable MaterialSearchData

	if {$count > 0} {
		set MaterialSearchData($dlg,status) [format $mc::MaterialResults [::locale::formatNumber $count]]
	} else {
		set MaterialSearchData($dlg,status) $mc::MaterialNoResults
	}
	SaveMaterialSearchState $dlg
}


proc UpdateMaterialSearchQuerySummary {dlg {white {}} {black {}}} {
	variable MaterialSearchData

	if {![winfo exists $dlg]} { return }

	if {![string length $white] || ![string length $black]} {
		set MaterialSearchData($dlg,querySummary) $mc::MaterialFilterNone
		wm title $dlg [format $mc::MaterialSearchTitle [::util::databaseName $MaterialSearchData($dlg,file)]]
		return
	}

	switch $MaterialSearchData($dlg,mode) {
		class {
			set summary [format $mc::MaterialFilterClass $white $black]
		}
		pawns {
			set summary [format $mc::MaterialFilterPawns $white $black]
		}
		default {
			set summary [format $mc::MaterialFilterExact $white $black]
		}
	}

	set MaterialSearchData($dlg,querySummary) $summary
	wm title $dlg [format $mc::MaterialSearchTitleActive [::util::databaseName $MaterialSearchData($dlg,file)] $summary]
}


proc ResetMaterialSearch {dlg} {
	variable MaterialSearchData

	if {![winfo exists $dlg]} { return }
	set MaterialSearchData($dlg,white) {}
	set MaterialSearchData($dlg,black) {}
	SetMaterialSearchMode $dlg exact
	catch {
		::scidb::view::close \
			$MaterialSearchData($dlg,file) \
			$MaterialSearchData($dlg,variant) \
			$MaterialSearchData($dlg,view)
	}
	set MaterialSearchData($dlg,view) \
		[::scidb::view::new \
			$MaterialSearchData($dlg,file) \
			$MaterialSearchData($dlg,variant) \
			unused unused unused unused master slave]
	::gamestable::scroll $MaterialSearchData($dlg,scrolledTable) home
	::gamestable::update \
		$MaterialSearchData($dlg,scrolledTable) \
		$MaterialSearchData($dlg,file) \
		$MaterialSearchData($dlg,variant) \
		0
	UpdateMaterialSearchHelp $dlg
	UpdateMaterialSearchQuerySummary $dlg
	UpdateMaterialSearchStatus $dlg 0
	set MaterialSearchData($dlg,lastSuccess) 0
	SaveMaterialSearchState $dlg 0
	focus $dlg.controls.white
}


proc RunMaterialSearch {dlg} {
	variable MaterialSearchData

	if {![winfo exists $dlg]} { return }

	set mode $MaterialSearchData($dlg,mode)
	if {[catch {
		switch $mode {
			pawns {
				set white [NormalizePawnRange $MaterialSearchData($dlg,white)]
				set black [NormalizePawnRange $MaterialSearchData($dlg,black)]
				set query [list material pawns [list $white $black]]
			}
			class {
				set white [NormalizeMaterialTerm $MaterialSearchData($dlg,white)]
				set black [NormalizeMaterialTerm $MaterialSearchData($dlg,black)]
				set query [list material class "$white:$black"]
			}
			default {
				set white [NormalizeMaterialTerm $MaterialSearchData($dlg,white)]
				set black [NormalizeMaterialTerm $MaterialSearchData($dlg,black)]
				set query [list material exact "$white:$black"]
			}
		}
	}]} {
		if {$mode eq "pawns"} {
			return [::dialog::error -parent $dlg -message $mc::MaterialInvalidPawns]
		}
		return [::dialog::error -parent $dlg -message $mc::MaterialInvalid]
	}

	::widget::busyCursor on
	set rc [catch {
		::scidb::view::search \
			$MaterialSearchData($dlg,file) \
			$MaterialSearchData($dlg,variant) \
			$MaterialSearchData($dlg,view) \
			null \
			none \
			$query
		set count [::scidb::view::count games \
			$MaterialSearchData($dlg,file) \
			$MaterialSearchData($dlg,variant) \
			$MaterialSearchData($dlg,view)]
		::gamestable::scroll $MaterialSearchData($dlg,scrolledTable) home
		::gamestable::update \
			$MaterialSearchData($dlg,scrolledTable) \
			$MaterialSearchData($dlg,file) \
			$MaterialSearchData($dlg,variant) \
			$count
		UpdateMaterialSearchQuerySummary $dlg $white $black
		set MaterialSearchData($dlg,lastSuccess) 1
		SaveMaterialSearchState $dlg 1
		UpdateMaterialSearchStatus $dlg $count
	} result options]
	::widget::busyCursor off
	if {$rc} {
		return -options $options $result
	}
}


proc LoadMaterialIntoDialog {dlg info} {
	variable MaterialSearchData

	set material [lindex $info [::gamestable::columnIndex material]]
	if {![string length $material] || [llength [split $material :]] != 2} {
		return 0
	}

	lassign [split $material :] MaterialSearchData($dlg,white) MaterialSearchData($dlg,black)
	SetMaterialSearchMode $dlg $MaterialSearchData($dlg,mode)
	return 1
}


proc SelectedMaterialInfo {dlg} {
	variable MaterialSearchData

	set index [::gamestable::selection $MaterialSearchData($dlg,table)]
	if {$index < 0} { return {} }

	return [::scidb::db::get gameInfo \
		$index \
		$MaterialSearchData($dlg,view) \
		$MaterialSearchData($dlg,file) \
		$MaterialSearchData($dlg,variant)]
}


proc UseCurrentGameMaterial {dlg} {
	variable MaterialSearchData

	set position [::scidb::game::current]
	if {$position < 0} {
		return [::dialog::info -parent $dlg -message $mc::MaterialNoCurrentGame]
	}

	lassign [::game::getSourceInfo $position] base variant view number
	if {![string length $base] || $number < 0} {
		return [::dialog::info -parent $dlg -message $mc::MaterialNoCurrentGame]
	}

	set info [::scidb::db::get gameInfo $number $view $base $variant]
	if {![LoadMaterialIntoDialog $dlg $info]} {
		return [::dialog::info -parent $dlg -message $mc::MaterialNoCurrentGame]
	}

	RunMaterialSearch $dlg
}


proc UseSelectedResultMaterial {dlg} {
	set info [SelectedMaterialInfo $dlg]
	if {![llength $info]} {
		return [::dialog::info -parent $dlg -message $mc::MaterialNoSelectedGame]
	}
	if {![LoadMaterialIntoDialog $dlg $info]} {
		return [::dialog::info -parent $dlg -message $mc::MaterialNoSelectedGame]
	}

	RunMaterialSearch $dlg
}


proc OpenMaterialResultsInSwitcher {dlg} {
	variable MaterialSearchData

	set rc [OpenFilteredViewInSwitcher \
		$dlg \
		$MaterialSearchData($dlg,file) \
		$MaterialSearchData($dlg,variant) \
		$MaterialSearchData($dlg,view) \
		material]
	if {$rc ne 0 && [winfo exists $dlg]} {
		destroy $dlg
	}
	return $rc
}


proc SaveMaterialWorkingSet {dlg} {
	variable MaterialSearchData

	set defaultName material
	if {[info exists MaterialSearchData($dlg,querySummary)]} {
		set summary $MaterialSearchData($dlg,querySummary)
		if {$summary ne $mc::MaterialFilterNone} {
			set defaultName $summary
		}
	}

	return [SaveFilteredViewAsWorkingSet \
		$dlg \
		$MaterialSearchData($dlg,file) \
		$MaterialSearchData($dlg,variant) \
		$MaterialSearchData($dlg,view) \
		material \
		$defaultName]
}


proc MaterialPresetState {dlg} {
	variable MaterialSearchData

	return [dict create \
		mode $MaterialSearchData($dlg,mode) \
		white $MaterialSearchData($dlg,white) \
		black $MaterialSearchData($dlg,black)]
}


proc ApplyMaterialPresetState {dlg state} {
	variable MaterialSearchData

	set MaterialSearchData($dlg,white) [dict get $state white]
	set MaterialSearchData($dlg,black) [dict get $state black]
	SetMaterialSearchMode $dlg [dict get $state mode]
	UpdateMaterialSearchQuerySummary $dlg
}


proc SaveMaterialPreset {dlg} {
	variable MaterialSearchData
	variable mc

	set defaultName material
	if {[info exists MaterialSearchData($dlg,querySummary)]} {
		set summary $MaterialSearchData($dlg,querySummary)
		if {$summary ne $mc::MaterialFilterNone} {
			set defaultName $summary
		}
	}

	set name [SaveSearchPresetState \
		$dlg \
		[namespace current]::MaterialSearchPresets \
		$defaultName \
		[MaterialPresetState $dlg]]
	if {![string length $name]} { return 0 }
	set MaterialSearchData($dlg,presetName) $name
	UpdateSearchPresetSelector \
		$dlg.controls.preset \
		[namespace current]::MaterialSearchData($dlg,presetName) \
		[namespace current]::MaterialSearchPresets
	return 1
}


proc LoadMaterialPreset {dlg} {
	variable MaterialSearchData
	variable MaterialSearchPresets
	variable mc

	set name [string trim $MaterialSearchData($dlg,presetName)]
	if {![string length $name] || ![info exists MaterialSearchPresets($name)]} {
		return [::dialog::info -parent $dlg -message $mc::SearchPresetMissing]
	}

	ApplyMaterialPresetState $dlg $MaterialSearchPresets($name)
	RunMaterialSearch $dlg
}


proc DeleteMaterialPreset {dlg} {
	variable MaterialSearchData

	set name [string trim $MaterialSearchData($dlg,presetName)]
	if {![DeleteSearchPresetState $dlg [namespace current]::MaterialSearchPresets $name]} {
		return 0
	}

	set MaterialSearchData($dlg,presetName) {}
	UpdateSearchPresetSelector \
		$dlg.controls.preset \
		[namespace current]::MaterialSearchData($dlg,presetName) \
		[namespace current]::MaterialSearchPresets
	return 1
}


proc RefineMaterialSearch {dlg mode} {
	variable MaterialSearchData

	set info [SelectedMaterialInfo $dlg]
	if {![llength $info]} {
		return [::dialog::info -parent $dlg -message $mc::MaterialNoSelectedGame]
	}
	SetMaterialSearchMode $dlg $mode
	if {![LoadMaterialIntoDialog $dlg $info]} {
		return [::dialog::info -parent $dlg -message $mc::MaterialNoSelectedGame]
	}
	RunMaterialSearch $dlg
}


proc CloseMaterialSearch {dlg} {
	variable MaterialSearchData

	if {[info exists MaterialSearchData($dlg,view)]} {
		catch {
			::scidb::view::close \
				$MaterialSearchData($dlg,file) \
				$MaterialSearchData($dlg,variant) \
				$MaterialSearchData($dlg,view)
		}
	}
	SaveMaterialSearchState $dlg
	foreach key [array names MaterialSearchData $dlg,*] {
		unset MaterialSearchData($key)
	}
}


proc OpenMaterialSearch {parent file variant} {
	variable MaterialSearchData

	set dlg [MaterialDialogName $file $variant]

	if {![winfo exists $dlg]} {
		set MaterialSearchData($dlg,file) $file
		set MaterialSearchData($dlg,variant) $variant
		set MaterialSearchData($dlg,presetName) {}
		set MaterialSearchData($dlg,mode) exact
		set MaterialSearchData($dlg,modeLabel) [MaterialModeLabel exact]
		set MaterialSearchData($dlg,white) {}
		set MaterialSearchData($dlg,black) {}
		set MaterialSearchData($dlg,help) $mc::MaterialExample
		set MaterialSearchData($dlg,querySummary) $mc::MaterialFilterNone
		set MaterialSearchData($dlg,status) $mc::MaterialNoResults
		set MaterialSearchData($dlg,lastSuccess) 0
		set MaterialSearchData($dlg,view) \
			[::scidb::view::new $file $variant unused unused unused unused master slave]

		tk::toplevel $dlg -class Scidb
		ttk::frame $dlg.controls
		ttk::frame $dlg.results
		pack $dlg.controls -side top -fill x
		pack $dlg.results -side top -fill both -expand yes

		ttk::label $dlg.controls.presetLabel -text $mc::SearchPreset
		ttk::combobox $dlg.controls.preset \
			-state readonly \
			-textvariable [namespace current]::MaterialSearchData($dlg,presetName) \
			-values [SearchPresetNames [namespace current]::MaterialSearchPresets] \
			-width 20
		ttk::label $dlg.controls.modeLabel -text $mc::MaterialMode
		ttk::combobox $dlg.controls.mode \
			-state readonly \
			-textvariable [namespace current]::MaterialSearchData($dlg,modeLabel) \
			-values [list $mc::MaterialModeExact $mc::MaterialModeClass $mc::MaterialModePawns] \
			-width 18
		ttk::label $dlg.controls.whiteLabel -text $mc::MaterialWhite
		ttk::entry $dlg.controls.white \
			-textvariable [namespace current]::MaterialSearchData($dlg,white) \
			-width 14
		ttk::label $dlg.controls.blackLabel -text $mc::MaterialBlack
		ttk::entry $dlg.controls.black \
			-textvariable [namespace current]::MaterialSearchData($dlg,black) \
			-width 14
		ttk::button $dlg.controls.search \
			-text $mc::MaterialSearchAction \
			-command [namespace code [list RunMaterialSearch $dlg]]
		ttk::button $dlg.controls.savePreset \
			-text $mc::SaveSearchPreset \
			-command [namespace code [list SaveMaterialPreset $dlg]]
		ttk::button $dlg.controls.loadPreset \
			-text $mc::LoadSearchPreset \
			-command [namespace code [list LoadMaterialPreset $dlg]]
		ttk::button $dlg.controls.deletePreset \
			-text $mc::DeleteSearchPreset \
			-command [namespace code [list DeleteMaterialPreset $dlg]]
		ttk::button $dlg.controls.current \
			-text $mc::MaterialUseCurrent \
			-command [namespace code [list UseCurrentGameMaterial $dlg]]
		ttk::button $dlg.controls.selected \
			-text $mc::MaterialUseSelected \
			-command [namespace code [list UseSelectedResultMaterial $dlg]]
		ttk::button $dlg.controls.refineExact \
			-text $mc::MaterialRefineExact \
			-command [namespace code [list RefineMaterialSearch $dlg exact]]
		ttk::button $dlg.controls.refineClass \
			-text $mc::MaterialRefineClass \
			-command [namespace code [list RefineMaterialSearch $dlg class]]
		ttk::button $dlg.controls.refinePawns \
			-text $mc::MaterialRefinePawns \
			-command [namespace code [list RefineMaterialSearch $dlg pawns]]
		ttk::button $dlg.controls.reset \
			-text $mc::MaterialReset \
			-command [namespace code [list ResetMaterialSearch $dlg]]
		ttk::button $dlg.controls.switcher \
			-text $mc::MaterialOpenInSwitcher \
			-command [namespace code [list OpenMaterialResultsInSwitcher $dlg]]
		ttk::button $dlg.controls.savews \
			-text $mc::SaveWorkingSet \
			-command [namespace code [list SaveMaterialWorkingSet $dlg]]
		ttk::button $dlg.controls.close \
			-text $mc::Close \
			-command [list destroy $dlg]
		ttk::label $dlg.controls.help \
			-textvariable [namespace current]::MaterialSearchData($dlg,help)
		ttk::label $dlg.controls.status \
			-textvariable [namespace current]::MaterialSearchData($dlg,status)
		ttk::label $dlg.controls.query \
			-textvariable [namespace current]::MaterialSearchData($dlg,querySummary)

		grid $dlg.controls.presetLabel -row 0 -column 0 -sticky w
		grid $dlg.controls.preset -row 0 -column 1 -columnspan 2 -sticky ew
		grid $dlg.controls.savePreset -row 0 -column 3 -sticky ew
		grid $dlg.controls.loadPreset -row 0 -column 4 -sticky ew
		grid $dlg.controls.deletePreset -row 0 -column 5 -sticky ew
		grid $dlg.controls.modeLabel -row 1 -column 0 -sticky w
		grid $dlg.controls.mode -row 1 -column 1 -sticky ew
		grid $dlg.controls.whiteLabel -row 1 -column 2 -sticky w
		grid $dlg.controls.white -row 1 -column 3 -sticky ew
		grid $dlg.controls.blackLabel -row 1 -column 4 -sticky w
		grid $dlg.controls.black -row 1 -column 5 -sticky ew
		grid $dlg.controls.search -row 1 -column 6 -sticky ew
		grid $dlg.controls.current -row 1 -column 7 -sticky ew
		grid $dlg.controls.selected -row 1 -column 8 -sticky ew
		grid $dlg.controls.refineExact -row 1 -column 9 -sticky ew
		grid $dlg.controls.refineClass -row 1 -column 10 -sticky ew
		grid $dlg.controls.refinePawns -row 1 -column 11 -sticky ew
		grid $dlg.controls.reset -row 1 -column 12 -sticky ew
		grid $dlg.controls.switcher -row 1 -column 13 -sticky ew
		grid $dlg.controls.savews -row 1 -column 14 -sticky ew
		grid $dlg.controls.close -row 1 -column 15 -sticky ew
		grid $dlg.controls.help -row 2 -column 0 -columnspan 16 -sticky w
		grid $dlg.controls.query -row 3 -column 0 -columnspan 16 -sticky w
		grid $dlg.controls.status -row 4 -column 0 -columnspan 16 -sticky w
		grid columnconfigure $dlg.controls 1 -weight 1
		grid columnconfigure $dlg.controls 2 -weight 1
		grid columnconfigure $dlg.controls 3 -weight 1
		grid columnconfigure $dlg.controls 5 -weight 1

		set MaterialSearchData($dlg,scrolledTable) $dlg.results.table
		set MaterialSearchData($dlg,table) [::gamestable::build \
			$MaterialSearchData($dlg,scrolledTable) \
			[namespace code [list MaterialSearchView $dlg]] \
			{number white black result event date eco material} \
			-id db:material-search:[string map {. _} $dlg] \
			-mode list]

		bind $dlg.controls.mode <<ComboboxSelected>> [namespace code [list SelectMaterialSearchMode $dlg]]
		bind $dlg.controls.preset <<ComboboxSelected>> [namespace code [list LoadMaterialPreset $dlg]]
		bind $dlg.controls.white <Return> [namespace code [list RunMaterialSearch $dlg]]
		bind $dlg.controls.black <Return> [namespace code [list RunMaterialSearch $dlg]]
		bind $dlg <Destroy> [namespace code [list CloseMaterialSearch %W]]

		wm transient $dlg [winfo toplevel $parent]
		wm withdraw $dlg
		wm minsize $dlg 720 360
		::util::place $dlg -parent [winfo toplevel $parent] -position center
		wm deiconify $dlg
	} else {
		raise $dlg
	}

	UpdateSearchPresetSelector \
		$dlg.controls.preset \
		[namespace current]::MaterialSearchData($dlg,presetName) \
		[namespace current]::MaterialSearchPresets
	if {[RestoreMaterialSearchState $dlg]} {
		RunMaterialSearch $dlg
	} else {
		UpdateMaterialSearchQuerySummary $dlg
	}
	focus $dlg.controls.white
}


proc RatingDialogName {file variant} {
	return .rating_[string map {: _ . _ / _} $file]_${variant}
}


proc SearchResultsTempFile {file suffix} {
	set base [file rootname [file tail $file]]
	if {![string length $base]} { set base search }
	set stamp [clock milliseconds]
	return [file normalize [file join /tmp "scidb-$suffix-$base-$stamp.sci"]]
}


proc WorkingSetFile {file suffix label} {
	set dir [file dirname $file]
	set base [file rootname [file tail $file]]
	if {![string length $base]} { set base search }

	set suffixName $suffix
	if {[string length $label]} {
		append suffixName "-" [SanitizeWorkingSetLabel $label]
	}

	set path [file normalize [file join $dir "scidb-$suffixName-$base.sci"]]
	if {[file exists $path]} {
		set stamp [clock milliseconds]
		set path [file normalize [file join $dir "scidb-$suffixName-$base-$stamp.sci"]]
	}
	return $path
}


proc WorkingSetDialogName {parent} {
	return ${parent}.workingset
}


proc SearchPresetDialogName {parent} {
	return ${parent}.searchpreset
}


proc PromptSearchPresetName {parent initialName} {
	variable SearchPresetPromptValue
	variable mc

	set SearchPresetPromptValue ""
	set dlg [SearchPresetDialogName $parent]
	catch { destroy $dlg }
	tk::toplevel $dlg -class Dialog
	pack [set top [ttk::frame $dlg.top -borderwidth 0 -takefocus 0]]
	ttk::label $top.label -text $mc::SearchPresetName
	ttk::entry $top.input \
		-textvariable [namespace current]::SearchPresetPromptValue \
		-width 36 \
		-validate key \
		-validatecommand { return [expr {"%P" ne "|"}] } \
		-invalidcommand { bell }
	set SearchPresetPromptValue [string trim $initialName]
	$top.input selection range 0 end

	grid $top.label -row 1 -column 1 -sticky w
	grid $top.input -row 3 -column 1 -sticky ew
	grid columnconfigure $top {0 2} -minsize $::theme::padx
	grid columnconfigure $top 1 -weight 1
	grid rowconfigure $top {0 2 4} -minsize $::theme::pady

	bind $top.input <Return> "$dlg.ok invoke"
	bind $dlg <Escape> "$dlg.cancel invoke"

	::widget::dialogButtons $dlg {ok cancel} -icons no
	$dlg.cancel configure -command [list destroy $dlg]
	$dlg.ok configure -command "
		set [namespace current]::SearchPresetPromptValue \[string trim \[$top.input get\]\]
		destroy $dlg
	"

	wm withdraw $dlg
	wm transient $dlg [winfo toplevel $parent]
	wm protocol $dlg WM_DELETE_WINDOW [list destroy $dlg]
	wm title $dlg $mc::SaveSearchPreset
	::util::place $dlg -parent [winfo toplevel $parent] -position center
	wm deiconify $dlg
	focus $top.input
	::ttk::grabWindow $dlg
	tkwait window $dlg
	::ttk::releaseGrab $dlg

	return [string trim $SearchPresetPromptValue]
}


proc PromptWorkingSetName {parent initialName} {
	variable WorkingSetPromptValue
	variable mc

	set WorkingSetPromptValue ""
	set dlg [WorkingSetDialogName $parent]
	catch { destroy $dlg }
	tk::toplevel $dlg -class Dialog
	pack [set top [ttk::frame $dlg.top -borderwidth 0 -takefocus 0]]
	ttk::label $top.label -text $mc::WorkingSetName
	ttk::entry $top.input \
		-textvariable [namespace current]::WorkingSetPromptValue \
		-width 36 \
		-validate key \
		-validatecommand { return [expr {"%P" ne "|"}] } \
		-invalidcommand { bell }
	set WorkingSetPromptValue [string trim $initialName]
	$top.input selection range 0 end

	grid $top.label -row 1 -column 1 -sticky w
	grid $top.input -row 3 -column 1 -sticky ew
	grid columnconfigure $top {0 2} -minsize $::theme::padx
	grid columnconfigure $top 1 -weight 1
	grid rowconfigure $top {0 2 4} -minsize $::theme::pady

	bind $top.input <Return> "$dlg.ok invoke"
	bind $dlg <Escape> "$dlg.cancel invoke"

	::widget::dialogButtons $dlg {ok cancel} -icons no
	$dlg.cancel configure -command [list destroy $dlg]
	$dlg.ok configure -command "
		set [namespace current]::WorkingSetPromptValue \[string trim \[$top.input get\]\]
		destroy $dlg
	"

	wm withdraw $dlg
	wm transient $dlg [winfo toplevel $parent]
	wm protocol $dlg WM_DELETE_WINDOW [list destroy $dlg]
	wm title $dlg $mc::SaveWorkingSet
	::util::place $dlg -parent [winfo toplevel $parent] -position center
	wm deiconify $dlg
	focus $top.input
	::ttk::grabWindow $dlg
	tkwait window $dlg
	::ttk::releaseGrab $dlg

	return [string trim $WorkingSetPromptValue]
}


proc SanitizeWorkingSetLabel {label} {
	set label [string trim $label]
	set label [string map {: _ / _ \\ _ " " _ . _} $label]
	set label [regsub -all {[^A-Za-z0-9_-]} $label _]
	set label [regsub -all {_+} $label _]
	set label [string trim $label _]
	if {![string length $label]} {
		set label workset
	}
	return $label
}


proc SearchPresetNames {varName} {
	upvar #0 $varName presets

	if {![array exists presets]} {
		return {}
	}
	return [lsort -dictionary [array names presets]]
}


proc UpdateSearchPresetSelector {selector currentVarName arrayVarName} {
	upvar #0 $currentVarName currentName
	upvar #0 $arrayVarName presets

	if {![winfo exists $selector]} { return }
	set names [SearchPresetNames $arrayVarName]
	$selector configure -values $names
	if {![info exists currentName]} {
		return
	}
	if {[lsearch -exact $names $currentName] < 0} {
		set currentName {}
	}
}


proc SaveSearchPresetState {parent arrayVarName presetName state} {
	variable mc
	upvar #0 $arrayVarName presets

	set name [PromptSearchPresetName $parent $presetName]
	if {![string length $name]} {
		return {}
	}

	if {[info exists presets($name)]} {
		set answer [::dialog::question \
			-parent $parent \
			-message [format $mc::SearchPresetOverwrite $name] \
			-default no]
		if {$answer ne "yes"} {
			return {}
		}
	}

	set presets($name) $state
	::dialog::info -parent $parent -message [format $mc::SearchPresetSaved $name]
	return $name
}


proc DeleteSearchPresetState {parent arrayVarName presetName} {
	variable mc
	upvar #0 $arrayVarName presets

	if {![string length $presetName] || ![info exists presets($presetName)]} {
		::dialog::info -parent $parent -message $mc::SearchPresetMissing
		return 0
	}

	set answer [::dialog::question \
		-parent $parent \
		-message [format $mc::SearchPresetDelete $presetName] \
		-default no]
	if {$answer ne "yes"} {
		return 0
	}

	unset presets($presetName)
	::dialog::info -parent $parent -message [format $mc::SearchPresetDeleted $presetName]
	return 1
}


proc SaveFilteredViewAsWorkingSet {parent source variant view suffix defaultName} {
	set name [PromptWorkingSetName $parent $defaultName]
	if {![string length $name]} { return 0 }
	return [OpenFilteredViewInSwitcher $parent $source $variant $view $suffix $name [WorkingSetFile $source $suffix $name]]
}


proc OpenFilteredViewInSwitcher {parent source variant view suffix {label {}} {targetFile {}}} {
	variable Vars
	variable mc

	set count [::scidb::view::count games $source $variant $view]
	if {$count <= 0} {
		::dialog::info -parent $parent -message $mc::SearchResultsEmpty
		return 0
	}

	set suffixName $suffix
	if {[string length $label]} {
		append suffixName "-" [SanitizeWorkingSetLabel $label]
	}
	if {[string length $targetFile]} {
		set tempFile $targetFile
	} else {
		set tempFile [SearchResultsTempFile $source $suffixName]
	}
	set cmd [list ::scidb::view::export \
		$source \
		$variant \
		$view \
		$tempFile \
		0 \
		0 \
		utf-8 \
		0 \
		{} \
		{}]
	set args [list ::export::Log {}]
	set options [list -message $::export::mc::ExportDatabase -interrupt yes]

	::log::open $::export::mc::ExportDatabase
	::log::delay
	::log::info [string map [list %src [::util::databaseName $source] %dst [::util::databaseName $tempFile]] $::export::mc::ExportGamesFromTo]

	set progressCmd [list ::progress::start [winfo toplevel $parent] $cmd $args $options 1]
	set result {}
	if {[catch { ::util::catchException $progressCmd result } rc opts]} {
		::progress::close
		::log::close
		return {*}$opts -rethrow 1
	}

	if {$rc == 1} {
		::progress::close
		::log::close
		return 0
	}

	lassign $result exported illegal
	if {$exported < 0} {
		set exported [expr {-$exported - 2}]
	}
	::progress::close
	::log::close

	if {[$Vars(switcher) contains? $tempFile]} {
		switchToBase $tempFile
	} else {
		openBase [winfo toplevel $parent] $tempFile no -switchToBase 1
	}

	if {[string length $label]} {
		return [::dialog::info \
			-parent $parent \
			-message [format $mc::WorkingSetSaved [::locale::formatNumber $exported] $label]]
	}

	return [::dialog::info \
		-parent $parent \
		-message [format $mc::SearchResultsOpened [::locale::formatNumber $exported]]]
}


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


proc AdvancedDialogName {file variant} {
	return .advanced_[string map {: _ . _ / _} $file]_${variant}
}


proc AdvancedSearchView {dlg base variant} {
	variable AdvancedSearchData

	if {![info exists AdvancedSearchData($dlg,view)]} { return 0 }
	if {$base ne $AdvancedSearchData($dlg,file)} { return 0 }
	if {$variant ne $AdvancedSearchData($dlg,variant)} { return 0 }
	return $AdvancedSearchData($dlg,view)
}


proc AdvancedSearchSessionKey {file variant} {
	return "$file:$variant"
}


proc SaveAdvancedSearchState {dlg {success {}}} {
	variable AdvancedSearchData
	variable AdvancedSearchState

	if {![info exists AdvancedSearchData($dlg,file)] || ![info exists AdvancedSearchData($dlg,variant)]} {
		return
	}

	set key [AdvancedSearchSessionKey $AdvancedSearchData($dlg,file) $AdvancedSearchData($dlg,variant)]
	if {$success eq {}} {
		if {[info exists AdvancedSearchData($dlg,lastSuccess)]} {
			set success $AdvancedSearchData($dlg,lastSuccess)
		} else {
			set success 0
		}
	}

	set AdvancedSearchState($key) [dict create \
		playerModeLabel $AdvancedSearchData($dlg,playerModeLabel) \
		player $AdvancedSearchData($dlg,player) \
		event $AdvancedSearchData($dlg,event) \
		site $AdvancedSearchData($dlg,site) \
		annotator $AdvancedSearchData($dlg,annotator) \
		position $AdvancedSearchData($dlg,position) \
		ratingType $AdvancedSearchData($dlg,ratingType) \
		ratingModeLabel $AdvancedSearchData($dlg,ratingModeLabel) \
		rangeA $AdvancedSearchData($dlg,rangeA) \
		rangeB $AdvancedSearchData($dlg,rangeB) \
		materialModeLabel $AdvancedSearchData($dlg,materialModeLabel) \
		whiteMaterial $AdvancedSearchData($dlg,whiteMaterial) \
		blackMaterial $AdvancedSearchData($dlg,blackMaterial) \
		querySummary $AdvancedSearchData($dlg,querySummary) \
		status $AdvancedSearchData($dlg,status) \
		lastSuccess $success]
}


proc RestoreAdvancedSearchState {dlg} {
	variable AdvancedSearchData
	variable AdvancedSearchState

	set key [AdvancedSearchSessionKey $AdvancedSearchData($dlg,file) $AdvancedSearchData($dlg,variant)]
	if {![info exists AdvancedSearchState($key)]} {
		set AdvancedSearchData($dlg,lastSuccess) 0
		UpdateAdvancedSearchQuerySummary $dlg
		return 0
	}

	set state $AdvancedSearchState($key)
	foreach keyName {
		playerModeLabel player event site annotator position
		ratingType ratingModeLabel rangeA rangeB
		materialModeLabel whiteMaterial blackMaterial
		querySummary status lastSuccess
	} {
		set AdvancedSearchData($dlg,$keyName) [dict get $state $keyName]
	}
	UpdateAdvancedSearchQuerySummary $dlg
	return $AdvancedSearchData($dlg,lastSuccess)
}


proc AdvancedPlayerModeLabel {mode} {
	variable mc

	switch -- $mode {
		white { return $mc::RatingModeWhite }
		black { return $mc::RatingModeBlack }
		default { return $mc::AdvancedPlayerAny }
	}
}


proc AdvancedPlayerModeFromLabel {label} {
	variable mc

	switch -- $label {
		$mc::RatingModeWhite { return white }
		$mc::RatingModeBlack { return black }
		default { return any }
	}
}


proc UpdateAdvancedSearchStatus {dlg count} {
	variable AdvancedSearchData
	variable mc

	if {$count > 0} {
		set AdvancedSearchData($dlg,status) [format $mc::AdvancedResults [::locale::formatNumber $count]]
	} else {
		set AdvancedSearchData($dlg,status) $mc::AdvancedNoResults
	}
	SaveAdvancedSearchState $dlg
}


proc UpdateAdvancedSearchQuerySummary {dlg {summary {}}} {
	variable AdvancedSearchData
	variable mc

	if {![winfo exists $dlg]} { return }

	if {![string length $summary]} {
		set summary $mc::AdvancedFilterNone
	}

	set AdvancedSearchData($dlg,querySummary) $summary
	if {$summary eq $mc::AdvancedFilterNone} {
		wm title $dlg [format $mc::AdvancedSearchTitle [::util::databaseName $AdvancedSearchData($dlg,file)]]
	} else {
		wm title $dlg [format $mc::AdvancedSearchTitleActive [::util::databaseName $AdvancedSearchData($dlg,file)] $summary]
	}
}


proc BuildAdvancedSearchQuery {dlg} {
	variable AdvancedSearchData
	variable mc

	set terms {}
	set filters {}

	set player [string trim $AdvancedSearchData($dlg,player)]
	if {[string length $player]} {
		set side [AdvancedPlayerModeFromLabel $AdvancedSearchData($dlg,playerModeLabel)]
		lappend terms [list playername $side $player]
		lappend filters "player=$player"
	}

	foreach {field subcommand label} {
		event eventname event
		site sitename site
		annotator annotatorname annotator
	} {
		set value [string trim $AdvancedSearchData($dlg,$field)]
		if {[string length $value]} {
			lappend terms [list $subcommand $value]
			lappend filters "$label=$value"
		}
	}

	set position [string trim $AdvancedSearchData($dlg,position)]
	if {[string length $position]} {
		if {![string is integer -strict $position] || $position < 0} {
			return -code error $mc::AdvancedInvalid
		}
		lappend terms [list position $position]
		lappend filters "position=$position"
	}

	set rangeA [string trim $AdvancedSearchData($dlg,rangeA)]
	if {[string length $rangeA]} {
		set rangeA [NormalizeRatingRange $rangeA]
		set ratingMode [RatingModeFromLabel $AdvancedSearchData($dlg,ratingModeLabel)]
		if {$ratingMode eq "both"} {
			set rangeB [NormalizeRatingRange $AdvancedSearchData($dlg,rangeB)]
			lappend terms [list rating $AdvancedSearchData($dlg,ratingType) both $rangeA $rangeB]
			lappend filters "rating=$AdvancedSearchData($dlg,ratingType) both $rangeA/$rangeB"
		} else {
			lappend terms [list rating $AdvancedSearchData($dlg,ratingType) $ratingMode $rangeA]
			lappend filters "rating=$AdvancedSearchData($dlg,ratingType) $ratingMode $rangeA"
		}
	}

	set white [string trim $AdvancedSearchData($dlg,whiteMaterial)]
	set black [string trim $AdvancedSearchData($dlg,blackMaterial)]
	if {[string length $white] || [string length $black]} {
		if {![string length $white] || ![string length $black]} {
			return -code error $mc::AdvancedInvalid
		}

		set materialMode [MaterialModeFromLabel $AdvancedSearchData($dlg,materialModeLabel)]
		switch -- $materialMode {
			pawns {
				set white [NormalizePawnRange $white]
				set black [NormalizePawnRange $black]
				lappend terms [list material pawns [list $white $black]]
				lappend filters "pawns=$white:$black"
			}
			class {
				set white [NormalizeMaterialTerm $white]
				set black [NormalizeMaterialTerm $black]
				lappend terms [list material class "${white}:${black}"]
				lappend filters "material class=${white}:${black}"
			}
			default {
				set white [NormalizeMaterialTerm $white]
				set black [NormalizeMaterialTerm $black]
				lappend terms [list material exact "${white}:${black}"]
				lappend filters "material=${white}:${black}"
			}
		}
	}

	if {![llength $terms]} {
		return -code error $mc::AdvancedInvalid
	}

	if {[llength $terms] == 1} {
		set query [lindex $terms 0]
	} else {
		set query [linsert $terms 0 AND]
	}

	return [list $query "Active filter: [join $filters {; }]"]
}


proc ResetAdvancedSearch {dlg} {
	variable AdvancedSearchData

	if {![winfo exists $dlg]} { return }
	foreach key {
		player event site annotator position rangeA rangeB whiteMaterial blackMaterial
	} {
		set AdvancedSearchData($dlg,$key) {}
	}
	set AdvancedSearchData($dlg,playerModeLabel) [AdvancedPlayerModeLabel any]
	set AdvancedSearchData($dlg,ratingType) Elo
	set AdvancedSearchData($dlg,ratingModeLabel) [RatingModeLabel white]
	set AdvancedSearchData($dlg,materialModeLabel) [MaterialModeLabel exact]
	catch {
		::scidb::view::close \
			$AdvancedSearchData($dlg,file) \
			$AdvancedSearchData($dlg,variant) \
			$AdvancedSearchData($dlg,view)
	}
	set AdvancedSearchData($dlg,view) \
		[::scidb::view::new \
			$AdvancedSearchData($dlg,file) \
			$AdvancedSearchData($dlg,variant) \
			unused unused unused unused master slave]
	::gamestable::scroll $AdvancedSearchData($dlg,scrolledTable) home
	::gamestable::update \
		$AdvancedSearchData($dlg,scrolledTable) \
		$AdvancedSearchData($dlg,file) \
		$AdvancedSearchData($dlg,variant) \
		0
	UpdateAdvancedSearchQuerySummary $dlg
	UpdateAdvancedSearchStatus $dlg 0
	set AdvancedSearchData($dlg,lastSuccess) 0
	SaveAdvancedSearchState $dlg 0
	focus $dlg.controls.player
}


proc RunAdvancedSearch {dlg} {
	variable AdvancedSearchData

	if {![winfo exists $dlg]} { return }

	if {[catch {BuildAdvancedSearchQuery $dlg} built]} {
		return [::dialog::error -parent $dlg -message $built]
	}

	lassign $built query summary

	::widget::busyCursor on
	set rc [catch {
		::scidb::view::search \
			$AdvancedSearchData($dlg,file) \
			$AdvancedSearchData($dlg,variant) \
			$AdvancedSearchData($dlg,view) \
			null \
			none \
			$query
		set count [::scidb::view::count games \
			$AdvancedSearchData($dlg,file) \
			$AdvancedSearchData($dlg,variant) \
			$AdvancedSearchData($dlg,view)]
		::gamestable::scroll $AdvancedSearchData($dlg,scrolledTable) home
		::gamestable::update \
			$AdvancedSearchData($dlg,scrolledTable) \
			$AdvancedSearchData($dlg,file) \
			$AdvancedSearchData($dlg,variant) \
			$count
		UpdateAdvancedSearchQuerySummary $dlg $summary
		UpdateAdvancedSearchStatus $dlg $count
		set AdvancedSearchData($dlg,lastSuccess) 1
		SaveAdvancedSearchState $dlg 1
	} result options]
	::widget::busyCursor off
	if {$rc} {
		return -options $options $result
	}
}


proc OpenAdvancedResultsInSwitcher {dlg} {
	variable AdvancedSearchData

	set rc [OpenFilteredViewInSwitcher \
		$dlg \
		$AdvancedSearchData($dlg,file) \
		$AdvancedSearchData($dlg,variant) \
		$AdvancedSearchData($dlg,view) \
		advanced]
	if {$rc ne 0 && [winfo exists $dlg]} {
		destroy $dlg
	}
	return $rc
}


proc SaveAdvancedWorkingSet {dlg} {
	variable AdvancedSearchData

	set defaultName advanced-search
	if {[info exists AdvancedSearchData($dlg,querySummary)]} {
		set summary $AdvancedSearchData($dlg,querySummary)
		if {$summary ne $mc::AdvancedFilterNone} {
			set defaultName $summary
		}
	}

	return [SaveFilteredViewAsWorkingSet \
		$dlg \
		$AdvancedSearchData($dlg,file) \
		$AdvancedSearchData($dlg,variant) \
		$AdvancedSearchData($dlg,view) \
		advanced \
		$defaultName]
}


proc AdvancedPresetState {dlg} {
	variable AdvancedSearchData

	set state [dict create]
	foreach key {
		playerModeLabel player event site annotator position
		ratingType ratingModeLabel rangeA rangeB
		materialModeLabel whiteMaterial blackMaterial
	} {
		dict set state $key $AdvancedSearchData($dlg,$key)
	}
	return $state
}


proc ApplyAdvancedPresetState {dlg state} {
	variable AdvancedSearchData

	foreach key {
		playerModeLabel player event site annotator position
		ratingType ratingModeLabel rangeA rangeB
		materialModeLabel whiteMaterial blackMaterial
	} {
		set AdvancedSearchData($dlg,$key) [dict get $state $key]
	}
	UpdateAdvancedSearchQuerySummary $dlg
}


proc SaveAdvancedPreset {dlg} {
	variable AdvancedSearchData
	variable mc

	set defaultName advanced-search
	if {[info exists AdvancedSearchData($dlg,querySummary)]} {
		set summary $AdvancedSearchData($dlg,querySummary)
		if {$summary ne $mc::AdvancedFilterNone} {
			set defaultName $summary
		}
	}

	set name [SaveSearchPresetState \
		$dlg \
		[namespace current]::AdvancedSearchPresets \
		$defaultName \
		[AdvancedPresetState $dlg]]
	if {![string length $name]} { return 0 }
	set AdvancedSearchData($dlg,presetName) $name
	UpdateSearchPresetSelector \
		$dlg.controls.preset \
		[namespace current]::AdvancedSearchData($dlg,presetName) \
		[namespace current]::AdvancedSearchPresets
	return 1
}


proc LoadAdvancedPreset {dlg} {
	variable AdvancedSearchData
	variable AdvancedSearchPresets
	variable mc

	set name [string trim $AdvancedSearchData($dlg,presetName)]
	if {![string length $name] || ![info exists AdvancedSearchPresets($name)]} {
		return [::dialog::info -parent $dlg -message $mc::SearchPresetMissing]
	}

	ApplyAdvancedPresetState $dlg $AdvancedSearchPresets($name)
	RunAdvancedSearch $dlg
}


proc DeleteAdvancedPreset {dlg} {
	variable AdvancedSearchData

	set name [string trim $AdvancedSearchData($dlg,presetName)]
	if {![DeleteSearchPresetState $dlg [namespace current]::AdvancedSearchPresets $name]} {
		return 0
	}

	set AdvancedSearchData($dlg,presetName) {}
	UpdateSearchPresetSelector \
		$dlg.controls.preset \
		[namespace current]::AdvancedSearchData($dlg,presetName) \
		[namespace current]::AdvancedSearchPresets
	return 1
}


proc UseCurrentPositionInAdvancedSearch {dlg} {
	variable AdvancedSearchData

	if {![winfo exists $dlg]} { return }
	set idn [::scidb::game::query idn]
	if {$idn <= 0} {
		set AdvancedSearchData($dlg,position) {}
	} else {
		set AdvancedSearchData($dlg,position) $idn
	}
}


proc CloseAdvancedSearch {dlg} {
	variable AdvancedSearchData

	if {![string match .advanced_* $dlg]} { return }
	if {[info exists AdvancedSearchData($dlg,view)]} {
		catch {
			::scidb::view::close \
				$AdvancedSearchData($dlg,file) \
				$AdvancedSearchData($dlg,variant) \
				$AdvancedSearchData($dlg,view)
		}
	}
	SaveAdvancedSearchState $dlg
	foreach key [array names AdvancedSearchData $dlg,*] {
		unset AdvancedSearchData($key)
	}
}


proc OpenAdvancedSearch {parent file variant} {
	variable AdvancedSearchData
	variable mc

	set dlg [AdvancedDialogName $file $variant]

	if {![winfo exists $dlg]} {
		set AdvancedSearchData($dlg,file) $file
		set AdvancedSearchData($dlg,variant) $variant
		set AdvancedSearchData($dlg,presetName) {}
		set AdvancedSearchData($dlg,playerModeLabel) [AdvancedPlayerModeLabel any]
		set AdvancedSearchData($dlg,ratingType) Elo
		set AdvancedSearchData($dlg,ratingModeLabel) [RatingModeLabel white]
		set AdvancedSearchData($dlg,materialModeLabel) [MaterialModeLabel exact]
		foreach key {
			player event site annotator position rangeA rangeB whiteMaterial blackMaterial
		} {
			set AdvancedSearchData($dlg,$key) {}
		}
		set AdvancedSearchData($dlg,querySummary) $mc::AdvancedFilterNone
		set AdvancedSearchData($dlg,status) $mc::AdvancedNoResults
		set AdvancedSearchData($dlg,lastSuccess) 0
		set AdvancedSearchData($dlg,view) \
			[::scidb::view::new $file $variant unused unused unused unused master slave]

		tk::toplevel $dlg -class Scidb
		ttk::frame $dlg.controls
		ttk::frame $dlg.results
		pack $dlg.controls -side top -fill x
		pack $dlg.results -side top -fill both -expand yes

		ttk::label $dlg.controls.presetLabel -text $mc::SearchPreset
		ttk::combobox $dlg.controls.preset \
			-state readonly \
			-textvariable [namespace current]::AdvancedSearchData($dlg,presetName) \
			-values [SearchPresetNames [namespace current]::AdvancedSearchPresets] \
			-width 22
		ttk::button $dlg.controls.savePreset \
			-text $mc::SaveSearchPreset \
			-command [namespace code [list SaveAdvancedPreset $dlg]]
		ttk::button $dlg.controls.loadPreset \
			-text $mc::LoadSearchPreset \
			-command [namespace code [list LoadAdvancedPreset $dlg]]
		ttk::button $dlg.controls.deletePreset \
			-text $mc::DeleteSearchPreset \
			-command [namespace code [list DeleteAdvancedPreset $dlg]]
		ttk::label $dlg.controls.playerModeLabel -text $mc::AdvancedPlayerMode
		ttk::combobox $dlg.controls.playerMode \
			-state readonly \
			-textvariable [namespace current]::AdvancedSearchData($dlg,playerModeLabel) \
			-values [list $mc::AdvancedPlayerAny $mc::RatingModeWhite $mc::RatingModeBlack] \
			-width 10
		ttk::label $dlg.controls.playerLabel -text $mc::AdvancedPlayer
		ttk::entry $dlg.controls.player \
			-textvariable [namespace current]::AdvancedSearchData($dlg,player) \
			-width 22
		ttk::label $dlg.controls.eventLabel -text $mc::AdvancedEvent
		ttk::entry $dlg.controls.event \
			-textvariable [namespace current]::AdvancedSearchData($dlg,event) \
			-width 22
		ttk::label $dlg.controls.siteLabel -text $mc::AdvancedSite
		ttk::entry $dlg.controls.site \
			-textvariable [namespace current]::AdvancedSearchData($dlg,site) \
			-width 18
		ttk::label $dlg.controls.annotatorLabel -text $mc::AdvancedAnnotator
		ttk::entry $dlg.controls.annotator \
			-textvariable [namespace current]::AdvancedSearchData($dlg,annotator) \
			-width 18
		ttk::label $dlg.controls.positionLabel -text $mc::AdvancedPosition
		ttk::entry $dlg.controls.position \
			-textvariable [namespace current]::AdvancedSearchData($dlg,position) \
			-width 8
		ttk::button $dlg.controls.useCurrentPosition \
			-text $mc::AdvancedUseCurrentPosition \
			-command [namespace code [list UseCurrentPositionInAdvancedSearch $dlg]]

		ttk::label $dlg.controls.ratingTypeLabel -text $mc::RatingType
		ttk::combobox $dlg.controls.ratingType \
			-state readonly \
			-textvariable [namespace current]::AdvancedSearchData($dlg,ratingType) \
			-values $::ratingbox::ratings(all) \
			-width 10
		ttk::label $dlg.controls.ratingModeLabel -text $mc::RatingMode
		ttk::combobox $dlg.controls.ratingMode \
			-state readonly \
			-textvariable [namespace current]::AdvancedSearchData($dlg,ratingModeLabel) \
			-values [list $mc::RatingModeWhite $mc::RatingModeBlack $mc::RatingModeAverage $mc::RatingModeBoth] \
			-width 16
		ttk::label $dlg.controls.rangeALabel -text $mc::RatingRangeA
		ttk::entry $dlg.controls.rangeA \
			-textvariable [namespace current]::AdvancedSearchData($dlg,rangeA) \
			-width 12
		ttk::label $dlg.controls.rangeBLabel -text $mc::RatingRangeB
		ttk::entry $dlg.controls.rangeB \
			-textvariable [namespace current]::AdvancedSearchData($dlg,rangeB) \
			-width 12

		ttk::label $dlg.controls.materialModeLabel -text $mc::MaterialMode
		ttk::combobox $dlg.controls.materialMode \
			-state readonly \
			-textvariable [namespace current]::AdvancedSearchData($dlg,materialModeLabel) \
			-values [list $mc::MaterialModeExact $mc::MaterialModeClass $mc::MaterialModePawns] \
			-width 18
		ttk::label $dlg.controls.whiteLabel -text $mc::MaterialWhite
		ttk::entry $dlg.controls.white \
			-textvariable [namespace current]::AdvancedSearchData($dlg,whiteMaterial) \
			-width 12
		ttk::label $dlg.controls.blackLabel -text $mc::MaterialBlack
		ttk::entry $dlg.controls.black \
			-textvariable [namespace current]::AdvancedSearchData($dlg,blackMaterial) \
			-width 12
		ttk::button $dlg.controls.search \
			-text $mc::AdvancedSearchAction \
			-command [namespace code [list RunAdvancedSearch $dlg]]
		ttk::button $dlg.controls.reset \
			-text $mc::AdvancedReset \
			-command [namespace code [list ResetAdvancedSearch $dlg]]
		ttk::button $dlg.controls.switcher \
			-text $mc::AdvancedOpenInSwitcher \
			-command [namespace code [list OpenAdvancedResultsInSwitcher $dlg]]
		ttk::button $dlg.controls.savews \
			-text $mc::SaveWorkingSet \
			-command [namespace code [list SaveAdvancedWorkingSet $dlg]]
		ttk::button $dlg.controls.close \
			-text $mc::Close \
			-command [list destroy $dlg]
		ttk::label $dlg.controls.help -text $mc::AdvancedSearchHelp
		ttk::label $dlg.controls.query \
			-textvariable [namespace current]::AdvancedSearchData($dlg,querySummary)
		ttk::label $dlg.controls.status \
			-textvariable [namespace current]::AdvancedSearchData($dlg,status)

		grid $dlg.controls.presetLabel -row 0 -column 0 -sticky w
		grid $dlg.controls.preset -row 0 -column 1 -columnspan 3 -sticky ew
		grid $dlg.controls.savePreset -row 0 -column 4 -sticky ew
		grid $dlg.controls.loadPreset -row 0 -column 5 -sticky ew
		grid $dlg.controls.deletePreset -row 0 -column 6 -sticky ew

		grid $dlg.controls.playerModeLabel -row 1 -column 0 -sticky w
		grid $dlg.controls.playerMode -row 1 -column 1 -sticky ew
		grid $dlg.controls.playerLabel -row 1 -column 2 -sticky w
		grid $dlg.controls.player -row 1 -column 3 -sticky ew
		grid $dlg.controls.eventLabel -row 1 -column 4 -sticky w
		grid $dlg.controls.event -row 1 -column 5 -sticky ew
		grid $dlg.controls.siteLabel -row 1 -column 6 -sticky w
		grid $dlg.controls.site -row 1 -column 7 -sticky ew
		grid $dlg.controls.annotatorLabel -row 1 -column 8 -sticky w
		grid $dlg.controls.annotator -row 1 -column 9 -sticky ew
		grid $dlg.controls.positionLabel -row 1 -column 10 -sticky w
		grid $dlg.controls.position -row 1 -column 11 -sticky ew
		grid $dlg.controls.useCurrentPosition -row 1 -column 12 -sticky ew -padx {4 0}

		grid $dlg.controls.ratingTypeLabel -row 2 -column 0 -sticky w
		grid $dlg.controls.ratingType -row 2 -column 1 -sticky ew
		grid $dlg.controls.ratingModeLabel -row 2 -column 2 -sticky w
		grid $dlg.controls.ratingMode -row 2 -column 3 -sticky ew
		grid $dlg.controls.rangeALabel -row 2 -column 4 -sticky w
		grid $dlg.controls.rangeA -row 2 -column 5 -sticky ew
		grid $dlg.controls.rangeBLabel -row 2 -column 6 -sticky w
		grid $dlg.controls.rangeB -row 2 -column 7 -sticky ew
		grid $dlg.controls.materialModeLabel -row 2 -column 8 -sticky w
		grid $dlg.controls.materialMode -row 2 -column 9 -sticky ew
		grid $dlg.controls.whiteLabel -row 2 -column 10 -sticky w
		grid $dlg.controls.white -row 2 -column 11 -sticky ew
		grid $dlg.controls.blackLabel -row 2 -column 12 -sticky w
		grid $dlg.controls.black -row 2 -column 13 -sticky ew

		grid $dlg.controls.search -row 3 -column 8 -sticky ew
		grid $dlg.controls.reset -row 3 -column 9 -sticky ew
		grid $dlg.controls.switcher -row 3 -column 10 -columnspan 2 -sticky ew
		grid $dlg.controls.savews -row 3 -column 12 -sticky ew
		grid $dlg.controls.close -row 3 -column 13 -sticky ew
		grid $dlg.controls.help -row 4 -column 0 -columnspan 14 -sticky w
		grid $dlg.controls.query -row 5 -column 0 -columnspan 14 -sticky w
		grid $dlg.controls.status -row 6 -column 0 -columnspan 14 -sticky w

		foreach col {1 3 5 7 9 11 13} {
			grid columnconfigure $dlg.controls $col -weight 1
		}

		set AdvancedSearchData($dlg,scrolledTable) $dlg.results.table
		set AdvancedSearchData($dlg,table) [::gamestable::build \
			$AdvancedSearchData($dlg,scrolledTable) \
			[namespace code [list AdvancedSearchView $dlg]] \
			{number white whiteElo black blackElo result event site date eco annotator material} \
			-id db:advanced-search:[string map {. _} $dlg] \
			-mode list]

		foreach widget {
			player event site annotator position rangeA rangeB white black
		} {
			bind $dlg.controls.$widget <Return> [namespace code [list RunAdvancedSearch $dlg]]
		}
		bind $dlg.controls.preset <<ComboboxSelected>> [namespace code [list LoadAdvancedPreset $dlg]]
		bind $dlg <Destroy> [namespace code [list CloseAdvancedSearch %W]]

		wm transient $dlg [winfo toplevel $parent]
		wm withdraw $dlg
		wm minsize $dlg 920 420
		::util::place $dlg -parent [winfo toplevel $parent] -position center
		wm deiconify $dlg
	} else {
		raise $dlg
	}

	UpdateSearchPresetSelector \
		$dlg.controls.preset \
		[namespace current]::AdvancedSearchData($dlg,presetName) \
		[namespace current]::AdvancedSearchPresets
	if {[RestoreAdvancedSearchState $dlg]} {
		RunAdvancedSearch $dlg
	} else {
		UpdateAdvancedSearchQuerySummary $dlg
	}
	focus $dlg.controls.player
}


} ;# namespace database
} ;# namespace application

// vi:set ts=3 sw=3:
