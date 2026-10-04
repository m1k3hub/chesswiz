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

::util::source database-maintenance

namespace eval application {
namespace eval database {
namespace eval mc {
set MaintenanceReport				"Maintenance Report"
set MaintenanceOverview			"Overview"
set MaintenanceOpenings			"Openings"
set MaintenanceDuplicates		"Duplicates"
set DuplicatesTitle					"Duplicate Games in '%s'"
set DuplicatesGroup					"Group %s (%s games)"
set NoDuplicatesFound				"No duplicate games found."
set EcoStatsTitle					"Opening Report for '%s'"
set MaintenanceReportTitle		"Maintenance Report for '%s'"
set EcoColEco						"ECO"
set EcoColTotal					"Games"
set EcoColWhite					"White"
set EcoColDraw						"Draw"
set EcoColBlack					"Black"
set EcoColWhitePct				"White %"
set EcoColDrawPct					"Draw %"
set EcoColBlackPct				"Black %"
set EcoColTrend					"Trend"
set Refresh							"Refresh"
set CopySummary					"Copy Summary"
set ReviewDuplicates				"Review Duplicates"
set CheckDuplicateGroup			"Check Group (AI)"
set DuplicateVerdict				"Game %s: %s"
set CompactNow						"Compact Now"
set ScidbBases						"Scidb databases"
set ConvertDatabase					"Convert Version"
set ConvertQuestion				"Convert this database to the legacy SCI format (version 95) for use with older scidb releases?\n\nAnswer No to convert to the current format (version 96, native correspondence clock storage)."
set ConvertTitle					"Convert Database Version"
set ConvertDestination			"Destination of the converted database"
set ConvertDone						"Conversion complete: %s games written to %s"
set OpeningsCovered				"Opening codes"
set DuplicateGroups				"Duplicate groups"
set DuplicateGames				"Games in duplicate groups"
set DeletedGames					"Deleted games"
set LargestGroup					"Largest group"
set TopOpening						"Top opening"
set CompactionStatus				"Compaction"
set CompactionNeeded				"Recommended"
set CompactionNotNeeded			"Not needed"
set NoOpeningsFound				"No openings found."
set DuplicateColSize				"Size"
set DuplicateColGames				"Games"
set DuplicateSummary				"%s groups, %s games"
set SelectExtraGames				"Select Extras"
set WhiteTrend						"White-leaning"
set DrawTrend						"Draw-heavy"
set BlackTrend						"Black-leaning"
set BalancedTrend					"Balanced"
set MarkDeleted					"Mark as deleted"

} ;# namespace mc

proc MaintenanceDialogName {file} {
	return .maintenance_[string map {: _ . _ / _ " " _} $file]
}


proc SelectedMaintenanceEco {dlg {warn 1}} {
	variable ReportData
	variable mc

	if {![winfo exists $dlg]} { return {} }
	set ecoTv $ReportData($dlg,ecoTv)
	set selection [$ecoTv selection]
	if {[llength $selection] == 0} {
		if {$warn} {
			::dialog::info -parent $dlg -message $mc::RepertoireNoEcoSelection
		}
		return {}
	}

	set item [lindex $selection 0]
	return [lindex [$ecoTv item $item -values] 0]
}


proc OpenMaintenanceEcoInSwitcher {dlg} {
	variable ReportData

	set eco [SelectedMaintenanceEco $dlg]
	if {![string length $eco]} { return 0 }

	set file $ReportData($dlg,file)
	set variant $ReportData($dlg,variant)
	set view $ReportData($dlg,ecoView)

	::scidb::view::search $file $variant $view null none [list eco $eco]
	return [OpenFilteredViewInSwitcher $dlg $file $variant $view maintenance-eco $eco]
}


proc SaveMaintenanceEcoWorkingSet {dlg} {
	variable ReportData

	set eco [SelectedMaintenanceEco $dlg]
	if {![string length $eco]} { return 0 }

	set file $ReportData($dlg,file)
	set variant $ReportData($dlg,variant)
	set view $ReportData($dlg,ecoView)

	::scidb::view::search $file $variant $view null none [list eco $eco]
	return [SaveFilteredViewAsWorkingSet $dlg $file $variant $view maintenance-eco $eco]
}


proc CollectMaintenanceData {file variant} {
	set groups [::scidb::db::findDuplicates $file $variant]
	set rows [::scidb::db::ecoStats $file $variant]
	set deleted [lindex [::scidb::db::get stats $file] 0]
	set active [::scidb::db::count games $file $variant]
	set total [::scidb::db::count total $file]
	if {[::scidb::db::get compact? $file $variant]} {
		set compact $mc::CompactionNeeded
	} else {
		set compact $mc::CompactionNotNeeded
	}

	set duplicateGames 0
	set largestGroup 0
	foreach group $groups {
		set n [llength $group]
		incr duplicateGames $n
		if {$n > $largestGroup} { set largestGroup $n }
	}

	set topEco "?"
	set topTotal 0
	foreach row $rows {
		lassign $row eco totalEco
		if {$totalEco > $topTotal} {
			set topTotal $totalEco
			set topEco $eco
		}
	}
	if {$topTotal > 0} {
		set topEco "$topEco ($topTotal)"
	} else {
		set topEco $mc::NoOpeningsFound
	}

	return [dict create \
		file $file \
		variant $variant \
		groups $groups \
		rows $rows \
		deleted $deleted \
		active $active \
		total $total \
		duplicateGroups [llength $groups] \
		duplicateGames $duplicateGames \
		largestGroup $largestGroup \
		openings [llength $rows] \
		topEco $topEco \
		compact $compact]
}


proc OpenMaintenanceReport {parent file variant {tab overview}} {
	variable ReportData

	set dlg [MaintenanceDialogName $file]
	set isNew [expr {![winfo exists $dlg]}]
	set resetEcoView 0
	set oldVariant {}

	if {!$isNew && [info exists ReportData($dlg,ecoView)]} {
		if {[info exists ReportData($dlg,variant)]} {
			set oldVariant $ReportData($dlg,variant)
		}
		if {![info exists ReportData($dlg,variant)] || $ReportData($dlg,variant) ne $variant} {
			set resetEcoView 1
		}
	}

	if {$isNew} {
		toplevel $dlg -class Scidb
		wm transient $dlg [winfo toplevel $parent]
		wm protocol $dlg WM_DELETE_WINDOW [list destroy $dlg]
		wm resizable $dlg true true

		set actions [ttk::frame $dlg.actions]
		pack $actions -side top -fill x -padx 6 -pady {6 2}

		ttk::button $actions.duplicates -text $mc::ReviewDuplicates \
			-command [namespace code [list SelectMaintenanceTab $dlg duplicates]]
		ttk::button $actions.compact -text $mc::CompactNow \
			-command [namespace code [list CompactReportDatabase $dlg]]
		ttk::button $actions.convert -text $mc::ConvertDatabase \
			-command [namespace code [list ConvertReportDatabase $dlg]]
		ttk::button $actions.copy -text $mc::CopySummary \
			-command [namespace code [list CopyMaintenanceSummary $dlg]]
		ttk::button $actions.refresh -text $mc::Refresh \
			-command [namespace code [list RefreshMaintenanceReport $dlg]]
		ttk::button $actions.close -text $mc::Close -command [list destroy $dlg]
		pack $actions.duplicates -side left -padx {0 4}
		pack $actions.compact -side left -padx 4
		pack $actions.convert -side left -padx 4
		pack $actions.copy -side left -padx 4
		pack $actions.refresh -side left -padx 4
		pack $actions.close -side right

		set nb [ttk::notebook $dlg.nb -takefocus 1]
		::ttk::notebook::enableTraversal $nb
		pack $nb -fill both -expand yes -padx 6 -pady 6

		set overview [ttk::frame $nb.overview]
		set duplicates [ttk::frame $nb.duplicates]
		set openings [ttk::frame $nb.openings]
		$nb add $overview -text $mc::MaintenanceOverview
		$nb add $duplicates -text $mc::MaintenanceDuplicates
		$nb add $openings -text $mc::MaintenanceOpenings

		set summary [ttk::labelframe $overview.summary -text $mc::MaintenanceOverview]
		pack $summary -fill x -expand no -padx 2 -pady 2
		foreach {key label row} [list \
			total $mc::EcoColTotal 0 \
			deleted $mc::DeletedGames 1 \
			groups $mc::DuplicateGroups 2 \
			dupgames $mc::DuplicateGames 3 \
			largest $mc::LargestGroup 4 \
			openings $mc::OpeningsCovered 5 \
			topEco $mc::TopOpening 6 \
			compact $mc::CompactionStatus 7] {
			ttk::label $summary.l_$key -text $label
			ttk::label $summary.v_$key -anchor w
			grid $summary.l_$key -row $row -column 0 -sticky w -padx 6 -pady 2
			grid $summary.v_$key -row $row -column 1 -sticky ew -padx 6 -pady 2
		}
		grid columnconfigure $summary 1 -weight 1

		set dupSummary [ttk::label $duplicates.summary -anchor w]
		pack $dupSummary -side top -fill x -padx 2 -pady {2 4}

		set dupBody [ttk::frame $duplicates.body]
		pack $dupBody -side top -fill both -expand yes
		set dupTv [ttk::treeview $dupBody.tv \
			-columns {index size games} \
			-displaycolumns {size games} \
			-show {tree headings} \
			-selectmode extended \
			-yscrollcommand [list $dupBody.vsb set]]
		$dupTv heading #0 -text "Group"
		$dupTv column index -width 0 -stretch 0
		$dupTv heading size -text $mc::DuplicateColSize -anchor e
		$dupTv heading games -text $mc::DuplicateColGames -anchor w
		$dupTv column #0 -width 240
		$dupTv column size -width 70 -anchor e
		$dupTv column games -width 280 -anchor w
		ttk::scrollbar $dupBody.vsb -orient vertical -command [list $dupTv yview]
		grid $dupTv -row 0 -column 0 -sticky nsew
		grid $dupBody.vsb -row 0 -column 1 -sticky ns
		grid rowconfigure $dupBody 0 -weight 1
		grid columnconfigure $dupBody 0 -weight 1

		set dupButtons [ttk::frame $duplicates.buttons]
		pack $dupButtons -side bottom -fill x -pady {4 0}
		ttk::button $dupButtons.browse -text $::browser::mc::BrowseGame
		ttk::button $dupButtons.select -text $mc::SelectExtraGames \
			-command [namespace code [list SelectDuplicateExtras $dupTv]]
		ttk::button $dupButtons.mark -text $mc::MarkDeleted
		pack $dupButtons.browse -side left -padx {0 4}
		pack $dupButtons.select -side left -padx {0 4}
		pack $dupButtons.mark -side left
		if {[llength [info commands ::ai::duplicate::reviewGroup]]} {
			ttk::button $dupButtons.check -text $mc::CheckDuplicateGroup
			ttk::label $dupButtons.verdict -anchor w
			pack $dupButtons.check -side left -padx {8 4}
			pack $dupButtons.verdict -side left -padx {4 0} -fill x -expand yes
		}

		set ecoSummary [ttk::label $openings.summary -anchor w]
		pack $ecoSummary -side top -fill x -padx 2 -pady {2 4}

		set ecoButtons [ttk::frame $openings.buttons]
		pack $ecoButtons -side bottom -fill x -pady {4 0}
		ttk::button $ecoButtons.switcher -text $mc::RepertoireOpenInSwitcher \
			-command [namespace code [list OpenMaintenanceEcoInSwitcher $dlg]]
		ttk::button $ecoButtons.savews -text $mc::SaveWorkingSet \
			-command [namespace code [list SaveMaintenanceEcoWorkingSet $dlg]]
		pack $ecoButtons.switcher -side left -padx {0 4}
		pack $ecoButtons.savews -side left

		set ecoBody [ttk::frame $openings.body]
		pack $ecoBody -side top -fill both -expand yes
		set ecoTv [ttk::treeview $ecoBody.tv \
			-columns {eco total white draw black whitepct drawpct blackpct trend} \
			-displaycolumns {eco total white draw black whitepct drawpct blackpct trend} \
			-show headings \
			-selectmode browse \
			-yscrollcommand [list $ecoBody.vsb set]]
		foreach {col label anchor width} [list \
			eco $mc::EcoColEco w 70 \
			total $mc::EcoColTotal e 70 \
			white $mc::EcoColWhite e 70 \
			draw $mc::EcoColDraw e 70 \
			black $mc::EcoColBlack e 70 \
			whitepct $mc::EcoColWhitePct e 75 \
			drawpct $mc::EcoColDrawPct e 75 \
			blackpct $mc::EcoColBlackPct e 75 \
			trend $mc::EcoColTrend w 120] {
			$ecoTv heading $col -text $label -anchor $anchor \
				-command [namespace code [list SortMaintenanceEco $dlg $col]]
			$ecoTv column $col -width $width -anchor $anchor
		}
		ttk::scrollbar $ecoBody.vsb -orient vertical -command [list $ecoTv yview]
		grid $ecoTv -row 0 -column 0 -sticky nsew
		grid $ecoBody.vsb -row 0 -column 1 -sticky ns
		grid rowconfigure $ecoBody 0 -weight 1
		grid columnconfigure $ecoBody 0 -weight 1

		set ReportData($dlg,nb) $nb
		set ReportData($dlg,dupTv) $dupTv
		set ReportData($dlg,ecoTv) $ecoTv
		set ReportData($dlg,ecoView) \
			[::scidb::view::new $file $variant unused unused unused unused master slave]
		set ReportData($dlg,ecoSortColumn) total
		set ReportData($dlg,ecoSortDirection) decreasing
		bind $ecoTv <Double-1> [namespace code [list OpenMaintenanceEcoInSwitcher $dlg]]
		bind $ecoTv <Return> [namespace code [list OpenMaintenanceEcoInSwitcher $dlg]]
		bind $dlg <Destroy> [namespace code [list CloseMaintenanceReport %W]]
	}

	set ReportData($dlg,file) $file
	set ReportData($dlg,variant) $variant
	if {$resetEcoView} {
		catch {
			::scidb::view::close \
				$file \
				$oldVariant \
				$ReportData($dlg,ecoView)
		}
		set ReportData($dlg,ecoView) \
			[::scidb::view::new $file $variant unused unused unused unused master slave]
	}
	set ReportData($dlg,data) [CollectMaintenanceData $file $variant]
	$dlg.nb.duplicates.buttons.browse configure \
		-command [namespace code [list BrowseDuplicateSelection $ReportData($dlg,dupTv) $file $variant]]
	$dlg.nb.duplicates.buttons.mark configure \
		-command [namespace code [list MarkDuplicates $ReportData($dlg,dupTv) $file $variant]]
	if {[winfo exists $dlg.nb.duplicates.buttons.check]} {
		$dlg.nb.duplicates.buttons.check configure \
			-command [namespace code [list CheckDuplicateGroup \
				$ReportData($dlg,dupTv) $file $variant $dlg.nb.duplicates.buttons.verdict]]
	}
	bind $ReportData($dlg,dupTv) <Double-1> \
		[namespace code [list BrowseDuplicateSelection $ReportData($dlg,dupTv) $file $variant]]
	bind $ReportData($dlg,dupTv) <Return> \
		[namespace code [list BrowseDuplicateSelection $ReportData($dlg,dupTv) $file $variant]]

	PopulateMaintenanceReport $dlg
	SelectMaintenanceTab $dlg $tab

	wm title $dlg [format $mc::MaintenanceReportTitle [::util::databaseName $file]]
	if {$isNew} {
		::util::place $dlg -parent $parent -position center
		wm deiconify $dlg
		focus $ReportData($dlg,nb)
	} else {
		raise $dlg
	}
}


proc CloseMaintenanceReport {dlg} {
	variable ReportData

	if {![string match .maintenance_* $dlg]} { return }
	if {[info exists ReportData($dlg,ecoView)]} {
		catch {
			::scidb::view::close \
				$ReportData($dlg,file) \
				$ReportData($dlg,variant) \
				$ReportData($dlg,ecoView)
		}
	}
	foreach key [array names ReportData $dlg,*] {
		unset ReportData($key)
	}
}


proc SelectMaintenanceTab {dlg tab} {
	variable ReportData

	set nb $ReportData($dlg,nb)
	switch -- $tab {
		duplicates	{ $nb select $nb.duplicates }
		openings		{ $nb select $nb.openings }
		default		{ $nb select $nb.overview }
	}
}


proc FormatPercent {value total} {
	if {$total <= 0} { return "0.0" }
	return [format %.1f [expr {100.0*$value/double($total)}]]
}


proc EcoTrend {white draws black} {
	if {$white > $draws && $white > $black} { return $mc::WhiteTrend }
	if {$black > $white && $black > $draws} { return $mc::BlackTrend }
	if {$draws > $white && $draws > $black} { return $mc::DrawTrend }
	return $mc::BalancedTrend
}


proc MaintenanceSummaryText {data} {
	return [join [list \
		"[::locale::formatNumber [dict get $data total]] $mc::EcoColTotal" \
		"[::locale::formatNumber [dict get $data deleted]] $mc::DeletedGames" \
		"[::locale::formatNumber [dict get $data duplicateGroups]] $mc::DuplicateGroups" \
		"[::locale::formatNumber [dict get $data duplicateGames]] $mc::DuplicateGames" \
		"$mc::TopOpening: [dict get $data topEco]" \
		"$mc::CompactionStatus: [dict get $data compact]"] "\n"]
}


proc CopyMaintenanceSummary {dlg} {
	variable ReportData
	clipboard clear
	clipboard append [MaintenanceSummaryText $ReportData($dlg,data)]
}


proc CompactReportDatabase {dlg} {
	variable ReportData
	Compact $dlg $ReportData($dlg,file)
	after idle [namespace code [list RefreshMaintenanceReport $dlg]]
}


proc ConvertReportDatabase {dlg} {
	variable ReportData
	ConvertDatabase $dlg $ReportData($dlg,file) $ReportData($dlg,variant)
}


proc ConvertDatabase {parent file variant} {
	variable mc

	if {[::scidb::db::get unsaved? $file]} {
		::dialog::error -parent $parent -message $mc::UnsavedFiles
		return
	}

	set reply [::dialog::question -parent $parent -message $mc::ConvertQuestion -default no]
	set version [expr { $reply eq "yes" ? 95 : 96 }]

	set title $mc::ConvertTitle
	set dstFile [::dialog::saveFile \
		-parent $parent \
		-class database \
		-filetypes [list [list $mc::ScidbBases {.sci}]] \
		-geometry last \
		-defaultextension .sci \
		-title "$title ($version)" \
		-customicon $::icon::16x16::filetypeArchive]
	if {[llength $dstFile] == 0} { return }
	lassign $dstFile dst dstEncoding

	if {[file exists $dst]} {
		::dialog::error -parent $parent -title $title \
			-message [format $mc::DatabaseAlreadyOpen [::util::databaseName $dst]]
		return
	}

	::scidb::db::setcreationversion $version
	if {[catch {
		::scidb::db::new $dst $variant [::application::database::lookupType Unspecific]
		::scidb::db::attach $dst $dst
	} rc opts]} {
		::scidb::db::setcreationversion 96
		return {*}$opts -rethrow 1 $rc
	}
	::scidb::db::setcreationversion 96	;# restore default (docs §3)

	set cmd [list ::scidb::db::copy $file $dst {}]
	if {[catch { ::util::catchException $cmd result } rc opts]} {
		::log::error $::import::mc::AbortedDueToInternalError
		return {*}$opts -rethrow 1 $rc
	}

	if {[catch { ::scidb::db::save $dst } rc opts]} {
		::log::error $::import::mc::AbortedDueToIoError
		return {*}$opts -rethrow 1 $rc
	}

	lassign $result total illegal accepted rejected
	::scidb::db::close $dst

	::dialog::info -parent $parent -title $mc::ConvertTitle \
		-message [format $mc::ConvertDone $total [::util::databaseName $dst]]
}


proc RefreshMaintenanceReport {dlg} {
	variable ReportData

	if {![winfo exists $dlg]} { return }

	set file $ReportData($dlg,file)
	set variant $ReportData($dlg,variant)
	set ReportData($dlg,data) [CollectMaintenanceData $file $variant]
	PopulateMaintenanceReport $dlg
}


proc PopulateMaintenanceReport {dlg} {
	variable ReportData

	set data $ReportData($dlg,data)
	set dupTv $ReportData($dlg,dupTv)
	set ecoTv $ReportData($dlg,ecoTv)

	$dlg.nb.overview.summary.v_total configure \
		-text [::locale::formatNumber [dict get $data total]]
	$dlg.nb.overview.summary.v_deleted configure \
		-text [::locale::formatNumber [dict get $data deleted]]
	$dlg.nb.overview.summary.v_groups configure \
		-text [::locale::formatNumber [dict get $data duplicateGroups]]
	$dlg.nb.overview.summary.v_dupgames configure \
		-text [::locale::formatNumber [dict get $data duplicateGames]]
	$dlg.nb.overview.summary.v_largest configure \
		-text [::locale::formatNumber [dict get $data largestGroup]]
	$dlg.nb.overview.summary.v_openings configure \
		-text [::locale::formatNumber [dict get $data openings]]
	$dlg.nb.overview.summary.v_topEco configure -text [dict get $data topEco]
	$dlg.nb.overview.summary.v_compact configure -text [dict get $data compact]

	$dlg.nb.duplicates.summary configure -text [format $mc::DuplicateSummary \
		[::locale::formatNumber [dict get $data duplicateGroups]] \
		[::locale::formatNumber [dict get $data duplicateGames]]]

	$dupTv delete [$dupTv children {}]
	set g 1
	foreach group [dict get $data groups] {
		set n [llength $group]
		set gameList {}
		foreach idx $group {
			lappend gameList "#[expr {$idx + 1}]"
		}
		set gid [$dupTv insert {} end \
			-text [format $mc::DuplicatesGroup $g $n] \
			-values [list {} $n [join $gameList { }]] \
			-open true]
		foreach idx $group {
			$dupTv insert $gid end \
				-text "Game [expr {$idx + 1}]" \
				-values [list [expr {$idx + 1}] {} "#[expr {$idx + 1}]"]
		}
		incr g
	}

	SortMaintenanceEco $dlg $ReportData($dlg,ecoSortColumn) 1

	set state [expr {[dict get $data deleted] > 0 ? "normal" : "disabled"}]
	$dlg.actions.compact configure -state $state
	set state [expr {[dict get $data duplicateGroups] > 0 ? "normal" : "disabled"}]
	$dlg.actions.duplicates configure -state $state
	$dlg.nb.duplicates.buttons.browse configure -state $state
	$dlg.nb.duplicates.buttons.select configure -state $state
	$dlg.nb.duplicates.buttons.mark configure -state $state
	if {[winfo exists $dlg.nb.duplicates.buttons.check]} {
		$dlg.nb.duplicates.buttons.check configure -state $state
	}
	set state [expr {[llength [dict get $data rows]] > 0 ? "normal" : "disabled"}]
	$dlg.nb.openings.buttons.switcher configure -state $state
	$dlg.nb.openings.buttons.savews configure -state $state
}


proc SortMaintenanceEco {dlg column {preserveDirection 0}} {
	variable ReportData

	if {!$preserveDirection} {
		if {$ReportData($dlg,ecoSortColumn) eq $column} {
			set ReportData($dlg,ecoSortDirection) [expr {
				$ReportData($dlg,ecoSortDirection) eq "increasing" ? "decreasing" : "increasing"
			}]
		} else {
			set ReportData($dlg,ecoSortColumn) $column
			set ReportData($dlg,ecoSortDirection) [expr {$column eq "eco" || $column eq "trend" ? "increasing" : "decreasing"}]
		}
	}

	set rows [dict get $ReportData($dlg,data) rows]
	set cooked {}
	foreach row $rows {
		lassign $row eco total white draws black
		set whitePct [FormatPercent $white $total]
		set drawPct [FormatPercent $draws $total]
		set blackPct [FormatPercent $black $total]
		set trend [EcoTrend $white $draws $black]
		lappend cooked [list \
			eco $eco \
			total $total \
			white $white \
			draw $draws \
			black $black \
			whitepct $whitePct \
			drawpct $drawPct \
			blackpct $blackPct \
			trend $trend]
	}

	set numericColumns {total white draw black whitepct drawpct blackpct}
	if {$column in $numericColumns} {
		set option [expr {$ReportData($dlg,ecoSortDirection) eq "increasing" ? "-increasing" : "-decreasing"}]
		set cooked [lsort $option -real -index [expr {[lsearch {eco total white draw black whitepct drawpct blackpct trend} $column]*2 + 1}] $cooked]
	} else {
		set option [expr {$ReportData($dlg,ecoSortDirection) eq "increasing" ? "-increasing" : "-decreasing"}]
		set cooked [lsort $option -dictionary -index [expr {[lsearch {eco total white draw black whitepct drawpct blackpct trend} $column]*2 + 1}] $cooked]
	}

	set ecoTv $ReportData($dlg,ecoTv)
	$ecoTv delete [$ecoTv children {}]
	foreach row $cooked {
		array set item $row
		$ecoTv insert {} end -values [list \
			$item(eco) $item(total) $item(white) $item(draw) $item(black) \
			$item(whitepct) $item(drawpct) $item(blackpct) $item(trend)]
	}

	if {[llength $cooked] > 0} {
		set top [lindex $cooked 0]
		array set item $top
		$dlg.nb.openings.summary configure -text "$mc::TopOpening: $item(eco) ($item(total))"
	} else {
		$dlg.nb.openings.summary configure -text $mc::NoOpeningsFound
	}
}


proc SelectDuplicateExtras {tv} {
	$tv selection set {}
	foreach group [$tv children {}] {
		set children [$tv children $group]
		set extra [lrange $children 1 end]
		if {[llength $extra]} {
			$tv selection add $extra
		}
	}
}


proc BrowseDuplicateSelection {tv file variant} {
	set selected [$tv selection]
	if {[llength $selected] == 0} {
		set focus [$tv focus]
		if {[string length $focus]} {
			set selected [list $focus]
		}
	}
	if {[llength $selected] == 0} { return }

	set item [lindex $selected 0]
	if {[$tv parent $item] eq {}} {
		set children [$tv children $item]
		if {[llength $children] == 0} { return }
		set item [lindex $children 0]
	}

	set index [lindex [$tv item $item -values] 0]
	if {$index eq {}} { return }
	::game::new $tv -base $file -variant $variant -number [expr {$index - 1}]
}


# Audit A5: the first game of the selected duplicate group against each other
# one, labelled same / different / unsure by ::ai::duplicate. Advice only: it
# never marks, merges or deletes anything.
proc CheckDuplicateGroup {tv file variant label} {
	set item [lindex [$tv selection] 0]
	if {$item eq {}} { set item [$tv focus] }
	if {$item eq {}} { return }
	if {[$tv parent $item] ne {}} { set item [$tv parent $item] }

	set numbers {}
	foreach child [$tv children $item] {
		set index [lindex [$tv item $child -values] 0]
		if {$index ne {}} { lappend numbers [expr {$index - 1}] }
	}
	if {[llength $numbers] < 2} { return }

	$label configure -text "..."
	::ai::duplicate::reviewGroup $file $variant $numbers \
		[namespace code [list ShowDuplicateVerdicts $label]]
}


proc ShowDuplicateVerdicts {label results} {
	variable mc

	if {![winfo exists $label]} { return }
	set parts {}
	foreach r $results {
		lassign $r number verdict source
		lappend parts [format $mc::DuplicateVerdict [expr {$number + 1}] \
			[::ai::duplicate::describe $verdict]]
	}
	$label configure -text [join $parts "; "]
}


} ;# namespace database
} ;# namespace application

# vi:set ts=3 sw=3:
