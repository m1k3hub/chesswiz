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


} ;# namespace database
} ;# namespace application

# vi:set ts=3 sw=3:
