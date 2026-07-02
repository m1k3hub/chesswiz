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

::util::source database-search-material

namespace eval application {
namespace eval database {
array set MaterialSearchPresets {}

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


} ;# namespace database
} ;# namespace application

# vi:set ts=3 sw=3:
