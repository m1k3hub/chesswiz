# ======================================================================
# ::context -- the per-object context menus (PROPOSAL section 3, C1-C12)
#
# ONE builder per object type. Every row is an action registered in
# ::action with a context tag (C1..C12); the menu is generated from that
# registry record (label, accelerator, enabled/visible predicate), so a
# feature added to the registry is reachable by right-click and by the
# assistant at once.
#
# The first row of every posted menu is "What can I do here?" (decision
# 004). It passes a structured record of the clicked object to the
# assistant, through the egress gate in tcl/ai-egress.tcl.
#
# A menu with no object under the pointer is not posted at all (R8).
#
#   ::context::build <C1..C12> <menu> <object-dict>
#   ::context::post  <C1..C12> <menu> <object-dict> ?x y?
#   ::context::rows  <C1..C12> <object-dict>
#   ::context::ask   <C1..C12> <object-dict>
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source context
}

package require Tcl 8.5

namespace eval ::context {
	variable Menus [dict create]
	variable Labels
	variable Keys
	variable Contexts
	variable Flags
	variable Counter 0
	variable LastMenu ""
	variable AssistantSink ""
	variable LastRecord ""
}

namespace eval ::context::mc {
	set WhatCanIDo		"What can I do here?"
	set Withheld		"Not sent: this request would carry private data. Withheld: %s."
	set NothingToPost	"There is nothing to show for this object."

	# English defaults, restored before every language load.
	set ::context::DefaultMC {}
	foreach _name [lsort [info vars]] {
		if {[array exists $_name] || [string index [namespace tail $_name] 0] eq "_"} { continue }
		lappend ::context::DefaultMC [namespace tail $_name] [set $_name]
	}
	unset _name
}

proc ::context::ResetMC {} {
	foreach {name value} $::context::DefaultMC {
		set ::context::mc::$name $value
	}
	return
}
::mc::addDefaultReset ::context::ResetMC

# ----------------------------------------------------------------------
# Small helpers (Tcl 8.5: no dict get?).
# ----------------------------------------------------------------------
proc ::context::LabelVar {id} {
	return [string map {. _ : _ - _} $id]
}

proc ::context::L {id} {
	variable Labels
	set var [LabelVar $id]
	# English is the source language: use the defaults in this file, so
	# switching back to English clears a previous translation.
	if {[info exists ::mc::langID] && $::mc::langID eq "en"} {
		if {[info exists Labels($id)]} { return $Labels($id) }
	}
	if {[info exists ::context::mc::$var]} { return [set ::context::mc::$var] }
	if {[info exists Labels($id)]} { return $Labels($id) }
	return $id
}

proc ::context::Key {id} {
	variable Keys
	if {[info exists Keys($id)]} { return $Keys($id) }
	return ""
}


# Register one menu row as a registry action. <contexts> is the list of
# C1..C12 menus the row appears in.
proc ::context::Item {id text contexts {keys {}} {visible {}} {enabled {}}} {
	variable Labels
	variable Keys
	variable Contexts

	set Labels($id) $text
	set Keys($id) $keys
	set Contexts($id) $contexts
	# One translateable variable per row; language files override it.
	set var [LabelVar $id]
	if {![info exists ::context::mc::$var]} {
		namespace eval ::context::mc [list set $var $text]
	}

	if {![dict exists $::action::Registry $id]} {
		::action::register $id [dict create \
			label $text \
			object {} \
			args {{object {type string default {}}}} \
			handler [list ::context::InvokeArgs $id] \
			what $text \
			ai 0 \
			context $contexts \
			doc $text \
		]
	} else {
		set record [::action::get $id]
		dict set record context $contexts
		dict set ::action::Registry $id $record
	}
	if {$visible ne ""} {
		dict set ::context::Predicates $id visible $visible
	}
	if {$enabled ne ""} {
		dict set ::context::Predicates $id enabled $enabled
	}
	return $id
}

# The assistant row is a registry action too (VAL-REG-002): the context id
# and the object travel as action arguments, so the menu command can stay
# exactly [::action::run context.ask <args>].
proc ::context::RegisterCore {} {
	variable CoreRegistered

	if {[info exists CoreRegistered]} { return }
	set CoreRegistered 1
	if {[dict exists $::action::Registry context.ask]} { return }
	::action::register context.ask [dict create \
		label $::context::mc::WhatCanIDo \
		object {} \
		args {{object {type string default {}}} {cid {type string default C1}}} \
		handler ::context::AskArgs \
		what {} \
		ai 0 \
		context {C1 C2 C3 C4 C5 C6 C7 C8 C9 C10 C11 C12} \
		doc "Ask the assistant about this position" \
	]
}

proc ::context::InvokeArgs {id argsDict} {
	set object {}
	if {[dict exists $argsDict object]} { set object [dict get $argsDict object] }
	return [Invoke $id $object]
}

proc ::context::AskArgs {argsDict} {
	set cid C1
	if {[dict exists $argsDict cid]} { set cid [dict get $argsDict cid] }
	set object {}
	if {[dict exists $argsDict object]} { set object [dict get $argsDict object] }
	return [Ask $cid $object]
}

namespace eval ::context {
	variable Predicates [dict create]
}

proc ::context::Define {cid rows} {
	variable Menus
	dict set Menus $cid [list list $rows]
	return
}

proc ::context::DefineObject {cid key rows} {
	variable Menus
	if {![dict exists $Menus $cid]} {
		dict set Menus $cid [list map [dict create]]
	}
	set entry [dict get $Menus $cid]
	if {[lindex $entry 0] eq "list"} {
		set map [dict create default [lindex $entry 1]]
	} else {
		set map [lindex $entry 1]
	}
	dict set map $key $rows
	dict set Menus $cid [list map $map]
	return
}

# ----------------------------------------------------------------------
# Rows: the declared menus. A row is one of
#   -                       separator
#   ask                     the assistant row
#   {header <kind>}         a disabled header (database/column/history)
#   {cascade <id> {ids...}} one cascade
#   <id>                    one action row
# ----------------------------------------------------------------------
proc ::context::Declare {} {
	# --- C1: board square / position -------------------------------
	Item c1.set_start_board		"Set Start Board…"			C1
	Item c1.set_start_position	"Set Start Position…"		C1
	Item c1.start_position		"Start Position"			C1
	Item c1.start.standard		"Standard"					C1
	Item c1.start.chess960		"Chess960"					C1
	Item c1.start.symm960		"Symm960"					C1
	Item c1.start.shuffle		"Shuffle"					C1
	Item c1.start.setup			"Set Up Position…"			C1
	Item c1.insert_null			"Insert Null Move"			C1 {Control-0 Ctrl+0} {[GameLoaded] && ![GameOver]}
	Item c1.flip_board			"Flip Board"				C1 {Control-f Ctrl+F}
	Item c1.copy_fen			"Copy FEN"					C1
	Item c1.copy_diagram		"Copy Diagram"				C1
	Item c1.edit_annotation		"Edit Annotation…"			{C1 C2} {Control-a Ctrl+A}
	Item c1.board_setup			"Board Setup…"				C1 {} {} {![BoardSetupOpen]}
	Define C1 {
		ask -
		c1.set_start_board
		c1.set_start_position
		{cascade c1.start_position {c1.start.standard c1.start.chess960 c1.start.symm960 c1.start.shuffle c1.start.setup}}
		-
		c1.insert_null
		-
		c1.flip_board
		-
		c1.copy_fen
		c1.copy_diagram
		c1.edit_annotation
		-
		c1.board_setup
	}

	# --- C2: a move in the notation --------------------------------
	Item c2.load_continuation	"Load First Game with this Continuation"	C2 {l L}
	Item c2.replace_move		"Replace Move"				C2 {r R}
	Item c2.add_variation		"Add New Variation"			C2 {v V}
	Item c2.new_main_line		"New Main Line"				C2
	Item c2.try_variation		"Try Variation"				C2 {t T}
	Item c2.exchange_move		"Exchange Move"				C2
	Item c2.promote_variation	"Promote Variation"			C2
	Item c2.remove_variation	"Remove Variation"			C2
	Item c2.comment_after		"Edit Comment After"		C2 {Control-c Ctrl+C}
	Item c2.comment_before		"Edit Comment Before"		C2 {Control-Shift-c Ctrl+Shift+C}
	Item c2.marks_palette		"Marks Palette…"			C2 {Control-m Ctrl+M}
	Item c2.move_info			"Edit Move Information…"	C2
	Item c2.annotate			"Annotate"					C2
	Item c2.annot.prefix		"Prefix symbols"			C2
	Item c2.annot.infix			"Infix symbols"				C2
	Item c2.annot.suffix		"Suffix symbols"			C2
	Item c2.explain_move		"Explain Move"				C2
	Item c2.insert_diagram		"Insert Diagram"			C2
	Item c2.insert_diagram_black "Insert Diagram from Black" C2
	Item c2.strip				"Strip"						C2
	Item c2.strip.moves			"Moves"						C2
	Item c2.strip.truncate		"Truncate"					C2
	Item c2.strip.variations	"Variations"				C2
	Item c2.strip.annotations	"Annotations"				C2
	Item c2.strip.info			"Move information"			C2
	Item c2.strip.marks			"Marks"						C2
	Item c2.strip.comments		"Comments"					C2
	Item c2.strip.language		"Language"					C2
	Item c2.copy_comments		"Copy Comments…"			C2
	Item c2.import_game		"Import PGN Game…"			C2
	Item c2.import_variation	"Import PGN Variation…"		C2
	Item c2.undo				"Undo …"					C2 {Control-z Ctrl+Z}
	Item c2.redo				"Redo …"					C2 {Control-y Ctrl+Y}
	Item c2.collapse			"Collapse Variations"		C2
	Item c2.expand				"Expand Variations"			C2
	Define C2 {
		ask
		-
		c2.load_continuation
		-
		c2.replace_move
		c2.add_variation
		c2.new_main_line
		c2.try_variation
		c2.exchange_move
		c2.promote_variation
		c2.remove_variation
		-
		c2.comment_after
		c2.comment_before
		c1.edit_annotation
		c2.marks_palette
		c2.move_info
		{cascade c2.annotate {c2.annot.prefix c2.annot.infix c2.annot.suffix}}
		-
		c2.explain_move
		-
		c2.insert_diagram
		c2.insert_diagram_black
		-
		{cascade c2.strip {c2.strip.moves c2.strip.truncate c2.strip.variations c2.strip.annotations c2.strip.info c2.strip.marks {cascade c2.strip.comments {c2.strip.language}}}}
		c2.copy_comments
		c2.import_game
		c2.import_variation
		-
		c2.undo
		c2.redo
		c2.collapse
		c2.expand
	}

	# --- C3: a game row in the game list ---------------------------
	Item c3.load				"Load Game"					C3 {space Space}
	Item c3.browse				"Browse Game…"				C3 {w W}
	Item c3.overview			"Overview…"					C3 {o O}
	Item c3.games_like			"Games Like This…"			C3
	Item c3.ask_about_game		"Ask About This Game"		C3
	Item c3.tournament			"Show Tournament Table…"	C3 {t T}
	Item c3.open_url			"Open URL"					C3 {u U}
	Item c3.merge				"Merge Game…"				C3
	Item c3.edit_characteristics "Edit Characteristics…"	C3
	Item c3.delete				"Delete / Undelete Game"	C3
	Item c3.flags				"Flags"						C3
	# The flags are the same set for every database; custom names come
	# from the database and are looked up when the menu is built.
	set flagRows {}
	if {[llength [info commands ::gamestable::column]]} {
		set flagId 0
		foreach flag {w b m e N p T K Q ! ? U * D G S ^ ~ =} {
			if {[info exists ::gamestable::mc::GameFlags($flag)]} {
				set text [set ::gamestable::mc::GameFlags($flag)]
			} else {
				set text $flag
			}
			set id c3.flag.[incr flagId]
			set Flags($id) $flag
			Item $id $text C3
			lappend flagRows $id
		}
	}
	Item c3.copy_game			"Copy Game"					C3 {Control-c Ctrl+C}
	Item c3.paste_games			"Paste Game(s)"				C3 {Control-v Ctrl+V} {![ClipboardEmpty]} {}
	Item c3.sort_column			"Sort by this Column"		C3
	Item c3.sort_asc			"Sort Ascending"			C3
	Item c3.sort_desc			"Sort Descending"			C3
	Item c3.sort.column			"Date"						C3
	Item c3.sort.asc			"Ascending"					C3
	Item c3.sort.desc			"Descending"				C3
	Define C3 {
		ask
		-
		c3.load
		c3.browse
		c3.overview
		-
		c3.games_like
		c3.ask_about_game
		c3.tournament
		c3.open_url
		-
		c3.merge
		c3.edit_characteristics
		c3.delete
		{cascade c3.flags {}}
		c3.copy_game
		c3.paste_games
		-
		{cascade c3.sort_column {c3.sort.column}}
		{cascade c3.sort_asc {c3.sort.asc}}
		{cascade c3.sort_desc {c3.sort.desc}}
	}
	# The flags submenu is populated from the static flag table above.
	variable Menus
	if {[llength $flagRows]} {
		set rows [lindex [dict get $Menus C3] 1]
		set at [lsearch -exact $rows {cascade c3.flags {}}]
		if {$at >= 0} {
			set rows [lreplace $rows $at $at [list cascade c3.flags $flagRows]]
			dict set Menus C3 [list list $rows]
		}
	}

	# --- C4: a database in the switcher ----------------------------
	Item c4.properties			"Properties…"				C4
	Item c4.open_new_tab		"Open in New Tab"			C4
	Item c4.close				"Close"						C4
	Item c4.search				"Search"					C4
	Item c4.search.current		"Current game"				C4
	Item c4.maintenance		"Maintenance"				C4
	Item c4.maintenance.compact "Compact database"			C4
	Item c4.reports			"Reports"					C4
	Item c4.reports.opening	"Opening report"			C4
	Item c4.import				"Import"					C4
	Item c4.import.pgn			"PGN file…"					C4
	Item c4.export				"Export"					C4
	Item c4.export.pgn			"PGN file…"					C4
	Item c4.download_games		"Download Games…"			C4
	Item c4.save_changes		"Save Changes"				C4
	Item c4.readonly			"Read-only"					C4
	Item c4.new_database		"New Database"				C4
	Item c4.new.scid			"Chesswiz database…"		C4
	Item c4.new.pgn			"PGN file…"					C4
	Item c4.open_database		"Open Database…"			C4
	Item c4.open_recent		"Open Recent"				C4
	Item c4.symbol_size		"Symbol Size"				C4
	Item c4.symbol.small		"Small"						C4
	Item c4.symbol.normal		"Normal"					C4
	Item c4.symbol.large		"Large"						C4
	Item c4.help				"Help…"						C4
	Define C4 {
		ask
		-
		{header database}
		c4.properties
		c4.open_new_tab
		c4.close
		-
		{cascade c4.search {c4.search.current}}
		{cascade c4.maintenance {c4.maintenance.compact}}
		{cascade c4.reports {c4.reports.opening}}
		{cascade c4.import {c4.import.pgn}}
		{cascade c4.export {c4.export.pgn}}
		c4.download_games
		c4.save_changes
		c4.readonly
		-
		{cascade c4.new_database {c4.new.scid c4.new.pgn}}
		c4.open_database
		{cascade c4.open_recent {}}
		-
		{cascade c4.symbol_size {c4.symbol.small c4.symbol.normal c4.symbol.large}}
		c4.help
	}
	# A base-less switcher menu (R5): new/open/recent only.
	DefineObject C4 empty {
		ask
		-
		{cascade c4.new_database {c4.new.scid c4.new.pgn}}
		c4.open_database
		{cascade c4.open_recent {}}
	}

	# --- C5: player / event / site --------------------------------
	Item c5.player_card		"Show Player Card"			C5 {} {[::capability::present playercard]}
	Item c5.prep_report		"Prep Report…"				C5
	Item c5.insights			"Insights…"					C5 {} {[::capability::present insights]}
	Item c5.player_url		"Open URL"					C5
	Item c5.event_table		"Show Tournament Table…"	C5
	Item c5.event_url			"Open URL"					C5
	Item c5.site_url			"Open URL"					C5
	Item c5.open_switcher		"Open Games in Switcher"	C5
	Item c5.save_working_set	"Save as Working Set"		C5
	Item c5.player.prep		"Prep Report"				C5
	Item c5.player.insights	"Insights"					C5 {} {[::capability::present insights]}
	DefineObject C5 player {
		ask
		-
		c5.player_card
		-
		c5.prep_report
		c5.insights
		-
		{cascade c5.player_url {}}
		-
		c5.open_switcher
		c5.save_working_set
	}
	DefineObject C5 event {
		ask
		-
		c5.event_table
		c5.event_url
		-
		c5.open_switcher
		c5.save_working_set
	}
	DefineObject C5 site {
		ask
		-
		c5.site_url
		-
		c5.open_switcher
		c5.save_working_set
	}

	# --- C6: an engine line in the analysis pane ------------------
	Item c6.add_move			"Add Move"					C6
	Item c6.add_sequence		"Add Sequence"				C6
	Item c6.add_line			"Add Line"					C6
	Item c6.add_all			"Add All"					C6
	Item c6.add_merge			"Add Merge"					C6
	Item c6.add_include		"Add Include"				C6
	Item c6.insert_comment		"Insert Move as Comment"	C6
	Item c6.explain_line		"Explain Line"				C6
	Item c6.copy_line			"Copy Line"					C6
	Item c6.copy_fen			"Copy FEN"					C6
	Item c6.pause_resume		"Pause / Resume"			C6
	Item c6.close_engine		"Close Engine"				C6
	Item c6.lock_engine		"Lock Engine"				C6
	Item c6.opponents_view		"Opponents View"			C6
	Item c6.best_first			"Best-First Order"			C6
	Item c6.multiple_variations "Multiple Variations"		C6
	Item c6.multi.1			"1"							C6
	Item c6.multi.2			"2"							C6
	Item c6.multi.3			"3"							C6
	Item c6.multi.4			"4"							C6
	Item c6.multi.5			"5"							C6
	Item c6.multi.6			"6"							C6
	Item c6.multi.7			"7"							C6
	Item c6.multi.8			"8"							C6
	Item c6.lines_per_variation "Lines per Variation"		C6
	Item c6.lines.1			"1"							C6
	Item c6.lines.2			"2"							C6
	Item c6.lines.3			"3"							C6
	Item c6.lines.4			"4"							C6
	Item c6.setup_engine		"Setup Engine…"				C6
	Item c6.setup_eval_edges	"Setup Eval Edges…"			C6
	Define C6 {
		ask
		-
		c6.add_move
		c6.add_sequence
		c6.add_line
		c6.add_all
		c6.add_merge
		c6.add_include
		c6.insert_comment
		-
		c6.explain_line
		c6.copy_line
		c6.copy_fen
		-
		c6.pause_resume
		c6.close_engine
		c6.lock_engine
		c6.opponents_view
		c6.best_first
		{cascade c6.multiple_variations {c6.multi.1 c6.multi.2 c6.multi.3 c6.multi.4 c6.multi.5 c6.multi.6 c6.multi.7 c6.multi.8}}
		{cascade c6.lines_per_variation {c6.lines.1 c6.lines.2 c6.lines.3 c6.lines.4}}
		c6.setup_engine
		c6.setup_eval_edges
	}

	# --- C7: a media entry ----------------------------------------
	Item c7.play			"Play"						C7
	Item c7.open_report		"Open Report"				C7
	Item c7.open_stream		"Open Stream…"				C7 {} {[::capability::present stream]}
	Item c7.external			"Open in External Player"	C7
	Item c7.show_in_board	"Show in Board"				C7
	Item c7.sync_options	"Sync Options"				C7
	Item c7.sync.position	"Position follow"			C7
	Item c7.sync.timeline	"Timeline"					C7
	Define C7 {
		ask
		-
		c7.play
		-
		c7.open_report
		c7.open_stream
		c7.external
		-
		c7.show_in_board
		{cascade c7.sync_options {c7.sync.position c7.sync.timeline}}
	}

	# --- C8: a tree row -------------------------------------------
	Item c8.move_actions		"move actions for this continuation"	C8
	Item c8.analyze			"Analyze This Position"		C8 {f4 F4}
	Item c8.start_search		"Start Search"				C8
	Item c8.search_mode		"Search Mode"				C8
	Item c8.search.exact		"Exact"						C8
	Item c8.search.slow		"Slow"						C8
	Item c8.search.fast		"Fast"						C8
	Item c8.automatic			"Automatic Search"			C8
	Item c8.inside_variations "Search Inside Variations"	C8
	Item c8.highlight			"Highlight Novelties"		C8
	Item c8.opening_report		"Opening Report…"			C8
	Item c8.reference_base		"Reference Base"			C8
	Item c8.reference.none		"None"						C8
	Item c8.lock_reference		"Lock Reference Base"		C8
	Item c8.copy_line			"Copy Line"					C8
	Item c8.save_line			"Save Line to Repertoire…"	C8
	Define C8 {
		ask
		-
		c8.move_actions
		c8.analyze
		-
		c8.start_search
		{cascade c8.search_mode {c8.search.exact c8.search.slow c8.search.fast}}
		c8.automatic
		c8.inside_variations
		c8.highlight
		c8.opening_report
		-
		{cascade c8.reference_base {c8.reference.none}}
		c8.lock_reference
		-
		c8.copy_line
		c8.save_line
	}

	# --- C9: a pane header (per-pane table) -----------------------
	Item c9.appearance		"Appearance"				C9
	Item c9.board_setup		"Board Setup…"				C9
	Item c9.tablebase		"Show Tablebase"			C9 {} {[::capability::present tablebase]}
	Item c9.flip_board		"Flip Board"				C9
	Item c9.start_position	"Start Position"			C9
	Item c9.not.display		"Display"					C9
	Item c9.not.font			"Font Size"					C9
	Item c9.not.font_inc		"Increase"					C9
	Item c9.not.font_dec		"Decrease"					C9
	Item c9.not.font_reset	"Reset"						C9
	Item c9.not.spacing		"Spacing"					C9
	Item c9.not.numbering		"Numbering"					C9
	Item c9.not.markers		"Markers"					C9
	Item c9.not.diagrams		"Diagrams"					C9
	Item c9.not.emoticons		"Emoticons"					C9
	Item c9.not.configure		"Configure Notation…"		C9
	Item c9.not.move_notation "Move Notation"			C9
	Item c9.not.move_info		"Move Info"					C9
	Item c9.not.language		"Language Selection"		C9
	Item c9.games.columns		"Columns"					C9
	Item c9.games.sort		"Sort"						C9
	Item c9.games.filters		"Filters"					C9
	Item c9.games.presets		"Save Search Presets"		C9
	Item c9.table.filter		"Filter"					C9
	Item c9.tree.search_mode	"Search Mode"				C9
	Item c9.tree.automatic	"Automatic Search"			C9
	Item c9.tree.novelties	"Highlight Novelties"		C9
	Item c9.tree.reference	"Reference Base"			C9
	Item c9.analysis.setup	"Set Up Engine…"			C9
	Item c9.analysis.multi	"Multiple Variations"		C9
	Item c9.analysis.lines	"Lines per Variation"		C9
	Item c9.analysis.opponents "Opponents View"			C9
	Item c9.analysis.best	"Best-First Order"			C9
	Item c9.media.show		"Show in Board"				C9
	Item c9.media.sync		"Sync Options"				C9
	Item c9.media.stream		"Open Stream…"				C9
	Item c9.report.font		"Font"						C9
	Item c9.report.size		"Size"						C9
	Item c9.report.family		"Family"					C9
	Item c9.report.print		"Print…"					C9
	Item c9.report.zoom		"Zoom"						C9
	Item c9.assistant.clear	"Clear Conversation"		C9
	Item c9.assistant.model	"Choose Model…"				C9
	Item c9.assistant.source	"Source"					C9
	Item c9.assistant.local	"Local"						C9
	Item c9.assistant.cloud	"Cloud"						C9
	Item c9.explorer.tablebase "Online Tablebase"		C9 {} {[::capability::present explorer]}
	Item c9.explorer.source	"Source"					C9 {} {[::capability::present explorer]}
	Item c9.maximise			"Maximise/Restore Pane"		C9
	Item c9.fold				"Fold Title Bar"			C9
	Item c9.amalgamate		"Amalgamate"				C9
	Item c9.float				"Float/Dock"				C9
	Item c9.stay_on_top		"Stay On Top"				C9
	Item c9.hide_leaving		"Hide When Leaving Tab"		C9
	Item c9.layout			"Layout"					C9
	Item c9.docking			"Docking Points"			C9
	Item c9.close				"Close Pane"				C9
	Item c9.pane.board		"Board pane"				C9
	Item c9.pane.notation	"Notation pane"				C9
	Item c9.pane.games		"Game list pane"			C9
	Item c9.pane.people		"Players / Events / Sites / Annotators / Positions panes"	C9
	Item c9.pane.tree		"Tree pane"					C9
	Item c9.pane.analysis	"Analysis pane"				C9
	Item c9.pane.media		"Media pane"				C9
	Item c9.pane.report		"Report / Info pane"		C9
	Item c9.pane.assistant	"Assistant pane"			C9
	Item c9.pane.explorer	"Explorer pane"				C9 {} {[::capability::present explorer]}

	DefineObject C9 board {
		ask
		-
		{cascade c9.appearance {}}
		c9.board_setup
		{cascade c9.tablebase {c9.explorer.tablebase}}
		c9.flip_board
		{cascade c9.start_position {c1.start.standard c1.start.chess960 c1.start.symm960 c1.start.shuffle c1.start.setup}}
		-
		c9.maximise
		c9.fold
		c9.amalgamate
		c9.float
		c9.stay_on_top
		c9.hide_leaving
		-
		{cascade c9.layout {}}
		c9.docking
		-
		c9.close
	}
	DefineObject C9 editor {
		ask
		-
		{cascade c9.not.display {{cascade c9.not.font {c9.not.font_inc c9.not.font_dec c9.not.font_reset}} c9.not.spacing c9.not.numbering c9.not.markers c9.not.diagrams c9.not.emoticons c9.not.configure}}
		{cascade c9.not.move_notation {}}
		{cascade c9.not.move_info {}}
		{cascade c9.not.language {}}
		-
		c9.maximise
		c9.fold
		c9.amalgamate
		c9.float
		c9.stay_on_top
		c9.hide_leaving
		-
		{cascade c9.layout {}}
		c9.docking
		-
		c9.close
	}
	DefineObject C9 games {
		ask
		-
		{cascade c9.games.columns {}}
		{cascade c9.games.sort {}}
		{cascade c9.games.filters {}}
		{cascade c9.games.presets {}}
		-
		c9.maximise
		c9.fold
		c9.amalgamate
		c9.float
		c9.stay_on_top
		c9.hide_leaving
		-
		{cascade c9.layout {}}
		c9.docking
		-
		c9.close
	}
	DefineObject C9 people {
		ask
		-
		{cascade c9.games.columns {}}
		{cascade c9.games.sort {}}
		{cascade c9.table.filter {}}
		-
		c9.maximise
		c9.fold
		c9.amalgamate
		c9.float
		c9.stay_on_top
		c9.hide_leaving
		-
		{cascade c9.layout {}}
		c9.docking
		-
		c9.close
	}
	DefineObject C9 tree {
		ask
		-
		{cascade c9.tree.search_mode {}}
		c9.tree.automatic
		c9.tree.novelties
		{cascade c9.tree.reference {}}
		-
		c9.maximise
		c9.fold
		c9.amalgamate
		c9.float
		c9.stay_on_top
		c9.hide_leaving
		-
		{cascade c9.layout {}}
		c9.docking
		-
		c9.close
	}
	DefineObject C9 analysis {
		ask
		-
		c9.analysis.setup
		{cascade c9.analysis.multi {}}
		{cascade c9.analysis.lines {}}
		c9.analysis.opponents
		c9.analysis.best
		-
		c9.maximise
		c9.fold
		c9.amalgamate
		c9.float
		c9.stay_on_top
		c9.hide_leaving
		-
		{cascade c9.layout {}}
		c9.docking
		-
		c9.close
	}
	DefineObject C9 media {
		ask
		-
		c9.media.show
		{cascade c9.media.sync {}}
		c9.media.stream
		-
		c9.maximise
		c9.fold
		c9.amalgamate
		c9.float
		c9.stay_on_top
		c9.hide_leaving
		-
		{cascade c9.layout {}}
		c9.docking
		-
		c9.close
	}
	DefineObject C9 report {
		ask
		-
		{cascade c9.report.font {c9.report.size c9.report.family}}
		c9.report.print
		c9.report.zoom
		-
		c9.maximise
		c9.fold
		c9.amalgamate
		c9.float
		c9.stay_on_top
		c9.hide_leaving
		-
		{cascade c9.layout {}}
		c9.docking
		-
		c9.close
	}
	DefineObject C9 assistant {
		ask
		-
		c9.assistant.clear
		c9.assistant.model
		{cascade c9.assistant.source {c9.assistant.local c9.assistant.cloud}}
		-
		c9.maximise
		c9.fold
		c9.amalgamate
		c9.float
		c9.stay_on_top
		c9.hide_leaving
		-
		{cascade c9.layout {}}
		c9.docking
		-
		c9.close
	}
	DefineObject C9 explorer {
		ask
		-
		c9.explorer.tablebase
		{cascade c9.explorer.source {}}
		-
		c9.maximise
		c9.fold
		c9.amalgamate
		c9.float
		c9.stay_on_top
		c9.hide_leaving
		-
		{cascade c9.layout {}}
		c9.docking
		-
		c9.close
	}
	DefineObject C9 other {
		ask
		-
		c9.maximise
		c9.fold
		c9.amalgamate
		c9.float
		c9.stay_on_top
		c9.hide_leaving
		-
		{cascade c9.layout {}}
		c9.docking
		-
		c9.close
	}

	# --- C10: a table column header -------------------------------
	Item c10.show_column		"Show Column"				C10
	Item c10.fill_column		"Fill Column"				C10
	Item c10.hide				"Hide"						C10
	Item c10.auto_stretch		"Auto Stretch Column"		C10
	Item c10.optimize			"Optimize Columns"			C10
	Item c10.fit				"Fit Columns"				C10
	Item c10.squeeze			"Squeeze Columns"			C10
	Item c10.configure		"Configure…"				C10
	Define C10 {
		ask
		-
		{header column}
		-
		{cascade c10.show_column {}}
		c10.fill_column
		c10.hide
		c10.auto_stretch
		-
		c10.optimize
		c10.fit
		c10.squeeze
		c10.configure
	}

	# --- C11: a comment in the comment editor ---------------------
	Item c11.copy				"Copy"						C11
	Item c11.cut				"Cut"						C11
	Item c11.paste				"Paste"						C11
	Item c11.insert_symbol		"Insert Symbol"				C11
	Item c11.insert_emoticon	"Insert Emoticon"			C11
	Item c11.format			"Format"					C11
	Item c11.copy_text		"Copy Text"					C11
	Item c11.explain_comment	"Explain Comment"			C11
	Item c11.draft_comment		"Draft Comment"				C11
	Item c11.translate_comment "Translate Comment"			C11
	Item c11.classify_comment	"Classify Comment"			C11
	Item c11.detect_language	"Detect Language"			C11
	Item c11.undo				"Undo"						C11
	Item c11.redo				"Redo"						C11
	Item c11.select_all		"Select All"				C11
	Item c11.clear			"Clear"						C11
	Item c11.revert			"Revert"					C11
	Item c11.switch_language	"Switch Language"			C11
	Item c11.add_language		"Add Language"				C11
	Item c11.display_emoticons "Display Emoticons"			C11
	Define C11 {
		ask
		-
		c11.copy
		c11.cut
		c11.paste
		{cascade c11.insert_symbol {}}
		{cascade c11.insert_emoticon {}}
		{cascade c11.format {}}
		{cascade c11.copy_text {}}
		-
		c11.explain_comment
		c11.draft_comment
		{cascade c11.translate_comment {}}
		c11.classify_comment
		c11.detect_language
		-
		c11.undo
		c11.redo
		c11.select_all
		c11.clear
		c11.revert
		-
		{cascade c11.switch_language {}}
		{cascade c11.add_language {}}
		c11.display_emoticons
	}

	# --- C12: the game bar (a game tab) ---------------------------
	Item c12.clear_history	"Clear History"				C12
	Item c12.new_game		"New Game"					C12
	Item c12.new.standard	"Standard"					C12
	Item c12.new.chess960	"Chess960"					C12
	Item c12.load_number	"Load Game Number…"			C12
	Item c12.import_game	"Import PGN Game…"			C12
	Item c12.save_game		"Save Game"					C12
	Item c12.save.replace	"Replace"					C12
	Item c12.save.replace_moves "Replace Moves"			C12
	Item c12.save.new		"Add as New"				C12
	Item c12.save.repertoire "Add to Repertoire"		C12
	Item c12.save.line		"Add Line"					C12
	Item c12.reload			"Reload from Database"		C12
	Item c12.copy_game		"Copy Game"					C12
	Item c12.copy_clipboard "Copy Game to Clipboard"	C12
	Item c12.paste			"Paste"						C12
	Item c12.paste.variation "Variation"				C12
	Item c12.paste.game		"Game"						C12
	Item c12.merge			"Merge"						C12
	Item c12.merge.game		"Game"						C12
	Item c12.export			"Export Game…"				C12
	Item c12.remove_history "Remove from History"		C12
	Item c12.close_tab		"Close Game Tab"			C12
	Define C12 {
		ask
		-
		{header history}
		c12.clear_history
		-
		{cascade c12.new_game {c12.new.standard c12.new.chess960}}
		c12.load_number
		c12.import_game
		-
		{cascade c12.save_game {c12.save.replace c12.save.replace_moves c12.save.new c12.save.repertoire c12.save.line}}
		c12.reload
		-
		c12.copy_game
		c12.copy_clipboard
		{cascade c12.paste {c12.paste.variation c12.paste.game}}
		{cascade c12.merge {c12.merge.game}}
		c12.export
		-
		c12.remove_history
		c12.close_tab
	}
	return
}

# vi:set ts=3 sw=3:

# ----------------------------------------------------------------------
# Selecting the row set: C4 has a base-less form, C5 depends on the
# object kind, C9 on the pane uid.
# ----------------------------------------------------------------------
proc ::context::ObjectKey {cid object} {
	switch -- $cid {
		C4 {
			set base [expr {[dict exists $object base] ? [dict get $object base] : ""}]
			if {$base eq ""} { return empty }
			return default
		}
		C5 {
			if {[dict exists $object kind]} { return [dict get $object kind] }
			return player
		}
		C9 {
			set uid [expr {[dict exists $object paneUid] ? [dict get $object paneUid] : ""}]
			set name [lindex [split $uid :] 0]
			switch -- $name {
				board { return board }
				editor - notation - pgn { return editor }
				games - dbgames { return games }
				players - events - sites - annotators - positions - player - event - site { return people }
				tree { return tree }
				analysis { return analysis }
				media { return media }
				report - information - info { return report }
				assistant { return assistant }
				explorer - eco { return explorer }
			}
			return other
		}
	}
	return default
}

proc ::context::Rows {cid object} {
	variable Menus
	if {![dict exists $Menus $cid]} { return {} }
	set entry [dict get $Menus $cid]
	switch -- [lindex $entry 0] {
		list { return [lindex $entry 1] }
		map {
			set menu [lindex $entry 1]
			set key [ObjectKey $cid $object]
			if {[dict exists $menu $key]} { return [dict get $menu $key] }
			if {[dict exists $menu default]} { return [dict get $menu default] }
			return {}
		}
	}
	return {}
}

# ----------------------------------------------------------------------
# Predicates (R1..R16 where the object carries the facts).
# ----------------------------------------------------------------------
proc ::context::GameLoaded {} {
	if {[catch { ::scidb::game::current } pos]} { return 0 }
	return [expr {$pos >= 0}]
}

proc ::context::GameOver {} {
	if {[catch { ::scidb::game::query over } over]} { return 0 }
	return $over
}

proc ::context::BoardSetupOpen {} {
	if {[llength [info commands ::board::options::isOpen]]} {
		return [::board::options::isOpen]
	}
	return 0
}

proc ::context::ClipboardEmpty {} {
	return [::game::clipboard::hidden?]
}

proc ::context::ClipboardCanPaste {} {
	if {[::game::clipboard::hidden?]} { return 0 }
	set base ""
	set variant ""
	catch { set base [::scidb::db::get name] }
	catch { set variant [::scidb::db::get variant?] }
	return [expr {[::game::clipboard::reason $base $variant] eq ""}]
}

proc ::context::Visible {id object} {
	set st [::menu::state $id $object]
	set visible [dict get $st visible]
	if {$id in {c3.sort_column c3.sort_asc c3.sort_desc}} {
		if {[dict exists $object sortable]} {
			set visible [expr {$visible && [dict get $object sortable] ? 1 : 0}]
		}
	}
	# R2: trial mode hides the save/replace/strip rows.
	if {$id in {c4.save_changes} && [::menu::TrialMode]} { set visible 0 }
	# R6/R7: the engine group belongs to a running line engine.
	if {$id in {c6.pause_resume c6.close_engine c6.lock_engine c6.opponents_view
			c6.best_first c6.multiple_variations c6.lines_per_variation}} {
		set running [::menu::EngineRunning]
		if {[dict exists $object engine]} {
			set engine [dict get $object engine]
			set running [expr {[string is integer -strict $engine]
				? ($engine >= 0 ? 1 : 0)
				: ($engine ne "" && $engine ne "-1" ? 1 : 0)}]
		}
		if {!$running} { set visible 0 }
	}
	# R10: strip and comment-before need a move; truncate needs mid-game.
	if {$id in {c2.comment_before c2.strip.moves c2.strip.truncate}} {
		set ply 0
		if {[dict exists $object ply]} {
			set ply [dict get $object ply]
		} else {
			catch { set ply [::scidb::game::ply] }
		}
		if {$ply <= 0} { set visible 0 }
	}
	if {$id eq "c2.strip.truncate" && $visible} {
		set over 0
		if {[dict exists $object over]} {
			set over [dict get $object over]
		} else {
			catch { set over [::scidb::game::query over] }
		}
		if {$over} { set visible 0 }
	}
	# R12: dock-only rows only while docked.
	if {$id in {c9.fold c9.amalgamate c9.docking}} {
		set uid [expr {[dict exists $object paneUid] ? [dict get $object paneUid] : ""}]
		set twm [expr {[dict exists $object twm] ? [dict get $object twm] : ""}]
		if {[::menu::PaneFloating $uid $twm]} { set visible 0 }
	}
	# R13: the report font/print group needs the HTML report surface.
	if {$id in {c9.report.font c9.report.size c9.report.family c9.report.print c9.report.zoom}} {
		if {[::menu::NoHtmlReport]} { set visible 0 }
	}
	return $visible
}

proc ::context::Enabled {id object} {
	set st [::menu::state $id $object]
	set enabled [dict get $st enabled]
	switch -- $id {
		c3.paste_games {
			set base [expr {[dict exists $object base] ? [dict get $object base] : ""}]
			set variant [expr {[dict exists $object variant] ? [dict get $object variant] : ""}]
			if {$base eq ""} { catch { set base [::scidb::db::get name] } }
			if {$variant eq ""} { catch { set variant [::scidb::db::get variant?] } }
			set enabled [expr {$enabled && [::game::clipboard::reason $base $variant] eq "" ? 1 : 0}]
		}
		c4.save_changes {
			if {[dict exists $object modified]} {
				set enabled [expr {$enabled && [dict get $object modified] ? 1 : 0}]
			}
		}
	}
	return $enabled
}

proc ::context::WhyDisabled {id object} {
	switch -- $id {
		c3.paste_games {
			set base [expr {[dict exists $object base] ? [dict get $object base] : ""}]
			set variant [expr {[dict exists $object variant] ? [dict get $object variant] : ""}]
			if {$base eq ""} { catch { set base [::scidb::db::get name] } }
			if {$variant eq ""} { catch { set variant [::scidb::db::get variant?] } }
			return [::game::clipboard::reason $base $variant]
		}
	}
	return ""
}

# ----------------------------------------------------------------------
# The action ids the menu for <cid> would post for <object>, in row order.
# Walks the same declared rows and visibility predicates as BuildRows, so
# the Ask list can scope C9 rows to the current pane's own menu. Cascade
# ids are included (a posted cascade is a row), separators, headers and
# the assistant row are not.
# ----------------------------------------------------------------------
proc ::context::MenuIds {cid object} {
	set ids {}
	foreach row [Rows $cid $object] {
		lappend ids {*}[MenuRowIds $cid $row $object]
	}
	return $ids
}

proc ::context::MenuRowIds {cid row object} {
	if {![llength $row] || $row eq "-"} { return {} }
	set kind [lindex $row 0]
	if {$kind eq "ask" || $kind eq "header"} { return {} }
	if {$kind eq "cascade"} {
		set id [lindex $row 1]
		if {![Visible $id $object]} { return {} }
		set ids [list $id]
		foreach sub [lindex $row 2] {
			lappend ids {*}[MenuRowIds $cid $sub $object]
		}
		return $ids
	}
	if {![Visible $row $object]} { return {} }
	return [list $row]
}

# ----------------------------------------------------------------------
# Build one context menu. <menu> must be a fresh Tk menu. Returns 1 when
# at least one row was added, 0 when the menu must not be posted (R8).
# ----------------------------------------------------------------------
proc ::context::Build {cid menu {object {}}} {
	set rows [Rows $cid $object]
	if {![llength $rows]} { return 0 }
	return [expr {[BuildRows $cid $menu $rows $object] ? 1 : 0}]
}

# Add <rows> to <menu>; a cascade may hold another cascade (C2 Strip,
# C9 Display). Returns the number of rows added.
proc ::context::BuildRows {cid menu rows object} {
	variable Counter

	set shown 0
	set separator 0

	foreach row $rows {
		if {$row eq "-"} {
			if {$shown} { set separator 1 }
			continue
		}
		if {$row eq "ask"} {
			if {$separator} { $menu add separator; set separator 0 }
			$menu add command \
				-label " $mc::WhatCanIDo" \
				-command [list ::action::run context.ask [dict create cid $cid object $object]]
			incr shown
			continue
		}
		set kind [lindex $row 0]
		if {$kind eq "header"} {
			if {$separator} { $menu add separator; set separator 0 }
			$menu add command -label " [Header [lindex $row 1] $object]" -state disabled
			incr shown
			continue
		}
		if {$kind eq "cascade"} {
			set id [lindex $row 1]
			set subs [lindex $row 2]
			if {![Visible $id $object]} { continue }
			if {$separator} { $menu add separator; set separator 0 }
			set sub $menu.__ctx[incr Counter]
			menu $sub -tearoff false
			set any [CascadePrefix $id $sub $object]
			if {[BuildRows $cid $sub $subs $object]} { set any 1 }
			$menu add cascade -label " [L $id] ▸" -menu $sub -state [expr {$any ? "normal" : "disabled"}]
			incr shown
			continue
		}
		# an action row
		if {![Visible $row $object]} { continue }
		if {$separator} { $menu add separator; set separator 0 }
		AddRow $menu $row $object
		incr shown
	}

	return $shown
}

# Some cascades carry a dynamic first line. A read-only database explains
# itself at the top of Maintenance instead of a cascade that only refuses to
# open (REPORT.md G23); the fixture compares cascades by label, so the hint
# stays inside the menu.
proc ::context::CascadePrefix {id menu object} {
	if {$id ne "c4.maintenance"} { return 0 }

	set base [expr {[dict exists $object base] ? [dict get $object base] : ""}]
	if {$base eq ""} { return 0 }
	if {[catch { ::scidb::db::get readonly? $base } readonly]} { return 0 }
	if {!$readonly} { return 0 }

	set ext ""
	catch {
		set switcher $::application::database::Vars(switcher)
		set ext [$switcher extension $base]
	}
	if {$ext in {pgn pgn.gz zip}} {
		set hint $::application::database::mc::MaintenanceReadOnlyPgn
	} else {
		set hint $::application::database::mc::MaintenanceReadOnly
	}
	$menu add command -label " $hint" -state disabled
	return 1
}

proc ::context::AddRow {menu id object} {
	set keys [Key $id]
	set accel ""
	if {[llength $keys] >= 2} { set accel [lindex $keys 1] }

	set label [L $id]
	# C3: several selected rows read "Copy Games" (VAL-CTX-005).
	if {$id eq "c3.copy_game" && [dict exists $object count]
			&& [dict get $object count] > 1} {
		set label [expr {[llength [info commands ::game::clipboard::mc::CopyGames]] \
			? $::game::clipboard::mc::CopyGames : "Copy Games"}]
	}

	set state [expr {[Enabled $id $object] ? "normal" : "disabled"}]
	if {$state eq "disabled"} {
		set why [WhyDisabled $id $object]
		if {$why ne ""} { append label " ($why)" }
	}
	set opts [list -label " $label" -state $state \
		-command [list ::action::run $id [dict create object $object]]]
	if {$accel ne ""} { lappend opts -accelerator $accel }
	eval [list $menu add command] $opts
	return
}

proc ::context::Header {kind object} {
	switch -- $kind {
		database {
			set base [expr {[dict exists $object base] ? [dict get $object base] : ""}]
			if {$base eq ""} { return "" }
			if {[llength [info commands ::util::databaseName]]} {
				if {![catch { ::util::databaseName $base } name]} { return $name }
			}
			return $base
		}
		column {
			if {[dict exists $object column]} { return [dict get $object column] }
			return ""
		}
		history {
			if {[dict exists $object history]} {
				set h [dict get $object history]
				if {[llength $h]} { return [join $h {, }] }
			}
			return "Games"
		}
	}
	return $kind
}

# ----------------------------------------------------------------------
# The current object per context. The Ask list has no pointer, so it uses
# the object the matching context menu would be posted with right now.
# Empty means there is no such object (the menu would not post).
# ----------------------------------------------------------------------
proc ::context::GameInTab {} {
	set gb ""
	catch { set gb $::application::pgn::Vars(gamebar) }
	if {$gb eq ""} { return 0 }
	if {[catch { ::gamebar::size $gb } n]} { return 0 }
	return [expr {$n > 0 ? 1 : 0}]
}

proc ::context::CurrentObject {cid} {
	switch -- $cid {
		C1 {
			set fen ""
			catch { set fen [::scidb::game::query fen] }
			if {$fen eq ""} { return {} }
			return [dict create fen $fen]
		}
		C2 {
			if {![GameInTab]} { return {} }
			if {[catch { set pos [::scidb::game::current] }]} { return {} }
			if {$pos < 0} { return {} }
			set base ""
			set variant ""
			set index ""
			catch { lassign [::scidb::game::link? $pos] base variant index }
			if {$index eq ""} { return {} }
			set ply 0
			catch { set ply [::scidb::game::ply] }
			set over 0
			catch { set over [::scidb::game::position atEnd?] }
			set mainline 1
			catch { set mainline [::scidb::game::position isMainline?] }
			return [dict create base $base variant $variant index $index \
				ply $ply san "" position $pos over $over mainline $mainline]
		}
		C3 {
			if {![GameInTab]} { return {} }
			set base ""
			catch { set base [::scidb::db::get name] }
			if {$base eq ""} { return {} }
			set index 0
			set variant Normal
			if {[catch { set pos [::scidb::game::current] }]} { set pos "" }
			if {$pos ne ""} {
				catch { lassign [::scidb::game::link? $pos] b variant index }
			}
			if {$index eq ""} { set index 0 }
			return [dict create base $base variant $variant index $index \
				column -1 sortable 1]
		}
		C4 {
			set base ""
			catch { set base [::scidb::db::get name] }
			return [dict create base $base]
		}
		C7 {
			set tree ""
			catch { set tree $::application::media::Priv(tree) }
			if {$tree eq "" || ![winfo exists $tree]} { return {} }
			set row ""
			catch { set row [$tree selection] }
			if {$row eq ""} { return {} }
			set vals {}
			catch { set vals [$tree item $row -values] }
			set type ""
			set title ""
			set path ""
			set index ""
			catch { lassign $vals type title path index }
			set base ""
			catch { set base [::scidb::db::get name] }
			return [dict create base $base mediaId $index path $path \
				title $title type $type]
		}
		C8 {
			if {![GameInTab]} { return {} }
			set fen ""
			catch { set fen [::scidb::game::query fen] }
			if {$fen eq ""} { return {} }
			return [dict create fen $fen move "" table "" row -1]
		}
		C9 {
			set twm ""
			catch { set twm [::application::twm board] }
			if {$twm eq ""} { return {} }
			set leaves {}
			catch { set leaves [$twm leaves] }
			if {![llength $leaves]} { return {} }
			set uid [lindex $leaves 0]
			set f [focus]
			foreach u $leaves {
				set p ""
				catch { set p [$twm leaf $u] }
				if {$p ne "" && ($f eq $p || [string match "$p.*" $f])} {
					set uid $u
					break
				}
			}
			set frame ""
			catch { set frame [$twm leaf $uid] }
			return [dict create paneUid $uid twm $twm frame $frame]
		}
		C10 {
			if {[catch { ::application::activeTab } tab]} { return {} }
			if {$tab ne "database"} { return {} }
			return [dict create column 0]
		}
		C11 {
			set dlg ""
			catch { set dlg $::comment::Vars(dialog) }
			if {$dlg eq "" || ![winfo exists $dlg] || ![winfo ismapped $dlg]} {
				return {}
			}
			set w $dlg
			set f [focus]
			if {[string match "$dlg*" $f]} { set w $f }
			set index ""
			catch { set index [::scidb::game::current] }
			return [dict create widget $w index $index]
		}
		C12 {
			return [dict create gameSlot 0]
		}
	}
	return {}
}

# {cid object} for a context-only action, or empty. C1/C2 actions (the
# edit-annotation row) are listed while either object exists.
proc ::context::CurrentObjectFor {id} {
	if {[catch { set rec [::action::get $id] }]} { return {} }
	set contexts [dict get $rec context]
	if {![llength $contexts] || [dict get $rec dropdown] ne ""} { return {} }
	foreach cid $contexts {
		set object [CurrentObject $cid]
		if {[dict size $object] && [HasObject $cid $object]} {
			return [list $cid $object]
		}
	}
	return {}
}

proc ::context::ObjectStart {object} {
	if {[dict exists $object ply]} {
		return [expr {[dict get $object ply] == 0 ? 1 : 0}]
	}
	if {[dict exists $object index]} {
		return [expr {[dict get $object index] == 0 ? 1 : 0}]
	}
	if {[catch { ::scidb::game::position atStart? } start]} { return 0 }
	return [expr {$start ? 1 : 0}]
}

proc ::context::ObjectEnd {object} {
	if {[dict exists $object over]} {
		return [expr {[dict get $object over] ? 1 : 0}]
	}
	# Context objects built before the move query carry no `over`; a
	# non-start position is mid-game unless it says otherwise.
	return 0
}

# R10: strip/truncate/comment rows follow the move object. Returns
# {visible enabled} or empty when the id has no object rule.
proc ::context::ObjectRule {id object} {
	switch -- $id {
		c2.strip.moves {
			set start [ObjectStart $object]
			set mainline 1
			if {[dict exists $object mainline]} {
				set mainline [dict get $object mainline]
			} else {
				if {[catch { ::scidb::game::position isMainline? } main]} {
					set main 1
				}
				set mainline [expr {$main ? 1 : 0}]
			}
			set ok [expr {$mainline && !$start ? 1 : 0}]
			return [list $ok $ok]
		}
		c2.strip.truncate {
			set start [ObjectStart $object]
			set end [ObjectEnd $object]
			set ok [expr {!$start && !$end ? 1 : 0}]
			return [list $ok $ok]
		}
		c2.comment_before {
			set ok [expr {![ObjectStart $object] ? 1 : 0}]
			return [list $ok $ok]
		}
		c2.comment_after {
			return [list 1 1]
		}
	}
	return {}
}

# ----------------------------------------------------------------------
# Post: no object under the pointer -> nothing is posted (R8).
# ----------------------------------------------------------------------
proc ::context::HasObject {cid object} {
	if {![dict size $object]} { return 0 }
	switch -- $cid {
		C1 {
			if {[dict exists $object fen]} { return [expr {[dict get $object fen] ne ""}] }
			if {[dict exists $object square]} { return [expr {[dict get $object square] ne ""}] }
			return 0
		}
		C2 {
			if {[dict exists $object index] || [dict exists $object ply]} { return 1 }
			if {[dict exists $object san]} { return [expr {[dict get $object san] ne ""}] }
			return 0
		}
		C3 {
			if {[dict exists $object index]} {
				return [expr {[dict get $object index] ni {"" none outside}}]
			}
			return 0
		}
		C4 { return 1 }
		C5 {
			if {![dict exists $object name]} { return 0 }
			return [expr {[dict get $object name] ne ""}]
		}
		C6 {
			return [expr {[dict exists $object lineId] || [dict exists $object pv]}]
		}
		C7 { return [expr {[dict exists $object mediaId] || [dict exists $object path]}] }
		C8 {
			return [expr {[dict exists $object fen] || [dict exists $object table]}]
		}
		C9 {
			set uid [expr {[dict exists $object paneUid] ? [dict get $object paneUid] : ""}]
			return [expr {$uid ne ""}]
		}
		C10 {
			if {[dict exists $object column]} { return [expr {[dict get $object column] ne ""}] }
			return 0
		}
		C11 {
			return [expr {[dict exists $object widget] || [dict exists $object index]}]
		}
		C12 {
			if {[dict exists $object gameSlot]} { return 1 }
			if {[dict exists $object id]} { return [expr {[dict get $object id] ne "-1"}] }
			return 0
		}
	}
	return 1
}

proc ::context::Post {cid menu object {x ""} {y ""}} {
	variable LastMenu

	if {![HasObject $cid $object]} { return 0 }
	if {![Build $cid $menu $object]} { return 0 }
	set LastMenu $menu
	bind $menu <<MenuUnpost>> +[list after idle [list catch [list destroy $menu]]]
	if {$x eq "" || $y eq ""} {
		set x [expr {[winfo pointerx $menu] - 4}]
		set y [expr {[winfo pointery $menu] - 4}]
	}
	catch { tk_popup $menu $x $y }
	return 1
}

# ----------------------------------------------------------------------
# "What can I do here?" -- the structured record handed to the assistant.
# Exactly the fields of VAL-CTX-002, no more.
# ----------------------------------------------------------------------
proc ::context::Record {cid object} {
	set record [dict create]
	switch -- $cid {
		C1 {
			dict set record square [expr {[dict exists $object square] ? [dict get $object square] : ""}]
			dict set record fen [expr {[dict exists $object fen] ? [dict get $object fen] : ""}]
		}
		C2 {
			dict set record base [expr {[dict exists $object base] ? [dict get $object base] : ""}]
			dict set record variant [expr {[dict exists $object variant] ? [dict get $object variant] : "Normal"}]
			dict set record index [expr {[dict exists $object index] ? [dict get $object index] : ""}]
			dict set record ply [expr {[dict exists $object ply] ? [dict get $object ply] : ""}]
			dict set record san [expr {[dict exists $object san] ? [dict get $object san] : ""}]
		}
		C3 {
			dict set record base [expr {[dict exists $object base] ? [dict get $object base] : ""}]
			dict set record variant [expr {[dict exists $object variant] ? [dict get $object variant] : "Normal"}]
			dict set record index [expr {[dict exists $object index] ? [dict get $object index] : ""}]
		}
		C4 {
			dict set record base [expr {[dict exists $object base] ? [dict get $object base] : ""}]
		}
		C5 {
			dict set record kind [expr {[dict exists $object kind] ? [dict get $object kind] : ""}]
			dict set record name [expr {[dict exists $object name] ? [dict get $object name] : ""}]
			dict set record base [expr {[dict exists $object base] ? [dict get $object base] : ""}]
		}
		C6 {
			dict set record engine [expr {[dict exists $object engine] ? [dict get $object engine] : ""}]
			dict set record lineId [expr {[dict exists $object lineId] ? [dict get $object lineId] : ""}]
			dict set record pv [expr {[dict exists $object pv] ? [dict get $object pv] : ""}]
		}
		C7 {
			dict set record base [expr {[dict exists $object base] ? [dict get $object base] : ""}]
			dict set record mediaId [expr {[dict exists $object mediaId] ? [dict get $object mediaId] : ""}]
			dict set record path [expr {[dict exists $object path] ? [dict get $object path] : ""}]
		}
		C8 {
			dict set record fen [expr {[dict exists $object fen] ? [dict get $object fen] : ""}]
			dict set record move [expr {[dict exists $object move] ? [dict get $object move] : ""}]
		}
		C9 {
			dict set record paneUid [expr {[dict exists $object paneUid] ? [dict get $object paneUid] : ""}]
		}
		C10 {
			dict set record table [expr {[dict exists $object table] ? [dict get $object table] : ""}]
			dict set record column [expr {[dict exists $object column] ? [dict get $object column] : ""}]
		}
		C11 {
			dict set record base [expr {[dict exists $object base] ? [dict get $object base] : ""}]
			dict set record index [expr {[dict exists $object index] ? [dict get $object index] : ""}]
			dict set record ply [expr {[dict exists $object ply] ? [dict get $object ply] : ""}]
		}
		C12 {
			dict set record gameSlot [expr {[dict exists $object gameSlot] ? [dict get $object gameSlot] : ""}]
		}
	}
	return $record
}

proc ::context::RecordText {cid record} {
	set text "$cid"
	foreach key [dict keys $record] {
		append text " $key=[dict get $record $key]"
	}
	return $text
}

proc ::context::Ask {cid object} {
	variable LastRecord

	set record [Record $cid $object]
	set LastRecord $record
	if {[catch {
		::ai::egress::ContextDecide $record [list ::context::AskDecision $cid $record]
	} err]} {
		# The gate itself failed: do not send anything.
		Withhold $cid $record "unknown"
	}
	return
}

proc ::context::AskDecision {cid record decision} {
	if {[dict exists $decision label] && [dict get $decision label] eq "hold"} {
		Withhold $cid $record [RecordText $cid $record]
		return
	}
	Deliver $cid $record
	return
}

proc ::context::Withhold {cid record fields} {
	variable LastWithheld
	set LastWithheld [dict create cid $cid record $record fields $fields]
	set message [format $mc::Withheld $fields]
	catch { ::ui::message $message }
	if {[llength [info commands ::dialog::info]]} {
		if {[catch { ::dialog::info -message $message }]} {
			catch { tk_messageBox -type ok -message $message }
		}
	} else {
		catch { tk_messageBox -type ok -message $message }
	}
	return
}

proc ::context::Deliver {cid record} {
	variable AssistantSink

	if {$AssistantSink ne ""} {
		return [uplevel #0 [list {*}$AssistantSink $record]]
	}
	if {[llength [info commands ::application::assistant::askContext]]} {
		return [::application::assistant::askContext $record]
	}
	set text "$mc::WhatCanIDo [RecordText $cid $record]"
	if {[llength [info commands ::application::assistant::ask]]} {
		return [::application::assistant::ask $text]
	}
	if {[llength [info commands ::application::assistant::offers::askAbout]]} {
		return [::application::assistant::offers::askAbout $text]
	}
	return
}

# ----------------------------------------------------------------------
# Invoke a context action from the menu or the registry.
# ----------------------------------------------------------------------
proc ::context::Invoke {id {object {}}} {
	if {[dict size $object] == 0} { set object [dict create] }
	if {[catch { Command $id $object } result]} {
		if {[llength [info commands ::log::error]]} {
			catch { ::log::error context "$id: $result" }
		}
		return "error: $result"
	}
	return $result
}

proc ::context::Command {id object} {
	switch -- $id {
		c9.pane.board { catch { ::menu::TogglePaneId board } }
		c9.pane.notation { catch { ::menu::TogglePaneId editor } }
		c9.pane.games { catch { ::menu::TogglePaneId games } }
		c9.pane.people { catch { ::menu::TogglePaneId players } }
		c9.pane.tree { catch { ::menu::TogglePaneId tree } }
		c9.pane.analysis { catch { ::menu::TogglePaneId analysis } }
		c9.pane.media { catch { ::menu::TogglePaneId media } }
		c9.pane.report { catch { ::menu::TogglePaneId report } }
		c9.pane.assistant { catch { ::menu::TogglePaneId assistant } }
		c9.pane.explorer { catch { ::menu::TogglePaneId explorer } }
		c1.set_start_board {
			set w [expr {[dict exists $object widget] ? [dict get $object widget] : ""}]
			if {$w ne "" && [info commands ::application::board::SetStartBoard] ne ""} {
				::application::board::SetStartBoard $w
			}
		}
		c1.set_start_position {
			set w [expr {[dict exists $object widget] ? [dict get $object widget] : ""}]
			if {$w ne "" && [info commands ::application::board::SetStartPosition] ne ""} {
				::application::board::SetStartPosition $w
			}
		}
		c1.start.standard { catch { ::application::pgn::Shuffle Normal } }
		c1.start.chess960 { catch { ::application::pgn::Shuffle Chess960 } }
		c1.start.symm960 { catch { ::application::pgn::Shuffle Symm960 } }
		c1.start.shuffle { catch { ::application::pgn::Shuffle Shuffle } }
		c1.start.setup {
			catch { ::setup::setupPositionMenu ::application::pgn [dict get $object menu] }
		}
		c1.insert_null { catch { ::move::addMove dialog -- } }
		c1.flip_board {
			set w [expr {[dict exists $object widget] ? [dict get $object widget] : ""}]
			if {$w ne ""} { catch { ::application::board::Rotate $w } }
		}
		c1.copy_fen { catch { ::setup::board::CopyFen } }
		c1.copy_diagram { catch { ::context::CopyDiagram $object } }
		c1.edit_annotation { catch { ::application::pgn::EditAnnotation } }
		c1.board_setup {
			set w [expr {[dict exists $object widget] ? [dict get $object widget] : ".application"}]
			catch { ::board::options::openConfigDialog $w ::application::board::Redraw }
		}
		c2.load_continuation { catch { ::context::MoveAction load $object } }
		c2.replace_move { catch { ::context::MoveAction replace $object } }
		c2.add_variation { catch { ::context::MoveAction variation $object } }
		c2.new_main_line { catch { ::context::MoveAction mainline $object } }
		c2.try_variation { catch { ::context::MoveAction trial $object } }
		c2.exchange_move { catch { ::context::MoveAction exchange $object } }
		c2.promote_variation { catch { ::application::pgn::PromoteVariation } }
		c2.remove_variation { catch { ::application::pgn::RemoveVariation } }
		c2.comment_after { catch { ::application::pgn::editComment after } }
		c2.comment_before { catch { ::application::pgn::editComment before } }
		c2.marks_palette { catch { ::application::pgn::openMarksPalette } }
		c2.move_info { catch { ::application::pgn::EditInfo .application } }
		c2.explain_move { catch { ::application::pgn::ExplainMove ::application::pgn "" } }
		c2.insert_diagram { catch { ::annotation::addNag suffix 155 } }
		c2.insert_diagram_black { catch { ::annotation::addNag suffix 156 } }
		c2.strip.moves { catch { ::scidb::game::strip moves } }
		c2.strip.truncate { catch { ::scidb::game::strip truncate } }
		c2.strip.variations { catch { ::scidb::game::strip variations } }
		c2.strip.annotations { catch { ::scidb::game::strip annotations } }
		c2.strip.info { catch { ::scidb::game::strip info } }
		c2.strip.marks { catch { ::scidb::game::strip marks } }
		c2.strip.comments { catch { ::scidb::game::strip comments } }
		c2.copy_comments { catch { ::application::pgn::CopyComments .application } }
		c2.import_game { catch { ::application::pgn::PasteClipboardGame } }
		c2.import_variation { catch { ::application::pgn::PasteClipboardVariation } }
		c2.undo { catch { ::application::pgn::Undo undo } }
		c2.redo { catch { ::application::pgn::Undo redo } }
		c2.collapse { catch { ::scidb::game::variation fold on } }
		c2.expand { catch { ::scidb::game::variation fold off } }
		c3.load {
			catch { ::gamestable::LoadGame [dict get $object path] [dict get $object index] }
		}
		c3.browse {
			catch { ::gamestable::Open(browse) [dict get $object path] [dict get $object index] }
		}
		c3.overview {
			catch { ::gamestable::Open(overview) [dict get $object path] [dict get $object index] }
		}
		c3.games_like {
			catch { ::gamestable::SimilarGames [dict get $object path] [dict get $object base] \
				[dict get $object variant] [dict get $object index] }
		}
		c3.ask_about_game {
			catch { ::gamestable::AskAboutGame [dict get $object path] [dict get $object base] \
				[dict get $object variant] [dict get $object index] }
		}
		c3.tournament {
			catch { ::gamestable::Open(tourntable) [dict get $object path] [dict get $object index] }
		}
		c3.open_url {
			catch { ::web::open [dict get $object path] [::gamestable::GetSite [dict get $object path] \
				[dict get $object base] [dict get $object variant] [dict get $object view] [dict get $object index]] }
		}
		c3.merge {
			catch { gamebar::mergeGame [dict get $object path] [list [dict get $object base] \
				[dict get $object variant] [dict get $object view] [dict get $object index]] }
		}
		c3.delete {
			catch { ::gamestable::deleteGame [dict get $object base] [dict get $object variant] [dict get $object index] }
		}
		c3.flag.* {
			return [GameFlag $object $id]
		}
		c3.copy_game {
			set numbers [::game::clipboard::selection [dict get $object path] [dict get $object base] \
				[dict get $object variant] [dict get $object view]]
			return [::game::clipboard::copy [dict get $object base] [dict get $object variant] $numbers]
		}
		c3.paste_games {
			set base [expr {[dict exists $object base] ? [dict get $object base] : ""}]
			set variant [expr {[dict exists $object variant] ? [dict get $object variant] : ""}]
			return [::game::clipboard::paste $base $variant]
		}
		c3.sort_column - c3.sort_asc - c3.sort_desc {
			catch { ::gamestable::SortColumn [dict get $object path] [dict get $object column] asc }
		}
		c4.properties { catch { ::application::database::Properties [dict get $object parent] } }
		c4.open_new_tab { catch { ::application::database::OpenBase [dict get $object base] 0 } }
		c4.close { catch { ::application::database::CloseBase [dict get $object parent] [dict get $object base] } }
		c4.download_games { catch { ::application::download::open [dict get $object parent] } }
		c4.save_changes { catch { ::application::database::Save [dict get $object base] } }
		c4.new.scid { catch { ::application::database::newBase [dict get $object parent] Normal "" } }
		c4.new.pgn { catch { ::application::database::newBase [dict get $object parent] Normal {} pgn } }
		c4.open_database { catch { ::application::database::OpenBases [dict get $object parent] . {} 1 } }
		c4.help { catch { ::help::open } }
		c5.player_card { catch { ::player::card::open [dict get $object name] [dict get $object base] } }
		c5.prep_report { catch { ::application::report::prep [dict get $object name] } }
		c5.insights { catch { ::insights::show [dict get $object name] } }
		c5.open_switcher { catch { ::application::database::searchCurrent [dict get $object parent] } }
		c5.save_working_set { catch { ::application::assistant::runTool save_working_set {} } }
		c6.add_move { catch { ::application::analysis::AddMove [dict get $object tree] 0 0 } }
		c6.close_engine { catch { ::application::analysis::CloseEngine [dict get $object tree] } }
		c6.pause_resume { catch { ::application::analysis::Pause [dict get $object tree] } }
		c6.setup_engine { catch { ::application::analysis::Setup [dict get $object tree] [dict get $object number] } }
		c6.setup_eval_edges { catch { ::application::analysis::SetupEvalEdges [dict get $object tree] } }
		c7.play { catch { ::mediainset::play [dict get $object mediaId] } }
		c7.open_stream { catch { ::mediainset::OpenStream [dict get $object base] } }
		c7.show_in_board { catch { ::mediainset::toggle } }
		c8.start_search { catch { ::application::tree::startSearch [dict get $object table] } }
		c8.analyze { catch { ::application::analysis::AnalyzePosition [dict get $object fen] } }
		c8.copy_line { catch { ::application::tree::CopyLine } }
		c8.save_line { catch { ::application::tree::SaveLine } }
		c10.optimize - c10.fit - c10.squeeze - c10.configure {
			catch { ::table::ConfigureColumns [dict get $object table] }
		}
		c11.copy { catch { ::tk_textCopy [dict get $object widget] } }
		c11.cut { catch { ::tk_textCut [dict get $object widget] } }
		c11.paste { catch { ::tk_textPaste [dict get $object widget] } }
		c9.not.font_inc {
			return [::context::PaneFont $object +1]
		}
		c9.not.font_dec {
			return [::context::PaneFont $object -1]
		}
		c9.not.font_reset {
			return [::context::PaneFont $object reset]
		}
		c11.undo { catch { [dict get $object widget] edit undo } }
		c11.redo { catch { [dict get $object widget] edit redo } }
		c11.select_all { catch { [dict get $object widget] tag add sel 1.0 end } }
		c11.clear { catch { [dict get $object widget] delete 1.0 end } }
		c12.load_number { catch { ::gamebar::LoadGameNumber [dict get $object parent] } }
		c12.import_game { catch { ::gamebar::ImportPgnGame [dict get $object parent] } }
		c12.reload { catch { ::gamebar::Reload [dict get $object parent] } }
		c12.copy_game { catch { ::gamebar::CopyGame [dict get $object parent] [dict get $object id] } }
		c12.export { catch { ::gamebar::ExportGame [dict get $object parent] [dict get $object id] } }
		c12.close_tab { catch { ::gamebar::CloseTab [dict get $object parent] [dict get $object id] } }
	}
	return
}

# Toggle one game flag on the game under the menu (C3).
proc ::context::GameFlag {object id} {
	variable Flags
	if {![dict exists $Flags $id]} { return }
	set flag [dict get $Flags $id]
	set base [expr {[dict exists $object base] ? [dict get $object base] : ""}]
	set variant [expr {[dict exists $object variant] ? [dict get $object variant] : "Normal"}]
	set index [expr {[dict exists $object index] ? [dict get $object index] : -1}]
	set view [expr {[dict exists $object view] ? [dict get $object view] : 0}]
	if {$base eq "" || $index < 0} { return }
	set info [::scidb::db::get gameInfo $index $view $base $variant]
	set current [::gamestable::column $info flags]
	set on [expr {[string first $flag $current] >= 0}]
	::scidb::db::set flag $index $view $base $variant $flag [expr {$on ? 0 : 1}]
	if {[dict exists $object path] && [llength [info commands ::gamestable::Refresh]]} {
		catch { ::gamestable::Refresh [dict get $object path] }
	}
	return
}

proc ::context::MoveAction {action object} {
	set parent [expr {[dict exists $object parent] ? [dict get $object parent] : "::application::pgn"}]
	if {[llength [info commands ::application::pgn::InvokeAction]]} {
		return [::application::pgn::InvokeAction $parent $action]
	}
	return
}

proc ::context::CopyDiagram {object} {
	set fen [expr {[dict exists $object fen] ? [dict get $object fen] : ""}]
	if {$fen eq ""} { return }
	if {[llength [info commands ::ai::diagram::html]]} {
		set html [::ai::diagram::html $fen]
		clipboard clear
		clipboard append $html
	}
	return
}


# ----------------------------------------------------------------------
# Per-pane font size (C9). A pane has its own font context, so changing
# it never changes the app-wide base size. The pane's widgets are bound
# to private clones of the fonts they already use, and only those clones
# are resized: the notation text (widget -font and the tag fonts) of this
# pane changes, every other pane keeps its font.
# ----------------------------------------------------------------------
proc ::context::PaneFontContext {uid} {
	return "pane:$uid"
}

proc ::context::PaneFontBaseSize {} {
	set base 11
	if {![catch { set size [::font::currentFontSize text] }]} {
		set base [expr {abs($size)}]
	} else {
		catch { set base [expr {abs($::font::Options(text:size))}] }
	}
	if {$base < 1} { set base 11 }
	return $base
}

# Every descendant that has a font of its own (Text, Entry, list-like
# widgets), including nested panes.
proc ::context::PaneFontWidgets {w} {
	set out {}
	foreach child [winfo children $w] {
		lappend out {*}[PaneFontWidgets $child]
		if {![catch { $child cget -font }]} { lappend out $child }
	}
	return $out
}

# Private clone of <font> for one pane widget or text tag. The clone keeps
# the family/style of the font the widget really uses and remembers its
# original size, so every later pane size is applied to that base.
proc ::context::PaneFontClone {key font} {
	variable PaneFontBase
	variable PaneFontOf
	variable PaneFontSerial

	if {[info exists PaneFontOf($key)]} {
		set name $PaneFontOf($key)
		if {![catch { font configure $name }]} { return $name }
	}
	if {[catch { array set a [font actual $font] }]} { return "" }
	if {![info exists a(-family)]} { return "" }

	incr PaneFontSerial
	set name "::context::paneFont$PaneFontSerial"
	catch { font delete $name }
	set size 10
	if {[info exists a(-size)]} { set size [expr {abs($a(-size))}] }
	set weight normal
	set slant roman
	set underline 0
	set overstrike 0
	foreach attr {-weight -slant -underline -overstrike} {
		set var [string range $attr 1 end]
		if {[info exists a($attr)]} { set $var $a($attr) }
	}
	if {[catch {
		font create $name -family $a(-family) -size $size \
			-weight $weight -slant $slant \
			-underline $underline -overstrike $overstrike
	}]} { return "" }

	set PaneFontBase($name) $size
	set PaneFontOf($key) $name
	return $name
}

proc ::context::PaneFontBind {frame uid} {
	foreach w [PaneFontWidgets $frame] {
		set font ""
		if {![catch { set font [$w cget -font] }] && $font ne ""} {
			set clone [PaneFontClone "$uid|w|$w" $font]
			if {$clone ne ""} { catch { $w configure -font $clone } }
		}
		if {[winfo class $w] ne "Text"} { continue }
		foreach tag [$w tag names] {
			set tagfont ""
			if {[catch { set tagfont [$w tag cget $tag -font] }]} { continue }
			if {$tagfont eq ""} { continue }
			set clone [PaneFontClone "$uid|t|$w|$tag" $tagfont]
			if {$clone ne ""} { catch { $w tag configure $tag -font $clone } }
		}
	}
	return
}

# Apply one absolute pane size to all fonts already bound to the pane.
proc ::context::PaneFontApplySize {uid size} {
	variable PaneFontBase
	variable PaneFontOf

	set delta [expr {$size - [PaneFontBaseSize]}]
	foreach key [array names PaneFontOf "$uid|*"] {
		set name $PaneFontOf($key)
		if {![info exists PaneFontBase($name)]} { continue }
		catch { font configure $name -size [expr {$PaneFontBase($name) + $delta}] }
	}
	return
}

# Called after a pane has been built: re-apply a size stored in the
# options file (the saved layout), without changing the global size.
proc ::context::PaneFontApply {frame uid} {
	set ctx [PaneFontContext $uid]
	if {![info exists ::font::Options($ctx:size)]} { return }
	if {$frame eq "" || ![winfo exists $frame]} { return }
	PaneFontBind $frame $uid
	PaneFontApplySize $uid $::font::Options($ctx:size)
	return
}

proc ::context::PaneFont {object delta} {
	set uid [expr {[dict exists $object paneUid] ? [dict get $object paneUid] : "board"}]
	set ctx [PaneFontContext $uid]
	set base [PaneFontBaseSize]
	# A pane starts at the global base, so its first change is relative to
	# what the user sees; the global size is never touched.
	if {![info exists ::font::Options($ctx:size)]} {
		set ::font::Options($ctx:size) $base
	}
	set current $::font::Options($ctx:size)
	if {$delta eq "reset"} {
		set value $base
	} elseif {[llength [info commands ::html::incrFontSize]]} {
		set value [::html::incrFontSize $current $delta]
	} elseif {$delta < 0} {
		set value [expr {max(1, $current + $delta)}]
	} else {
		set value [expr {$current + $delta}]
	}
	set ::font::Options($ctx:size) $value

	set frame [expr {[dict exists $object frame] ? [dict get $object frame] : ""}]
	if {$frame ne "" && [winfo exists $frame]} {
		PaneFontBind $frame $uid
		PaneFontApplySize $uid $value
		catch { event generate $frame <<FontSizeChanged>> -data $delta }
	}
	return $value
}

# The pane font size a test (or a caller) can read back.
proc ::context::PaneFontSize {uid} {
	set ctx [PaneFontContext $uid]
	if {[info exists ::font::Options($ctx:size)]} { return $::font::Options($ctx:size) }
	return [PaneFontBaseSize]
}

::context::RegisterCore
::context::Declare
