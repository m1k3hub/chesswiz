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
	# Check marks on the View > Panes rows: one scalar per pane kind.
	variable PaneVisible
	array set PaneVisible {}
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
	set ExportLichess					"Lichess study…"
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
	set UploadStudy						"Upload to Lichess Study…"
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
	set StartEngine					"Start Engine"
	set StopEngine					"Stop Engine"
	set EngineDictionary				"Engine Dictionary…"
	set ChooseReviewEngine			"Choose Engine for Review…"
	set AnalyzePosition				"Analyze This Position"
	set Explain							"Explain"
	set ExplainPosition				"Position"
	set ExplainLine					"Line"
	set ExplainMove					"Move"
	set ExplainComment					"Comment"
	set AnnotateGameWithAI			"Annotate Game with AI…"
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
	set AnnotateGameWithAI			"Annotate Game with AI…"
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
	set SupportChesswiz				"&Support Chesswiz…"
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

	# The English defaults, restored before every language load (a
	# language file only overrides the ids it defines).
	set ::menu::DefaultMC {}
	foreach _name [lsort [info vars]] {
		if {[array exists $_name] || [string index [namespace tail $_name] 0] eq "_"} { continue }
		lappend ::menu::DefaultMC [namespace tail $_name] [set $_name]
	}
	unset _name
}

proc ::menu::ResetLabels {} {
	foreach {name value} $::menu::DefaultMC {
		set ::menu::mc::$name $value
	}
	return
}
::mc::addDefaultReset ::menu::ResetLabels

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
				[list cmd menu.file.export.lichess ExportLichess "" {::menu::DbOpen}] \
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
			[list cmd menu.game.export.study UploadStudy "" {::menu::GameLoaded}] \
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
			[list cmd menu.analysis.annotate AnnotateGameWithAI "" {::menu::ModulePresent annotate}] \
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
			[list cmd menu.help.bug ContactBugReport {} {expr {$::menu::BugTracker ne ""}}] \
			[list cmd menu.help.feature ContactFeatureRequest {} {expr {$::menu::FeatureRequestTracker ne ""}}] \
			[list cmd menu.help.support SupportChesswiz] \
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

	# A row hidden because its module is absent on this platform (e.g. file
	# types without xdg-mime on macOS) must not run from the registry either:
	# ::action::run enforces only the enabled predicate.
	if {$enabled eq "" && [string match {::menu::ModulePresent *} $visible]} {
		set enabled $visible
	}

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
		if {$id eq "app-quit"} { dict set rec confirm 1 }
		dict set ::action::Registry $id $rec
		return
	}
	# Quitting loses the open databases and the session; a click asks
	# nothing, but the assistant route (direct call or run_action) must
	# have the user's go-ahead.
	set confirm [expr {$id eq "app-quit" ? 1 : 0}]
	::action::register $id [dict create \
		label    $label \
		object   {} \
		args     {} \
		handler  [list ::menu::Invoke $id] \
		what     $label \
		confirm  $confirm \
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

	# Offer the support page when the assistant is asked how to donate.
	dict set ::action::Registry menu.help.support ai 1
	dict set ::action::Registry menu.help.support doc "Open the Chesswiz support page to donate or support development."

	# The New Game variants are dispatched by ::menu::Invoke but have no
	# drop-down row, so they are registered here for ::action::run.
	foreach id {game.new.normal game.new.three game.new.crazy game.new.variants} {
		Register $id [MC NewGame] "" "" "" ""
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
	if {[catch { set running [::application::analysis::Running] }]} { return 0 }
	return [expr {[llength $running] ? 1 : 0}]
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
proc ::menu::PaneFloating {uid {twm ""}} {
	# R12: true only for a pane that exists and is currently undocked.
	# A pane's leaf lives in a metaframe; the metaframe's toplevel is the
	# floating window when the pane is undocked (same test the app uses).
	if {$uid eq ""} { return 0 }
	if {$twm eq ""} {
		if {[catch { set twm [::application::twm] }]} { return 0 }
	}
	if {$twm eq ""} { return 0 }
	if {[catch { set leaf [$twm leaf $uid] }] || $leaf eq ""} { return 0 }
	if {[catch { set top [$twm toplevel $leaf] }]} { return 0 }
	if {[catch { set floating [$twm isfloat $top] }]} { return 0 }
	return [expr {$floating ? 1 : 0}]
}
proc ::menu::NoHtmlReport {} {
	# R13: the HTML report surface is the report renderer; a build without
	# it has no report font/print group. Opening a report builds the pane,
	# so "pane not yet created" is not the same as "surface absent".
	return [expr {[::capability::present report] ? 0 : 1}]
}
proc ::menu::Sortable {} {
	if {[catch { set v $::gamestable::Vars(sortable) }]} { return 1 }
	return [expr {$v ? 1 : 0}]
}
proc ::menu::EngineLabel {} {
	if {[EngineRunning]} { return [MC StopEngine] }
	return [MC StartEngine]
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
	}
	# (Re-)register every row so the built menu always carries the labels
	# of the current language; a language load only overrides variables,
	# so a stale label would otherwise survive until the app is restarted.
	RegisterTree
	RegisterExtras
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
	# First-run selection and other callers use mc::setLang directly.
	# Keep cached menus in sync through the common notification, too.
	bind $menu <<LanguageChanged>> [list ::menu::BuildDropdown $menu]
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
				set paneSuffix ""
				if {[string match {menu.view.panes.*} $id]} {
					set paneSuffix [string range $id 16 end]
				}
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
				if {$paneSuffix ne "" && !$DropdownForceAll && [PaneReason $paneSuffix] ne ""} {
					# A pane this layout cannot open is not posted: Tk never
					# activates a disabled menu row, so a reason attached to
					# one could never be shown (::action::run still says why).
					continue
				}
				if {$paneSuffix ne ""} {
					# A checkbutton shows the pane's current state; the
					# command always asks the layout, never the mark, so a
					# click can only ever perform the real toggle.
					set var ::menu::PaneVisible($paneSuffix)
					set $var [PaneChecked $paneSuffix]
					lappend opts -variable $var -onvalue 1 -offvalue 0
					eval [list $menu add checkbutton] $opts
				} else {
					eval [list $menu add command] $opts
				}
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

proc ::menu::PaneSuffix {name} {
	# The layout uses the singular uid; the public action id keeps the old
	# plural spelling from the pre-redesign menu (and from the fixture).
	set aliases {
		player players event events site sites annotator annotators
		position positions dbgames games
	}
	if {[dict exists $aliases $name]} { return [dict get $aliases $name] }
	return $name
}

proc ::menu::PaneUid {twm suffix} {
	# Exact dispatch: the public id names a pane kind, the layout leaf is the
	# uid (analysis panes carry a number: analysis:1).
	set aliases {
		players player
		events event
		sites site
		annotators annotator
		positions position
		games games
	}
	set wanted $suffix
	if {[dict exists $aliases $suffix]} { set wanted [dict get $aliases $suffix] }
	foreach uid [$twm leaves] {
		if {[::application::NameFromUid $uid] eq $wanted} { return $uid }
	}
	return ""
}

proc ::menu::FillPanes {menu} {
	set twm [CurrentTWM]
	if {$twm eq ""} { return }
	set seen {}
	foreach uid [$twm leaves] {
		set suffix [PaneSuffix [::application::NameFromUid $uid]]
		if {$suffix in $seen} { continue }
		lappend seen $suffix
		catch {
			lassign [AmpText [::application::twm::PaneLabel $uid]] text ul
			$menu add command -label $text -underline $ul \
				-command [list ::action::run menu.view.panes.$suffix]
		}
	}
}

# The layout leaf a public pane id names. A pane that is already in the
# layout keeps its exact uid (analysis panes carry a number); an absent one
# resolves to the uid the layout uses when it creates the pane.
proc ::menu::PaneLayoutUid {suffix} {
	set twm [PaneTWM]
	if {$twm ne ""} {
		set uid [PaneUid $twm $suffix]
		if {$uid ne ""} { return $uid }
	}
	switch -- $suffix {
		board		{ return board }
		editor		{ return editor }
		games		{ return games }
		tree		{ return tree }
		analysis	{ return analysis:1 }
		media		{ return media }
		report		{ return report }
		assistant	{ return assistant }
		explorer	{ return explorer }
	}
	return ""
}

# Empty when the pane can be toggled now. A non-empty text is the reason the
# posted row is disabled: either the build has no such pane, or the optional
# module that owns it is absent.
proc ::menu::PaneReason {suffix} {
	set twm [PaneTWM]
	if {$twm eq ""} { return "The board layout is not available." }
	if {[PaneLayoutUid $suffix] eq ""} {
		return "This pane is not available in this build."
	}
	if {[llength [info commands ::capability::present]]} {
		switch -- $suffix {
			report		{ if {![::capability::present report]} { return "The report module is not available." } }
			assistant	{ if {![::capability::present assistant]} { return "The assistant module is not available." } }
			explorer	{ if {![::capability::present explorer]} { return "The opening explorer module is not available." } }
		}
	}
	return ""
}

proc ::menu::PaneOpenable {suffix} {
	return [expr {[PaneReason $suffix] eq ""}]
}

proc ::menu::PaneChecked {suffix} {
	set twm [PaneTWM]
	if {$twm eq ""} { return 0 }
	return [expr {[PaneUid $twm $suffix] ne ""}]
}

proc ::menu::SyncPaneCheck {suffix} {
	if {[info exists ::menu::PaneVisible($suffix)]} {
		set ::menu::PaneVisible($suffix) [PaneChecked $suffix]
	}
}

proc ::menu::TogglePane {twm uid} {
	# A pane that is part of the layout is hidden (or restored from the
	# collapsed presentation by ChangeState). A pane that is absent is
	# reopened through the layout's show API, which creates the leaf and
	# brings its tab/parent to the front.
	if {$uid eq ""} { return 0 }
	if {$uid in [$twm leaves]} {
		catch { ::application::twm::ChangeState $twm $uid }
	} elseif {[llength [info commands ::application::openPane]]} {
		::application::openPane $uid
	} else {
		catch { ::application::twm::ChangeState $twm $uid }
	}
	return 1
}

proc ::menu::TogglePaneId {suffix} {
	# Selecting the page must not focus the board canvas: that leaf may
	# have just been hidden by the preceding toggle.
	.application.nb select .application.nb.board
	update idletasks
	set twm [PaneTWM]
	if {$twm eq ""} { return 0 }
	if {![PaneOpenable $suffix]} { return "error: [PaneReason $suffix]" }
	set uid [PaneLayoutUid $suffix]
	if {$uid eq ""} { return 0 }
	# The assistant panel remembers whether it should appear at startup:
	# hiding it (View > Panes, one-click Hide) clears the option, reopening
	# it sets the option again (VAL-AI-011).
	if {$suffix eq "assistant"} {
		catch { ::application::assistant::panel::SetEnabled [expr {![PaneChecked $suffix]}] }
	}
	set result [TogglePane $twm $uid]
	update idletasks
	SyncPaneCheck $suffix
	return $result
}

# Dynamic values are arguments, rather than scripts stored in the registry.
# Register before any menu is opened so the assistant can use these directly.
proc ::menu::RegisterDynamicActions {} {
	foreach {id label spec} {
		menu.view.theme {Set interface theme} {{name {type string required 1 description {Installed theme name}}}}
		menu.view.colors {Set interface color scheme} {{name {type string enum {dark lite} required 1}}}
		menu.view.icon_size {Set toolbar icon size} {{name {type string enum {small medium large} required 1}}}
		menu.view.language {Set interface language} {{name {type string required 1 description {Language name or language code}}}}
		menu.view.layout.fold {Fold or unfold all titlebars} {{fold {type boolean required 1}}}
		menu.view.layout.pane {Toggle layout pane} {{uid {type string required 1 description {Layout pane identifier}}}}
		menu.view.layout.load {Restore named layout} {{name {type string required 1}}}
		menu.view.layout.arrow_size {Set docking arrow size} {{pixels {type integer enum {16 24 32} required 1}}}
		menu.view.layout.docking {Show docking points} {{show {type boolean required 1}}}
	} {
		if {[dict exists $::action::Registry $id]} { continue }
		::action::register $id [dict create label $label object {} args $spec \
			handler [list ::menu::RunDynamic $id] what $label doc $label \
			ai 0 operator 1 dropdown 09.950]
	}
}

proc ::menu::RunDynamic {id arguments} {
	switch -- $id {
		menu.view.colors { set ::colors::Scheme [dict get $arguments name]; return $::colors::Scheme }
		menu.view.icon_size { set ::toolbar::Options(icons:size) [dict get $arguments name]; return $::toolbar::Options(icons:size) }
		menu.view.layout.arrow_size { set ::twm::Options(cross:size) [dict get $arguments pixels]; return $::twm::Options(cross:size) }
		menu.view.theme {
			set name [dict get $arguments name]
			if {$name ni [ttk::style theme names] || $name eq "classic"} { return "error: unknown theme '$name'" }
			::theme::setTheme $name
			return [::theme::currentTheme]
		}
		menu.view.language {
			set name [dict get $arguments name]
			set valid 0
			foreach language $::i18n::languages {
				if {$name in [lrange $language 0 1]} { set valid 1; break }
			}
			if {!$valid} { return "error: unknown language '$name'" }
			return [SwitchLanguage $name]
		}
	}
	set twm [CurrentTWM]
	if {$twm eq ""} { return "error: no layout selected" }
	switch -- $id {
		menu.view.layout.fold {
			set selector [expr {[dict get $arguments fold] ? "!flat" : "flat"}]
			set frames [$twm collect $selector]
			if {[llength $frames]} { $twm togglebar {*}$frames }
			return [llength $frames]
		}
		menu.view.layout.pane {
			set uid [dict get $arguments uid]
			set layoutId $::application::Vars($twm:id)
			array set opts $::application::Vars($layoutId:init:options)
			if {$uid ni [$twm leaves] && ![info exists opts($uid)]} { return "error: unknown pane '$uid'" }
			::application::twm::ChangeState $twm $uid
			return [$twm isdocked $uid]
		}
		menu.view.layout.load {
			set name [dict get $arguments name]
			set layoutId $::application::Vars($twm:id)
			if {$name ni [::application::twm::glob $layoutId]} { return "error: unknown layout '$name'" }
			return [::application::twm::loadLayout $twm $name]
		}
		menu.view.layout.docking {
			set layoutId $::application::Vars($twm:id)
			set ::application::twm::Options($layoutId:docking:showall) [dict get $arguments show]
			::application::twm::ShowAllDockingPoints $twm
			return [dict get $arguments show]
		}
	}
	return "error: unknown display operation"
}

# Preserve the native layout builder's labels, check variables and state.
# Only replace recognised callbacks; unknown operations stay visible to the
# strict coverage walk, rather than being silently classified as mapped.
proc ::menu::WireLayoutMenu {twm menu} {
	set n [$menu index end]
	if {$n eq "none"} { return }
	for {set i 0} {$i <= $n} {incr i} {
		set type [$menu type $i]
		if {$type eq "cascade"} {
			WireLayoutMenu $twm [$menu entrycget $i -menu]
			continue
		}
		if {$type ni {command checkbutton radiobutton}} { continue }
		set cmd [$menu entrycget $i -command]
		if {[lindex $cmd 0] eq "::namespace" && [lindex $cmd 1] eq "inscope"} { set cmd [lindex $cmd 3] }
		set op [namespace tail [lindex $cmd 0]]
		set action ""
		if {$type eq "radiobutton" && [$menu entrycget $i -variable] eq "::twm::Options(cross:size)"} {
			set action [list ::action::run menu.view.layout.arrow_size [dict create pixels [$menu entrycget $i -value]]]
		}
		switch -- $op {
			togglebar {
				if {[lindex $cmd 0] ne $twm} { continue }
			}
			ChangeState { set action [list ::action::run menu.view.layout.pane [dict create uid [lindex $cmd 2]]] }
			loadLayout { set action [list ::action::run menu.view.layout.load [dict create name [lindex $cmd 2]]] }
			SaveLayout { set action [list ::action::run menu.view.layout.save] }
			open { if {[lindex $cmd 0] eq "::application::layout::open"} { set action [list ::action::run menu.view.layout.manage] } }
			ShowAllDockingPoints {
				set var [$menu entrycget $i -variable]
				set action [format {::action::run menu.view.layout.docking [dict create show $%s]} $var]
			}
		}
		if {[lindex $cmd 0] eq $twm && [lindex $cmd 1] eq "togglebar" && $type eq "command"} {
			set fold [expr {[string trim [$menu entrycget $i -label]] eq $::application::twm::mc::FoldAllTitleBars}]
			set action [list ::action::run menu.view.layout.fold [dict create fold $fold]]
		}
		if {$action ne ""} { $menu entryconfigure $i -command $action }
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
			-command [list ::action::run menu.view.theme [dict create name $style]]
		::theme::configureRadioEntry $menu
	}
}

proc ::menu::FillColors {menu} {
	lassign [AmpText [set ::menu::mc::OrdinaryMonitor]] text ul
	$menu add radiobutton -label $text -underline $ul \
		-variable ::colors::Scheme -value dark \
		-command [list ::action::run menu.view.colors {name dark}]
	::theme::configureRadioEntry $menu
	lassign [AmpText [set ::menu::mc::HighQualityMonitor]] text ul
	$menu add radiobutton -label $text -underline $ul \
		-variable ::colors::Scheme -value lite \
		-command [list ::action::run menu.view.colors {name lite}]
	::theme::configureRadioEntry $menu
}

proc ::menu::FillIconSize {menu} {
	foreach size $::toolbar::iconSizes {
		set var ::toolbar::mc::[string toupper $size 0 0]
		lassign [AmpText [set $var]] text ul
		$menu add radiobutton -label $text -underline $ul \
			-variable ::toolbar::Options(icons:size) -value $size \
			-command [list ::action::run menu.view.icon_size [dict create name $size]]
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
				-command [list ::action::run menu.view.language [dict create name $lang]]
		}
	}
}

# Relabel the live drop-down after a language switch (VAL-BAR-007). The
# registry labels are refreshed from the newly loaded mc strings, then the
# menu widget is rebuilt so the top cascades and their leaves show them.
proc ::menu::SwitchLanguage {lang} {
	# the View > Language rows pass the language's name (Deutsch); setLang wants its id (de)
	set n [lsearch -exact -index 0 $::i18n::languages $lang]
	if {$n >= 0} { set lang [lindex $::i18n::languages $n 1] }
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
				# A toggle with a label script (Start / Stop Engine) shows
				# state at runtime; the structural fixture records its
				# registered label.
				if {$kind eq "toggle" && [catch { ::action::get [lindex $node 1] } rec] == 0} {
					if {[dict exists $rec label]} { set label [NormLabel [dict get $rec label]] }
				}
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
	::inventoryaction::Register
	if {[dict exists $::action::Registry app-fullscreen]} {
		dict set ::action::Registry app-fullscreen args {{state {type enum default toggle enum {toggle on off} description {Use off to exit fullscreen, on to enter, or toggle}}}}
		dict set ::action::Registry app-fullscreen schema {}
		dict set ::action::Registry app-fullscreen handler {::menu::Invoke app-fullscreen}
	}
	if {![dict exists $::action::Registry help.close]} {
		::action::register help.close [dict create label "Close Help" what "Close Help" object {} ai 1 \
			doc "Close the Help window after reading the manual." \
			purpose "Close the Help window after reading the manual." \
			when "Use this after reading a manual page to return to the main application." \
			examples {{Close the manual window} {Dismiss Help and return to my game}} \
			args {} handler ::menu::CloseHelp]
	}
	if {![dict exists $::action::Registry view.dialog.close]} {
		::action::register view.dialog.close [dict create label "Close dialog" what "Close dialog" object {} ai 1 \
			doc "Close a named information or preferences dialog. Unsaved form fields are discarded." \
			args {{dialog {type enum required 1 enum {about correspondence crosstable engine_dictionary iccf keyboard pgn player_dictionary review_engine}}}} \
			handler ::menu::CloseNamedDialog]
	}
	RegisterDynamicActions
	foreach operation {rename delete} {
		if {[dict exists $::action::Registry layout.$operation]} { continue }
		::action::register layout.$operation [dict create \
			label "[string totitle $operation] saved layout" object {} ai 1 confirm 1 \
			what "$operation saved layout" \
			args {{name {type string required 1}} {new_name {type string default {}}} {overwrite {type boolean default 0}}} \
			doc "[string totitle $operation] a saved layout by name without opening the layout manager." \
			handler [list ::menu::RunNamedLayoutMutation $operation]]
	}
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
	# Rows reached from the dynamic Game submenus. They have a dedicated
	# branch in Do, but the rows themselves are generated from DynId, so the
	# registry walk only sees the ids when they are registered here as well.
	set i 0
	foreach {id labelName} {
		menu.game.paste_clip PasteClipbase
		menu.game.paste_tab PasteGameTab
		menu.game.merge_clip MergeClipbase
		menu.game.merge_tab MergeGameTab
		menu.game.history.recent RecentGames
	} {
		incr i
		Register $id [MC $labelName] "" "" "" [format "03.%03d" [expr {850 + $i}]]
	}
	# "Clipbase" is the game clipboard: reuse game.paste's handler so the
	# posted row and the assistant paste the same remembered games.
	if {[dict exists $::action::Registry game.paste]} {
		set rec [::action::get menu.game.paste_clip]
		set paste [::action::get game.paste]
		dict set rec handler [dict get $paste handler]
		dict set rec args [dict get $paste args]
		dict set ::action::Registry menu.game.paste_clip $rec
	}
	# Engine toggle is posted from the static Analysis cascade as a toggle;
	# RegisterNodes gives toggles no order, so give it one here.
	Register menu.analysis.engine_toggle [MC StartStopEngine] "" "" "" "06.001"
	# One row per pane, with the same label the posted row shows. The list is
	# id -> label key, never a flat word list: "game list" is one label.
	set order 890
	foreach {uid labelName} {
		board PaneBoard
		editor PaneEditor
		games PaneGameList
		players PanePlayers
		events PaneEvents
		sites PaneSites
		annotators PaneAnnotators
		positions PanePositions
		tree PaneTree
		analysis PaneAnalysis
		media PaneMedia
		report PaneReport
		assistant PaneAssistant
		explorer PaneExplorer
	} {
		incr order
		# A pane that cannot be opened in this state is posted disabled, with
		# the reason attached as the row's tooltip; it is never an enabled
		# no-op. The enabled predicate is also what ::action::run enforces.
		Register menu.view.panes.$uid [MC $labelName] "" "" \
			[list ::menu::PaneOpenable $uid] [format "09.%03d" $order]
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

# Panes belong to the board layout even when the notebook is showing another
# page. Called by-id (script, palette), a pane toggle still has an obvious
# target; fall back to the board twm instead of silently doing nothing.
proc ::menu::PaneTWM {} {
	# View > Panes always controls the board layout, also while another
	# notebook page is shown; fall back to the current layout only when the
	# board layout has not been built yet.
	if {[llength [info commands ::application::reflow::boardTwm]]} {
		if {![catch { set twm [::application::reflow::boardTwm] }] && $twm ne ""} {
			return $twm
		}
	}
	set twm [CurrentTWM]
	if {$twm ne ""} { return $twm }
	if {[llength [info commands ::application::twm]] == 0} { return "" }
	catch { set twm [::application::twm board] }
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

# Explicit operation adapters: the same menu action collects omitted input
# interactively, or executes supplied input through the existing native APIs.
proc ::menu::OperationKind {id} {
	switch -- $id {
		menu.file.new.normal - menu.file.new.three - menu.file.new.crazy -
		menu.file.new.variants - c4.new.scid - c4.new.pgn { return new }
		menu.file.open - c4.open_database { return open }
		menu.file.import.pgn - menu.file.import.db - c4.import.pgn { return import }
		menu.file.export.pgn - menu.file.export.html - c4.export.pgn { return export }
		menu.db.search.plain { return search }
		menu.view.layout.save - menu.view.layout.save_as { return layout-save }
		menu.view.layout.manage { return layout-manage }
		menu.edit.keyboard { return keyboard }
		menu.edit.preferences.pgn { return pgn-options }
		app-log { return log }
		menu.tools.engine_console { return engine-log }
		menu.tools.book { return book }
		menu.training.endgame { return endgame }
		menu.training.tactics { return tactics }
		menu.training.repertoire { return repertoire }
        menu.training.play_engine { return play-engine }
        menu.training.engine_match { return engine-match }
        menu.analysis.game_review { return game-review }
        menu.analysis.review_engine { return review-engine }
        menu.tools.iccf { return iccf-settings }
        menu.tools.download { return download }
        menu.training.training_set { return training-set }
        menu.tools.player_card { return private-card }
        menu.tools.correspondence { return correspondence }
        menu.analysis.compare_engines { return comparison }
        menu.analysis.engines { return engine-admin }
	}
	return ""
}

proc ::menu::OperationSpec {id} {
	set kind [OperationKind $id]
    if {$kind eq "comparison"} {
        return {
            {operation {type enum default {} enum {{} start stop close status}}}
            {engines {type array default {}}}
            {seconds {type integer default 10 range {1 600}}}
        }
    }
    if {$kind eq "engine-admin"} {
        return {
            {operation {type enum default {} enum {{} list add update delete clear_usage webpage close}}}
            {engine {type string default {}}}
            {filename {type string default {} description {Engine executable for add}}}
            {name {type string required 0}}
            {directory {type string required 0}}
            {logo {type string required 0}}
            {parameters {type string required 0}}
            {webpage {type string required 0}}
            {email {type string required 0}}
            {country {type string required 0}}
            {discard {type boolean required 0 description {Explicitly discard unsaved administration form fields when closing}}}
        }
    }
    if {$kind eq "correspondence"} {
        return {
            {operation {type enum default {} enum {{} refresh sync open}}}
            {number {type integer default 0 range {0 100000000}}}
            {filter {type enum default all enum {all ongoing finished}}}
        }
    }
    if {$kind eq "private-card"} {
        set spec {
            {operation {type enum default {} enum {{} list get save delete lookup rating_fill new_draft close} description {rating_fill returns draft and filled fields using supplied name/FideID and fields, preserving nonempty values without saving; new_draft returns blank fields and clears an active form without saving.}}}
            {name {type string default {}}}
            {photo {type string default {} description {Image filename to copy when saving}}}
        }
        foreach field $::playercard::PrivateFields {
            if {$field eq "Name"} { continue }
            set type string
            if {$field eq "Me"} { set type boolean }
            lappend spec [list $field [list type $type required 0]]
        }
        return $spec
    }
    if {$kind eq "training-set"} {
        return {
            {operation {type enum default {} enum {{} start status cancel}}}
            {patterns {type array default {}}}
            {player {type string default {}}}
            {max {type integer default 20 range {1 1000}}}
            {scan {type integer default 300 range {1 10000}}}
            {depth {type integer default 14 range {1 64}}}
            {filename {type string default {}}}
        }
    }
    if {$kind eq "download"} {
        return {
            {operation {type enum default {} enum {{} start cancel status}}}
            {source {type enum default twic enum {twic lichess study broadcast player url}}}
            {base {type string default {}}}
            {issues {type integer default 1 range {1 100}}}
            {lichess {type string default {}}}
            {studies {type string default {}}}
            {broadcast {type string default {}}}
            {refresh {type integer default 0 range {0 1440}}}
            {url {type string default {}}}
            {site {type enum default Lichess enum {Lichess Chess.com}}}
            {player {type string default {}}}
            {months {type integer default 1 range {1 120}}}
        }
    }
    if {$kind eq "review-engine"} {
        return {
            {operation {type enum default {} enum {{} list select status}}}
            {engine {type string default {} description {Configured UCI engine name; empty selects the bundled engine}}}
        }
    }
    if {$kind eq "iccf-settings"} {
        return {
            {operation {type enum default {} enum {{} save status}}}
            {username {type string default {}}}
            {password {type string default {}}}
            {endpoint {type string default {} description {XFCC endpoint; empty retains the existing endpoint}}}
        }
    }
    if {$kind eq "game-review"} {
        return {
            {operation {type enum default {} enum {{} start cancel status}}}
            {depth {type integer default 12 range {1 64}}}
        }
    }
    if {$kind eq "play-engine"} {
        return {
            {operation {type enum default {} enum {{} start move resign offer_draw takeback close status}}}
            {engine {type string default {} description {Configured engine name}}}
            {move {type string default {} description {Legal SAN move for the user}}}
            {color {type enum default white enum {white black random}}}
            {minutes {type integer default 10 range {0 180}}}
            {increment {type integer default 2 range {0 60}}}
            {movetime {type integer default 1000 range {1 600000}}}
            {elo {type integer default 1600 range {0 4000}}}
            {skill {type integer default 5 range {0 20}}}
        }
    }
    if {$kind eq "engine-match"} {
        return {
            {operation {type enum default {} enum {{} open start close status}}}
            {mode {type enum default match enum {match gauntlet}}}
            {engines {type array default {} description {Configured engine names; two for a match}}}
            {games {type integer default 2 range {2 1000}}}
            {minutes {type integer default 5 range {0 180}}}
            {increment {type integer default 2 range {0 60}}}
            {movetime {type integer default 1000 range {1 600000}}}
            {suite {type string default {}}}
            {suite_plies {type integer default 10 range {1 40}}}
            {base {type string default {} description {Writable destination database; empty uses the game clipboard}}}
            {tablebase {type boolean default 1}}
            {online {type boolean default 0}}
        }
    }
	if {$kind eq "repertoire"} {
		return {
			{operation {type enum default {} enum {{} open start move grade stop close status}}}
			{base {type string default {} description {Open source database; empty uses the current game}}}
			{side {type enum default white enum {white black}}}
			{variant {type string default Normal}}
			{move {type string default {} description {Answer in SAN}}}
			{grade {type integer default 2 range {1 3} description {1 Hard, 2 Good, 3 Easy}}}
		}
	}
	if {$kind eq "tactics"} {
		return {
			{operation {type enum default {} enum {{} open move retry solution next status}}}
			{filename {type string default {} description {FEN-based puzzle PGN file}}}
			{move {type string default {} description {SAN or UCI move}}}
		}
	}
	if {$kind eq "keyboard"} {
		return {
			{operation {type enum default {} enum {{} list set reset reset_all}}}
			{action {type string default {} description {Key-editor action id}}}
			{key {type string default {} description {Key specification such as Control-Shift-F12}}}
		}
	}
	if {$kind eq "pgn-options"} {
		set fields {}
		foreach field $::export::Fields(pgn) {
			if {$field eq "use_chessbase_format"} { set field compatibility_format }
			lappend fields $field
		}
		return [list \
			{operation {type enum default {} enum {{} list set reset}}} \
			[list option [list type enum default {} enum [linsert $fields 0 {}]]] \
			{value {type boolean default 1}}]
	}
	if {$kind in {log engine-log}} {
		return {{operation {type enum default {} enum {{} clear close}}}}
	}
	if {$kind eq "endgame"} {
		return {
			{operation {type enum default {} enum {{} catalog status start move retry continue give_up next close} description {Endgame session operation; omit to open the ending chooser}}}
			{ending {type string default {} description {Catalog ending id for start; use catalog to list ids}}}
			{index {type integer default 0 range {0 10000} description {Zero-based position within the ending}}}
			{move {type string default {} description {Legal SAN move for the user's turn}}}
		}
	}
	if {$kind eq "book"} {
		return {
			{operation {type enum default {} enum {{} open new save add add_last remove reweight create close} description {Book operation; omit to open the book editor}}}
			{filename {type string default {} description {Book file for open, new or create}}}
			{move {type string default {} description {SAN move for add, remove or reweight}}}
			{weight {type integer default 1 range {0 65535}}}
			{overwrite {type boolean default 0}}
			{plies {type integer default 40 range {1 10000}}}
			{min_games {type integer default 1 range {1 1000000}}}
			{weight_mode {type enum default frequency enum {frequency score}}}
		}
	}
	if {$kind in {layout-save layout-manage}} {
		set spec {
			{name {type string default {} description {Saved layout name; omit to collect it in the dialog}}}
			{overwrite {type boolean default 0 description {Allow replacing an existing layout}}}
		}
		if {$kind eq "layout-manage"} {
			lappend spec {operation {type enum default {} enum {{} list rename delete load replace link} description {List, rename, delete, load, replace or link saved layouts; omit to open the manager}}}
			lappend spec {new_name {type string default {} description {New name for the rename operation}}}
			lappend spec {link {type string default {} description {Board layout to link; empty unlinks the layout}}}
		}
		return $spec
	}
	if {$kind eq "search"} { return [dict get [::action::get search_games] args] }
	if {$kind eq ""} { return {} }
	return {
		{filename {type string default {} description {File to create, open, import or export; omit to choose in a dialog}}}
		{encoding {type string default utf-8 description {Text encoding for database creation and export}}}
		{overwrite {type boolean default 0 description {Allow replacing an existing export file}}}
	}
}

proc ::menu::OperationSupplied {id arguments} {
	if {[OperationKind $id] in {endgame tactics repertoire keyboard pgn-options log engine-log play-engine engine-match game-review review-engine iccf-settings download training-set private-card correspondence comparison engine-admin}} {
		return [expr {[dict exists $arguments operation] && [dict get $arguments operation] ne ""}]
	}
	if {[OperationKind $id] eq "book"} {
		return [expr {[dict exists $arguments operation] && [dict get $arguments operation] ne ""}]
	}
	if {[OperationKind $id] eq "layout-save"} {
		return [expr {[dict exists $arguments name] && [dict get $arguments name] ne ""}]
	}
	if {[OperationKind $id] eq "layout-manage"} {
		return [expr {[dict exists $arguments operation] && [dict get $arguments operation] ne ""}]
	}
	if {[OperationKind $id] eq "search"} {
		dict for {key value} $arguments {
			if {$key eq "object" || ($key eq "color" && $value eq "any")} { continue }
			if {$value ne ""} { return 1 }
		}
		return 0
	}
	return [expr {[dict exists $arguments filename] && [dict get $arguments filename] ne ""}]
}

proc ::menu::OperationCallback {args} { return 0 }

proc ::menu::WriteDatabaseFile {filename format encoding overwrite {base ""} {variant ""}} {
	set filename [file normalize $filename]
	if {[file exists $filename] && !$overwrite} { error "file exists; supply overwrite true to replace it: $filename" }
	if {$base eq ""} { set base [CurrentBase] }
	if {$variant eq ""} { set variant [CurrentVariant] }
	# Never replace the database being read, even with overwrite permission.
	if {[::scidb::db::get open? $filename]} { error "cannot export over an open database" }
	switch -- $format {
		pgn {
			set result [::scidb::view::export $base $variant 0 $filename [::export::getPgnFlags] 0 $encoding 0 {} {{* yes}} \
				::menu::OperationCallback {} ::menu::OperationCallback {}]
		}
		html {
			set result [::scidb::view::printHtml $base $variant 0 $filename 63 {{* yes}} \
				::menu::OperationCallback {} ::menu::OperationCallback {}]
		}
		default { error "unsupported export format: $format" }
	}
	return "exported games to $filename"
}

proc ::menu::RunOperation {id arguments} {
	set kind [OperationKind $id]
    if {$kind in {play-engine engine-match game-review review-engine iccf-settings download training-set private-card correspondence comparison engine-admin}} {
        return [RunSessionOperation $kind $arguments]
    }
	if {$kind in {keyboard pgn-options log engine-log}} { return [RunDialogOperation $kind $arguments] }
	if {$kind eq "repertoire"} { return [::reptrainer::runOperation $arguments] }
	if {$kind eq "tactics"} { return [::tactics::runOperation $arguments] }
	if {$kind eq "endgame"} { return [::endtrainer::runOperation $arguments] }
	if {$kind eq "book"} { return [::book::runOperation $arguments] }
	if {$kind in {layout-save layout-manage}} { return [RunLayoutOperation $kind $arguments] }
	if {$kind eq "search"} {
		set checked [::application::assistant::CheckArgs search_games $arguments]
		set result [::application::assistant::DoSearchGames [dict get $checked criteria]]
		::application::assistant::DoShowSearch
		return $result
	}
	set filename [dict get $arguments filename]
	switch -- $kind {
		new {
			if {[file exists $filename]} { error "database already exists: $filename" }
			set variant Normal
			if {$id eq "menu.file.new.three"} { set variant ThreeCheck }
			if {$id eq "menu.file.new.crazy"} { set variant Crazyhouse }
			return [::application::database::newBase .application $variant $filename [dict get $arguments encoding]]
		}
		open { return [::application::assistant::DoOpenDatabase $filename] }
		import {
			if {![file readable $filename]} { error "cannot read file: $filename" }
			set base [CurrentBase]
			if {[dict exists $arguments object base]} { set base [dict get $arguments object base] }
			if {[::scidb::db::get readonly? $base]} { error "database is read-only" }
			::import::import .application $base [list $filename] $::import::mc::DatabaseImport [dict get $arguments encoding]
			if {$base eq [CurrentBase]} { ::application::database::refreshBase $base }
			return "imported $filename"
		}
		export {
			set format [expr {$id eq "menu.file.export.html" ? "html" : "pgn"}]
			set base [CurrentBase]
			if {[dict exists $arguments object base]} { set base [dict get $arguments object base] }
			return [WriteDatabaseFile $filename $format [dict get $arguments encoding] [dict get $arguments overwrite] $base]
		}
	}
	error "no operation adapter for $id"
}

# Use the same layout persistence as the native dialogs. Only registry calls
# with explicit names reach this path; interactive callers keep their dialogs.
proc ::menu::RunLayoutOperation {kind arguments} {
	set twm [CurrentTWM]
	if {$twm eq ""} { error "no layout selected" }
	set id $::application::Vars($twm:id)
	set variant $::application::Vars($id:layout:variant)
	if {$kind eq "layout-manage" && [dict get $arguments operation] eq "list"} {
		return [::application::twm::glob $id]
	}
	set name [dict get $arguments name]
	::application::twm::checkLayoutName $name
	if {$kind eq "layout-save"} {
		return [::application::twm::saveNamedLayout $twm $name [dict get $arguments overwrite]]
	}
	if {![file exists [::application::twm::makeFilename $id $variant $name]]} {
		error "layout does not exist: $name"
	}
	switch -- [dict get $arguments operation] {
		rename - delete {
			set operation [dict get $arguments operation]
			return [::action::run layout.$operation [dict create name $name \
				new_name [dict get $arguments new_name] overwrite [dict get $arguments overwrite]]]
		}
		load { ::application::twm::loadLayout $twm $name; return $name }
		replace { ::application::twm::replaceLayout $twm $variant $name; return $name }
		link {
			if {$id eq "board"} { error "board layouts cannot link to another board layout" }
			set link [dict get $arguments link]
			if {$link ne ""} {
				::application::twm::checkLayoutName $link
				if {$link ni [::application::twm::glob board]} { error "board layout does not exist: $link" }
			}
			::application::twm::setLink $id $name $link
			return $link
		}
	}
}

proc ::menu::RunNamedLayoutMutation {operation arguments} {
	set twm [CurrentTWM]
	if {$twm eq ""} { error "no layout selected" }
	set name [dict get $arguments name]
	::application::twm::checkLayoutName $name
	set id $::application::Vars($twm:id)
	set variant $::application::Vars($id:layout:variant)
	if {![file exists [::application::twm::makeFilename $id $variant $name]]} {
		error "layout does not exist: $name"
	}
	if {$operation eq "delete"} { return [::application::twm::deleteNamedLayout $twm $name $variant] }
	return [::application::twm::renameNamedLayout $twm $name [dict get $arguments new_name] [dict get $arguments overwrite]]
}

proc ::menu::InvokeOperationAlias {id original arguments} {
	if {[OperationSupplied $id $arguments]} { return [RunOperation $id $arguments] }
	return [{*}$original $arguments]
}

# Reject malformed names before any window, slot or engine can change.
proc ::menu::ValidateMatchArgs {arguments} {
	if {[dict get $arguments operation] ne "start"} {return $arguments}
	set names [dict get $arguments engines]
	if {![llength $names]} {return $arguments}
	if {([dict get $arguments mode] eq "match" && [llength $names] != 2) || [llength $names] < 2} {
		return -code error -errorcode {CHESSWIZ ARGUMENT engines} "engines must contain two names for a match, or at least two for a gauntlet"
	}
	foreach name $names {
		if {$name ni [::enginematch::EngineNames]} {
			return -code error -errorcode {CHESSWIZ ARGUMENT engines} "unknown configured UCI engine '$name'; pass engine names as an array, without separator punctuation"
		}
	}
	return $arguments
}

proc ::menu::WireOperations {} {
	foreach id [::action::list] {
		if {[OperationKind $id] eq ""} { continue }
		set rec [::action::get $id]
		set spec [OperationSpec $id]
		# Preserve the object resolver used by context-menu actions.
		foreach param [dict get $rec args] {
			if {[lindex $param 0] eq "object"} { lappend spec $param }
		}
		dict set rec args $spec
		set kind [OperationKind $id]
		if {$kind in {keyboard pgn-options log engine-log tactics repertoire play-engine engine-match game-review review-engine iccf-settings download training-set private-card correspondence comparison engine-admin}} {
			dict set rec doc "Run [dict get $rec label] with operation arguments; omit operation to open its window. Use the list or status operation where available to inspect current state."
		}
		if {$kind eq "engine-match"} {dict set rec validate ::menu::ValidateMatchArgs}
		dict set rec schema ""
		set handler [dict get $rec handler]
		if {[lindex $handler 0] ni {::menu::Invoke ::menu::InvokeOperationAlias}} {
			dict set rec handler [list ::menu::InvokeOperationAlias $id $handler]
		}
		dict set ::action::Registry $id $rec
	}
}

proc ::menu::Invoke {id {argsDict {}}} {
	if {[catch {
		if {$id eq "app-fullscreen" && [dict exists $argsDict state] && [dict get $argsDict state] ne "toggle"} {
			::menu::setFullscreen [expr {[dict get $argsDict state] eq "on"}]
			set result [::menu::fullscreen?]
		} elseif {[OperationSupplied $id $argsDict]} {
			RunOperation $id $argsDict
		} else { ::menu::Do $id }
	} result options]} {
		::debuglog::log menu "$id: [dict get $options -errorinfo]"
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
			return [::export::open .application -base [CurrentBase] -variant [CurrentVariant] -view 0 -name [::util::databaseName [CurrentBase] no] -extension pgn]
		}
		menu.file.export.html {
			return [::export::open .application -base [CurrentBase] -variant [CurrentVariant] -view 0 -name [::util::databaseName [CurrentBase] no] -extension html]
		}
		menu.file.export.archive { return [::menu::dbCreateArchive .application [CurrentBase]] }
		menu.file.export.lichess {
			return [::application::lichess::study::open .application \
				-base [CurrentBase] -variant [CurrentVariant] -view 0 -kind database]
		}
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
				::tk_textCopy [focus]
			} else {
				::application::pgn::editComment after
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
				::application::pgn::editAnnotation
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
			::gamebar::CopyThisGameToClipbase .application [::gamebar::selected $::application::pgn::Vars(gamebar)]
			return
		}
		menu.game.paste_clip { return [::application::pgn::PasteClipboardGame] }
		menu.game.paste_tab { return [::application::pgn::PasteClipboardGame] }
		menu.game.merge_clip { return [::gamebar::mergeGame .application -1] }
		menu.game.merge_tab {
			set current [::scidb::game::current]
			set tabs {}
			catch {
				foreach id [::gamebar::getIdList [::application::pgn::gamebar]] {
					if {$id != $current} { lappend tabs $id }
				}
			}
			if {![llength $tabs]} {
				for {set i 0} {$i < 9} {incr i} {
					if {$i != $current && [::scidb::game::query $i open?]} {
						lappend tabs $i
					}
				}
			}
			set target -1
			if {[llength $tabs]} { set target [lindex $tabs 0] }
			::gamebar::mergeGame .application $target
			return
		}
		game-export { return [::gamebar::exportGame .application] }
		menu.game.export.study {
			return [::application::lichess::study::open .application \
				-base [CurrentBase] -variant [CurrentVariant] -view 0 -kind game]
		}
		menu.game.history.recent {
			if {[::game::historyIsEmpty?]} { return }
			::game::openGame .application 0
			return
		}
		menu.game.history.clear { return [::application::database::ClearHistory] }
		menu.game.close {
			set pos [::gamebar::selected $::application::pgn::Vars(gamebar)]
			if {$pos eq "" || [::gamebar::CheckIfModified .application $pos]} { return }
			::application::pgn::release $pos
			::game::release $pos
			return
		}

		menu.db.search.plain { return [::application::database::OpenPlainSearch .application [CurrentBase] [CurrentVariant]] }
		menu.db.search.advanced { return [::application::database::searchCurrent .application] }
		menu.db.search.material { return [::application::database::OpenMaterialSearch .application [CurrentBase] [CurrentVariant]] }
		menu.db.search.rating { return [::application::database::OpenRatingSearch .application [CurrentBase] [CurrentVariant]] }
		menu.db.search.duplicates { return [::application::database::ShowDuplicates .application [CurrentBase] [CurrentVariant]] }
		menu.db.search.query { return [::application::database::OpenCql6Search .application [CurrentBase] [CurrentVariant]] }
		menu.db.reports.eco { return [::application::database::ShowEcoStats .application [CurrentBase] [CurrentVariant]] }
		menu.db.reports.opening { return [::application::database::ShowOpeningReport .application] }
		menu.db.reports.repertoire { return [::application::database::OpenRepertoireReport .application [CurrentBase] [CurrentVariant]] }
		menu.db.reports.result { return [::application::assistant::runTool check_results {}] }
		menu.db.reports.timecontrol { return [::application::assistant::runTool event_types {}] }
		menu.db.reports.trends { return [::application::assistant::runTool database_trend {}] }
		menu.db.maintenance.compact { return [::application::assistant::runTool compact_database {}] }
		menu.db.maintenance.strip_moves { return [::scidb::game::strip moves] }
		menu.db.maintenance.strip_tags { return [::scidb::game::strip tags] }
		menu.db.maintenance.convert { return [::application::assistant::runTool convert_database {}] }
		menu.db.maintenance.recode { return [::application::database::Recode [CurrentBase] .application] }
		menu.db.maintenance.change_icon { return [::menu::DbProperties] }
		menu.db.discover { return [::application::database::discover::open .application] }
		menu.db.properties { return [::menu::DbProperties] }
		menu.db.readonly {
			set base [CurrentBase]
			if {$base ne ""} {
				set var ::application::database::Vars(flag:readonly)
				set $var [expr {![::scidb::db::get readonly? $base]}]
				::application::database::ToggleReadOnly $var $base
			}
			return
		}
		menu.db.player.update { return [::playerdata::updateFide .application] }
		menu.db.player.names { return [::playerdata::checkSpellings .application] }

		menu.board.start.standard { return [::application::pgn::Shuffle Normal] }
		menu.board.start.chess960 { return [::application::pgn::Shuffle Chess960] }
		menu.board.start.symm960 { return [::application::pgn::Shuffle Symm960] }
		menu.board.start.shuffle { return [::application::pgn::Shuffle Shuffle] }
		menu.board.start.setup { return [::setup::popupPositionMenu ::application::pgn .application] }
		menu.board.set_start_board { return [::application::board::SetStartBoard .application] }
		menu.board.set_start_position { return [::application::board::SetStartPosition .application] }
		board-flip { return [::application::board::Rotate $::application::board::Vars(widget:frame)] }
		board-null-move { return [::application::board::InsertNullMove] }
		menu.board.setup { return [::board::options::openConfigDialog .application ::application::board::Redraw] }
		menu.board.appearance.side { ::menu::ToggleBoardOption side-to-move; return }
		menu.board.appearance.material { ::menu::ToggleBoardOption material-values; return }
		menu.board.appearance.border { ::menu::ToggleBoardOption border; return }
		menu.board.appearance.coordinates { ::menu::ToggleBoardOption coordinates; return }
		menu.board.appearance.small_letters { ::menu::ToggleBoardOption coords-small; return }
		menu.board.appearance.suggested { ::menu::ToggleBoardOption show-suggested ::board::hilite; return }
		menu.board.appearance.arrows { ::menu::ToggleBoardOption variations:arrows ::application::board::Options; return }
		menu.board.appearance.annotation { ::menu::ToggleBoardOption show:annotation ::application::board::Options; return }
		menu.board.tablebase.show { ::menu::ToggleTablebase enabled; return }
		menu.board.tablebase.online { ::menu::ToggleTablebase online; return }
		menu.board.tablebase.local { return [::tablebase::chooseFolder .application] }

		menu.analysis.engine_toggle {
			if {[EngineRunning]} {
				# CloseEngine takes the pane's tree, not the engine number
				set number [lindex [::application::analysis::Running] 0]
				::application::analysis::CloseEngine $::application::analysis::NumberToTree($number)
			} else {
				::application::analysis::startEngine [::application::analysis::defaultEngine]
			}
			return
		}
		menu.analysis.engines { return [::engine::openAdmininstration .application] }
		menu.analysis.engine_dictionary { return [::engine::showEngineDictionary .application] }
		menu.analysis.compare_engines { return [::application::analysis::openComparison .application] }
		menu.analysis.review_engine { return [::ai::engine::chooseDialog .application] }
		menu.analysis.analyze { return [::application::analysis::AnalyzeCurrentPosition] }
		menu.analysis.game_review { return [::gamereview::run .application] }
		menu.analysis.explain.position { return [::application::ai::analyze .application] }
		menu.analysis.explain.line {
			set running [::application::analysis::Running]
			if {![llength $running]} { return [::application::analysis::AnalyzeCurrentPosition] }
			set number [lindex $running 0]
			set tree $::application::analysis::NumberToTree($number)
			set best [::application::analysis::BestLine $tree]
			if {![llength $best]} { return }
			set row [lindex $best 0]
			return [::application::ai::explainLine .application \
				[set ${tree}::Vars(pv:$row)] [::scidb::pos::fen]]
		}
		menu.analysis.explain.move { return [::application::pgn::ExplainMove .application::pgn ""] }
		menu.analysis.explain.comment {
			set pos after
			if {[info exists ::comment::Vars(pos)]} {
				set pos $::comment::Vars(pos)
			} elseif {[catch {::scidb::game::query comment after} c1] || [string trim $c1] eq ""} {
				if {![catch {::scidb::game::query comment before} c2] && [string trim $c2] ne ""} {
					set pos before
				}
			}
			return [::application::ai::explainComment .application $pos]
		}
		menu.analysis.annotate { return [::ai::annotate::toggle .application] }
		menu.analysis.factcheck { return [::ai::factcheck::current .application] }
		menu.analysis.tablebase.show { ::menu::ToggleTablebase enabled; return }
		menu.analysis.tablebase.online { ::menu::ToggleTablebase online; return }
		menu.analysis.tablebase.local { return [::tablebase::chooseFolder .application] }
		menu.analysis.explorer { return [::menu::TogglePaneId explorer] }

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
		menu.tools.player_card { return [::playercard::setupPrivateCard .application] }
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
				::application::twm::SaveLayout $twm $twm \
					::application::twm::DoSaveLayout {} $::application::twm::mc::SaveLayout
			}
			return
		}
		menu.view.layout.manage {
			set twm [CurrentTWM]
			if {$twm ne ""} {
				set layoutId $::application::Vars($twm:id)
				::application::layout::open $twm $layoutId \
					$::application::Vars($layoutId:layout:variant) \
					[::application::twm::currentLayoutName $twm]
			}
			return
		}
		menu.view.font_inc { after idle { ::font::changeFontSize +1 }; return }
		menu.view.font_dec { after idle { ::font::changeFontSize -1 }; return }
		app-fullscreen { return [::menu::viewFullscreen toggle] }
		app-log { return [::log::show -force] }
		menu.view.tip { return [::tips::open .application] }

		app-help { return [::help::open .application] }
		menu.help.bug { return [::menu::bugReport .application] }
		menu.help.feature { return [::menu::featureRequest .application] }
		menu.help.support { return [::menu::support .application] }
		menu.help.about {
			if {[tk windowingsystem] eq "aqua"} { return [::menu::MacAbout] }
			return [::info::openDialog .application]
		}

		menu.view.panes.board { return [::menu::TogglePaneId board] }
		menu.view.panes.editor { return [::menu::TogglePaneId editor] }
		menu.view.panes.games { return [::menu::TogglePaneId games] }
		menu.view.panes.players { return [::menu::TogglePaneId players] }
		menu.view.panes.events { return [::menu::TogglePaneId events] }
		menu.view.panes.sites { return [::menu::TogglePaneId sites] }
		menu.view.panes.annotators { return [::menu::TogglePaneId annotators] }
		menu.view.panes.positions { return [::menu::TogglePaneId positions] }
		menu.view.panes.tree { return [::menu::TogglePaneId tree] }
		menu.view.panes.analysis { return [::menu::TogglePaneId analysis] }
		menu.view.panes.media { return [::menu::TogglePaneId media] }
		menu.view.panes.report { return [::menu::TogglePaneId report] }
		menu.view.panes.assistant { return [::menu::TogglePaneId assistant] }
		menu.view.panes.explorer { return [::menu::TogglePaneId explorer] }
		view.pane_zoom {
			::application::switchTab board
			return [::application::TogglePaneZoom {} [PaneTWM]]
		}
		view.focus_zoom {
			set twm [PaneTWM]
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

# The board header uses checkbuttons, which change the variable before
# invoking the callback. Registry actions must perform that change themselves.
proc ::menu::ToggleTablebase {option} {
	set ::tablebase::Options($option) [expr {!$::tablebase::Options($option)}]
	::tablebase::toggle
	return
}

proc ::menu::ToggleBoardOption {option {arrayName ::board::layout}} {
	upvar #0 $arrayName options
	set options($option) [expr {!$options($option)}]
	::application::board::Redraw
	return
}

# The key-editor ids are registry ids (VAL-REG-003). Do this after the
# drop-down module is loaded; ::menu::Register later refreshes the
# placement of the ids the drop-down also carries.
::application::keyEditor::RegisterActions

# Form controls and assistant operations share the same persistent settings APIs.
proc ::menu::CloseNamedDialog {arguments} {
	set windows [dict create about .application.infoDialog correspondence .application.corrGames \
		engine_dictionary .application.engineDict iccf .application.iccfSettings \
		keyboard .application.shortcutPreferences pgn .application.pgnOptions \
		player_dictionary .application.playerDict review_engine .application.__aiengine__]
	if {[dict get $arguments dialog] eq "crosstable"} {
		set window $::crosstable::Reuse
		if {$window eq ""} {return "dialog closed"}
	} else {set window [dict get $windows [dict get $arguments dialog]]}
	if {[winfo exists $window]} { destroy $window }
	return "dialog closed"
}

proc ::menu::RunDialogOperation {kind arguments} {
	set operation [dict get $arguments operation]
	switch -- $kind {
		keyboard {
			set action [dict get $arguments action]
			switch -- $operation {
				list {
					set result {}
					foreach entry $::application::keyEditor::Actions {
						set id [lindex $entry 0]
						dict set result $id [::application::keyEditor::CurrentKey $id]
					}
					return $result
				}
				set - reset {
					if {$action eq ""} { return [Do menu.edit.keyboard] }
					set found 0
					foreach entry $::application::keyEditor::Actions {
						if {[lindex $entry 0] eq $action} { set found 1; break }
					}
					if {!$found} { error "unknown key action: $action" }
					if {$operation eq "set"} {
						if {[dict get $arguments key] eq ""} { return [Do menu.edit.keyboard] }
						::application::keyEditor::SetKey $action [dict get $arguments key]
					} else { ::application::keyEditor::ResetAction $action }
				}
				reset_all { ::application::keyEditor::ResetAll }
			}
			set tree .application.shortcutPreferences.content.keys.list.tree
			if {[winfo exists $tree]} { ::application::keyEditor::FillTable $tree }
			return "keyboard preferences updated"
		}
		pgn-options {
			::export::migrateOptions
			set option [dict get $arguments option]
			if {$option eq "compatibility_format"} { set option use_chessbase_format }
			if {$operation eq "set"} {
				if {$option eq ""} { return [Do menu.edit.preferences.pgn] }
				set value [dict get $arguments value]
				if {$value && $option in {use_chessbase_format use_scidb_import_format use_strict_pgn_standard}} {
					foreach other {use_chessbase_format use_scidb_import_format use_strict_pgn_standard} {
						set ::export::Values(pgn,flag,$other) 0
					}
				}
				set ::export::Values(pgn,flag,$option) $value
			} elseif {$operation eq "reset"} {
				foreach field [array names ::export::Defaults pgn,flag,*] {
					set ::export::Values($field) $::export::Defaults($field)
				}
			}
			set frame .application.pgnOptions.options
			if {[winfo exists $frame]} { ::export::options::SetupFlags $frame pgn }
			set result {}
			foreach field $::export::Fields(pgn) {
				set name $field
				if {$name eq "use_chessbase_format"} { set name compatibility_format }
				dict set result $name $::export::Values(pgn,flag,$field)
			}
			return $result
		}
		log {
			if {$operation eq "clear"} {
				if {[winfo exists $::log::Log.top.text]} { ::log::Clear }
			} elseif {[winfo exists $::log::Log]} { wm withdraw $::log::Log }
			return "log $operation complete"
		}
		engine-log {
			set dialog .application.engineLog
			if {$operation eq "clear"} {
				if {[winfo exists $dialog.top.text]} { ::engine::ClearLog $dialog.top.text }
			} else { ::engine::CloseLog $dialog }
			return "engine console $operation complete"
		}
	}
}

# Supplied session arguments use the same execution APIs as the native forms.
proc ::menu::RunSessionOperation {kind arguments} {
    set operation [dict get $arguments operation]
    switch -- $kind {
        comparison {
            switch -- $operation {
                start {
                    set names [dict get $arguments engines]
                    if {[llength $names] < 2} { return [::application::analysis::openComparison .application] }
                    foreach name $names {
                        if {[::engine::FindIndex $name] < 0 || ![::application::analysis::CanAnalyse $name]} {
                            error "engine cannot analyse: $name"
                        }
                    }
                    ::application::analysis::StartNamedComparison $names [dict get $arguments seconds]
                }
                stop { ::application::analysis::FinishComparison }
                close { ::application::analysis::CloseComparison }
            }
            return [dict create lines [::application::analysis::ComparisonLines] timer $::application::analysis::compare::Vars(after)]
        }
        engine-admin {
            set name [dict get $arguments engine]
            switch -- $operation {
                list { return $::engine::Engines }
                add {
                    set filename [dict get $arguments filename]
                    if {$filename eq ""} { return [::engine::openAdmininstration .application] }
                    return [::engine::install $filename]
                }
                delete { return [::action::run remove_engine [dict create engine $name]] }
                update - clear_usage { return [::engine::updateEntry $name $arguments] }
                webpage {
                    set index [::engine::FindIndex $name]
                    if {$index < 0} { error "no engine named '$name'" }
                    set url [dict get [lindex $::engine::Engines $index] Url]
                    if {$url eq ""} { error "engine has no webpage" }
                    return [::web::open .application $url]
                }
                close {
                    if {[winfo exists .application.adminEngines]} {
                        if {[dict exists $arguments discard]} {
                            if {![dict get $arguments discard] && ![::arrayEqual ::engine::Data ::engine::Data_]} {
                                error "unsaved engine fields; supply discard true to close"
                            }
                            destroy .application.adminEngines
                        } else {
                            ::engine::CloseSetup .application.adminEngines.top.list
                        }
                    }
                    return closed
                }
            }
        }
        correspondence {
            switch -- $operation {
                sync { return [::iccf::xfcc::getGames] }
                refresh { return [dict create games [::application::corr::games::localGames [dict get $arguments filter]]] }
                open {
                    set number [dict get $arguments number]
                    if {$number < 1} { return [::application::corr::games::open .application] }
                    return [::game::new .application -base [CurrentBase] -number [expr {$number-1}] -variant [CurrentVariant]]
                }
            }
        }
        private-card { return [::playercard::runOperation $arguments] }
        training-set {
            switch -- $operation {
                start {
                    set spec {}
                    foreach key {patterns player max scan depth} { lappend spec -$key [dict get $arguments $key] }
                    lappend spec -file [dict get $arguments filename]
                    return [::ai::cql::training .application {*}$spec]
                }
                cancel { set ::ai::cql::Priv(cancel) 1 }
            }
            return [dict create running $::ai::cql::Priv(running)]
        }
        download {
            switch -- $operation {
                start {
                    set base [dict get $arguments base]
                    if {$base eq ""} { set base [CurrentBase] }
                    set spec {}
                    foreach key {source issues lichess studies broadcast refresh url site player months} {
                        dict set spec -$key [dict get $arguments $key]
                    }
                    set ::menu::DownloadResult {}
                    ::application::download::run $base $spec ::menu::DownloadDone
                }
                cancel { ::application::download::Close }
            }
            return [dict create running $::application::download::Priv(running) result $::menu::DownloadResult]
        }
        review-engine {
            switch -- $operation {
                list { return [::ai::engine::uciEngines] }
                select { ::ai::engine::select [dict get $arguments engine] }
            }
            return [dict create engine $::ai::engine::Options(engine)]
        }
        iccf-settings {
            if {$operation eq "save"} {
                ::iccf::xfcc::configure [dict get $arguments username] [dict get $arguments password] [dict get $arguments endpoint]
            }
            # Credentials never enter the assistant reply.
            return [dict create configured [::iccf::xfcc::configured?] endpoint $::iccf::xfcc::Config(endpoint)]
        }
        game-review {
            switch -- $operation {
                start { return [::gamereview::run .application -depth [dict get $arguments depth]] }
                cancel { return [::gamereview::cancel] }
                status { return [dict create running [::gamereview::running?]] }
            }
        }
        play-engine {
            switch -- $operation {
                start {
                    set engine [dict get $arguments engine]
                    if {$engine eq ""} { return [::playengine::open .application] }
                    set spec {}
                    foreach key {engine color minutes increment movetime elo skill} {
                        lappend spec -$key [dict get $arguments $key]
                    }
                    return [::playengine::StartGame $spec]
                }
                move { return [::playengine::UserMove [dict get $arguments move]] }
                resign { ::playengine::Resign }
                offer_draw { ::playengine::OfferDraw }
                takeback { ::playengine::Takeback }
                close { ::playengine::Close }
            }
            set status ""
            if {[info exists ::playengine::Priv(statusText)]} {set status $::playengine::Priv(statusText)}
            return [dict create active $::playengine::Priv(active) phase $::playengine::Priv(phase) status $status]
        }
        engine-match {
            switch -- $operation {
                open { return [::enginematch::open .application] }
                start {
                    if {[llength [dict get $arguments engines]] < 2} { return [::enginematch::open .application] }
                    set spec {}
                    foreach key {mode engines games minutes increment movetime suite} {
                        lappend spec -$key [dict get $arguments $key]
                    }
                    set base [dict get $arguments base]
                    if {$base eq ""} { set base $::scidb::clipbaseName }
                    lappend spec -base $base -suitePlies [dict get $arguments suite_plies] \
                        -tb [dict get $arguments tablebase] -online [dict get $arguments online]
                    ::enginematch::open .application
                    if {![::enginematch::StartMatch $spec]} {
                        return -code error -errorcode {CHESSWIZ PRECONDITION match} $::enginematch::Priv(lastError)
                    }
                    return 1
                }
                close { ::enginematch::Close }
            }
            return [dict create running $::enginematch::Priv(running) saved $::enginematch::Priv(saved)]
        }
    }
}

proc ::menu::DownloadDone {result} {
    set ::menu::DownloadResult $result
}
namespace eval ::menu { variable DownloadResult {} }

# Share the native Help teardown, which also cancels its document callbacks.
proc ::menu::CloseHelp {arguments} {
    ::help::Destroy
    return "Help closed"
}
