# ======================================================================
# ::menu::dropdown -- the reorganised main drop-down (decision 003)
#
# The button keeps its place in .application.nb; its entries are the
# task cascades File..Help from PROPOSAL section 2 (main drop-down, not a
# menu bar). The tree below is data; every command row is a registry
# action and every menu -command is exactly [::action::run <id>].
# Cascades fill lazily on first post; the top menu is built once.
# ======================================================================

namespace eval menu {
	variable DropdownTree {}
	variable DropdownFilled [dict create]
	variable DropdownOrder 0
	variable DropdownCounter 0
	variable DropdownWidget ""
}

namespace eval menu::mc {
	# Top-level cascades
	set File							"File"
	set Edit							"Edit"
	set Game							"Game"
	set Database						"Database"
	set Board							"Board"
	set Analysis						"Analysis"
	set Training						"Training"
	set Tools							"Tools"
	set View							"View"

	# File
	set NewDatabase					"New Database"
	set OpenDatabase					"Open Database…"
	set OpenRecent						"Open Recent"
	set CloseDatabase					"Close Database"
	set SaveChanges					"Save Changes"
	set Import							"Import"
	set ImportPgn						"PGN file(s)…"
	set ImportDb						"Games from another database…"
	set Export							"Export"
	set ExportPgn						"PGN…"
	set ExportHtml						"HTML report…"
	set ExportArchive					"Portable archive (.scv)…"
	set CreateDatabaseArchive		"Create Database Archive…"

	# Edit
	set EditUndo						"Undo"
	set EditRedo						"Redo"
	set EditCut							"Cut"
	set EditCopy						"Copy"
	set EditPaste						"Paste"
	set SelectAll						"Select All"
	set Find							"Find"
	set KeyboardPreferences			"Keyboard Preferences…"
	set Preferences					"Preferences"
	set PgnExportOptions				"PGN export options…"

	# Game
	set NewGame							"New Game"
	set LoadGameNumber				"Load Game Number…"
	set NextGame						"Next Game"
	set PreviousGame					"Previous Game"
	set FirstGame						"First Game"
	set LastGame						"Last Game"
	set RandomGame						"Random Game"
	set SaveGame						"Save Game"
	set ReplaceGame					"Replace Game"
	set ReplaceMoves					"Replace Moves"
	set AddAsNewGame					"Add as New Game"
	set AddToRepertoire				"Add to Repertoire"
	set AddLineToRepertoire			"Add Line to Repertoire"
	set ReloadFromDatabase			"Reload from Database"
	set CopyGame						"Copy Game"
	set PasteGame						"Paste Game"
	set PasteClipbase					"paste last clipbase game"
	set PasteGameTab					"paste from game tab"
	set MergeGame						"Merge Game"
	set MergeClipbase					"merge clipbase"
	set MergeGameTab					"merge from game tab"
	set ExportGame						"Export Game…"
	set GameHistory					"Game History"
	set RecentGames					"recent games"
	set ClearHistory					"Clear History"
	set CloseGame						"Close Game"

	# Database
	set DbSearch						"Search"
	set SearchPlain					"Plain-Language…"
	set SearchAdvanced				"Advanced…"
	set SearchMaterial				"Material…"
	set SearchRating					"Rating…"
	set SearchDuplicates				"Duplicates…"
	set SearchQuery					"Query Editor…"
	set Reports							"Reports"
	set ReportEco						"ECO Statistics…"
	set ReportOpening					"Opening Report…"
	set ReportRepertoire				"Repertoire Report…"
	set ReportResult					"Result Check…"
	set ReportTimeControl			"Time-Control Profile…"
	set ReportTrends					"Trends…"
	set Maintenance						"Maintenance"
	set MaintCompact					"Compact…"
	set MaintStripMoves				"Strip Move Information…"
	set MaintStripTags				"Strip PGN Tags…"
	set MaintConvert					"Convert to Native Format…"
	set MaintRecode					"Recode…"
	set MaintChangeIcon				"Change Icon…"
	set MaintRepertoireType			"Repertoire Type"
	set Properties						"Properties…"
	set ReadOnly						"Read-only"
	set PlayerData						"Player Data"
	set UpdateRating					"Update Rating Data…"
	set CheckNames						"Check Name Spellings…"

	# Board
	set StartPosition					"Start Position"
	set StandardPosition				"Standard"
	set Chess960Position				"Chess960"
	set Symm960Position				"Symm960"
	set ShufflePosition				"Shuffle"
	set SetUpPosition					"Set Up Position…"
	set SetStartBoard					"Set Start Board…"
	set SetStartPosition				"Set Start Position…"
	set FlipBoard						"Flip Board"
	set InsertNullMove					"Insert Null Move"
	set BoardSetup						"Board Setup…"
	set Appearance						"Appearance"
	set AppSideToMove					"side to move"
	set AppMaterialValues			"material values/bar"
	set AppBorder						"border"
	set AppCoordinates					"coordinates"
	set AppSmallLetters				"small letters"
	set AppSuggestedMove				"suggested move"
	set AppVariationArrows				"variation arrows"
	set AppAnnotation					"annotation"
	set AppAnnotationTimeout		"annotation timeout"
	set AppSlidingVariation			"sliding variation pane"
	set AppPromotedMark				"promoted-piece mark"
	set ShowTablebase					"Show Tablebase"
	set ShowTablebaseShow			"show"
	set ShowTablebaseOnline			"online lookup"
	set ShowTablebaseLocal			"local folder…"

	# Analysis
	set StartStopEngine				"Start / Stop Engine"
	set EngineDictionary				"Engine Dictionary…"
	set ChooseReviewEngine			"Choose Engine for Review…"
	set AnalyzePosition				"Analyze This Position"
	set Explain							"Explain"
	set ExplainPosition				"Position"
	set ExplainLine					"Line"
	set ExplainMove					"Move"
	set ExplainComment					"Comment"
	set FactCheckAnnotations		"Fact-Check Annotations"
	set Tablebase						"Tablebase"
	set OpeningExplorer				"Opening Explorer"

	# Training
	set TacticsTrainer					"Tactics Trainer…"
	set TrainRepertoire				"Train Repertoire…"
	set StudyPlan						"Study Plan…"
	set OpponentBrief					"Opponent Brief…"
	set TrainingSetFromGames			"Training Set from Games…"
	set CheckGameResults				"Check Game Results…"

	# Tools
	set PlayerDictionary				"Player Dictionary…"
	set PlayerCard						"Player Card…"
	set EngineConsole					"Engine Console…"
	set ImportGames					"Import Games…"
	set Assistant						"Assistant"
	set VoiceAssistant					"Voice Assistant"
	set InstallLegacyFonts			"Install Legacy Fonts…"

	# View
	set Panes							"Panes"
	set LoadLayout						"Load Layout"
	set SaveLayout						"Save Layout"
	set SaveLayoutAs					"Save Layout As…"
	set ManageLayouts					"Manage Layouts…"
	set Colors							"Colors"
	set IconSize						"Icon Size"
	set IncreaseFontSize				"Increase Font Size"
	set DecreaseFontSize				"Decrease Font Size"

	# Shared / moved labels (exact PROPOSAL section 2 text)
	# Variants / shared mnemonic labels
	set Normal							"Normal"
	set Three-check					"Three-check"
	set Crazyhouse					"Crazyhouse"
	set {variant list}				"variant list"
	set Quit								"Quit"
	set Layout							"Layout"
	set Toolbars						"Toolbars"
	set Theme								"Theme"
	set Language						"Language"

	set DiscoverDatabases			"Discover Databases…"
	set Open3DBoard					"Open 3D Board"
	set OpenWebGL3DBoard				"Open WebGL 3D Board"
	set Embed3DBoard					"3D Board in Main Window"
	set EndgameTrainer				"Endgame Trainer…"
	set GuessTheMove					"Guess the Move…"
	set PlayAgainstEngine			"Play Against Engine…"
	set EngineMatch					"Engine Match…"
	set StudyPlan						"Study Plan…"
	set OpponentBrief					"Opponent Brief…"
	set TrainingSetFromGames			"Training Set from Games…"
	set CheckGameResults				"Check Game Results…"
	set OpeningBookEditor			"Book Editor…"
	set CorrespondenceGames			"Correspondence Games…"
	set ICCFSettings					"ICCF Settings…"
	set DownloadGames					"Download Games…"
	set ChooseModel					"Choose Model…"
	set VoiceAssistant					"Voice Assistant"
	set InstallLegacyFonts			"Install Legacy Fonts…"
	set MenuAssignFileTypes		"Assign File Types…"
	set PlayerDictionary				"Player Dictionary…"
	set PlayerCard						"Player Card…"
	set EngineConsole					"Engine Console…"
	set ImportGames					"Import Games…"
	set Assistant						"Assistant"
	set EngineDictionary				"Engine Dictionary…"
	set CompareEngines				"Compare Engines…"
	set MenuEngines					"Engines…"
	set GameReview						"Game Review…"
	set FactCheckAnnotations		"Fact-Check Annotations"
	set Tablebase						"Tablebase"
	set OpeningExplorer				"Opening Explorer"
	set ChooseReviewEngine			"Choose Engine for Review…"
	set AnalyzePosition				"Analyze This Position"
	set Explain							"Explain"
	set ExplainPosition				"Position"
	set ExplainLine					"Line"
	set ExplainMove					"Move"
	set ExplainComment					"Comment"
	set MenuShowLog					"Show Log…"
	set Fullscreen						"Full-Screen"
	set MenuTipOfTheDay				"Tip of the Day…"
	set MenuAboutChesswiz			"About Chesswiz…"
	set ContactBugReport				"Bug Report"
	set ContactFeatureRequest		"Feature Request"
	set MenuPrivatePlayerCard		"Private Player Card…"
	set StartStopEngine				"Start / Stop Engine"

	# View panes (dynamic rows; labels frozen in the fixture)
	set PaneBoard						"board"
	set PaneEditor					"editor"
	set PaneGameList				"game list"
	set PanePlayers					"players"
	set PaneEvents					"events"
	set PaneSites					"sites"
	set PaneAnnotators				"annotators"
	set PanePositions				"positions"
	set PaneTree						"tree"
	set PaneAnalysis				"analysis"
	set PaneMedia					"media"
	set PaneReport					"report"
	set PaneAssistant				"assistant"
	set PaneExplorer				"explorer"
	set PerToolbarCheckbuttons	"per toolbar checkbuttons"

	# Help
	set Help							"Help"
}

# Node constructors (kept tiny so the tree below reads like the fixture).
proc ::menu::MC {name} {
	return [set ::menu::mc::$name]
}

proc ::menu::Sep {} {
	return {sep}
}

proc ::menu::CmdNode {id label {accel ""} {visible ""} {enabled ""}} {
	return [list cmd $id $label $accel $visible $enabled]
}

proc ::menu::CascadeNode {label {accel ""} {children dynamic}} {
	return [list cascade $label $accel $children]
}

proc ::menu::DynNode {label} {
	return [list dyn $label]
}

proc ::menu::ToggleNode {id label accel labelScript} {
	return [list toggle $id $label $accel $labelScript]
}

proc ::menu::DefineTree {} {
	variable DropdownTree

	set DropdownTree [list \
		[list cascade File "" [list \
			[list cascade NewDatabase "Ctrl+Shift+N" [list \
				[list cmd menu.file.new.normal Normal] \
				[list cmd menu.file.new.three Three-check] \
				[list cmd menu.file.new.crazy Crazyhouse] \
				[list cmd menu.file.new.variants "variant list"] \
			]] \
			[list cmd menu.file.open OpenDatabase "Ctrl+O"] \
			[list cascade OpenRecent "" dynamic] \
			[list cmd menu.file.close CloseDatabase "Ctrl+W" {::menu::DbOpen}] \
			[list cmd menu.file.save SaveChanges "Ctrl+S" {::menu::DbOpen} {::menu::DbWritable}] \
			[list sep] \
			[list cascade Import "" [list \
				[list cmd menu.file.import.pgn ImportPgn "" {::menu::DbOpen} {::menu::DbWritable}] \
				[list cmd menu.file.import.db ImportDb "" {::menu::DbOpen} {::menu::DbWritable}] \
			]] \
			[list cascade Export "" [list \
				[list cmd menu.file.export.pgn ExportPgn "" {::menu::DbOpen}] \
				[list cmd menu.file.export.html ExportHtml "" {::menu::DbOpen}] \
				[list cmd menu.file.export.archive ExportArchive "" {::menu::DbOpen}] \
			]] \
			[list cmd menu.file.archive_create CreateDatabaseArchive "" {::menu::DbOpen} {::menu::DbWritable}] \
			[list sep] \
			[list cmd app-quit Quit "Ctrl+Q"] \
		]] \
		[list cascade Edit "" [list \
			[list cmd app-undo EditUndo "Ctrl+Z"] \
			[list cmd app-redo EditRedo "Ctrl+Y"] \
			[list sep] \
			[list cmd app-cut EditCut "Ctrl+X"] \
			[list cmd app-copy EditCopy "Ctrl+C"] \
			[list cmd app-paste EditPaste "Ctrl+V"] \
			[list cmd app-select-all SelectAll "Ctrl+A"] \
			[list cmd app-find Find "Ctrl+F"] \
			[list sep] \
			[list cmd menu.edit.keyboard KeyboardPreferences] \
			[list cascade Preferences "" [list \
				[list cmd menu.edit.preferences.engines MenuEngines] \
				[list cmd menu.edit.preferences.pgn PgnExportOptions] \
				[list cmd menu.edit.preferences.player MenuPrivatePlayerCard] \
			]] \
		]] \
		[list cascade Game "" [list \
			[list cascade NewGame "Ctrl+Shift+G" dynamic] \
			[list cmd menu.game.load_number LoadGameNumber "" {::menu::DbOpen}] \
			[list cmd game-next NextGame "Ctrl+Down"] \
			[list cmd game-prev PreviousGame "Ctrl+Up"] \
			[list cmd game-first FirstGame "Ctrl+Home"] \
			[list cmd game-last LastGame "Ctrl+End"] \
			[list cmd menu.game.random RandomGame "" {::menu::DbOpen}] \
			[list sep] \
			[list cascade SaveGame "" [list \
				[list cmd game-replace ReplaceGame "Ctrl+R" {expr {[::menu::GameLoaded] && ![::menu::TrialMode]}} {::menu::DbWritable}] \
				[list cmd game-replace-moves ReplaceMoves "Ctrl+V" {expr {[::menu::GameLoaded] && ![::menu::TrialMode]}} {::menu::DbWritable}] \
				[list cmd game-save AddAsNewGame "Ctrl+S" {expr {[::menu::GameLoaded] && ![::menu::TrialMode]}} {::menu::DbWritable}] \
				[list cascade AddToRepertoire "" dynamic] \
				[list cascade AddLineToRepertoire "" dynamic] \
			]] \
			[list cmd menu.game.reload ReloadFromDatabase "" {::menu::GameLoaded}] \
			[list sep] \
			[list cmd menu.game.copy CopyGame "" {::menu::GameLoaded}] \
			[list cascade PasteGame "" [list \
				[list dyn PasteClipbase] \
				[list dyn PasteGameTab] \
			]] \
			[list cascade MergeGame "" [list \
				[list dyn MergeClipbase] \
				[list dyn MergeGameTab] \
			]] \
			[list cmd game-export ExportGame "Ctrl+E" {::menu::GameLoaded}] \
			[list sep] \
			[list cascade GameHistory "" [list \
				[list dyn RecentGames] \
				[list cmd menu.game.history.clear ClearHistory "" {::menu::GameLoaded}] \
			]] \
			[list cmd menu.game.close CloseGame "" {::menu::GameLoaded}] \
		]] \
		[list cascade Database "" [list \
			[list cascade DbSearch "" [list \
				[list cmd menu.db.search.plain SearchPlain "" {::menu::DbOpen}] \
				[list cmd menu.db.search.advanced SearchAdvanced "" {::menu::DbOpen}] \
				[list cmd menu.db.search.material SearchMaterial "" {::menu::DbOpen}] \
				[list cmd menu.db.search.rating SearchRating "" {::menu::DbOpen}] \
				[list cmd menu.db.search.duplicates SearchDuplicates "" {::menu::DbOpen}] \
				[list cmd menu.db.search.query SearchQuery "" {::menu::DbOpen}] \
			]] \
			[list cascade Reports "" [list \
				[list cmd menu.db.reports.eco ReportEco "" {::menu::DbOpen}] \
				[list cmd menu.db.reports.opening ReportOpening "" {::menu::DbOpen}] \
				[list cmd menu.db.reports.repertoire ReportRepertoire "" {::menu::DbOpen}] \
				[list cmd menu.db.reports.result ReportResult "" {::menu::DbOpen}] \
				[list cmd menu.db.reports.timecontrol ReportTimeControl "" {::menu::DbOpen} {::menu::ModulePresent event}] \
				[list cmd menu.db.reports.trends ReportTrends "" {::menu::DbOpen} {::menu::ModulePresent trend}] \
			]] \
			[list cascade Maintenance "" [list \
				[list cmd menu.db.maintenance.compact MaintCompact "" {::menu::DbOpen} {::menu::DbWritable}] \
				[list cmd menu.db.maintenance.strip_moves MaintStripMoves "" {expr {[::menu::DbOpen] && ![::menu::TrialMode]}} {::menu::DbWritable}] \
				[list cmd menu.db.maintenance.strip_tags MaintStripTags "" {expr {[::menu::DbOpen] && ![::menu::TrialMode]}} {::menu::DbWritable}] \
				[list cmd menu.db.maintenance.convert MaintConvert "" {::menu::DbOpen} {::menu::DbWritable}] \
				[list cmd menu.db.maintenance.recode MaintRecode "" {::menu::DbOpen} {::menu::DbWritable}] \
				[list cmd menu.db.maintenance.change_icon MaintChangeIcon "" {::menu::DbOpen} {::menu::DbWritable}] \
				[list cascade MaintRepertoireType "" dynamic] \
			]] \
			[list sep] \
			[list cmd menu.db.discover DiscoverDatabases] \
			[list cmd menu.db.properties Properties "" {::menu::DbOpen}] \
			[list cmd menu.db.readonly ReadOnly "" {::menu::DbOpen}] \
			[list sep] \
			[list cascade PlayerData "" [list \
				[list cmd menu.db.player.update UpdateRating "" {::menu::DbOpen} {::menu::DbWritable}] \
				[list cmd menu.db.player.names CheckNames "" {::menu::DbOpen}] \
			]] \
		]] \
		[list cascade Board "" [list \
			[list cascade StartPosition "" [list \
				[list cmd menu.board.start.standard StandardPosition "" {::menu::NormalVariant}] \
				[list cmd menu.board.start.chess960 Chess960Position] \
				[list cmd menu.board.start.symm960 Symm960Position] \
				[list cmd menu.board.start.shuffle ShufflePosition] \
				[list cmd menu.board.start.setup SetUpPosition] \
			]] \
			[list cmd menu.board.set_start_board SetStartBoard] \
			[list cmd menu.board.set_start_position SetStartPosition] \
			[list sep] \
			[list cmd board-flip FlipBoard "Ctrl+F"] \
			[list cmd board-null-move InsertNullMove "Ctrl+0"] \
			[list sep] \
			[list cmd menu.board.setup BoardSetup] \
			[list cascade Appearance "" [list \
				[list cmd menu.board.appearance.side AppSideToMove] \
				[list cmd menu.board.appearance.material AppMaterialValues] \
				[list cmd menu.board.appearance.border AppBorder] \
				[list cmd menu.board.appearance.coordinates AppCoordinates] \
				[list cmd menu.board.appearance.small_letters AppSmallLetters] \
				[list cmd menu.board.appearance.suggested AppSuggestedMove] \
				[list cmd menu.board.appearance.arrows AppVariationArrows] \
				[list cmd menu.board.appearance.annotation AppAnnotation] \
				[list cascade AppAnnotationTimeout "" dynamic] \
				[list cascade AppSlidingVariation "" dynamic] \
				[list cascade AppPromotedMark "" dynamic] \
			]] \
			[list sep] \
			[list cascade ShowTablebase "" [list \
				[list cmd menu.board.tablebase.show ShowTablebaseShow "" {::menu::ModulePresent tablebase}] \
				[list cmd menu.board.tablebase.online ShowTablebaseOnline "" {::menu::ModulePresent tablebase}] \
				[list cmd menu.board.tablebase.local ShowTablebaseLocal "" {::menu::ModulePresent tablebase}] \
			]] \
		]] \
		[list cascade Analysis "" [list \
			[list toggle menu.analysis.engine_toggle StartStopEngine "" ::menu::EngineLabel] \
			[list cmd menu.analysis.engines MenuEngines] \
			[list cmd menu.analysis.engine_dictionary EngineDictionary] \
			[list cmd menu.analysis.compare_engines CompareEngines] \
			[list cmd menu.analysis.review_engine ChooseReviewEngine "" {::menu::ModulePresent chooseengine}] \
			[list sep] \
			[list cmd menu.analysis.analyze AnalyzePosition "F4" {::menu::ModulePresent ai}] \
			[list cmd menu.analysis.game_review GameReview "" {::menu::ModulePresent review}] \
			[list cascade Explain "" [list \
				[list cmd menu.analysis.explain.position ExplainPosition "" {::menu::ModulePresent ai}] \
				[list cmd menu.analysis.explain.line ExplainLine "" {::menu::ModulePresent ai}] \
				[list cmd menu.analysis.explain.move ExplainMove] \
				[list cmd menu.analysis.explain.comment ExplainComment "" {::menu::ModulePresent ai}] \
			]] \
			[list cmd menu.analysis.factcheck FactCheckAnnotations "" {::menu::ModulePresent factcheck}] \
			[list sep] \
			[list cascade Tablebase "" [list \
				[list cmd menu.analysis.tablebase.show ShowTablebaseShow "" {::menu::ModulePresent tablebase}] \
				[list cmd menu.analysis.tablebase.online ShowTablebaseOnline "" {::menu::ModulePresent tablebase}] \
				[list cmd menu.analysis.tablebase.local ShowTablebaseLocal "" {::menu::ModulePresent tablebase}] \
			]] \
			[list cmd menu.analysis.explorer OpeningExplorer "" {::menu::ModulePresent explorer}] \
		]] \
		[list cascade Training "" [list \
			[list cmd menu.training.tactics TacticsTrainer] \
			[list cmd menu.training.endgame EndgameTrainer "" {::menu::ModulePresent endtrainer}] \
			[list cmd menu.training.guess GuessTheMove "Ctrl+G" {::menu::ModulePresent guessmove}] \
			[list cmd menu.training.repertoire TrainRepertoire "" {::menu::ModulePresent reptrainer}] \
			[list sep] \
			[list cmd menu.training.play_engine PlayAgainstEngine "" {::menu::ModulePresent playengine}] \
			[list cmd menu.training.engine_match EngineMatch "" {::menu::ModulePresent enginematch}] \
			[list sep] \
			[list cmd menu.training.studyplan StudyPlan "" {::menu::ModulePresent studyplan}] \
			[list cmd menu.training.brief OpponentBrief "" {::menu::ModulePresent brief}] \
			[list cmd menu.training.training_set TrainingSetFromGames "" {::menu::ModulePresent training}] \
			[list cmd menu.training.check_results CheckGameResults "" {::menu::ModulePresent quality}] \
		]] \
		[list cascade Tools "" [list \
			[list cmd menu.tools.book OpeningBookEditor] \
			[list sep] \
			[list cmd menu.tools.player_dictionary PlayerDictionary] \
			[list cmd menu.tools.player_card PlayerCard "" {::menu::ModulePresent playercard}] \
			[list sep] \
			[list cmd menu.tools.correspondence CorrespondenceGames] \
			[list cmd menu.tools.iccf ICCFSettings] \
			[list sep] \
			[list cmd menu.tools.engine_console EngineConsole] \
			[list cmd menu.tools.import_games ImportGames] \
			[list cmd menu.tools.download DownloadGames "" {::menu::ModulePresent download}] \
			[list sep] \
			[list cmd menu.tools.assistant Assistant "" {::menu::ModulePresent assistant}] \
			[list cmd menu.tools.choose_model ChooseModel "" {::menu::ModulePresent models}] \
			[list cmd menu.tools.voice VoiceAssistant "" {::menu::ModulePresent voice}] \
			[list sep] \
			[list cmd menu.tools.file_types MenuAssignFileTypes "" {::menu::ModulePresent filetypes}] \
			[list cmd menu.tools.legacy_fonts InstallLegacyFonts "" {::menu::ModulePresent legacyfonts}] \
		]] \
		[list cascade View "" [list \
			[list cascade Panes "" [list \
				[list dyn PaneBoard] \
				[list dyn PaneEditor] \
				[list dyn PaneGameList] \
				[list dyn PanePlayers] \
				[list dyn PaneEvents] \
				[list dyn PaneSites] \
				[list dyn PaneAnnotators] \
				[list dyn PanePositions] \
				[list dyn PaneTree] \
				[list dyn PaneAnalysis] \
				[list dyn PaneMedia] \
				[list dyn PaneReport] \
				[list dyn PaneAssistant] \
				[list dyn PaneExplorer] \
			]] \
			[list cascade Layout "" [list \
				[list cascade LoadLayout "" dynamic] \
				[list cmd menu.view.layout.save SaveLayout] \
				[list cmd menu.view.layout.save_as SaveLayoutAs] \
				[list cmd menu.view.layout.manage ManageLayouts] \
			]] \
			[list cascade Toolbars "" [list [list dyn PerToolbarCheckbuttons]]] \
			[list sep] \
			[list cascade Theme "" dynamic] \
			[list cascade Colors "" dynamic] \
			[list cascade IconSize "" dynamic] \
			[list cascade Language "" dynamic] \
			[list sep] \
			[list cmd menu.view.font_inc IncreaseFontSize "Ctrl+Shift++"] \
			[list cmd menu.view.font_dec DecreaseFontSize "Ctrl+Shift+−"] \
			[list sep] \
			[list cmd app-fullscreen Fullscreen "F11"] \
			[list cmd app-log MenuShowLog "Ctrl+L"] \
			[list cmd menu.view.tip MenuTipOfTheDay] \
		]] \
		[list cascade Help "" [list \
			[list cmd app-help Help "F1"] \
			[list sep] \
			[list cmd menu.help.bug ContactBugReport] \
			[list cmd menu.help.feature ContactFeatureRequest] \
			[list sep] \
			[list cmd menu.help.about MenuAboutChesswiz] \
		]] \
	]
	return
}

proc ::menu::Label {id} {
	# Focus-dependent Edit entries (PROPOSAL section 7.4): on the board the
	# Ctrl+A/Ctrl+C pair edits the annotation/comment, in a text widget it
	# selects/copies. With no focus the text meaning is the menu meaning, so
	# the built drop-down keeps its default labels.
	if {$id eq "app-select-all"} {
		if {[::menu::BoardFocus?]} { return $::application::pgn::mc::EditAnnotation }
		return [MC SelectAll]
	}
	if {$id eq "app-copy"} {
		if {[::menu::BoardFocus?]} { return $::application::pgn::mc::EditCommentAfter }
		return [MC EditCopy]
	}
	# Label of a registry action (used by the dump and the tests).
	if {[catch { set rec [::action::get $id] }]} { return $id }
	return [dict get $rec label]
}

# Is the focus in a board/notation pane (not in a text field)?
proc ::menu::BoardFocus? {} {
	set w [focus]
	if {$w eq ""} { return 0 }
	if {[::menu::TextWidget?]} { return 0 }
	return [string match .application.nb.board.* $w]
}

# The focused text widget, if any (editable or read-only: copy/select still work).
proc ::menu::TextWidget? {} {
	set w [focus]
	if {$w eq ""} { return 0 }
	return [expr {[winfo class $w] in {Text Entry TEntry TCombobox Spinbox TSpinbox}}]
}

proc ::menu::TextWidget {} {
	set w [focus]
	if {$w ne "" && [::menu::TextWidget?]} { return $w }
	return ""
}

# A menu accelerator in the drop-down's own spelling (Ctrl+Down, F10,
# Ctrl+Shift+G). It is formatted from the key spec the binding uses; the
# localised arrow glyphs of the key-editor table are not used here.
proc ::menu::FormatAccel {spec} {
	if {[llength [info commands ::application::keyEditor::NormalizeKeySpec]]} {
		set spec [::application::keyEditor::NormalizeKeySpec $spec]
	}
	set mods {}
	set key $spec
	if {[regexp {^(.*-)([^<>-]+)$} $spec -> modifiers keysym]} {
		set key $keysym
		foreach mod [split $modifiers -] {
			if {$mod eq ""} { continue }
			switch -- [string tolower $mod] {
				control { lappend mods Ctrl }
				shift	 { lappend mods Shift }
				alt		 { lappend mods Alt }
				default { lappend mods [string totitle $mod] }
			}
		}
	}
	if {[string length $key] == 1 && [string is alpha $key]} {
		set key [string toupper $key]
	}
	if {[llength $mods] == 0} { return $key }
	return "[join $mods +]+$key"
}

proc ::menu::Accel {id} {
	# The menu shows the key the binding uses, so a user override moves the
	# accelerator with it (VAL-REG-003). Actions outside the key-editor table
	# keep the key registered with their drop-down row.
	if {[llength [info commands ::application::keyEditor::CurrentKey]]} {
		if {[catch { set key [::application::keyEditor::CurrentKey $id] }]} { set key "" }
		if {$key ne ""} { return [::menu::FormatAccel $key] }
	}
	if {[catch { set rec [::action::get $id] }]} { return "" }
	set keys [dict get $rec keys]
	if {[llength $keys] >= 2} { return [lindex $keys 1] }
	return ""
}

# Accelerator of a cascade row (New Database / New Game). New Game reads
# the key-editor binding; New Database is shown only while its binding
# exists, so the advertised key is a real one.
proc ::menu::CascadeAccel {labelName {fallback ""}} {
	switch -- $labelName {
		NewGame {
			set accel [::menu::Accel game-new]
			if {$accel ne ""} { return $accel }
		}
		NewDatabase {
			foreach spec {Control-Shift-n Control-Shift-N} {
				if {[bind .application <$spec>] ne ""} {
					return [::menu::FormatAccel $spec]
				}
			}
		}
	}
	return $fallback
}

# A posted drop-down keeps the accelerators of the bindings that were in
# effect when it was filled. A rebind (or a scheme switch) calls this to
# move the rows to the new keys without rebuilding the posted menu.
proc ::menu::RefreshAccelerators {} {
	variable DropdownWidget

	if {$DropdownWidget eq "" || ![winfo exists $DropdownWidget]} { return }
	::menu::UpdateAccelerators $DropdownWidget
}

proc ::menu::UpdateAccelerators {menu} {
	set n [$menu index end]
	if {$n eq "" || $n eq "none"} { return }
	for {set i 0} {$i <= $n} {incr i} {
		set type [$menu type $i]
		if {$type eq "cascade"} {
			set sub ""
			catch { set sub [$menu entrycget $i -menu] }
			if {$sub ne "" && [winfo exists $sub]} {
				::menu::UpdateAccelerators $sub
			}
			set label ""
			catch { set label [NormLabel [$menu entrycget $i -label]] }
			if {$label ne ""} {
				set accel ""
				if {$label eq [NormLabel [MC NewDatabase]]} {
					set accel [::menu::CascadeAccel NewDatabase ""]
				} elseif {$label eq [NormLabel [MC NewGame]]} {
					set accel [::menu::CascadeAccel NewGame ""]
				}
				if {$accel ne ""} {
					catch { $menu entryconfigure $i -accelerator $accel }
				}
			}
		} elseif {$type in {command checkbutton radiobutton}} {
			set cmd ""
			catch { set cmd [$menu entrycget $i -command] }
			if {[regexp {::action::run (\S+)$} $cmd -> id]} {
				catch { $menu entryconfigure $i -accelerator [::menu::Accel $id] }
			}
		}
	}
}

# ----------------------------------------------------------------------
# Registration. Every command row becomes one registry action.
# ----------------------------------------------------------------------
proc ::menu::Register {id label {accel ""} {visible ""} {enabled ""} {order ""}} {
	variable DropdownOrder

	if {[dict exists $::action::Registry $id]} {
		# Already registered (assistant tool or context action): keep its
		# handler, but refresh the drop-down placement and the label so a
		# language switch relabels the menu (VAL-BAR-007).
		set rec [::action::get $id]
		dict set rec menu $order
		dict set rec dropdown $order
		if {$label ne ""} { dict set rec label $label }
		if {$accel ne ""} { dict set rec keys [list {} $accel] }
		if {$visible ne ""} { dict set rec visible $visible }
		if {$enabled ne ""} { dict set rec enabled $enabled }
		dict set ::action::Registry $id $rec
		return
	}
	::action::register $id [dict create \
		label    $label \
		object   {} \
		args     {} \
		handler  [list ::menu::Invoke $id] \
		what     $label \
		ai       0 \
		keys     [list {} $accel] \
		menu     $order \
		dropdown $order \
		doc      $label \
		visible  $visible \
		enabled  $enabled \
	]
}

proc ::menu::RegisterTree {} {
	variable DropdownTree
	set n 0
	foreach top $DropdownTree {
		incr n
		set topName [lindex $top 1]
		if {[lindex $top 0] ne "cascade"} { continue }
		set children [lindex $top 3]
		set i 0
		foreach node $children {
			incr i
			RegisterNodes $node [format "%02d.%03d" $n $i] $topName
		}
	}
}

proc ::menu::RegisterNodes {node order top} {
	variable DropdownCounter

	set kind [lindex $node 0]
	switch -- $kind {
		cmd {
			set id [lindex $node 1]
			set labelName [lindex $node 2]
			set accel [lindex $node 3]
			set visible [lindex $node 4]
			set enabled [lindex $node 5]
			Register $id [MC $labelName] $accel $visible $enabled $order
		}
		toggle {
			set id [lindex $node 1]
			set labelName [lindex $node 2]
			set accel [lindex $node 3]
			Register $id [MC $labelName] $accel "" ""
		}
		cascade {
			set children [lindex $node 3]
			if {$children ne "dynamic"} {
				set i 0
				foreach child $children {
					incr i
					RegisterNodes $child "${order}.$i" $top
				}
			}
		}
	}
	return
}

# ----------------------------------------------------------------------
# State. One mechanism for drop-down and context menus (R1-R16).
# ----------------------------------------------------------------------
proc ::menu::state {id {object {}}} {
	set visible 1
	set enabled 1

	if {[catch { set rec [::action::get $id] }]} {
		set rec ""
	}
	if {$rec ne ""} {
		set vp [dict get $rec visible]
		if {$vp ne ""} {
			if {[catch { uplevel #0 $vp } answer]} { set answer 1 }
			set visible [expr {$answer ? 1 : 0}]
		}
		set ep [dict get $rec enabled]
		if {$ep ne ""} {
			if {[catch { uplevel #0 $ep } answer]} { set answer 1 }
			set enabled [expr {$answer ? 1 : 0}]
		}

		# Context-only actions exist only while their object does. With no
		# explicit object (the Ask list, a direct ::menu::state call), use
		# the current object the matching context menu would receive.
		if {[llength [dict get $rec context]] && [dict get $rec dropdown] eq ""} {
			if {![dict size $object] \
			 && [llength [info commands ::context::CurrentObjectFor]]} {
				set current [::context::CurrentObjectFor $id]
				if {[llength $current]} {
					set object [lindex $current 1]
				} else {
					set visible 0
				}
			}
		}
	}

	# Object-scoped rules (R10): strip/truncate/comment rows follow the
	# move the menu or the Ask list is acting on.
	if {[llength [info commands ::context::ObjectRule]]} {
		set rule [::context::ObjectRule $id $object]
		if {[llength $rule]} {
			set visible [expr {$visible && [lindex $rule 0] ? 1 : 0}]
			set enabled [expr {$enabled && [lindex $rule 1] ? 1 : 0}]
		}
	}

	# Context predicates live in ::context (they call helpers there).
	if {[info exists ::context::Predicates] && [dict exists $::context::Predicates $id]} {
		set pred [dict get $::context::Predicates $id]
		if {[dict exists $pred visible]} {
			if {[catch { namespace eval ::context [list expr [dict get $pred visible]] } answer]} {
				set answer 1
			}
			set visible [expr {$visible && $answer ? 1 : 0}]
		}
		if {[dict exists $pred enabled]} {
			if {[catch { namespace eval ::context [list expr [dict get $pred enabled]] } answer]} {
				set answer 1
			}
			set enabled [expr {$enabled && $answer ? 1 : 0}]
		}
	}

	# R16: whole cascades greyed (never hidden) on the other tab.
	set top [::menu::TopOf $id]
	if {$top eq "Board" && [::menu::OnDatabaseTab]} { set enabled 0 }
	if {$top eq "Database" && [::menu::BoardOnlyLayout]} { set enabled 0 }

	return [dict create visible $visible enabled $enabled]
}

proc ::menu::TopOf {id} {
	if {[catch { set rec [::action::get $id] }]} { return "" }
	set order [dict get $rec dropdown]
	if {$order eq ""} { return "" }
	switch -- [lindex [split $order .] 0] {
		01 { return "File" }
		02 { return "Edit" }
		03 { return "Game" }
		04 { return "Database" }
		05 { return "Board" }
		06 { return "Analysis" }
		07 { return "Training" }
		08 { return "Tools" }
		09 { return "View" }
		10 { return "Help" }
	}
	return ""
}

proc ::menu::OnDatabaseTab {} {
	if {[catch { ::application::activeTab } tab]} { return 0 }
	return [expr {$tab eq "database"}]
}

proc ::menu::BoardOnlyLayout {} {
	if {[catch { ::application::activeTab } tab]} { return 0 }
	if {$tab ne "board"} { return 0 }
	if {[catch { ::application::twm } twm]} { return 0 }
	if {$twm eq ""} { return 0 }
	set name ""
	catch { set name [::application::twm::currentLayoutName $twm] }
	return [expr {[string match -nocase {*board*} $name] ? 1 : 0}]
}

# R1-R16 predicates used by the tree and by context menus.
proc ::menu::GameLoaded {} {
	if {[catch { ::application::pgn::empty? } empty]} { return 0 }
	return [expr {!$empty}]
}
proc ::menu::TrialMode {} {
	if {[catch { ::game::trialMode? } t]} { return 0 }
	return [expr {$t ? 1 : 0}]
}
proc ::menu::DbOpen {} {
	set base ""
	catch { set base [::scidb::db::get name] }
	if {$base eq ""} { return 0 }
	if {$base eq $::scidb::clipbaseName} { return 0 }
	return 1
}
proc ::menu::DbWritable {} {
	set base ""
	catch { set base [::scidb::db::get name] }
	if {$base eq ""} { return 0 }
	if {[catch { ::scidb::db::get readonly? $base } ro]} { return 1 }
	return [expr {!$ro}]
}
proc ::menu::EngineRunning {} {
	if {[catch { ::engine::id } id]} { return 0 }
	return [expr {$id >= 0 ? 1 : 0}]
}
proc ::menu::GameOver {} {
	if {[catch { ::scidb::game::query over } over]} { return 0 }
	return [expr {$over ? 1 : 0}]
}
proc ::menu::NormalVariant {} {
	set v Normal
	catch { set v [::scidb::db::get variant?] }
	return [expr {$v eq "Normal" ? 1 : 0}]
}
proc ::menu::ModulePresent {module} {
	return [::capability::present $module]
}
proc ::menu::BoardSetupOpen {} {
	set open 0
	catch { set open [::board::options::isOpen] }
	return [expr {$open ? 1 : 0}]
}
proc ::menu::PaneFloating {uid} {
	return 0
}
proc ::menu::NoHtmlReport {} {
	return 0
}
proc ::menu::Sortable {} {
	if {[catch { set v $::gamestable::Vars(sortable) }]} { return 1 }
	return [expr {$v ? 1 : 0}]
}
proc ::menu::EngineLabel {} {
	if {[EngineRunning]} { return [MC StartStopEngine] }
	return [MC StartStopEngine]
}

# ----------------------------------------------------------------------
# Build / lazy fill.
# ----------------------------------------------------------------------
proc ::menu::WidgetName {name} {
	return [string tolower [string map {" " "" "…" "" "&" ""} $name]]
}

# Tk menus spell mnemonics with "&"; the visible text drops it and the
# character after it is underlined (the same convention as the old bar).
proc ::menu::AmpText {text} {
	lassign [::tk::UnderlineAmpersand $text] plain ul
	return [list " $plain" [expr {$ul < 0 ? -1 : $ul + 1}]]
}

proc ::menu::BuildDropdown {menu} {
	variable DropdownTree
	variable DropdownFilled
	variable DropdownWidget

	if {[llength $DropdownTree] == 0} {
		DefineTree
		RegisterTree
		RegisterExtras
	}
	set DropdownFilled [dict create]
	catch { $menu delete 0 end }
	foreach top $DropdownTree {
		if {[lindex $top 0] ne "cascade"} { continue }
		set labelName [lindex $top 1]
		set accel [::menu::CascadeAccel $labelName [lindex $top 2]]
		set sub $menu.[WidgetName [MC $labelName]]
		catch { destroy $sub }
		menu $sub -tearoff 0
		$sub configure -postcommand [list ::menu::FillTop $labelName $sub]
		lassign [AmpText [MC $labelName]] text ul
		$menu add cascade -label $text -underline $ul -menu $sub -accelerator $accel
	}
	set DropdownWidget $menu
	return $menu
}

proc ::menu::ClearMenu {menu} {
	if {![winfo exists $menu]} { return }
	catch { $menu delete 0 end }
}

proc ::menu::FillTop {labelName menu} {
	variable DropdownTree
	variable DropdownFilled
	variable DropdownForceAll

	if {![info exists DropdownForceAll]} { set DropdownForceAll 0 }
	if {!$DropdownForceAll && [dict exists $DropdownFilled $labelName]} { return }
	dict set DropdownFilled $labelName 1

	set children {}
	foreach top $DropdownTree {
		if {[lindex $top 1] eq $labelName} { set children [lindex $top 3]; break }
	}
	if {![llength $children]} { return }
	ClearMenu $menu
	FillNodes $children $menu 0
}

proc ::menu::FillNodes {nodes menu level} {
	variable DropdownCounter
	variable DropdownForceAll

	if {![info exists DropdownForceAll]} { set DropdownForceAll 0 }
	set lastSep 1
	foreach node $nodes {
		set kind [lindex $node 0]
		switch -- $kind {
			sep {
				if {!$lastSep} { $menu add separator; set lastSep 1 }
				continue
			}
			cmd {
				set id [lindex $node 1]
				# skip hidden entries, but never in dump mode
				if {!$DropdownForceAll} {
					set st [state $id]
					if {![dict get $st visible]} { continue }
				}
				set accel [Accel $id]
				lassign [AmpText [Label $id]] text ul
				set opts [list -label $text -underline $ul]
				if {$accel ne ""} { lappend opts -accelerator $accel }
				if {!$DropdownForceAll} {
					lappend opts -state [expr {[dict get $st enabled] ? "normal" : "disabled"}]
				}
				lappend opts -command [list ::action::run $id]
				eval [list $menu add command] $opts
				set lastSep 0
			}
			toggle {
				set id [lindex $node 1]
				set label [uplevel #0 [lindex $node 4]]
				lassign [AmpText $label] text ul
				set opts [list -label $text -underline $ul -command [list ::action::run $id]]
				set accel [lindex $node 3]
				if {$accel ne ""} { lappend opts -accelerator $accel }
				eval [list $menu add command] $opts
				set lastSep 0
			}
			cascade {
				set labelName [lindex $node 1]
				set accel [::menu::CascadeAccel $labelName [lindex $node 2]]
				set children [lindex $node 3]
				# A static cascade whose rows are all hidden (module absent,
				# no database, ...) would be a dead entry: drop it.
				if {!$DropdownForceAll && $children ne "dynamic"} {
					set any 0
					foreach child $children {
						set ck [lindex $child 0]
						if {$ck eq "sep"} { continue }
						if {$ck eq "cmd"} {
							if {[dict get [state [lindex $child 1]] visible]} { set any 1; break }
						} else {
							set any 1; break
						}
					}
					if {!$any} { continue }
				}
				set sub $menu.__dd[incr DropdownCounter]
				catch { destroy $sub }
				menu $sub -tearoff 0
				if {$children eq "dynamic"} {
					$sub configure -postcommand [list ::menu::FillDynamic $labelName $sub]
				} else {
					$sub configure -postcommand [list ::menu::FillStatic $children $sub]
				}
				lassign [AmpText [MC $labelName]] text ul
				set opts [list -label $text -underline $ul -menu $sub]
				if {$accel ne ""} { lappend opts -accelerator $accel }
				eval [list $menu add cascade] $opts
				set lastSep 0
			}
			dyn {
				set labelName [lindex $node 1]
				set id [::menu::DynId $labelName]
				lassign [AmpText [MC $labelName]] text ul
				set opts [list -label $text -underline $ul]
				if {$id ne ""} {
					if {!$DropdownForceAll && ![dict get [state $id] visible]} { continue }
					lappend opts -command [list ::action::run $id]
					if {!$DropdownForceAll} {
						set st [state $id]
						lappend opts -state [expr {[dict get $st enabled] ? "normal" : "disabled"}]
					}
				} else {
					lappend opts -state disabled
				}
				eval [list $menu add command] $opts
				set lastSep 0
			}
		}
	}
}

proc ::menu::FillStatic {nodes menu} {
	variable DropdownForceAll
	if {![info exists DropdownForceAll]} { set DropdownForceAll 0 }
	ClearMenu $menu
	FillNodes $nodes $menu 1
}

proc ::menu::DynId {labelName} {
	switch -- $labelName {
		PasteClipbase { return menu.game.paste_clip }
		PasteGameTab { return menu.game.paste_tab }
		MergeClipbase { return menu.game.merge_clip }
		MergeGameTab { return menu.game.merge_tab }
		PaneBoard { return menu.view.panes.board }
		PaneEditor { return menu.view.panes.editor }
		PaneGameList { return menu.view.panes.games }
		PanePlayers { return menu.view.panes.players }
		PaneEvents { return menu.view.panes.events }
		PaneSites { return menu.view.panes.sites }
		PaneAnnotators { return menu.view.panes.annotators }
		PanePositions { return menu.view.panes.positions }
		PaneTree { return menu.view.panes.tree }
		PaneAnalysis { return menu.view.panes.analysis }
		PaneMedia { return menu.view.panes.media }
		PaneReport { return menu.view.panes.report }
		PaneAssistant { return menu.view.panes.assistant }
		PaneExplorer { return menu.view.panes.explorer }
		RecentGames { return menu.game.history.recent }
	}
	return ""
}

proc ::menu::FillDynamic {labelName menu} {
	ClearMenu $menu
	switch -- $labelName {
		OpenRecent {
			if {[llength [info commands ::application::database::addRecentlyUsedToMenu]]} {
				::application::database::addRecentlyUsedToMenu .application $menu
			}
		}
		NewGame - AddToRepertoire - AddLineToRepertoire {
			# variant / repertoire destinations are generated from data
		}
		MaintRepertoireType {
			# generated from the open database's repertoire types
		}
		AppAnnotationTimeout - AppSlidingVariation - AppPromotedMark {
			# board appearance submenus are generated from board options
		}
		Panes {
			FillPanes $menu
		}
		Toolbars {
			foreach parent [::toolbar::activeParents] {
				catch { ::toolbar::addToolbarMenu $menu $parent none }
			}
		}
		Theme {
			FillTheme $menu
		}
		Colors {
			FillColors $menu
		}
		IconSize {
			FillIconSize $menu
		}
		Language {
			FillLanguage $menu
		}
		LoadLayout {
			set twm [CurrentTWM]
			if {$twm ne ""} {
				catch { ::application::twm::makeLayoutMenu $twm $menu }
			}
		}
		RecentGames {
			FillRecentGames $menu
		}
	}
	return
}

proc ::menu::FillPanes {menu} {
	if {[catch { ::application::twm } twm]} { return }
	if {$twm eq ""} { return }
	set names [array names ::application::Pane]
	foreach name [lsort $names] {
		catch {
			lassign [AmpText [set ::application::Pane($name)]] text ul
			$menu add command -label $text -underline $ul \
				-command [list ::menu::TogglePane $twm $name]
		}
	}
}

proc ::menu::TogglePane {twm uid} {
	# Pane headers own visibility; the View cascade offers the same names.
	if {[llength [info commands ::context::Post]]} {
		set frame ""
		catch { set frame [$twm pane $uid] }
		if {$frame ne ""} {
			catch { ::application::twm::ChangeState $twm $uid }
		}
	}
}

proc ::menu::FillTheme {menu} {
	set theme [::theme::currentTheme]
	set styles [lsort -dictionary [ttk::style theme names]]
	set i [lsearch -exact $styles default]
	if {$i >= 0} { set styles [linsert [lreplace $styles $i $i] 0 default] }
	foreach style $styles {
		if {$style eq "classic"} { continue }
		lassign [AmpText $style] text ul
		$menu add radiobutton -label $text -underline $ul \
			-variable ::menu::Theme -value $style \
			-command [list ::theme::setTheme $style]
		::theme::configureRadioEntry $menu
	}
}

proc ::menu::FillColors {menu} {
	lassign [AmpText [set ::menu::mc::OrdinaryMonitor]] text ul
	$menu add radiobutton -label $text -underline $ul \
		-variable ::colors::Scheme -value dark
	::theme::configureRadioEntry $menu
	lassign [AmpText [set ::menu::mc::HighQualityMonitor]] text ul
	$menu add radiobutton -label $text -underline $ul \
		-variable ::colors::Scheme -value lite
	::theme::configureRadioEntry $menu
}

proc ::menu::FillIconSize {menu} {
	foreach size $::toolbar::iconSizes {
		set var ::toolbar::mc::[string toupper $size 0 0]
		lassign [AmpText [set $var]] text ul
		$menu add radiobutton -label $text -underline $ul \
			-variable ::toolbar::Options(icons:size) -value $size
		::theme::configureRadioEntry $menu
	}
}

proc ::menu::FillLanguage {menu} {
	foreach lang [lsort [array names ::mc::input]] {
		if {![string length $lang]} { continue }
		catch {
			set flag $::country::icon::flag([set ::mc::langToCountry([set ::mc::lang$lang])])
			lassign [AmpText $lang] text ul
			$menu add command -label $text -underline $ul -image $flag -compound left \
				-command [list ::menu::SwitchLanguage $lang]
		}
	}
}

# Relabel the live drop-down after a language switch (VAL-BAR-007). The
# registry labels are refreshed from the newly loaded mc strings, then the
# menu widget is rebuilt so the top cascades and their leaves show them.
proc ::menu::SwitchLanguage {lang} {
	if {[catch { ::mc::setLang $lang }]} { return }
	::menu::RegisterTree
	::menu::RegisterExtras
	set menu ""
	catch {
		if {[winfo exists $::application::Vars(menu:entries)]} {
			set menu $::application::Vars(menu:entries)
		}
	}
	if {$menu ne ""} {
		::menu::BuildDropdown $menu
		if {[llength [info commands ::application::UpdateSettingsText]]} {
			catch { ::application::UpdateSettingsText .application.nb.menu_main }
		}
	}
	return $lang
}

proc ::menu::FillRecentGames {menu} {
	if {[catch { ::game::gameList } games]} { return }
	foreach entry $games {
		lassign $entry position
		if {$position eq ""} { continue }
		set tags ""
		catch { set tags [::scidb::game::getTags $position] }
		set label ""
		catch { set label [string trim [::gamebar::getText $::application::pgn::Vars(gamebar) $position]] }
		if {$label eq ""} { set label "game [incr ::menu::DropdownCounter]" }
		lassign [AmpText $label] text ul
		$menu add command -label $text -underline $ul \
			-command [list ::scidb::game::switch $position]
	}
}

# ----------------------------------------------------------------------
# Dump: the built drop-down, in tests/fixtures/menubar-expected.txt form.
# Dynamic cascades print as an ENTRY with a trailing marker and are not
# descended (their rows are the frozen dynamic exemptions).
# ----------------------------------------------------------------------
proc ::menu::NormLabel {text} {
	set text [string trim $text]
	set text [string map {& {}} $text]
	regsub {\.\.\.$} $text "\u2026" text
	return $text
}

proc ::menu::Dump {menu} {
	variable DropdownTree
	variable DropdownForceAll

	if {![info exists DropdownForceAll]} { set DropdownForceAll 0 }
	set old $DropdownForceAll
	set DropdownForceAll 1
	if {[llength $DropdownTree] == 0} { DefineTree; RegisterTree; RegisterExtras }
	catch { $menu delete 0 end }
	foreach top $DropdownTree {
		set labelName [lindex $top 1]
		set sub $menu.[WidgetName [MC $labelName]]
		catch { destroy $sub }
		menu $sub -tearoff 0
		$sub configure -postcommand [list ::menu::FillTop $labelName $sub]
		lassign [AmpText [MC $labelName]] text ul
		$menu add cascade -label $text -underline $ul -menu $sub -accelerator [::menu::CascadeAccel $labelName [lindex $top 2]]
		::menu::FillTop $labelName $sub
	}
	# Keep dump mode on while the submenus are rendered: DumpNodes fills
	# nested static cascades, and hidden rows must still be printed.
	set out [::menu::DumpMenu $menu $DropdownTree 0 1]
	set DropdownForceAll $old
	return [join $out \n]
}

proc ::menu::DumpMenu {menu tree level isRoot} {
	set out {}
	set n [$menu index end]
	if {$n eq ""} { return $out }
	if {$level == 0} {
		foreach top $tree {
			if {[lindex $top 0] ne "cascade"} { continue }
			lappend out "MENU [NormLabel [MC [lindex $top 1]]]"
			set sub $menu.[WidgetName [MC [lindex $top 1]]]
			set children [lindex $top 3]
			set out [concat $out [DumpNodes $sub $children 2 1]]
			lappend out ""
		}
		if {[llength $out]} { set out [lrange $out 0 end-1] }
		return $out
	}
	return $out
}

proc ::menu::DumpNodes {menu nodes indent topLevel} {
	set out {}
	set index -1
	set lastSep 1
	foreach node $nodes {
		set kind [lindex $node 0]
		switch -- $kind {
			sep {
				if {!$lastSep} { incr index; set lastSep 1 }
				lappend out "[string repeat " " $indent]SEP"
				continue
			}
			cmd - toggle {
				incr index
				set lastSep 0
				if {$index > [$menu index end]} { continue }
				set label [NormLabel [$menu entrycget $index -label]]
				set accel ""
				catch { set accel [$menu entrycget $index -accelerator] }
				lappend out "[string repeat " " $indent]ENTRY $label[expr {$accel ne "" ? " $accel" : ""}]"
			}
			dyn {
				incr index
				set lastSep 0
				if {$index > [$menu index end]} { continue }
				set label [NormLabel [$menu entrycget $index -label]]
				lappend out "[string repeat " " $indent]ENTRY $label"
			}
			cascade {
				incr index
				set lastSep 0
				if {$index > [$menu index end]} { continue }
				set label [NormLabel [$menu entrycget $index -label]]
				set accel ""
				catch { set accel [$menu entrycget $index -accelerator] }
				lappend out "[string repeat " " $indent]ENTRY $label \u25b8[expr {$accel ne "" ? " $accel" : ""}]"
				set children [lindex $node 3]
				if {$children ne "dynamic"} {
					set sub [$menu entrycget $index -menu]
					::menu::FillStatic $children $sub
					lappend out "[string repeat " " [expr {$indent + 2}]]SUBMENU $label"
					lappend out {*}[DumpNodes $sub $children [expr {$indent + 4}] 0]
				}
			}
		}
	}
	return $out
}

# ----------------------------------------------------------------------
# Extra registry actions that are reached from pane headers / tests but
# not from a drop-down row. Keeping them here means the key editor ids
# and the old widget paths resolve to real actions.
# ----------------------------------------------------------------------
proc ::menu::RegisterExtras {} {
	Register view.pane_zoom "Maximise / Restore Pane" "Ctrl+Shift+Z" "" "" "00.001"
	Register view.focus_zoom "Focus follows size" "" "" "" "00.002"
	Register view.focus_ratio "Zoom ratio" "" "" "" "00.003"
	Register view.focus_pin "Pin board size" "" "" "" "00.004"
	# The former Extras 3D entries: PROPOSAL section 5 places them in the
	# board pane header / View > Panes. They stay registry actions so the
	# assistant and the palette can reach them when the module is present.
	Register view.board3d.open [MC Open3DBoard] "" {::capability::present board3d} "" "09.910"
	Register view.board3d.webgl [MC OpenWebGL3DBoard] "" {::capability::present webgl3d} "" "09.911"
	Register view.board3d.embed [MC Embed3DBoard] "" {::capability::present embed3d} "" "09.912"
	foreach pair {
		board board editor editor games "game list" players players
		events events sites sites annotators annotators positions positions
		tree tree analysis analysis media media report report
		assistant assistant explorer explorer
	} {
		set uid [lindex $pair 0]
		set label [lindex $pair 1]
		Register menu.view.panes.$uid $label "" "" "" "09.900"
	}
}

# ----------------------------------------------------------------------
# Handlers. One dispatcher; every command row is ::action::run <id>.
# ----------------------------------------------------------------------
proc ::menu::CurrentBase {} {
	set base ""
	catch { set base [::scidb::db::get name] }
	return $base
}

# The layout (twm) of the notebook page the user is looking at, or "" when
# that page has none. The main drop-down is global: it can be posted on the
# Information page, which owns no panes, so the View > Layout cascade is
# filled with nothing there. ::application::twm reports that case by raising
# "no twm selected" -- a menu is not the place to report it, and the error
# used to escape from the cascade's -postcommand while the menu was posted,
# which aborted the cascade and made bgerror drop the menu's grab (the main
# menu then posted and unposted erratically). Ask under catch, like
# CurrentBase and the callers in application.tcl and media-inset.tcl do, and
# let every caller decide what "no layout here" means.
proc ::menu::CurrentTWM {} {
	if {[llength [info commands ::application::twm]] == 0} { return "" }
	if {[catch { set twm [::application::twm] }]} { return "" }
	return $twm
}

proc ::menu::CurrentVariant {} {
	set variant Normal
	catch { set variant [::scidb::db::get variant?] }
	return $variant
}

proc ::menu::FocusText {} {
	set w [focus]
	if {$w eq ""} { return "" }
	if {[catch { $w edit undo }]} { return "" }
	return $w
}

proc ::menu::Invoke {id {argsDict {}}} {
	if {[catch { ::menu::Do $id } result]} {
		if {[llength [info commands ::log::error]]} {
			catch { ::log::error menu "$id: $result" }
		}
		return "error: $result"
	}
	return $result
}

proc ::menu::Do {id} {
	switch -- $id {
		menu.file.new.normal { return [::menu::dbNew .application Normal] }
		menu.file.new.three { return [::menu::dbNew .application ThreeCheck] }
		menu.file.new.crazy { return [::menu::dbNew .application Crazyhouse] }
		menu.file.new.variants { return [::menu::dbNew .application Normal] }
		menu.file.open { return [::menu::dbOpen .application] }
		menu.file.close { return [::menu::dbClose .application] }
		menu.file.save { return [::application::database::SaveChanges .application] }
		menu.file.import.pgn { return [::menu::dbImport .application [CurrentBase] pgn] }
		menu.file.import.db { return [::menu::dbImport .application [CurrentBase] db] }
		menu.file.export.pgn {
			return [::export::open .application -base [CurrentBase] -variant [CurrentVariant] -extension pgn]
		}
		menu.file.export.html {
			return [::export::open .application -base [CurrentBase] -variant [CurrentVariant] -extension html]
		}
		menu.file.export.archive { return [::menu::dbCreateArchive .application [CurrentBase]] }
		menu.file.archive_create { return [::menu::dbCreateArchive .application [CurrentBase]] }

		app-quit { return [::application::shutdown] }
		app-undo {
			set w [FocusText]
			if {$w ne ""} { catch { $w edit undo } } else { catch { ::application::pgn::Undo undo } }
			return
		}
		app-redo {
			set w [FocusText]
			if {$w ne ""} { catch { $w edit redo } } else { catch { ::application::pgn::Undo redo } }
			return
		}
		app-cut {
			set w [FocusText]
			if {$w ne ""} { catch { ::tk_textCut $w } }
			return
		}
		app-copy {
			# focus-dependent, like the menu label: text copies, the board
			# edits the comment after the move (PROPOSAL section 7.4)
			if {[::menu::TextWidget?]} {
				catch { ::tk_textCopy [focus] }
			} else {
				catch { ::application::pgn::editComment after }
			}
			return
		}
		app-paste {
			set w [FocusText]
			if {$w ne ""} { catch { ::tk_textPaste $w } }
			return
		}
		app-select-all {
			if {[::menu::TextWidget?]} {
				catch { [focus] tag add sel 1.0 end }
			} else {
				catch { ::application::pgn::editAnnotation }
			}
			return
		}
		app-find { return [::application::keyEditor::Find [focus]] }
		menu.edit.keyboard { return [::application::ShortcutPreferences .application] }
		menu.edit.preferences.engines { return [::engine::openAdmininstration .application] }
		menu.edit.preferences.pgn { return [::menu::setupPgnOptions .application] }
		menu.edit.preferences.player { return [::playercard::setupPrivateCard .application] }

		game.new.normal { return [::menu::gameNew .application Normal] }
		game.new.three { return [::menu::gameNew .application ThreeCheck] }
		game.new.crazy { return [::menu::gameNew .application Crazyhouse] }
		game.new.variants { return [::menu::gameNew .application Normal] }
		menu.game.load_number { return [::gamebar::LoadGameNumber .application] }
		game-next { return [::application::board::LoadGame(any) .application next] }
		game-prev { return [::application::board::LoadGame(any) .application prev] }
		game-first { return [::application::board::LoadGame(any) .application first] }
		game-last { return [::application::board::LoadGame(any) .application last] }
		menu.game.random { return [::application::board::LoadGame(any) .application random] }
		game-replace { return [::application::board::SaveGame replace] }
		game-replace-moves { return [::application::pgn::saveGame replace] }
		game-save { return [::application::board::SaveGame add] }
		menu.game.reload { return [::gamebar::ReloadCurrentGame .application] }
		menu.game.copy {
			catch { ::gamebar::CopyGame .application [::gamebar::selected $::application::pgn::Vars(gamebar)] }
			return
		}
		menu.game.paste_clip { catch { ::application::pgn::PasteClipboardGame }; return }
		menu.game.paste_tab { catch { ::gamebar::PasteClipboardContent .application }; return }
		menu.game.merge_clip { catch { ::gamebar::mergeGame .application -1 }; return }
		menu.game.merge_tab { catch { ::gamebar::mergeGame .application -1 }; return }
		game-export { return [::gamebar::exportGame .application] }
		menu.game.history.recent {
			if {[catch { ::game::gameList } games] || ![llength $games]} { return }
			catch { ::scidb::game::switch [lindex [lindex $games 0] 0] }
			return
		}
		menu.game.history.clear { return [::application::database::ClearHistory] }
		menu.game.close { return [::gamebar::CloseTab .application [::gamebar::selected $::application::pgn::Vars(gamebar)]] }

		menu.db.search.plain { return [::application::database::OpenPlainSearch .application [CurrentBase] [CurrentVariant]] }
		menu.db.search.advanced { return [::application::database::searchCurrent .application] }
		menu.db.search.material { return [::application::database::searchCurrent .application] }
		menu.db.search.rating { return [::application::database::searchCurrent .application] }
		menu.db.search.duplicates { return [::application::database::searchCurrent .application] }
		menu.db.search.query { return [::application::database::OpenCql6Search .application [CurrentBase] [CurrentVariant]] }
		menu.db.reports.eco { return [::application::database::searchCurrent .application] }
		menu.db.reports.opening { return [::application::database::searchCurrent .application] }
		menu.db.reports.repertoire { return [::application::database::searchCurrent .application] }
		menu.db.reports.result { return [::application::assistant::runTool check_game_results {}] }
		menu.db.reports.timecontrol { return [::application::assistant::runTool time_controls {}] }
		menu.db.reports.trends { return [::application::assistant::runTool database_trends {}] }
		menu.db.maintenance.compact { return [::application::assistant::runTool compact_database {}] }
		menu.db.maintenance.strip_moves { catch { ::scidb::game::strip moves }; return }
		menu.db.maintenance.strip_tags { catch { ::scidb::game::strip tags }; return }
		menu.db.maintenance.convert { return [::application::assistant::runTool convert_database {}] }
		menu.db.maintenance.recode { return [::application::assistant::runTool recode_database {}] }
		menu.db.maintenance.change_icon { catch { ::menu::DbProperties }; return }
		menu.db.discover { return [::application::database::discover::open .application] }
		menu.db.properties { return [::menu::DbProperties] }
		menu.db.readonly { catch { ::application::database::ToggleReadOnly 0 [CurrentBase] }; return }
		menu.db.player.update { return [::playerdata::updateFide .application] }
		menu.db.player.names { return [::playerdata::checkSpellings .application] }

		menu.board.start.standard { return [::application::pgn::Shuffle Normal] }
		menu.board.start.chess960 { return [::application::pgn::Shuffle Chess960] }
		menu.board.start.symm960 { return [::application::pgn::Shuffle Symm960] }
		menu.board.start.shuffle { return [::application::pgn::Shuffle Shuffle] }
		menu.board.start.setup { catch { ::setup::setupPositionMenu ::application::pgn }; return }
		menu.board.set_start_board { catch { ::application::board::SetStartBoard .application }; return }
		menu.board.set_start_position { catch { ::application::board::SetStartPosition .application }; return }
		board-flip { catch { ::application::board::Rotate $::application::board::Vars(widget:frame) }; return }
		board-null-move { catch { ::application::board::InsertNullMove }; return }
		menu.board.setup { catch { ::board::options::openConfigDialog .application ::application::board::Redraw }; return }
		menu.board.appearance.side { ::menu::ToggleBoardOption side-to-move; return }
		menu.board.appearance.material { ::menu::ToggleBoardOption material-values; return }
		menu.board.appearance.border { ::menu::ToggleBoardOption border; return }
		menu.board.appearance.coordinates { ::menu::ToggleBoardOption coordinates; return }
		menu.board.appearance.small_letters { ::menu::ToggleBoardOption small-letters; return }
		menu.board.appearance.suggested { ::menu::ToggleBoardOption suggested-move; return }
		menu.board.appearance.arrows { ::menu::ToggleBoardOption variation-arrows; return }
		menu.board.appearance.annotation { ::menu::ToggleBoardOption annotation; return }
		menu.board.tablebase.show { catch { ::tablebase::toggle }; return }
		menu.board.tablebase.online { catch { ::tablebase::toggle }; return }
		menu.board.tablebase.local { catch { ::tablebase::chooseFolder .application }; return }

		menu.analysis.engine_toggle {
			if {[EngineRunning]} {
				catch { ::application::analysis::CloseEngine [lindex [array names ::application::analysis::NumberToTree] 0] }
			} else {
				catch { ::application::analysis::startEngine [::application::analysis::defaultEngine] }
			}
			return
		}
		menu.analysis.engines { return [::engine::openAdmininstration .application] }
		menu.analysis.engine_dictionary { return [::engine::showEngineDictionary .application] }
		menu.analysis.compare_engines { return [::application::analysis::openComparison .application] }
		menu.analysis.review_engine { catch { ::ai::engine::chooseDialog .application }; return }
		menu.analysis.analyze { catch { ::application::analysis::AnalyzePosition [::scidb::pos::fen] }; return }
		menu.analysis.game_review { return [::gamereview::run .application] }
		menu.analysis.explain.position { return [::application::ai::analyze .application] }
		menu.analysis.explain.line { catch { ::application::ai::explainLine .application }; return }
		menu.analysis.explain.move { catch { ::application::pgn::ExplainMove .application::pgn "" }; return }
		menu.analysis.explain.comment { return [::application::ai::analyze .application] }
		menu.analysis.factcheck { return [::ai::factcheck::current .application] }
		menu.analysis.tablebase.show { catch { ::tablebase::toggle }; return }
		menu.analysis.tablebase.online { catch { ::tablebase::toggle }; return }
		menu.analysis.tablebase.local { catch { ::tablebase::chooseFolder .application }; return }
		menu.analysis.explorer { catch { ::application::explorer::toggle }; return }

		menu.training.tactics { return [::tactics::open .application] }
		menu.training.endgame { return [::endtrainer::open .application] }
		menu.training.guess { return [::guessmove::start] }
		menu.training.repertoire { return [::reptrainer::open .application] }
		menu.training.play_engine { return [::playengine::open .application] }
		menu.training.engine_match { return [::enginematch::open .application] }
		menu.training.studyplan { return [::ai::studyplan::run .application] }
		menu.training.brief { return [::ai::brief::ask .application] }
		menu.training.training_set { return [::ai::cql::training .application] }
		menu.training.check_results { return [::ai::cql::qualityReport .application] }

		menu.tools.book { return [::book::openEditor .application] }
		menu.tools.player_dictionary { return [::playerdict::open .application] }
		menu.tools.player_card { catch { ::player::card::open }; return }
		menu.tools.correspondence { return [::application::corr::games::open .application] }
		menu.tools.iccf { return [::iccf::xfcc::openSettings .application] }
		menu.tools.engine_console { return [::engine::openEngineLog .application] }
		menu.tools.import_games { return [::menu::dbImport .application [CurrentBase] pgn] }
		menu.tools.download { return [::application::download::openActive .application] }
		menu.tools.assistant { return [::application::assistant::show] }
		menu.tools.choose_model { return [::application::ai::models::show .application] }
		menu.tools.voice { return [::application::voice::toggle] }
		menu.tools.file_types { return [::menu::AssignFileTypes .application] }
		menu.tools.legacy_fonts { return [::font::installChessBaseFonts .application] }

		menu.view.layout.save - menu.view.layout.save_as {
			set twm [CurrentTWM]
			if {$twm ne ""} {
				catch { ::application::twm::SaveLayout $twm .application {} {} }
			}
			return
		}
		menu.view.layout.manage {
			set twm [CurrentTWM]
			if {$twm ne ""} { catch { ::application::twm::Menu $twm .application 0 0 } }
			return
		}
		menu.view.font_inc { after idle { ::font::changeFontSize +1 }; return }
		menu.view.font_dec { after idle { ::font::changeFontSize -1 }; return }
		app-fullscreen { catch { ::menu::viewFullscreen toggle }; return }
		app-log { catch { ::log::show -force }; return }
		menu.view.tip { catch { ::tips::open .application }; return }

		app-help { return [::help::open .application] }
		menu.help.bug { return [::menu::bugReport .application] }
		menu.help.feature { return [::menu::featureRequest .application] }
		menu.help.about { return [::info::openDialog .application] }

		menu.view.panes.* { ::menu::TogglePane [lindex [split $id .] end]; return }
		view.pane_zoom { catch { ::application::TogglePaneZoom }; return }
		view.focus_zoom {
			set twm [CurrentTWM]
			if {$twm eq ""} { return 0 }
			set ::application::focuszoom::enabled($twm) \
				[expr {![::application::focuszoom::isEnabled $twm]}]
			::application::focuszoom::toggle $twm
			return [::application::focuszoom::isEnabled $twm]
		}
		view.focus_ratio {
			set r [expr {[set ::application::focuszoom::ratio] + 0.2}]
			if {$r > 1.8} { set r 1.2 }
			return [::application::focuszoom::setRatio $r]
		}
		view.focus_pin {
			set ::application::focuszoom::pinBoard [expr {![set ::application::focuszoom::pinBoard]}]
			return [set ::application::focuszoom::pinBoard]
		}
		view.board3d.open { return [::board3d::openViewer .application] }
		view.board3d.webgl { return [::board3d::openWebGLViewer] }
		view.board3d.embed { return [::board3d::toggleEmbed] }
	}
	return
}

proc ::menu::DbProperties {} {
	set base [CurrentBase]
	if {$base eq ""} { return }
	catch {
		set switcher $::application::database::Vars(switcher)
		$switcher show $base
	}
	return
}

proc ::menu::ToggleBoardOption {option} {
	variable ::board::layout
	if {[info exists ::board::layout($option)]} {
		set ::board::layout($option) [expr {!$::board::layout($option)}]
	}
	catch { ::application::board::Redraw }
	return
}

# The key-editor ids are registry ids (VAL-REG-003). Do this after the
# drop-down module is loaded; ::menu::Register later refreshes the
# placement of the ids the drop-down also carries.
catch { ::application::keyEditor::RegisterActions }
