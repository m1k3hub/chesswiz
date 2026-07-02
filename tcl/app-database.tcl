# ======================================================================
# Author : $Author$
# Version: $Revision: 1523 $
# Date   : $Date: 2018-09-17 08:11:58 -0400 (Mon, 17 Sep 2018) $
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

::util::source database-pane

namespace eval application {
namespace eval database {
namespace eval mc {

set FileOpen							"Open Database"
set FileOpenRecent					"Open Recent"
set FileNew								"New Database"
set FileExport							"Export"
set FileImport(pgn)					"Import PGN files"
set FileImport(db)					"Import Databases"
set FileCreate							"Create Archive"
set FileSaveChanges					"Save Changes"
set FileClose							"Close"
set FileMaintenance					"Maintenance"
set FileConvertToScidb				"Convert to .sci"
set FileCompact						"Compact"
set FileStripMoveInfo				"Strip Move Information"
set FileStripPGNTags					"Strip PGN Tags"
set HelpSwitcher						"Help for Database Switcher"

set File									"File"
set SymbolSize							"Symbol Size"
set Large								"Large"
set Medium								"Medium"
set Small								"Small"
set Tiny									"Tiny"
set LoadMessage						"Opening database '%s'"
set UpgradeMessage					"Upgrading database '%s'"
set CompactMessage					"Compacting database '%s'"
set CannotOpenFile					"Cannot open file '%s'."
set EncodingFailed					"Character decoding %s failed."
set DatabaseAlreadyOpen				"Database '%s' is already open."
set Properties							"Properties"
set Preload								"Preload"
set MissingEncoding					"Missing character encoding %s (using %s instead)"
set DescriptionTooLarge				"Description is too large."
set DescrTooLargeDetail				"The entry contains %d characters, but only %d characters are allowed."
set ClipbaseDescription				"Temporary database, not kept on disk."
set HardLinkDetected					"Cannot load file '%file1' because it is already loaded as file '%file2'. This can only happen if hard links are involved."
set HardLinkDetectedDetail			"If we load this database twice the application may crash due to the usage of threads."
set OverwriteExistingFiles			"Overwrite exisiting files in directory '%s'?"
set SelectDatabases					"Select the databases to be opened"
set ExtractArchive					"Extract archive %s"
set SelectVariant						"Select Variant"
set Example								"Example"
set UnsavedFiles						"This PGN file is unsaved."
set FileIsRemoved						"File '%s' is removed. Please use the export dialog if you like to save this database."
set FileIsNotWritable				"File '%s' is not writeable. Please use the export dialog if you like to save this database, or set this file writeable."
set OverwriteOriginalFile			"Important note: The original file '%s' will be overwritten."
set SetupPgnOptions					"Probably the PGN options should be set before saving."
set CloseAllDeletedGames			"Close all deleted games of database '%s'?"
set CannotCompactDatabase			"Cannot compact database because the following games belonging to this database are modified:"

set RecodingDatabase					"Recoding %base from %from to %to"
set RecodedGames						"%s game(s) recoded"

set ChangeIcon							"Change Icon"
set MarkAsRepertoire					"Mark As Opening Database"
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
set Recode								"Recode"
set EditDescription					"Edit Description"
set EmptyClipbase						"Empty Clipbase"

set Maintenance						"Maintenance"
set PreferScidbTitle				"Convert '%s' to .sci?"
set PreferScidbMessage				"This workflow is optimized for Scidb databases (.sci)."
set PreferScidbDetail				"For best speed on large databases, convert '%s' to .sci before using %s. You can continue with the current format, but it may be slow."
set ContinueAnyway					"Continue"
set ConvertNow						"Convert Now"
set StripMoveInfo						"Strip move information from database '%s'"
set StripPGNTags						"Strip PGN tags from database '%s'"
set GamesStripped(0)					"No game stripped"
set GamesStripped(1)					"One game stripped"
set GamesStripped(N)					"%s games stripped"
set GamesRemoved(0)					"No game removed"
set GamesRemoved(1)					"One game removed"
set GamesRemoved(N)					"%s games removed"
set AllGamesMustBeClosed			"All games must be closed before this operation can be done."
set ReallyCompact						"Really compact database '%s'?"
set ReallyCompactDetail(1)			"Only one game will be deleted."
set ReallyCompactDetail(N)			"%s games will be deleted."
set RemoveSpace						"Some empty spaces will be removed."
set CompactionRecommended			"It is recommended to compact the database."
set SearchPGNTags						"Searching for PGN tags"
set SelectSuperfluousTags			"Select superfluous tags:"
set WillBePermanentlyDeleted		"Please note: This action will permanently delete the concerned information from database."
set ReadWriteFailed					"Setting the database writable failed:"
set NoExtraTagsFound					"No tags found for deletion."

set FindDuplicates					"Find Duplicates"
set EcoStats							"Opening Report"
set SearchByMaterial				"Search by Material"
set SearchByRating					"Search by Rating"
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
set OpeningPrepTitle				"Opening Prep for '%s'"
set OpeningPrepSearching			"Searching reference moves for the current position..."
set OpeningPrepNoMoves				"No moves found for the current position."
set OpeningPrepUnsupported		"Opening prep is currently available only for the normal chess variant."
set OpeningPrepRefresh				"Refresh"
set OpeningPrepPlayMove			"Play Selected Move"
set OpeningPrepLoadGame			"Load First Game"
set OpeningPrepOpenEco			"ECO Stats"
set OpeningPrepOpenInSwitcher	"Open Selected ECO Games In Switcher"
set OpeningPrepSaveWorkingSet	"Save Selected ECO Games Working Set..."
set OpeningPrepMethod				"Method"
set OpeningPrepRareOnly			"Low-frequency moves only"
set OpeningPrepRareLimit			"Max games"
set OpeningPrepRareNoMoves		"No low-frequency moves found for the current position."
set OpeningPrepRareSummary		"Low-frequency moves: %s candidate moves, %s games, top move %s"
set OpeningPrepRareStatus		"Showing moves with %s games or fewer."
set OpeningPrepSummaryNone		"Current position: no move statistics loaded"
set OpeningPrepSummary			"Current position: %s candidate moves, %s games, top move %s"
set OpeningPrepRefBase				"Reference database"
set OpeningPrepPosition			"Position"
set OpeningPrepStatus				"Status"
set OpeningPrepColMove			"Move"
set OpeningPrepColEco				"ECO"
set OpeningPrepColFreq			"Games"
set OpeningPrepColScore			"Score"
set OpeningPrepColDraws			"Draw %"
set OpeningPrepColResult			"Result"
set OpeningPrepColAvgRating		"Avg %s"
set OpeningPrepColLastYear		"Last"
set OpeningPrepColBestPlayer		"Best Player"
set OpeningPrepNoSelection		"No move is selected."
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
set CompactNow						"Compact Now"
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
set Close							"Close"

set T_Unspecific						"Unspecific"
set T_Temporary						"Temporary"
set T_Work								"Work"
set T_Clipbase							"Clipbase"
set T_MyGames							"My Games"
set T_Informant						"Informant"
set T_LargeDatabase					"Large Database"
set T_CorrespondenceChess			"Correspondence Chess"
set T_EmailChess						"Email Chess"
set T_InternetChess					"Internet Chess"
set T_ComputerChess					"Computer Chess"
set T_Chess960							"Chess 960"
set T_PlayerCollection				"Player Collection"
set T_PlayerCollectionFemale		"Player Collection"
set T_Tournament						"Tournament"
set T_TournamentSwiss				"Tournament Swiss"
set T_GMGames							"GM Games"
set T_IMGames							"IM Games"
set T_BlitzGames						"Blitz Games"
set T_Tactics							"Tactics"
set T_Endgames							"Endgames"
set T_Analysis							"Analysis"
set T_Training							"Training"
set T_Match								"Match"
set T_Studies							"Studies"
set T_Jewels							"Jewels"
set T_Problems							"Problems"
set T_Patzer							"Patzer"
set T_Gambit							"Gambit"
set T_Important						"Important"
set T_Openings							"Openings"
set T_OpeningsWhite					"Openings White"
set T_OpeningsBlack					"Openings Black"
set T_PGNFile							"PGN file"
set T_Bughouse							"Bughouse"
set T_Antichess						"Antichess"
set T_ThreeCheck						"Three-check"
set T_Crazyhouse						"Crazyhouse"

set OpenDatabase						"Open Database"
set OpenRecentDatabase				"Open Recent Database"
set NewDatabase						"New Database"
set CloseDatabase						"Close Database '%s'"
set SetReadonly						"Set Database '%s' readonly"
set SetWriteable						"Set Database '%s' writable"

set OpenReadonly						"Open readonly"
set OpenWriteable						"Open writable"

set UpgradeDatabase					"%s is an old format database that cannot be opened writable.\n\nUpgrading will create a new version of the database and after that remove the original files.\n\nThis may take a while, but it only needs to be done one time.\n\nDo you want to upgrade this database now?"
set UpgradeDatabaseDetail			"\"No\" will open the database readonly, and you cannot set it writable."

set MoveInfo(evaluation)			"Evaluation"
set MoveInfo(playersClock)			"Players Clock"
set MoveInfo(elapsedGameTime)		"Elapsed Game Time"
set MoveInfo(elapsedMoveTime)		"Elapsed Move Time"
set MoveInfo(elapsedMilliSecs)	"Elapsed Milliseconds"
set MoveInfo(clockTime)				"Clock Time"
set MoveInfo(corrChessSent)		"Correspondence Chess Sent"
set MoveInfo(videoTime)				"Video Time"

}

set MoveInfoExample(evaluation)			{ {[%eval -6.05]}		{-6.05} }
set MoveInfoExample(playersClock)		{ {[%clk 1:05:23]}	{clk 1:05:23} }
set MoveInfoExample(elapsedGameTime)	{ {[%egt 1:25:42]}	{egt 1:25:42} }
set MoveInfoExample(elapsedMoveTime)	{ {[%emt 0:05:42]}	{emt 0:05:42} }
set MoveInfoExample(elapsedMilliSecs)	{ {[%emt 102.34]}		{emt 102.34} }
set MoveInfoExample(clockTime)			{ {[%ct 17:10:42]}	{ct 17:10:42} }
set MoveInfoExample(corrChessSent)		{ {[%ccsnt 2011.06.16, 17:53:02]} {2011.06.16, 17:53:02} }
set MoveInfoExample(videoTime)			{ {[%vt 122.44]}		{vt 122.44} }

set MoveInfoAttrs {evaluation playersClock elapsedGameTime elapsedMoveTime
							elapsedMilliSecs clockTime corrChessSent videoTime}

set Variants {Normal ThreeCheck Bughouse Crazyhouse Antichess Losers}
set Tabs {games player event site annotator position}

array set Vars {
	selection		0
	icon				0
	ignore-next		0
	counter			0
	motion			-1
	current			-1
	afterid			{}
	showDisabled	0
	pressed			0
	dragging			0
	mintabs			3
}


array set Options {
	visible 10
}

variable PreOpen			{}
variable RecentFiles		{}
variable RecentURL		{}
variable MaxHistory		10
variable CurrentBase		""
array set NonSciWorkflowAdvice {}
array set MaterialSearchPresets {}
array set RatingSearchPresets {}
array set AdvancedSearchPresets {}

array set Positions		{}

set Types(sci)				[::scidb::db::get types sci]
set Types(si3)				[::scidb::db::get types si3]
set Types(si4)				[::scidb::db::get types si4]


proc build {tab width height} {
	variable ::scidb::clipbaseName
	variable Variants
	variable Vars
	variable Tabs

	set ::util::clipbaseName [set [namespace current]::mc::T_Clipbase]

	set main [tk::panedwindow $tab.main \
		-orient vertical \
		-opaqueresize true \
		-borderwidth 0 \
	]
	pack $main -fill both -expand yes

	set contents [::ttk::notebook $tab.contents -class UndockingNotebook -takefocus 1]
	::ttk::notebook::enableTraversal $contents
	::theme::configurePanedWindow $main
	set switcher [::database::switcher $main.switcher \
		-switchcmd [namespace current]::switchToBase \
		-updatecmd [namespace current]::UpdateVariants \
		-popupcmd [namespace current]::PopupMenu \
		-opencmd [namespace current]::OpenBase \
	]

	$main add $switcher
	$main add $contents

	foreach tab $Tabs {
		::ttk::frame $contents.$tab -class Scidb
		set var [namespace parent]::mc::Tab($tab)
		$contents add $contents.$tab -sticky nsew -compound right
		if {$Vars(showDisabled)} { $contents tab $contents.$tab -image $icon::16x16::undock_disabled }
		::widget::notebookSetLabel $contents $contents.$tab [set $var]
		${tab}::build $contents.$tab
		set Vars($tab) $contents.$tab
		bind $contents.$tab <Destroy> [namespace code [list DestroyTab %W $contents.$tab]]
	}
	set Vars(twm) $Vars([lindex $Tabs 0]).twm

	$main paneconfigure $switcher -sticky nsew -stretch never
	$main paneconfigure $contents -sticky nsew -stretch always

	bind $contents.games <<TableMinSize>> \
		[namespace code [list TableMinSize $main $contents $switcher %d]]
	set Vars(configure) [namespace code [list Configure $main $contents $switcher %h]]
	set Vars(configure:height) 0
	bind $main <Configure> $Vars(configure)

	bind $main <Double-Button-1> { break }
	bind $main <Double-Button-2> { break }
	bind $main <<FontSizeChanged>> [namespace code { FontSizeChanged %W }]

	::toolbar::setup $switcher -id database
	set tbFile [::toolbar::toolbar $switcher \
		-hide 1 \
		-id database-switcher \
		-tooltipvar [namespace current]::mc::File \
	]

	foreach event {ToolbarShow ToolbarHide ToolbarFlat ToolbarIcon} {
		bind $tbFile <<$event>> [namespace code [list ToolbarShow $switcher]]
	}

	set Vars(button:new) [::toolbar::add $tbFile dropdownbutton \
		-image $::icon::toolbarDocNew \
		-tooltip "$mc::NewDatabase ($::mc::VariantName(Normal))..." \
		-arrowttipvar [::mc::var [namespace current]::mc::NewDatabase "..."] \
		-command [list ::menu::dbNew $main Normal] \
		-menucmd ::menu::addVariantsToMenu \
	]
	::toolbar::add $tbFile dropdownbutton \
		-image $::icon::toolbarDocOpen \
		-tooltipvar [::mc::var [namespace current]::mc::OpenDatabase "..."] \
		-arrowttipvar [namespace current]::mc::OpenRecentDatabase \
		-command [list ::menu::dbOpen $main] \
		-menucmd [namespace current]::addRecentlyUsedToMenu \
		;
	set Vars(button:close) [::toolbar::add $tbFile button \
		-image $::icon::toolbarDocClose \
		-tooltipvar [namespace current]::_CloseDatabase \
		-command [list ::menu::dbClose $main] \
	]
	set Vars(button:save) [::toolbar::add $tbFile button \
		-image $::icon::toolbarSave \
		-tooltipvar [::mc::var [namespace current]::mc::FileSaveChanges ...] \
		-command [namespace code [list SaveChanges $main]] \
		-state disabled \
	]
	set var [namespace current]::Vars(flag:readonly)
	set $var 0
	set Vars(button:readonly) [::toolbar::add $tbFile checkbutton \
		-image $::icon::toolbarLock \
		-tooltipvar [namespace current]::_Readonly \
		-variable $var \
		-command [namespace code [list ToggleReadOnly $var]] \
	]
#	::toolbar::add $tbFile button \
#		-image $::icon::toolbarHelp \
#		-tooltipvar [namespace current]::mc::HelpSwitcher \
#		-command [list ::help::open $sitcher Database-Switcher] \
#		;

	set Vars(switcher) $switcher
	set Vars(contents) $contents
	set Vars(windows) [$contents tabs]
	set Vars(main) $main
	set Vars(first-tab-change) 1
	set Vars(current:tab) games
	set Vars(linespace) 0
	set Vars(shift) 0
	set Vars(after) {}

	set tbClipbase [::toolbar::toolbar $switcher \
		-id database-clipbase \
		-tooltipvar [namespace current]::mc::SelectVariant \
	]
	foreach variant $Variants {
		set Vars(widget:$variant) [::toolbar::add $tbClipbase button \
			-image $::icon::toolbarVariant($variant) \
			-command [namespace code [list SwitchVariant $variant]] \
			-variable [namespace current]::Vars(variant) \
			-value $variant \
			-tooltip [GetTip $variant] \
		]
	}

	::scidb::db::subscribe gameList [namespace current]::Update
	after idle [namespace code [list ToolbarShow $switcher]]

	bind $contents <<NotebookTabChanged>> [namespace code TabChanged]
	bind $contents <<LanguageChanged>> [namespace code LanguageChanged]

	$Vars(switcher) add $::scidb::clipbaseName [::scidb::db::get clipbase type] no
	$Vars(switcher) current $::scidb::clipbaseName
	SetClipbaseDescription
	bind $contents <<LanguageChanged>> +[namespace code SetClipbaseDescription]
	switchToBase $clipbaseName
}


proc switcherSize {} {
	variable Vars

	if {![info exists Vars(main)]} { return 0 }
	if {![winfo exists $Vars(main)]} { return 0 }
	return [expr {[$Vars(main) cget -sashwidth] + [winfo height $Vars(switcher)]}]
}


proc finish {app} {
	variable Positions
	variable Vars

	foreach w [array names Positions] {
		set tabs [$Vars(contents) tabs]
		for {set i 0} {$i < [llength $tabs] && ![string match *$w [lindex $tabs $i]]} {incr i} {}
		Undock $Vars(contents) $i $Positions($w)
	}

	unset Positions
	array set Positions {}

	# must be done after the toplevel window has been mapped
	after idle [list $Vars(switcher) activate]
}


proc preOpen {parent} {
	variable CurrentBase
	variable RecentFiles
	variable PreOpen

	if {![::process::testOption re-open]} { return }

	foreach file $PreOpen {
		set i [FindRecentFile $file]
		lassign [lindex $RecentFiles $i] type file encoding readonly
		if {[llength $encoding] && $encoding ni [encoding names]} {
			set encoding $::encoding::defaultEncoding
			::log::error $mc::Preload [format $mc::MissingEncoding $encoding $encoding]
		}
		if {[file readable $file]} {
			::log::hide 1
			set active [expr {$CurrentBase eq $file}]
			openBase $parent $file no -encoding $encoding -readonly $readonly -switchToBase $active
			if {$active} { set current $file }
			::log::hide 0
		} 
	}
}


proc activate {w flag} {
	variable Vars

	set w [$Vars(contents) select]
	set tab [lindex [split $w .] end]
	::toolbar::activate $Vars(switcher) $flag
	${tab}::activate $Vars($tab) $flag
	::annotation::hide $flag
	::marks::hide $flag

	set twm $w.twm
	if {[::scidb::tk::twm exists $twm]} {
		set cmd [expr {$flag ? "show" : "hide"}]
		foreach w [$twm floats] { if {[$twm get! $w hide 0]} { $twm $cmd $w } }
	}
}


proc setActive {flag} {
	variable Vars
	${Vars(current:tab)}::setActive $flag
}


proc twm {} {
	return [set [namespace current]::Vars(twm)]
}


proc currentVariant {} {
	variable Vars
	if {[info exists Vars(variant)]} { return $Vars(variant) }
	return Normal
}


proc openBase {parent file byUser args} {
	variable Vars
	variable RecentFiles

	set file [file normalize $file]
	if {[string length [set ext [file extension $file]]]} {
		set ext [::scidb::misc::mapExtension $ext]
		set file "[file rootname $file].$ext"
	} else {
		set ext [string range $ext 1 end]
	}

	set ext [string tolower $ext]

	if {![file readable $file]} {
		removeRecentFile $file
		::dialog::error -parent $parent -message [format $mc::CannotOpenFile $file]
		return 0
	}

	if {[file type $file] eq "link"} { set file [file normalize [file readlink $file]] }

	if {[file extension $file] eq ".scv"} {
		# TODO: check if already open
		return [::remote::busyOperation { OpenArchive $parent $file $byUser {*}$args }]
	}

	array set opts { -readonly -1 -encoding "" -switchToBase 1 -variant Undetermined }
	array set opts $args

	if {$opts(-encoding) eq $::encoding::mc::AutoDetect} {
		set opts(-encoding) $::encoding::autoEncoding
	}
	if {![$Vars(switcher) contains? $file]} {
		foreach base [$Vars(switcher) bases] {
			if {$ext eq [$Vars(switcher) extension $base]} {
				if {[::scidb::misc::hardLinked? $file $base]} {
					set msg [string map [list "%file1" $file "%file2" $base] $mc::HardLinkDetected]
					::dialog::error \
						-parent .application \
						-message $msg \
						-detail $mc::HardLinkDetectedDetail \
						-topmost 1 \
						;
					return 0
				}
			}
		}
		if {[llength $opts(-encoding)] == 0 || $opts(-encoding) eq $::encoding::autoEncoding} {
			set k [FindRecentFile $file]
			if {$k >= 0} { set opts(-encoding) [lindex $RecentFiles $k 2] }
		}
		if {$opts(-readonly) == -1} {
			set k [FindRecentFile $file]
			if {$k >= 0} { set opts(-readonly) [lindex $RecentFiles $k 3] }
		}
		set name [::util::databaseName $file]
		set msg [format $mc::LoadMessage $name]
		if {[llength $opts(-encoding)] == 0} {
			switch $ext {
				sci - si3 - si4 - cbh - cbf			{ set opts(-encoding) auto }
				pgn - pgn.gz - bpgn - bpgn.gz - zip	{ set opts(-encoding) $::encoding::defaultEncoding }
			}
		}
		switch $ext {
			sci - si3 - si4 - cbh - cbf {
				set args {}
				if {$ext ne "sci"} {
					set opts(-readonly) 1
				} elseif {$opts(-readonly) == -1} {
					set opts(-readonly) 0
				}
				set args [list -readonly $opts(-readonly)]
				if {[llength $opts(-encoding)]} { lappend args -encoding $opts(-encoding) }
				set cmd [list ::scidb::db::load $file]
				set options [list -message $msg -interrupt yes]
				set rc [::util::catchException { ::progress::start $parent $cmd $args $options }]
				if {$rc != 0} { return 0 }
			}
			bpgn - bpgn.gz {
				return -code error "BPGN is not yet supported"
			}
			pgn - pgn.gz - zip {
				set type [lookupType PGNFile]
				set cmd [list ::import::open $parent $file $msg $opts(-encoding) $type]
				set rc [::util::catchException $cmd]
				if {$rc != 0} {
					catch { ::scidb::db::close $file }
					return 0
				}
				if {$opts(-readonly) == -1} {
					set opts(-readonly) 1
				}
			}
		}
		if {![::scidb::db::get open? $file]} {
			::dialog::error -parent $parent -message [format $mc::CannotOpenFile $file]
			return 0
		}
		set readonly $opts(-readonly)
		if {$ext == "sci" && [::scidb::db::get upgrade? $file]} {
			set opts(-readonly) 1
			set rc [::dialog::question \
				-parent $parent \
				-message [format $mc::UpgradeDatabase $name] \
				-detail $mc::UpgradeDatabaseDetail \
			]
			if {$rc eq "yes"} {
				set cmd [list ::scidb::db::upgrade $file]
				set options [list -message [format $mc::UpgradeMessage $name]]
				set rc [::util::catchException { ::progress::start $parent $cmd {} $options }]
				::scidb::db::close $file
				if {$rc != 0} { return 0 }
				set cmd [list ::scidb::db::load $file]
				set options [list -message $msg -interrupt yes]
				set rc [::util::catchException { ::progress::start $parent $cmd {} $options }]
				if {$rc != 0} { return 0 }
				set opts(-readonly) $readonly
			}
		}
		if {![::scidb::db::get writable? $file]} { set opts(-readonly) 1 }
		::scidb::db::set readonly $file $opts(-readonly)
		set type [::scidb::db::get type $file]
		$Vars(switcher) add $file $type $opts(-readonly) $opts(-encoding)
		AddRecentFile $type $file $opts(-encoding) $readonly
		CheckEncoding $parent $file [::scidb::db::get usedencoding $file]
	} else {
		$Vars(switcher) see $file
		if {$byUser} {
			set msg [format $mc::DatabaseAlreadyOpen [::util::databaseName $file]]
			::dialog::info -parent $parent -message $msg
		}
	}

	if {$opts(-switchToBase) eq "last"} {
		variable CurrentBase
		set opts(-switchToBase) [expr {$CurrentBase eq $file}]
	}
	if {$opts(-switchToBase)} { switchToBase $file }

	if {$opts(-variant) ne "Undetermined"} {
		 SwitchVariant $opts(-variant)
	}

	return 1
}


proc prepareClose {} {
	variable Vars
	variable PreOpen

	set current [::scidb::db::get name]
	set active ""

	set PreOpen {}

	foreach base [$Vars(switcher) bases] {
		if {[$Vars(switcher) type $base] ne [::scidb::db::get clipbase type]} {
			lappend PreOpen $base
		}
	}
}


proc closeBase {parent {file {}}} {
	if {[string length $file] == 0} {
		set file [::scidb::db::get name]
	}

	if {[::scidb::db::get unsaved? $file]} {
		append msg $mc::UnsavedFiles "\n\n"
		append msg $::application::mc::ThrowAwayAllChanges
		set reply [::dialog::question -parent $parent -message $msg -default no]
		if {$reply ne "yes"} { return }
	}

	::remote::busyOperation { CloseBase $parent $file }
}


proc newBase {parent variant file {encoding ""}} {
	variable Vars

	set file [file normalize $file]

	if {[$Vars(switcher) contains? $file]} {
		set msg [format $mc::DatabaseAlreadyOpen [::util::databaseName $file]]
		::dialog::error -parent $parent -message $msg
		return 0
	}
	
	set ext [string tolower [file extension $file]]
	if {$ext in {.pgn .pgn.gz}} { set type PGNFile } else { set type Unspecific }
	::widget::busyCursor on
	::scidb::db::new $file $variant [lookupType $type] {*}$encoding
	::scidb::db::attach $file $file
	set encoding [::scidb::db::get encoding $file]
	$Vars(switcher) add $file $type no $encoding
	AddRecentFile $type $file $encoding no
	::widget::busyCursor off
	switchToBase $file

	return 1
}


proc lookupType {type} {
	variable Types
	return [lsearch -exact $Types(sci) $type]
}


proc refreshBase {base} {
	variable Vars

	::scidb::db::switch $base [$Vars(switcher) variant?]
	$Vars(switcher) update $base
}


proc switchToBase {filename} {
	variable Vars

	if {[catch { $Vars(switcher) current $filename }]} {
		# may happen if open failed
		return
	}
	[namespace parent]::twm::switchLayout $Vars(variant) db
	::scidb::db::switch $filename $Vars(variant)
	UpdateAfterSwitch $filename $Vars(variant)
}


proc recentFiles {} {
	variable RecentFiles
	variable Vars

	set recentFiles {}
	foreach entry $RecentFiles {
		set file [lindex $entry 1]
		if {![$Vars(switcher) contains? $file]} {
			lassign $entry type file encoding readonly
			if {[string match $::scidb::dir::home* $file]} {
				set file [string replace $file 0 [expr {[string length $::scidb::dir::home] - 1}] "~"]
			}
			set name [::util::databaseName $file]
			lappend recentFiles [list $type $file $name $encoding $readonly]
		}
	}

	return $recentFiles
}


proc removeRecentFile {file} {
	variable RecentFiles

	if {[set index [FindRecentFile $file]] >= 0} {
		set RecentFiles [lreplace $RecentFiles $index $index]
		[namespace parent]::information::update
#		::menu::configureOpenRecent [GetRecentState]
	}
}


proc renameRecentFile {oldName newName} {
	variable RecentFiles

	if {[set index [FindRecentFile $oldName]] >= 0} {
		lassign [lindex $RecentFiles $index] type - encoding readonly
		set entry [list $type $newName $encoding $readonly]
		set RecentFiles [lreplace $RecentFiles $index $index $entry]
		[namespace parent]::information::update
#		::menu::configureOpenRecent [GetRecentState]
	}
}


proc selectEvent {base variant index} {
	variable Vars

	event::select $Vars(event) $base $variant $index

	if {[winfo toplevel $Vars(event)] eq $Vars(event)} {
		event::activate $Vars(event) 1
	} elseif {$Vars(contents) ne "event"} {
		after 1 [list $Vars(contents) select $Vars(contents).event]
	}
}


proc selectSite {base variant index} {
	variable Vars

	site::select $Vars(site) $base $variant $index

	if {[winfo toplevel $Vars(site)] eq $Vars(site)} {
		site::activate $Vars(site) 1
	} elseif {$Vars(contents) ne "site"} {
		after 1 [list $Vars(contents) select $Vars(contents).site]
	}
}


proc selectPlayer {base variant index} {
	variable Vars

	player::select $Vars(player) $base $variant $index

	if {[winfo toplevel $Vars(player)] eq $Vars(player)} {
		player::activate $Vars(player) 1
	} elseif {$Vars(contents) ne "player"} {
		after 1 [list $Vars(contents) select $Vars(contents).player]
	}
}


proc setFocus {} {
	[set [namespace current]::Vars(switcher)] focus
}


proc addRecentlyUsedToMenu {parent m} {
	variable Vars

	set recentFiles [recentFiles]
	set parent [winfo toplevel $parent]

	if {[llength $recentFiles]} {
		foreach entry $recentFiles {
			lassign $entry type file name encoding readonly
			set dir [file dirname $file]
			$m add command \
				-label " $name  \u25b8  $dir" \
				-image [set [namespace current]::icons::${type}(16x16)] \
				-compound left \
				-command [namespace code \
					[list openBase $parent $file yes -encoding $encoding -readonly $readonly]] \
				;
		}
		$m add separator
		$m add command \
			-label " $::game::mc::ClearHistory" \
			-image $::icon::16x16::clear \
			-compound left \
			-command [namespace code ClearHistory] \
			;
	} else {
		$m add command -label "($::mc::Empty)"
	}

	return [llength $recentFiles]
}


proc OpenArchive {parent file byUser args} {
	variable _Select

	lassign [::archive::inspect $file] header files
	if {[llength $header] == 0} { return [::log::show] }

	set bases {}
	set overwrite {}

	foreach entry $files {
		foreach pair $entry {
			lassign $pair attr value
			if {$attr eq "FileName"} {
				switch [string tolower [file extension $value]] {
					.sci - .si3 - .si4 - .cbh - .cbf - .pgn - .pgn.gz - .bpgn - .bpgn.gz {
						lappend bases $value
						if {[file exists $value]} { lappend overwrite "\u26ab [file tail $value]" }
					}
				}
			}
		}
	}

	if {[llength $bases] == 0} { return 1 }
	set dirname [file dirname $file]
	if {[llength $overwrite] > 0} {
		append msg [format $mc::OverwriteExistingFiles $dirname]
		append msg "\n\n"
		append msg [join $overwrite \n]
		set answer [::dialog::question -parent $parent -message $msg -default no]
		if {$answer eq "no"} { return 1 }
	}

	set progress $parent.__progress
	::dialog::progressbar::open $progress \
		-mode indeterminate \
		-message [format $mc::ExtractArchive [file rootname [file tail $file]]] \
		;
	set rc [::archive::unpack $file ::menu::archive::getName $progress $dirname]
	destroy $progress
	if {!$rc} { return [::log::show] }

	if {[llength $bases] == 1} {
		return [openBase $parent [lindex $bases 0] $byUser {*}$args]
	}

	set dlg $parent.__choose__
	toplevel $dlg -class Scidb
	bind $dlg <Escape> [list $dlg.cancel invoke]
	wm protocol $dlg WM_DELETE_WINDOW [list destroy $dlg]
	wm transient $dlg [winfo toplevel $parent]
	wm withdraw $dlg
	wm title $dlg [string trim [format $mc::LoadMessage ""]]
	wm resizable $dlg false false
	set top [ttk::frame $dlg.top]
	pack $top
	ttk::label $top.select -text $mc::SelectDatabases
	grid $top.select -row 1 -column 1
	set r 3
	set n 0
	foreach base $bases {
		set _Select($n) [expr {$n == 0}]
		ttk::checkbutton $top.base$r -text [file tail $base] -variable [namespace current]::_Select($n)
		grid $top.base$r -row $r -column 1 -sticky w
		grid rowconfigure $top [incr r] -minsize $::theme::pady
		incr r
		incr n
	}
	grid rowconfigure $top [list 0 $r] -minsize $::theme::pady
	grid rowconfigure $top 2 -minsize $::theme::padY
	grid columnconfigure $top {0 2} -minsize $::theme::padx
	::widget::dialogButtons $dlg {ok cancel}
	$dlg.ok configure -command [namespace code [list OpenBases $parent $dlg $bases $byUser {*}$args]]
	$dlg.cancel configure -command [list destroy $dlg]
	::util::place $dlg -parent $parent -position center
	wm deiconify $dlg
	focus $dlg
	::ttk::grabWindow $dlg
	tkwait window $dlg
	::ttk::releaseGrab $dlg
	return 1
}


proc OpenBases {parent dlg bases byUser args} {
	variable _Select

	array set opts { -readonly -1 -encoding "" -switchToBase 1 }
	array set opts $args
	set opts(-switchToBase) 0

	set n 0
	foreach base $bases {
		if {$_Select($n)} { openBase $parent $base $byUser {*}[array get opts] }
		incr n
	}
	destroy $dlg
}


proc ClearHistory {} {
	variable RecentFiles

	set RecentFiles {}
	[namespace parent]::information::update
	#::menu::configureOpenRecent [GetRecentState]
}


proc OpenBase {file readonly} {
	variable Vars
	openBase $Vars(switcher) $file $readonly
}


proc CloseBase {parent file} {
	variable Vars
	variable ::scidb::clipbaseName

	if {[llength $file] == 0} {
		set file [::scidb::db::get name]
		if {$file eq $clipbaseName} { return }
	}

	if {[::game::releaseAll $parent $file]} {
		::widget::busyCursor on
		$Vars(switcher) remove $file
		::scidb::db::close $file
		if {![file exists $file]} {
			removeRecentFile $file
		}
		[namespace parent]::information::update
		::widget::busyCursor off
	}
}


proc FontSizeChanged {w} {
	variable Vars

	if {$w eq $Vars(main)} {
		after idle [namespace code RefreshSwitcher]
	}
}


proc SwitchVariant {variant} {
	variable Vars

	set Vars(variant) $variant
	$Vars(switcher) variant $variant
	::scidb::db::switch [$Vars(switcher) current?] $variant
}


proc SetClipbaseDescription {} {
	variable ::scidb::clipbaseName
	::scidb::db::set description $clipbaseName $mc::ClipbaseDescription
}


proc TabChanged {} {
	variable Vars

	set newTab [lindex [split [$Vars(contents) select] .] end]
	set curTab $Vars(current:tab)
	if {!$Vars(first-tab-change) && $newTab eq $curTab} { return }
	set Vars(first-tab-change) 0
	set w $Vars($curTab)
	${curTab}::activate $w 0
	${newTab}::activate $Vars($newTab) 1
	set Vars(current:tab) $newTab

	set w $Vars(contents)
	set tabs [$w tabs]
	foreach t $tabs {
		if {[$w select] eq $t && [llength $tabs] > $Vars(mintabs)} {
			set icon $icon::16x16::undock
		} elseif {$Vars(showDisabled)} {
			set icon $icon::16x16::undock_disabled
		} else {
			set icon {}
		}
		$w tab $t -image $icon
	}

	set twm $Vars($curTab).twm
	if {[::scidb::tk::twm exists $twm]} {
		foreach w [$twm collect floats] { $twm hide $w }
	}
	set twm $Vars($newTab).twm
	if {[::scidb::tk::twm exists $twm]} {
		foreach w [$twm collect floats] { $twm show $w }
	}
	set Vars(twm) $twm
}


proc ToolbarShow {pane} {
	variable Vars

return ;# TODO
	update idletasks
	set minheight [::toolbar::totalHeight $pane]
	if {$minheight == 1} {
		after idle [namespace code [list ToolbarShow $pane]]
	} else {
		incr minheight [expr {2*[games::borderwidth $Vars(games)]}]
		[winfo parent $pane] paneconfigure $pane -minsize $minheight
	}
}


proc LogCopyDb {unused arguments} {
	lassign $arguments type code gameNo
	set line ""

	append line $::import::mc::GameNumber " " [::locale::formatNumber $gameNo]
	append line ": "

	if {[info exists import::mc::$code]} {
		append line [set ::import::mc::$code]
	} else {
		append line $code
	}

	::log::$type $line
	update idletasks
}


proc UpdateVariants {{variant ""}} {
	variable Variants
	variable Vars

	if {[string length $variant]} { set Vars(variant) $variant }

	set usedVariants [::scidb::app::activeVariants]
	foreach variant $Variants {
		if {$variant ni $usedVariants} {
			::toolbar::remove $Vars(widget:$variant)
		} else {
			::toolbar::add $Vars(widget:$variant)
		}
	}

	if {$Vars(variant) ni $usedVariants} {
		SwitchVariant [lindex [::scidb::db::get variants [$Vars(switcher) current?]] 0]
	}

	UpdateAfterSwitch [::scidb::db::get name] $Vars(variant)
}


proc UpdateAfterSwitch {filename variant} {
	variable ::scidb::clipbaseName
	variable Vars
	variable Tabs

	if {$filename ne $clipbaseName} { set CurrentBase $filename }
	set readonly [::scidb::db::get readonly? $filename]

	if {$filename eq $clipbaseName} { set closeState disabled } else { set closeState normal }
	if {$filename eq $clipbaseName || ![::scidb::db::get writable? $filename]} {
		set roState disabled
	} else {
		switch [string tolower [file extension $filename]] {
			.pgn - .pgn.gz	{ set roState [::makeState ![::scidb::db::get unsaved? $filename]] }
			.sci				{ set roState normal }
			default			{ set roState disabled }
		}
	}

	::toolbar::childconfigure $Vars(button:close) -state $closeState
	::toolbar::childconfigure $Vars(button:readonly) -state $roState

	set Vars(flag:readonly) $readonly
	CheckTabState
	CheckSaveState $filename

	foreach file [$Vars(switcher) bases] {
		if {$file eq $filename} {
			if {$readonly} { set str $mc::SetWriteable } else { set str $mc::SetReadonly }
			set name [::util::databaseName $filename]
			set [namespace current]::_CloseDatabase [format $mc::CloseDatabase $name]
			set [namespace current]::_Readonly [format $str $name]
		}
	}

	foreach tab $Tabs {
		if {$tab ne "games" && [winfo toplevel $Vars($tab)] eq $Vars($tab)} {
			${tab}::activate $Vars($tab) 1
		}
	}
}


proc CheckSaveState {base} {
	variable ::scidb::clipbaseName
	variable Vars

	if {$base eq $clipbaseName || ![::scidb::db::get unsaved? $base]} {
		set state disabled
	} else {
		set state normal
	}
	::toolbar::childconfigure $Vars(button:save) -state $state
}


proc CheckTabState {} {
	variable Vars

	set codec [::scidb::db::get codec]

	if {[winfo toplevel $Vars(annotator)] ne $Vars(annotator)} {
		if {$codec eq "sci" || $codec eq "cbh"} { set state normal } else { set state hidden }
		$Vars(contents) tab $Vars(annotator) -state $state
	}

	if {[winfo toplevel $Vars(position)] ne $Vars(position)} {
		if {$codec eq "sci"} { set state normal } else { set state hidden }
		$Vars(contents) tab $Vars(position) -state $state
	}

	if {[winfo toplevel $Vars(site)] ne $Vars(site)} {
		if {$codec eq "cbf"} { set state hidden } else { set state normal }
		$Vars(contents) tab $Vars(site) -state $state
	}
}


proc Update {id base variant {view 0} {index -1}} {
	variable Vars

	CheckSaveState $base

	if {$index >= 0} {
		after cancel $Vars(after)
		set Vars(after) [after idle [namespace code { RefreshSwitcher }]]
	}
}


proc RefreshSwitcher {} {
	variable Vars
	$Vars(switcher) update [$Vars(switcher) current?]
}


proc RefreshBaseState {base variant} {
	variable Vars

	CheckSaveState $base
	$Vars(switcher) update $base $variant

	if {[$Vars(switcher) current?] eq $base} {
		UpdateAfterSwitch $base $variant
	}
}


proc LanguageChanged {} {
	variable Vars
	variable Variants
	variable ::scidb::clipbaseName

	set ::util::clipbaseName [set [namespace current]::mc::T_Clipbase]
	$Vars(switcher) update $clipbaseName [::scidb::db::get variant? $clipbaseName]
	set base [$Vars(switcher) current?]

	if {[::scidb::db::get readonly? $base]} {
		set str $mc::SetWriteable
	} else {
		set str $mc::SetReadonly
	}
	set name [::util::databaseName $base]
	set [namespace current]::_CloseDatabase [format $mc::CloseDatabase $name]
	set [namespace current]::_Readonly [format $str $name]

	foreach t $Vars(windows) {
		set var [namespace parent]::mc::Tab([lindex [split $t .] end])
		if {[winfo toplevel $t] eq $t} {
			wm title $t "$::scidb::app - [::mc::stripAmpersand [set $var]]"
		} else {
			::widget::notebookSetLabel $Vars(contents) $t [set $var]
		}
	}

	::toolbar::childconfigure $Vars(button:new) \
		-tooltip "$mc::NewDatabase ($::mc::VariantName(Normal))..."

	foreach variant $Variants {
		::toolbar::childconfigure $Vars(widget:$variant) -tooltip [GetTip $variant]
	}
}


proc GetTip {variant} {
	switch $variant {
		Losers {
			set tip "$::mc::VariantName(Antichess) - $::mc::VariantName(Losers)"
		}
		Antichess {
			set tip "$::mc::VariantName(Antichess) - "
			append tip "$::mc::VariantName(Suicide)/$::mc::VariantName(Giveaway)"
		}
		default {
			set tip $::mc::VariantName($variant)
		}
	}
	return $tip
}


proc TableMinSize {main contents switcher sizeInfo} {
	variable Vars

	if {[winfo toplevel $Vars(games)] eq $Vars(games)} { return }
	set height [winfo height $contents]
	if {$height <= 1} { return }

	ConfList $main $contents $switcher [winfo height $main]
	AlignList $main $contents $switcher
	after idle [list $switcher update]
}


proc AlignList {main contents switcher} {
	variable Vars

	set zeroHeight [expr {[games::computeHeight $Vars(games) 0]}]
	set tabbarSize [::theme::notebookTabPaneSize $contents]
	set minsize [expr {$zeroHeight + $tabbarSize + 1}] ;# XXX any border, probably in tabbar?
	set linespace [games::linespace $Vars(games)]
	set height [winfo height $contents]

	set h [expr {(($height - $minsize)/$linespace)*$linespace} + $minsize]
	if {$h > $height} { decr h $linespace }
	if {$h < $height} {
		if {$height - $h > abs($Vars(shift))} { incr h $linespace }
		set shift [expr {$height - $h}]
		incr Vars(shift) $shift
		lassign [$main sash coord 0] x y
		$main sash place 0 $x [expr {$y + $shift}]
	}
}


proc ConfList {main contents switcher height} {
	variable Vars
	variable Tabs

	set sashwidth [$main cget -sashwidth]
	set linespace [games::linespace $Vars(games)]
	set Vars(linespace) $linespace
	set overhang [games::overhang $Vars(games)]
	set topHeight [expr {$overhang + 4*$linespace + $sashwidth}]
	set tabbarSize [::theme::notebookTabPaneSize $contents]
	set toolbarSize [games::computeHeight $Vars(games)]
	set minsize [[namespace parent]::twm::minHeight]
	set minsize [expr {max($topHeight + $toolbarSize, $minsize) + $tabbarSize}]
	$main paneconfigure $contents -minsize $minsize -gridsize $linespace
}


proc InitList {main contents switcher height} {
	variable Vars

	if {$Vars(linespace) == 0} {
		ConfList $main $contents $switcher $height
	}

	set sashwidth [$main cget -sashwidth]
	set switcherHeight [expr {[$switcher minheight] + [::toolbar::totalHeight $switcher]}]
	set zeroHeight [expr {[games::computeHeight $Vars(games) 0]}]
	set tabbarSize [::theme::notebookTabPaneSize $contents]
	set linespace [games::linespace $Vars(games)]
	set n [expr {($height - $switcherHeight - $tabbarSize - $zeroHeight - $sashwidth + 1)/$linespace}]
	set paneHeight [expr {[games::computeHeight $Vars(games) $n] + $tabbarSize}]
	incr paneHeight 1 ;# XXX any border, probably in tabbar?
	lassign [$main sash coord 0] x y
	decr height $paneHeight
	$main sash place 0 $x [expr {$height - $sashwidth}]
	set Vars(shift) 0
}


proc Configure {main contents switcher height} {
	variable Vars

	if {[winfo toplevel $Vars(games)] eq $Vars(games)} { return }
	if {$height <= 1} { return }

	if {$Vars(configure:height) == 0} {
		InitList $main $contents $switcher $height
	} elseif {$height != $Vars(configure:height)} {
		after cancel $Vars(afterid)
		set Vars(afterid) [after 150 [namespace code [list AlignList $main $contents $switcher]]]
	}

	set Vars(configure:height) $height
}


proc PopupMenu {parent x y {base ""}} {
	variable ::scidb::clipbaseName
	variable Types
	variable Vars
	variable ::table::options

	if {$Vars(ignore-next)} {
		set Vars(ignore-next) 0
		return
	}

	if {[string length $base] > 0} { set Vars(ignore-next) 1 }
	set menu $parent.__menu__
	catch { destroy $menu }
	menu $menu -tearoff 0
	catch { wm attributes $menu -type popup_menu }
	set top [winfo toplevel $parent]
	set readonly 0
	set isSciFormat 1

	if {[string length $base] > 0 && [$Vars(switcher) active? $base]} {
		set readonly [::scidb::db::get readonly? $base]
		if {$readonly} { set readonlyState disabled } else { set readonlyState normal }
		set ext [$Vars(switcher) extension $base]
		set type [$Vars(switcher) type $base]
		set isClipbase [expr {$base eq $clipbaseName}]
		set isSciFormat [expr {$ext eq "sci" || $isClipbase}]
		set name [::util::databaseName $base]
		$menu add command                                    \
			-label " $name"                                   \
			-image $::icon::16x16::none                       \
			-compound left                                    \
			-background $options(menu:headerbackground)       \
			-foreground $options(menu:headerforeground)       \
			-activebackground $options(menu:headerbackground) \
			-activeforeground $options(menu:headerforeground) \
			-font $options(menu:headerfont)                   \
			;
		$menu add separator

		$menu add command \
			-label " $mc::Properties" \
			-image $::icon::16x16::info \
			-compound left \
			-command [namespace code [list $Vars(switcher) show $base]] \
			;
		$menu add command \
			-label " $mc::FileExport..." \
			-image $::icon::16x16::fileExport \
			-compound left \
			-command [list ::export::open $parent \
							-base $base \
							-variant $Vars(variant) \
							-extension [$Vars(switcher) extension $base] \
							-name $name \
							-view 0] \
			;
		$menu add command \
			-label " $mc::FileImport(db)..." \
			-image $::icon::16x16::databaseImport \
			-compound left \
			-command [list ::menu::dbImport $top $base db] \
			-state $readonlyState \
			;
		$menu add command \
			-label " $mc::FileImport(pgn)..." \
			-image $::icon::16x16::filetypePGN \
			-compound left \
			-command [list ::menu::dbImport $top $base pgn] \
			-state $readonlyState \
			;

		$menu add command \
			-label " $mc::FileCreate..." \
			-image $::icon::16x16::filetypeArchive \
			-compound left \
			-command [list ::menu::dbCreateArchive $top $base] \
			;

		$menu add separator

		set maint [menu $menu.maintenance -tearoff no]
		$menu add cascade \
			-menu $maint \
			-label " $mc::FileMaintenance" \
			-image $::icon::16x16::setup \
			-compound left \
			-state $readonlyState \
			;

		if {!$readonly} {
			if {!$isClipbase} {
				set state $readonlyState
				if {![info exists Types($ext)]} { set state disabled }
				if {$ext eq "sci" || $ext eq "si3" || $ext eq "si4"} {
					$maint add command \
						-label " $mc::ChangeIcon..." \
						-image $::icon::16x16::none \
						-compound left \
						-command [namespace code [list ChangeIcon $top $base]] \
						-state $state \
						;
					set repertoire [menu $maint.repertoire -tearoff false]
					foreach repertoireType {Openings OpeningsWhite OpeningsBlack} label [list $mc::RepertoireBoth $mc::RepertoireWhite $mc::RepertoireBlack] {
						$repertoire add command \
							-label " $label" \
							-command [namespace code [list SetDatabaseType $base $repertoireType]]
					}
					$maint add cascade \
						-label " $mc::MarkAsRepertoire" \
						-image $::icon::16x16::none \
						-compound left \
						-menu $repertoire \
						-state $state \
						;
				}
				$maint add command \
					-label " $mc::EditDescription..." \
					-image $::icon::16x16::edit \
					-compound left \
					-command [namespace code [list EditDescription $parent $base]] \
					-state $readonlyState \
					;
			}

			if {!$isSciFormat} {
				$maint add command \
					-label " $mc::FileConvertToScidb..." \
					-image $::icon::16x16::fileExport \
					-compound left \
					-command [namespace code [list ConvertDatabaseToScidb $top $base $Vars(variant)]] \
					-state $readonlyState \
					;
			}

			if {$isSciFormat} {
				set count [::scidb::db::count games $base $Vars(variant)]
				if {$count} { set state $readonlyState } else { set state disabled }
				$maint add command \
					-label " $mc::FileStripMoveInfo..." \
					-image $::icon::16x16::delete \
					-compound left \
					-command [namespace code [list StripMoveInfo $parent $base]] \
					-state $state \
					;
				$maint add command \
					-label " $mc::FileStripPGNTags..." \
					-image $::icon::16x16::delete \
					-compound left \
					-command [namespace code [list StripPGNTags $parent $base]] \
					-state $state \
					;

				if {[::scidb::db::get compact? $base $Vars(variant)]} {
					set state normal
				} else {
					set state disabled
				}
				$maint add command \
					-label " $mc::FileCompact..." \
					-image $::icon::16x16::none \
					-compound left \
					-command [namespace code [list Compact $top $base]] \
					-state $state \
					;

				set count [::scidb::db::count games $base $Vars(variant)]
				if {$count} { set state normal } else { set state disabled }
				$maint add command \
					-label " $mc::FindDuplicates..." \
					-image $::icon::16x16::none \
					-compound left \
					-command [namespace code [list ShowDuplicates $top $base $Vars(variant)]] \
					-state $state \
					;
				$maint add command \
					-label " $mc::EcoStats..." \
					-image $::icon::16x16::none \
					-compound left \
					-command [namespace code [list ShowEcoStats $top $base $Vars(variant)]] \
					-state $state \
					;
				if {$type in {Openings OpeningsWhite OpeningsBlack}} {
					$maint add command \
						-label " $mc::RepertoireReport..." \
						-image $::icon::16x16::none \
						-compound left \
						-command [namespace code [list OpenRepertoireReport $top $base $Vars(variant)]] \
						-state $state \
						;
				}
				$maint add command \
					-label " $mc::SearchByMaterial..." \
					-image $::icon::16x16::none \
					-compound left \
					-command [namespace code [list OpenMaterialSearch $top $base $Vars(variant)]] \
					-state $state \
					;
				$maint add command \
					-label " $mc::SearchByRating..." \
					-image $::icon::16x16::none \
					-compound left \
					-command [namespace code [list OpenRatingSearch $top $base $Vars(variant)]] \
					-state $state \
					;
				$maint add command \
					-label " $mc::AdvancedSearch..." \
					-image $::icon::16x16::none \
					-compound left \
					-command [namespace code [list OpenAdvancedSearch $top $base $Vars(variant)]] \
					-state $state \
					;
			}
		}

		if {!$isClipbase} {
			$menu add command \
				-label " $mc::FileClose" \
				-image $::icon::16x16::close \
				-compound left \
				-command [namespace code [list closeBase $parent $base]] \
				;
			if {[::scidb::db::get unsaved? $base]} {
				$menu add command \
					-label " $mc::FileSaveChanges..." \
					-image $::icon::16x16::save \
					-compound left \
					-command [namespace code [list SaveChanges $parent $base]] \
					;
			}
		} else {
			set count [::scidb::db::count games $base $Vars(variant)]
			if {$count} { set state normal } else { set state disabled }
			$menu add command \
				-label " $mc::EmptyClipbase" \
				-image $::icon::16x16::trash \
				-compound left \
				-command [namespace code [list EmptyClipbase $parent]] \
				-state $state \
				;
		}
		switch $ext {
			si3 - si4 - cbh - cbf - pgn - pgn.gz - bpgn - bpgn.gz {
				if {[file readable $base] && ![::scidb::db::get unsaved? $base]} {
					set state normal
				} else {
					set state disabled
				}
				$menu add command \
					-label " $mc::Recode..." \
					-image $::icon::16x16::none \
					-compound left \
					-command [namespace code [list Recode $base $top]] \
					-state $state
					;
			}
		}

		$menu add separator

		if {!$isClipbase && ($ext eq "sci" || $ext eq "pgn" || $ext eq "pgn.gz")} {
			variable ReadOnly_
			set ReadOnly_ [::scidb::db::get readonly? $base]
			if {![::scidb::db::get writable? $base] || [::scidb::db::get unsaved? $base]} {
				set state disabled
			} else {
				set state normal
			}
			set var [namespace current]::ReadOnly_
			$menu add checkbutton \
				-label " $::database::switcher::mc::ReadOnly" \
				-image $::icon::16x16::lock \
				-compound left \
				-command [namespace code [list ToggleReadOnly $var $base]] \
				-variable $var \
				-state $state \
				;
			::theme::configureCheckEntry $menu
			$menu add separator
		}
	}

	$menu add command \
		-label " $mc::FileOpen..." \
		-image $::icon::16x16::databaseOpen \
		-compound left \
		-command [list ::menu::dbOpen $top] \
		;

	set m [menu $menu.mOpenRecent -tearoff false]
	set state normal
	if {[addRecentlyUsedToMenu [winfo parent [winfo parent $parent]] $m] == 0} { set state disabled }
	$menu add cascade \
		-menu $m \
		-label " [::mc::stripAmpersand $mc::FileOpenRecent]" \
		-image $::icon::16x16::databaseOpen \
		-compound left \
		-state $state \
		;

	$menu add command \
		-label " $mc::FileNew ($::mc::VariantName(Normal))..." \
		-image $::icon::16x16::databaseNew \
		-compound left \
		-command [list ::menu::dbNew $top Normal] \
		;

	menu $menu.mFileNew -tearoff 0
	$menu add cascade \
		-menu $menu.mFileNew \
		-label " $mc::FileNew..." \
		-image $::icon::16x16::databaseNewAlt \
		-compound left \
		;
	::menu::addVariantsToMenu $top $menu.mFileNew 1

#	if {$index == -1 && [::scidb::db::get name] ne $clipbaseName} {
#		$menu add separator
#		set name [::util::databaseName [::scidb::db::get name]]
#		set text [format [set [namespace current]::mc::Close] $name]
#		set cmd [namespace code [list closeBase $parent]]
#		$menu add command -label " $text" -image $::icon::16x16::close -compound left -command $cmd
#	}

	$menu add separator
	set m [menu $menu.mIconSize -tearoff false]
	$menu add cascade              \
		-menu $m                    \
		-label " $mc::SymbolSize"   \
		-image $::icon::16x16::none \
		-compound left              \
		;
	foreach {name size} {Large 48 Medium 32 Small 24 Tiny 16} {
		$m add radiobutton                                   \
			-label " [set mc::$name]"                         \
			-value $size                                      \
			-variable ::database::switcher::Options(iconsize) \
			;
		::theme::configureRadioEntry $m
	}

	$menu add separator
	$menu add command \
		-label " [::mc::stripAmpersand $mc::HelpSwitcher]..." \
		-image $::icon::16x16::help \
		-compound left \
		-command [list ::help::open .application Database-Switcher] \
		;

	::tooltip::hide
	tk_popup $menu $x $y
}


proc ToggleReadOnly {var {base ""}} {
	variable Vars
	variable RecentFiles

	set readonly [set $var]
	if {[string length $base] == 0} { set base [::scidb::db::get name] }

	if {![::scidb::db::set readonly $base $readonly]} {
		set $var [expr {!$readonly}]
		append msg $mc::ReadWriteFailed " " $::util::mc::IOError(NotOriginalVersion) "."
		::dialog::error -parent [winfo toplevel $Vars(switcher)] -message $msg
		return
	}

	if {[::scidb::db::get name] eq $base} { set Vars(flag:readonly) $readonly }
	SwitchVariant [$Vars(switcher) readonly $base $readonly]

	set k [FindRecentFile $base]
	if {$k >= 0} { lset RecentFiles $k 3 $readonly }

	if {$readonly} { set str $mc::SetWriteable } else { set str $mc::SetReadonly }
	set [namespace current]::_Readonly [format $str [::util::databaseName $base]]
}


proc EmptyClipbase {parent} {
	variable ::scidb::clipbaseName
	variable Vars

	if {[::game::releaseAll $parent $clipbaseName $Vars(variant)]} {
		::widget::busyCursor on
		::scidb::db::clear $clipbaseName $Vars(variant)
		::widget::busyCursor off
	}
}


proc SaveChanges {parent {base ""}} {
	set parent [winfo toplevel $parent]
	if {[string length $base] == 0} { set base [scidb::db::get name] }

	wm withdraw [set dlg [tk::toplevel $parent.save -class Dialog]]
	pack [set top [ttk::frame $dlg.top]] -fill both
	set padY $::theme::pady

	if {[file size $base] > 0} {
		set text [format $mc::OverwriteOriginalFile [file tail $base]]
		ttk::label $top.warning -wraplength 250 -text $text
		set font [$top.warning cget -font]
		if {[string length $font] == 0} { set font TkDefaultFont }
		$top.warning configure -font [::font::makeBoldFont $font]
		grid $top.warning -row 1 -column 1 -columnspan 3 -sticky w
		grid rowconfigure $top {0} -minsize $::theme::pady
		set padY $::theme::padY
	}

	ttk::label $top.options -wraplength 250 -text $mc::SetupPgnOptions
	set text [::mc::stripAmpersand $::menu::mc::PgnOptions]
	ttk::button $top.setup -text "$text..." -command [list ::menu::setupPgnOptions $dlg]
	grid $top.options -row 3 -column 1 -columnspan 3 -sticky w
	grid $top.setup -row 5 -column 1 -columnspan 3 -sticky we
	grid columnconfigure $top {0 2 4} -minsize $::theme::padx
	grid rowconfigure $top 2 -minsize $padY
	grid rowconfigure $top {4 6} -minsize $::theme::pady

	::widget::dialogButtons $dlg {ok cancel}
	$dlg.ok configure -command [namespace code [list DoSaveChanges $dlg $base]]
	$dlg.cancel configure -command [list destroy $dlg]

	update idletasks
	set width [winfo reqwidth $top.setup]
	if {[winfo exists $top.warning]} { $top.warning configure -wraplength $width }
	$top.options configure -wraplength $width

	wm protocol $dlg WM_DELETE_WINDOW [$dlg.cancel cget -command]
	wm transient $dlg [winfo toplevel $parent]
	wm withdraw $dlg
	wm title $dlg $mc::FileSaveChanges
	wm resizable $dlg false false
	::util::place $dlg -parent $parent -position center
	wm deiconify $dlg
	focus $top.setup
	::ttk::grabWindow $dlg
	tkwait window $dlg
	::ttk::releaseGrab $dlg
}


proc DoSaveChanges {parent base} {
	variable RecentFiles

	if {![file exists $base]} {
		set msg [format $mc::FileIsRemoved [file tail $base]]
		::dialog::error -parent $parent -message $msg
	} elseif {![file writable $base]} {
		set msg [format $mc::FileIsNotWritable [file tail $base]]
		::dialog::error -parent $parent -message $msg
	} else {
		set encoding [expr {[::export::testUTF8Flag] ? "utf-8" : "iso8859-1"}]
		set cmd [list scidb::db::savePGN $base $encoding [::export::getPgnFlags]]
		set options [list -message $mc::FileSaveChanges]
		set result [::progress::start $parent $cmd {} $options]
		CheckSaveState $base

		set i [FindRecentFile $base]
		if {$i >= 0} { lset RecentFiles $i 2 [::scidb::db::get usedencoding $base] }

		# TODO
		switch $result {
			IsUpTodate	{ ;# cannot happen }
			IsReadonly	{ ;# cannot happen }
			IsRemoved	{ ;# cannot happen }
			Updated		{ ;# succesfully saved }
			HasChanged	{}
		}
	}

	destroy $parent
}


proc EditDescription {parent file} {
	variable Vars

	set s [::scidb::db::get description $file]
	set s [string map {"\r\n" "\\n"} $s]
	set s [string map {"\t" "\\t" "\n" "\\n" "\r" ""} $s]
	set Vars(description) $s
	set dlg [tk::toplevel $parent.descr -class Dialog]
	set top [ttk::frame $dlg.top -borderwidth 0 -takefocus 0]
	pack $top -fill both
	::ttk::entry $top.entry -takefocus 1 -width 80 -textvar [namespace current]::Vars(description)
	$top.entry selection range 0 end
	$top.entry icursor end
	pack $top.entry -fill x -padx $::theme::padx -pady $::theme::pady
	::widget::dialogButtons $dlg {ok cancel}
	$dlg.ok configure -command [namespace code [list SetDescription $dlg $file]]
	$dlg.cancel configure -command [list destroy $dlg]
	wm protocol $dlg WM_DELETE_WINDOW [$dlg.cancel cget -command]
	wm transient $dlg [winfo toplevel $parent]
	wm withdraw $dlg
	wm title $dlg "$mc::EditDescription ([::util::databaseName $file])"
	wm resizable $dlg false false
	::util::place $dlg -parent $parent -position below
	wm deiconify $dlg
	focus $top.entry
	::ttk::grabWindow $dlg
	tkwait window $dlg
	::ttk::releaseGrab $dlg
}


proc SetDescription {dlg file} {
	variable Vars

	set Vars(description) [string trim $Vars(description)]
	set s [string map {"\\t" "\t" "\\n" "\n"} $Vars(description)]
	set length [::scidb::db::set description $file $s]

	if {$length == 0} {
		CheckSaveState $file
		RefreshSwitcher
		destroy $dlg
	} else {
		::dialog::error \
			-parent $dlg \
			-message $mc::DescriptionTooLarge \
			-detail [format $mc::DescrTooLargeDetail [string length $Vars(description)] $length] \
			;
	}
}


proc StripMoveInfo {parent file} {
	variable MoveInfoExample
	variable MoveInfoAttrs
	variable Vars

	set rc [::game::closeAll \
		$parent $file $Vars(variant) $mc::FileStripMoveInfo $mc::AllGamesMustBeClosed]
	if {!$rc} { return }

	set dlg [tk::toplevel $parent.stripMoveInfo]
	set top [ttk::frame $dlg.top -takefocus 0]
	set row 1

	foreach attr $MoveInfoAttrs {
		set Vars(moveInfo:$attr) [expr {$attr ne "videoTime"}]
		ttk::checkbutton $top.$attr \
			-text $mc::MoveInfo($attr) \
			-variable [namespace current]::Vars(moveInfo:$attr) \
			-command [namespace code [list CheckOkButton $dlg.ok]] \
			;
		ttk::label $top.l1$attr -text "$mc::Example: \"[lindex $MoveInfoExample($attr) 1]\""
		ttk::label $top.l2$attr -text [lindex $MoveInfoExample($attr) 0]
		grid $top.$attr   -row $row -column 1 -sticky we
		grid $top.l1$attr -row $row -column 3 -sticky w
		grid $top.l2$attr -row $row -column 5 -sticky w
		grid rowconfigure $top [incr row] -minsize $::theme::pady
		incr row
	}

	ttk::separator $top.sep
	ttk::label $top.warning \
		-text $mc::WillBePermanentlyDeleted \
		-padding left \
		-font TkHeadingFont \
		-wraplength 100 \
		;
	grid $top.sep -row $row -column 1 -columnspan 5 -sticky we
	grid $top.warning -row [expr {$row + 2}] -column 1 -columnspan 5 -sticky we
	grid rowconfigure $top [list [expr {$row + 1}] [expr {$row + 3}]] -minsize $::theme::pady
	bind $top <Configure> [namespace code [list ResizeLabel $top.warning %w]]

	grid columnconfigure $top {0 4 6} -minsize $::theme::padx
	grid columnconfigure $top {2} -minsize $::theme::padX
	grid rowconfigure $top 0 -minsize $::theme::pady
	pack $top -fill both

	::widget::dialogButtons $dlg {ok cancel}
	$dlg.cancel configure -command [list destroy $dlg]
	$dlg.ok configure -command [namespace code [list DoStripMoveInfo $dlg $file]]

	wm protocol $dlg WM_DELETE_WINDOW [list destroy $dlg]
	wm transient $dlg [winfo toplevel $parent]
	wm withdraw $dlg
	wm title $dlg $mc::FileStripMoveInfo
	wm resizable $dlg false false
	::util::place $dlg -parent [winfo toplevel $parent] -position center
	wm deiconify $dlg
	focus $top.evaluation
	::ttk::grabWindow $dlg
	tkwait window $dlg
	::ttk::releaseGrab $dlg
}


proc CheckOkButton {btn} {
	variable MoveInfoAttrs
	variable Vars

	foreach attr $MoveInfoAttrs {
		if {$Vars(moveInfo:$attr)} {
			$btn configure -state normal
			return
		}
	}

	$btn configure -state disabled
}


proc DoStripMoveInfo {dlg file} {
	variable ::scidb::clipbaseName
	variable MoveInfoAttrs
	variable Vars

	set parent [winfo parent $dlg]
	destroy $dlg

	set attrs {}
	foreach attr $MoveInfoAttrs {
		if {$Vars(moveInfo:$attr)} { lappend attrs $attr }
	}

	set name [::util::databaseName $file]
	set cmd [list ::scidb::view::strip moveInfo $file $Vars(variant) 0 $attrs]
	set title [format $mc::StripMoveInfo $name]
	set options [list -message $title]
	set n [::progress::start $parent $cmd {} $options]
	switch $n {
		0 - 1		{ set info $mc::GamesStripped($n) }
		default	{ set info $mc::GamesStripped(N) }
	}

	::log::open $mc::Maintenance
	::log::info $title
	::log::info $info
	::log::close

	set total [::scidb::db::count total $file]

	if {$file ne $clipbaseName && ($n >= 1000 || ($total > 1000 && $n >= ($total + $n)/3))} {
		::dialog::info \
			-parent $parent \
			-title "$::scidb::app: $mc::Maintenance" \
			-message $mc::CompactionRecommended \
			;
	}
}


proc StripPGNTags {parent file} {
	variable Vars

	set cmd [list ::scidb::view::enumTags $file $Vars(variant) 0]
	set title $mc::SearchPGNTags
	set options [list -message $title -interrupt yes]
	set tags [::progress::start $parent $cmd {} $options]
	if {$tags eq "interrupted"} { return }

	if {[llength $tags] == 0} {
		return [::dialog::info -parent $parent -message $mc::NoExtraTagsFound]
	}

	set dlg [tk::toplevel $parent.stripPgnTags]
	pack [set top [ttk::frame $dlg.top -takefocus 0]] -fill both
	set row 3

	ttk::label $top.header -text $mc::SelectSuperfluousTags -font TkHeadingFont
	grid $top.header -row 1 -column 1 -columnspan 3 -sticky w

	foreach pair $tags {
		lassign $pair name freq
		set Vars(tag:$name) 0
		ttk::checkbutton $top.b$name \
			-text $name \
			-command [namespace code [list CheckTagSelection $dlg.ok $tags]] \
			-variable [namespace current]::Vars(tag:$name) \
			;
		ttk::label $top.f$name -text [::locale::formatNumber $freq]
		grid $top.b$name -row $row -column 1 -sticky we
		grid $top.f$name -row $row -column 3 -sticky e
		grid rowconfigure $top [incr row] -minsize $::theme::pady
		incr row
	}

	ttk::separator $top.sep
	ttk::label $top.warning \
		-text $mc::WillBePermanentlyDeleted \
		-padding left \
		-font TkHeadingFont \
		-wraplength 100 \
		;
	grid $top.sep -row $row -column 1 -columnspan 3 -sticky we
	grid $top.warning -row [expr {$row + 2}] -column 1 -columnspan 3 -sticky we
	grid rowconfigure $top [list [expr {$row + 1}] [expr {$row + 3}]] -minsize $::theme::pady
	bind $top <Configure> [namespace code [list ResizeLabel $top.warning %w]]

	grid rowconfigure $top {0 2} -minsize $::theme::pady
	grid columnconfigure $top {0 4} -minsize $::theme::padx
	grid columnconfigure $top {2} -minsize $::theme::padX

	::widget::dialogButtons $dlg {ok cancel}
	$dlg.ok configure -command [namespace code [list DoStripPGNTags $dlg $file $tags]] -state disabled
	$dlg.cancel configure -command [list destroy $dlg]

	wm transient $dlg [winfo toplevel $parent]
	wm withdraw $dlg
	wm title $dlg $mc::FileStripPGNTags
	wm resizable $dlg false false
	::util::place $dlg -parent $parent -position center
	wm deiconify $dlg
	focus $top.b[lindex $tags 0 0]
	::ttk::grabWindow $dlg
	tkwait window $dlg
	::ttk::releaseGrab $dlg
}


proc ResizeLabel {w width} {
	set width [expr {$width - 2*$::theme::padx}]
	if {$width <= 1} { return }
	$w configure -wraplength $width
}


proc CheckTagSelection {btn tags} {
	variable Vars

	foreach pair $tags {
		if {$Vars(tag:[lindex $pair 0])} {
			return [$btn configure -state normal]
		}
	}

	$btn configure -state disabled
}


proc DoStripPGNTags {dlg file tags} {
	variable ::scidb::clipbaseName
	variable Vars

	set parent [winfo parent $dlg]
	destroy $dlg

	set attrs {}
	foreach pair $tags {
		set name [lindex $pair 0]
		if {$Vars(tag:$name)} { lappend attrs $name }
	}

	set name [::util::databaseName $file]
	set cmd [list ::scidb::view::strip tags $file $Vars(variant) 0 $attrs]
	set title [format $mc::StripPGNTags $name]
	set options [list -message $title]
	set n [::progress::start $parent $cmd {} $options]
	switch $n {
		0 - 1		{ set info $mc::GamesStripped($n) }
		default	{ set info $mc::GamesStripped(N) }
	}

	::log::open $mc::Maintenance
	::log::info $title
	::log::info $info
	::log::close

	set total [::scidb::db::count total $file]

	if {$file ne $clipbaseName && ($n >= 1000 || ($total > 1000 && $n >= ($total + $n)/3))} {
		::dialog::info \
			-parent $parent \
			-title "$::scidb::app: $mc::Maintenance" \
			-message $mc::CompactionRecommended \
			;
	}
}


proc Compact {parent file} {
	set name [::util::databaseName $file]
	set title [format $mc::CompactMessage $name]

	set openGames {}
	set modifiedGames {}
	set pos 0
	foreach entry [::game::gameList] {
		lassign $entry base _ number
		if {$base eq $file} {
			if {[::scidb::game::query $pos modified?]} {
				lappend modifiedGames $pos
			} else {
				lappend openGames $pos
			}
		}
		incr pos
	}
	if {[llength $modifiedGames]} {
		set msg [format $mc::CannotCompactDatabase $name]
		append msg <embed>

		::dialog::error \
			-parent $parent \
			-title $title \
			-message $msg \
			-embed [namespace code [list ::game::embedReleaseMessage $modifiedGames]] \
			;
		return
	}

	set msg [format $mc::ReallyCompact [::util::databaseName $file]]
	set n [lindex [::scidb::db::get stats $file] 0]
	switch $n {
		0			{ set detail $mc::RemoveSpace }
		1			{ set detail $mc::ReallyCompactDetail(1) }
		default	{ set detail [format $mc::ReallyCompactDetail(N) $n] }
	}
	set reply [::dialog::question \
		-parent $parent \
		-title "$::scidb::app: $mc::Maintenance" \
		-message $msg \
		-detail $detail \
		-buttons {yes no} \
		-default no \
	]
	if {$reply eq "no"} { return }

	if {[llength $openGames]} {
		set msg [format $mc::CloseAllDeletedGames $name]
		append msg <embed>

		set reply [::dialog::question \
			-parent $parent \
			-title $title \
			-message $msg \
			-buttons {yes no} \
			-default yes \
			-embed [namespace code [list ::game::embedReleaseMessage $openGames]] \
		]

		if {$reply eq "yes"} {
			foreach pos $openGames {
				::application::pgn::release $pos
				::game::release $pos
			}
		}
	}

	set variant [::scidb::app::variant]
	::browser::closeAll $file $variant
	::overview::closeAll $file $variant
	set cmd [list ::scidb::db::compact $file]
	set options [list -message $title]
	::progress::start $parent $cmd {} $options
	switch $n {
		0 - 1		{ set info $mc::GamesRemoved($n) }
		default	{ set info $mc::GamesRemoved(N) }
	}
	::log::open $mc::Maintenance
	::log::info $title
	::log::info $info
	::log::close
}



proc ShowDuplicates {parent file variant} {
	OpenMaintenanceReport $parent $file $variant duplicates
}


proc MarkDuplicates {tv file variant} {
	set selected [$tv selection]
	if {[llength $selected] == 0} { return }
	set changed 0
	set parents {}
	foreach item $selected {
		set par [$tv parent $item]
		if {$par eq {}} { continue }
		set index [lindex [$tv item $item -values] 0]
		if {$index eq {}} { continue }
		set idx [expr {$index - 1}]
		::scidb::db::markDeleted $file $variant $idx
		$tv delete $item
		lappend parents $par
		set changed 1
	}
	if {!$changed} { return }
	foreach par [lsort -unique $parents] {
		if {[llength [$tv children $par]] == 0} {
			$tv delete $par
		}
	}
	RefreshBaseState $file $variant
	if {[llength [$tv children {}]] == 0} {
		set dlg [winfo toplevel $tv]
		if {[string match .maintenance_* $dlg]} {
			RefreshMaintenanceReport $dlg
		} else {
			destroy $dlg
		}
		return
	}
	set dlg [winfo toplevel $tv]
	if {[string match .maintenance_* $dlg]} {
		RefreshMaintenanceReport $dlg
	}
}


proc ShowEcoStats {parent file variant} {
	OpenOpeningPrepReport $parent $file $variant
}


proc MaterialDialogName {file variant} {
	return .material_[string map {: _ . _ / _} $file]_${variant}
}


proc OpeningPrepDialogName {file variant} {
	return .openingprep_[string map {: _ . _ / _} $file]_${variant}
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
		ttk::button $controls.load -text $mc::OpeningPrepLoadGame \
			-command [namespace code [list OpeningPrepLoadSelectedGame $dlg]]
		ttk::button $controls.eco -text $mc::OpeningPrepOpenEco \
			-command [namespace code [list OpenMaintenanceReport $dlg $file $variant openings]]
		ttk::button $controls.switcher -text $mc::OpeningPrepOpenInSwitcher \
			-command [namespace code [list OpenOpeningPrepEcoInSwitcher $dlg]]
		ttk::button $controls.savews -text $mc::OpeningPrepSaveWorkingSet \
			-command [namespace code [list SaveOpeningPrepEcoWorkingSet $dlg]]
		ttk::button $controls.close -text $mc::Close -command [list destroy $dlg]

		grid $controls.methodLabel -row 0 -column 0 -sticky w
		grid $controls.method -row 0 -column 1 -sticky ew
		grid $controls.ratingLabel -row 0 -column 2 -sticky w -padx {8 0}
		grid $controls.rating -row 0 -column 3 -sticky ew
		grid $controls.rareOnly -row 0 -column 4 -sticky w -padx {8 0}
		grid $controls.rareLimitLabel -row 0 -column 5 -sticky w -padx {4 0}
		grid $controls.rareLimit -row 0 -column 6 -sticky ew
		grid $controls.refresh -row 0 -column 7 -sticky ew -padx {8 0}
		grid $controls.play -row 0 -column 8 -sticky ew -padx {4 0}
		grid $controls.load -row 0 -column 9 -sticky ew -padx {4 0}
		grid $controls.eco -row 0 -column 10 -sticky ew -padx {4 0}
		grid $controls.switcher -row 0 -column 11 -sticky ew -padx {4 0}
		grid $controls.savews -row 0 -column 12 -sticky ew -padx {4 0}
		grid $controls.close -row 0 -column 13 -sticky e -padx {4 0}
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


proc MaintenanceDialogName {file} {
	return .maintenance_[string map {: _ . _ / _} $file]
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
		ttk::button $actions.copy -text $mc::CopySummary \
			-command [namespace code [list CopyMaintenanceSummary $dlg]]
		ttk::button $actions.refresh -text $mc::Refresh \
			-command [namespace code [list RefreshMaintenanceReport $dlg]]
		ttk::button $actions.close -text $mc::Close -command [list destroy $dlg]
		pack $actions.duplicates -side left -padx {0 4}
		pack $actions.compact -side left -padx 4
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


proc Recode {file parent} {
	variable RecentFiles
	variable Vars

	set enc [::scidb::db::get usedencoding $file]
	set ext [string tolower [$Vars(switcher) extension $file]]
	switch $ext {
		cbh 		{ set defaultEncoding $::encoding::windowsEncoding }
		cbf		{ set defaultEncoding $::encoding::dosEncoding }
		default	{ set defaultEncoding utf-8 }
	}
	set encoding [::encoding::choose $parent $enc $defaultEncoding]
	if {[llength $encoding] == 0 || $encoding eq $enc} { return }

	set name [::util::databaseName $file]
	set msg [string map [list "%base" $name "%from" $enc "%to" $encoding] $mc::RecodingDatabase]
	::log::open $mc::Recode
	::log::info $msg

	switch $ext {
		pgn - bpgn {
			::import::showOnlyEncodingWarnings true
			closeBase $parent $file
			openBase $parent $file no -encoding $encoding -readonly yes
			::import::showOnlyEncodingWarnings false
		}

		default {
			lappend options -message $msg
			::progress::start $parent [list ::scidb::db::recode $file $encoding] {} $options
		}
	}

	set count [::scidb::db::count total $file]
	::log::info [format $mc::RecodedGames [::locale::formatNumber $count]]
	::log::close

	$Vars(switcher) encoding $file $encoding
	set i [lsearch -exact -index 1 $RecentFiles $file]
	if {$i >= 0} { lset RecentFiles $i 2 $encoding }

	if {![string match *pgn $ext]} {
		# openBase ic already checking the encoding status
		CheckEncoding $parent $file [::scidb::db::get usedencoding $file]
	}
}


proc CheckEncoding {parent file encoding} {
	if {[::scidb::db::get encodingState $file] eq "failed"} {
		::dialog::warning -parent $parent -buttons {ok} -message [format $mc::EncodingFailed $encoding]
	}
}


proc ChangeIcon {parent file} {
	variable Types
	variable Options
	variable Vars

	set dlg [tk::toplevel $parent.changeIcon -class Dialog]
	set ext [string tolower [$Vars(switcher) extension $file]]
	if {[winfo workareaheight $parent] >= 650} { set rows 10 } else { set rows 9 }
	set cols [expr {([llength $Types($ext)] + $rows - 1)/$rows}]
	set list [::tlistbox $dlg.list \
		-visible $Options(visible) \
		-linespace 48 \
		-skiponeunit no \
		-columns $cols \
		-height $rows \
		-ipady 5 \
	]
	pack $list -expand yes -fill both
	$list addcol image -id image
	$list addcol text -id text

	set typeList {}
	foreach t $Types($ext) { lappend typeList [list $t [set mc::T_$t]] }
	set typeList [lsort -index 1 $typeList]

	foreach entry $typeList {
		lassign $entry t text
		$list insert [list [set [namespace current]::icons::${t}(48x48)] $text]
	}
	$list resize

	set type [$Vars(switcher) type $file]
	set Vars(icon) [lsearch -exact -index 0 $typeList $type]
	bind $list <Configure> [namespace code { ConfigureIconList %W }]
	bind $list <Escape> [list $dlg.cancel invoke]
	bind $list <<ListboxSelect>> [namespace code [list SelectIcon %W %d $typeList $file]]
	$list select $Vars(icon)
	::widget::dialogButtons $dlg {ok cancel}
	$dlg.ok configure -command [namespace code [list SetIcon $dlg $typeList $file]]
	$dlg.cancel configure -command [list destroy $dlg]
	wm protocol $dlg WM_DELETE_WINDOW [list destroy $dlg]
	wm transient $dlg [winfo toplevel $parent]
	wm withdraw $dlg
	wm title $dlg "$mc::ChangeIcon ([::util::databaseName $file])"
	wm resizable $dlg false false
	::util::place $dlg -parent $parent -position center
	wm deiconify $dlg
	focus $dlg.list
	::ttk::grabWindow $dlg
	tkwait window $dlg
	::ttk::releaseGrab $dlg
}


proc SelectIcon {w data typeList file} {
	variable Vars

	if {$data eq ""} {
		SetIcon $w $typeList $file
	} else {
		set Vars(icon) $data
	}
}


proc SetIcon {w typeList file} {
	variable Vars
	variable Types
	variable RecentFiles

	set type [lindex $typeList $Vars(icon) 0]
	set selection [lsearch -exact $Types(sci) $type]
	set type [lindex $Types(sci) $selection]
	$Vars(switcher) type $file $type
	::scidb::db::set type $file $selection
	destroy [winfo toplevel $w]
	lset RecentFiles [FindRecentFile $file] 0 $type
	[namespace parent]::information::update
}


proc SetDatabaseType {file type} {
	variable Vars
	variable Types
	variable RecentFiles

	set selection [lsearch -exact $Types(sci) $type]
	if {$selection < 0} { return }
	$Vars(switcher) type $file $type
	::scidb::db::set type $file $selection
	set i [FindRecentFile $file]
	if {$i >= 0} {
		lset RecentFiles $i 0 $type
	}
	[namespace parent]::information::update
}


proc ConfigureIconList {w} {
	variable Options
	set Options(visible) [$w cget -height]
}


proc AddRecentFile {type file encoding readonly} {
	variable RecentFiles
	variable MaxHistory

	set i [FindRecentFile $file]
	if {$i >= 0} { set RecentFiles [lreplace $RecentFiles $i $i] }
	set RecentFiles [linsert $RecentFiles 0 [list $type $file $encoding $readonly]]
	if {[llength $RecentFiles] > $MaxHistory} { set RecentFiles [lrange $RecentFiles 0 9] }
	[namespace parent]::information::update
	#::menu::configureOpenRecent [GetRecentState]
}


proc GetRecentState {} {
	variable RecentFiles
	variable Vars

	set count 0

	foreach entry $RecentFiles {
		set file [lindex $entry 1]
		if {![$Vars(switcher) contains? $file]} { incr count }
	}

	if {$count == 0} { return disabled }
	return normal
}


proc FindRecentFile {file} {
	variable RecentFiles
	return [lsearch -index 1 $RecentFiles $file]
}


proc WriteOptions {chan} {
	::options::writeList $chan [namespace current]::RecentFiles
	::options::writeList $chan [namespace current]::PreOpen
	::options::writeItem $chan [namespace current]::Positions
	::options::writeItem $chan [namespace current]::CurrentBase
	::options::writeItem $chan [namespace current]::MaterialSearchPresets 0
	::options::writeItem $chan [namespace current]::RatingSearchPresets 0
	::options::writeItem $chan [namespace current]::AdvancedSearchPresets 0
}
::options::hookWriter [namespace current]::WriteOptions


proc DestroyTab {w tab} {
	variable Positions

	if {$w eq $tab} {
		if {[winfo toplevel $w] eq $w} {
			set Positions([lindex [split $w .] end]) [wm geometry $w]
		}
	}
}


proc Identify {nb x y} {
	set index [$nb index @$x,$y]
	if {[llength $index] == 0} { return {-1 ""} }
	if {[llength [$nb tab $index -image]] == 0} { return [list $index "label"] }
	if {[$nb identify $x $y] ne "label"} { return [list $index ""] }
	set x1 $x
	while {[$nb identify [expr {$x1 + 1}] $y] eq "label"} { incr x1 +1 }
	incr x1 -16
	if {$x1 <= $x} { return [list $index "icon"] }
	return [list $index "label"]
}


proc Motion {nb x y {showTooltip 1}} {
	variable Vars

	if {[llength [$nb tabs]] == $Vars(mintabs)} { return }
	lassign [Identify $nb $x $y] index what
	if {$index == -1} { set what "label" }

	switch $what {
		icon {
			if {[$nb tab $index -image] eq $icon::16x16::undock_disabled} { return }
			if {$Vars(pressed)} {
				set icon $icon::16x16::undock_sunken
			} else {
				set icon $icon::16x16::undock_active
				if {$index != $Vars(motion) && $showTooltip} {
					::tooltip::show $nb $::twm::mc::Undock
				}
			}
			set Vars(motion) $index
		}

		label {
			return [Leave $nb]
		}

		default {
			if {$index >= 0} {
				if {[$nb index [$nb select]] == $index} {
					set icon $icon::16x16::undock
				} elseif {$Vars(showDisabled)} {
					set icon $icon::16x16::undock_disabled
				} else {
					set icon {}
				}
			}
			set Vars(motion) -1
			::tooltip::hide
		}
	}

	if {$index >= 0} {
		$nb tab $index -image $icon
	}
}


proc Enter {nb} {
	variable Vars

	if {[llength [$nb tabs]] == $Vars(mintabs)} { return }

	if {$Vars(motion) >= 0 && $Vars(motion) < [llength [$nb tabs]]} {
		set icon [$nb tab $Vars(motion) -image]

		if {[llength $icon] > 0 && $icon ne $icon::16x16::undock_disabled} {
			$nb tab $Vars(motion) -image $icon::16x16::undock
			set Vars(motion) -1
		}
	}
}


proc Leave {nb} {
	variable Vars

	::tooltip::hide
	if {[llength [$nb tabs]] == $Vars(mintabs)} { return }

	if {$Vars(motion) >= 0} {
		foreach t [$nb tabs] {
			set icon [$nb tab $t -image]
			if {[llength $icon] > 0 && $icon ne $icon::16x16::undock_disabled} {
				$nb tab $t -image $icon::16x16::undock
			}
		}
		set Vars(motion) -1
	}
}


proc ButtonPress {nb x y} {
	variable Vars

	::tooltip::hide
	lassign [Identify $nb $x $y] index what
	if {$what eq "icon" && [$nb index [$nb select]] != $index} { set what "label" }

	switch $what {
		icon {
			if {[llength [$nb tabs]] == $Vars(mintabs)} { return }
			if {[$nb tab $index -image] eq $icon::16x16::undock_disabled} { return }
			$nb tab $index -image $icon::16x16::undock_sunken
			set Vars(pressed) 1
		}

		label {
			set Vars(current) $index
			ttk::notebook::Press $nb $x $y
			after idle [namespace code [list Motion $nb $x $y 0]]
		}
	}
}


proc ButtonRelease {nb x y} {
	variable Vars

	set Vars(pressed) 0
	set current $Vars(current)
	set Vars(current) -1

	if {[llength [$nb tabs]] == $Vars(mintabs)} { return }
	lassign [Identify $nb $x $y] index what
	if {$index == -1} { set index $Vars(motion) }

	if {$index >= 0} {
		if {$current == $index} { return }
		if {[llength [$nb tab $index -image]] == 0} { return }
		if {[$nb tab $index -image] eq $icon::16x16::undock_disabled} { return }
		$nb tab $index -image $icon::16x16::undock
	}

	if {$what eq "icon"} {
		Undock $nb $index
	}

	::tooltip::hide
	after idle [namespace code [list Motion $nb $x $y 0]]
}


proc Undock {nb index {geometry {}}} {
	variable Vars

	set title [$nb tab $index -text]
	set w [lindex [$nb tabs] $index]
	$nb forget $w
	if {[string length $geometry] == 0} {
		set wd [winfo width $w]
		set ht [winfo height $w]
		if {$wd <= 1 || $ht <= 1} {
			set v [lindex [$nb tabs] 0]
			set wd [winfo width $v]
			set ht [winfo height $v]
		}
	}
	::scidb::tk::twm release $w
	update idle ;# is reducing flickering
	if {[string length $geometry] == 0} {
		wm geometry $w ${wd}x${ht}
	} else {
		wm geometry $w $geometry
	}
	set id [lindex [split $w .] end]
	# TODO: use [computeHeight $Vars($id) 8] instead
	set overhang [${id}::overhang $Vars($id)]
	set linespace [${id}::linespace $Vars($id)]
	set minheight [expr {8*$linespace + $overhang}]
#	wm transient $w [winfo toplevel $nb]
	wm minsize $w 500 $minheight
	wm title $w "$::scidb::app - $title"
	wm state $w normal
	wm protocol $w WM_DELETE_WINDOW [namespace code [list Dock $nb $w]]
}


proc Dock {nb w} {
	variable Vars
	variable Tabs

	if {[llength [$nb tabs]] == $Vars(mintabs)} {
		$nb tab [$nb select] -image $icon::16x16::undock
	}
	::scidb::tk::twm capture $w
	set id [lindex [split $w .] end]
	set indices {}
	foreach t [$nb tabs] {
		set i [lsearch -exact $Tabs [lindex [split $t .] end]]
		lappend indices $i
	}
	set indices [lsort -integer $indices]
	set i [lsearch -exact $Tabs $id]
	set k 0
	while {$k < [llength $indices] && [lindex $indices $k] < $i} { incr k }
	if {$k == [llength [$nb tabs]]} { set k end }
	if {$Vars(showDisabled)} { set icon $icon::16x16::undock_disabled } else { set icon {} }
	$nb insert $k $w -sticky nsew -compound right -image $icon
	set var [namespace parent]::mc::Tab($id)
	::widget::notebookSetLabel $nb $w [set $var]
	${id}::activate $Vars($id) 0
	CheckTabState
}


namespace eval icon {
namespace eval 16x16 {

set undock [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAMAAAAoLQ9TAAAA2FBMVEUAAAAAAAAAAAAAAAAB
	DhcAAAAAAxQ9PT0uLi53d3ZOTk5Tk6tFRUVCQkIQT2hVla08PDw6Ojo3Nzc2NjZAhJ5so7OH
	h4ZycnKJpqJambCLtrcYYn7FxMRHaXeBta99rbbLy8oeY32goJ9xmJShoaC1tbXAwL8qc460
	tLS2tbS3t7ZzjZbIyMiTk5N+pLIAAAAAAAAAAAAAAAAAAACKucK/v77AwL/BwcDExMTKycnR
	0dHj4+Lp6Oft7ezt7e3u7u3u7u7v7+7w8O/w8PDx8fDy8vHz8/L09PQeL5dpAAAAAXRSTlMA
	QObYZgAAAFhJREFUGNNjYCAXGBsaGgMBkoAJCOjDeMZ6EAEDCF8dyDN2tHVwcjHSAQtogwSc
	nF3d3KFmaBrbWBpDgBpYQMPY2srC3NRMF2aDlrGDvb2tHbKdEMBANQAAtIkRPpJ+I/QAAAAA
	SUVORK5CYII=
}]

set undock_active [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAMAAAAoLQ9TAAAA21BMVEUAAAAAAAAAAAAAAAAB
	DhcAAAAAAxQ9PT0uLi53d3ZOTk5Tk6tFRUVCQkIQT2hVla08PDw6Ojo3Nzc2NjZAhJ5so7OH
	h4ZycnKJpqJambCLtrcYYn7FxMRHaXeBta99rbbLy8oeY32goJ9xmJShoaC1tbXAwL8qc460
	tLS2tbS3t7ZzjZbIyMiTk5N+pLIAAAAAAAAAAAAAAAAAAACKucK/v77AwL/BwcDExMTKycnR
	0dHj4+Lp6Oft7ezt7e3u7u3u7u7v7+7w8O/w8PDx8fDy8vHz8/L09PT///8tKC41AAAAAXRS
	TlMAQObYZgAAAGZJREFUGNNj8EADDB4MKEAMl4CxoaExECAJmICAPlTA2FgPImAAEVAH8owd
	bR2cXIx0wALaIAEnZ1c3d6gZmsY2lsYQoAYW0DC2trIwNzXThVmrZexgb29rZ4xwB1Q9fpfi
	FRBDBQA1Mxx0CnVnXwAAAABJRU5ErkJggg==
}]

set undock_sunken [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAMAAAAoLQ9TAAAA2FBMVEUAAAAAAAAAAAABDhcA
	AAAAAxQ9PT0uLi53d3ZOTk5Tk6tFRUVCQkIQT2hVla08PDw6Ojo3Nzc2NjZAhJ5so7OHh4Zy
	cnKJpqJambCLtrcYYn7FxMRHaXeBta99rbbLy8oeY32goJ9xmJShoaC1tbXAwL8qc460tLS2
	tbS3t7ZzjZbIyMiTk5N+pLIAAAAAAAAAAAAAAAAAAACKucK/v77AwL/BwcDExMTKycnR0dHj
	4+Lp6Oft7ezt7e3u7u3u7u7v7+7w8O/w8PDx8fDy8vHz8/L09PT///9HJVJiAAAAAXRSTlMA
	QObYZgAAAGZJREFUGNNjEEUDDKIMKMAdl4CRgYERECAJGIOAHlTAyEgXIqAPEVAD8owcbOwd
	nQ21wQJaIAFHJxdXN6gZGkbWFkYQoAoWUDeysjQ3MzHVgVmraWRvZ2dja4RwB1Q9fpfiFXBH
	BQCaEhuBKwIaLAAAAABJRU5ErkJggg==
}]

set undock_disabled [image create photo -width 16 -height 16]
::scidb::tk::image disable $undock $undock_disabled

} ;# namespace 16x16
} ;# namespace icon
} ;# namespace database
} ;# namespace application

ttk::copyBindings TNotebook UndockingNotebook

bind UndockingNotebook <Motion>				{ application::database::Motion %W %x %y }
bind UndockingNotebook <Enter>				{ application::database::Enter %W }
bind UndockingNotebook <Leave>				{ application::database::Leave %W }
bind UndockingNotebook <ButtonPress-1>		{ application::database::ButtonPress %W %x %y }
bind UndockingNotebook <ButtonRelease-1>	{ application::database::ButtonRelease %W %x %y }

# vi:set ts=3 sw=3:
