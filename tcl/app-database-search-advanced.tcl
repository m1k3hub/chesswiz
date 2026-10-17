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

::util::source database-search-advanced

namespace eval application {
namespace eval database {
array set AdvancedSearchPresets {}

proc AdvancedDialogName {file variant} {
	return .advanced_[string map {: _ . _ / _ " " _} $file]_${variant}
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
		if {[string index $player 0] ne "=" && ![regexp {[*?\[\],]} $player]} {
			# A plain surname also finds "Surname, First" and "Surname First":
			# names are stored as "Carlsen, M", and an exact pattern "Carlsen"
			# would only match a player stored as just "Carlsen".
			lappend terms [list OR \
				[list playername $side $player] \
				[list playername $side "$player,*"] \
				[list playername $side "$player *"]]
		} else {
			lappend terms [list playername $side $player]
		}
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

		# At most four label/field pairs a row: with all fields in two rows the
		# dialog was wider than a 1920 px screen at 200%.
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

		grid $dlg.controls.annotatorLabel -row 2 -column 0 -sticky w
		grid $dlg.controls.annotator -row 2 -column 1 -sticky ew
		grid $dlg.controls.positionLabel -row 2 -column 2 -sticky w
		grid $dlg.controls.position -row 2 -column 3 -sticky ew
		grid $dlg.controls.useCurrentPosition -row 2 -column 4 -columnspan 2 -sticky w -padx {4 0}

		grid $dlg.controls.ratingTypeLabel -row 3 -column 0 -sticky w
		grid $dlg.controls.ratingType -row 3 -column 1 -sticky ew
		grid $dlg.controls.ratingModeLabel -row 3 -column 2 -sticky w
		grid $dlg.controls.ratingMode -row 3 -column 3 -sticky ew
		grid $dlg.controls.rangeALabel -row 3 -column 4 -sticky w
		grid $dlg.controls.rangeA -row 3 -column 5 -sticky ew
		grid $dlg.controls.rangeBLabel -row 3 -column 6 -sticky w
		grid $dlg.controls.rangeB -row 3 -column 7 -sticky ew

		grid $dlg.controls.materialModeLabel -row 4 -column 0 -sticky w
		grid $dlg.controls.materialMode -row 4 -column 1 -sticky ew
		grid $dlg.controls.whiteLabel -row 4 -column 2 -sticky w
		grid $dlg.controls.white -row 4 -column 3 -sticky ew
		grid $dlg.controls.blackLabel -row 4 -column 4 -sticky w
		grid $dlg.controls.black -row 4 -column 5 -sticky ew

		grid $dlg.controls.search -row 5 -column 2 -sticky ew
		grid $dlg.controls.reset -row 5 -column 3 -sticky ew
		grid $dlg.controls.switcher -row 5 -column 4 -columnspan 2 -sticky ew
		grid $dlg.controls.savews -row 5 -column 6 -sticky ew
		grid $dlg.controls.close -row 5 -column 7 -sticky ew
		grid $dlg.controls.help -row 6 -column 0 -columnspan 8 -sticky w
		grid $dlg.controls.query -row 7 -column 0 -columnspan 8 -sticky w
		grid $dlg.controls.status -row 8 -column 0 -columnspan 8 -sticky w
		$dlg.controls.help configure -wraplength [expr {[winfo screenwidth $dlg]/2}]

		foreach col {1 3 5 7} {
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
		bind $dlg <F1> [list ::help::open .application Advanced-Search -parent $dlg]

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

# vi:set ts=3 sw=3:
