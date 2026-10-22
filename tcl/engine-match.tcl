# ======================================================================
# Engine matches and gauntlets ("Engine Match...", Extras menu): engines
# configured for the app play each other, the games are saved into a
# database, and a live table reports the score and the Elo difference.
#
# Modes: "match" is two engines playing a series, "gauntlet" is one
# engine playing each of the others (round-robin over the opponents).
# Colours alternate within a pairing; an optional opening suite (a PGN
# file or a database) seeds each game with the first plies of one of its
# games, each opening played with both colours.
#
# The chess work happens on one ordinary game slot (like the training
# game of tcl/play-engine.tcl), so the games can be watched on the
# board; board input is off while a match runs, and closing or switching
# away from the slot stops the match. Two engine processes per game (one
# per side; the same engine can mirror itself) are spoken UCI with over
# pipes, driven by fileevent exactly like tcl/play-engine.tcl -- nothing
# blocks the UI between moves. The engines' own UCI scores feed the
# adjudication: an agreed heavy score ends the game (resign rule), a run
# of flat scores after move 40 is a draw, and with seven pieces or fewer
# the tablebases (local Syzygy first, else the online lookup) decide.
# Mate, stalemate, repetition, the fifty-move rule, bare material and
# flag falls end games too; the Termination tag records why.
#
#   ::enginematch::open .application     the dialog
#   ::enginematch::StartMatch $spec      programmatically:
#       -engines {A B ...} -mode match|gauntlet -games <n per pairing>
#       -minutes <n> -increment <s> | -movetime <ms>
#       -suite <file|open base> -suitePlies <n> -base <database>
#       -tb <bool> -online <bool>
# and ::enginematch::RequestMove <side> is the seam the tests stub: the
# default talks to the engine pipes, a stub answers through GotMove.
# Covered by tests/test_app_engine_match.tcl.
# ======================================================================

::util::source engine-match

package require Tcl 8.5
package require Tk 8.5

namespace eval ::enginematch {
namespace eval mc {

set Title				"Engine Match"
set Mode				"Mode:"
set MatchMode			"Match: two engines"
set GauntletMode		"Gauntlet: one engine against the others"
set Engine1				"Engine A:"
set Engine2				"Engine B:"
set GauntletEngine		"Gauntlet engine:"
set Opponents			"Opponents (keep the selection):"
set Games				"Games per pairing:"
set GamesDetail			"colours alternate; each opening is played with both colours"
set TimeControl			"Time control:"
set Clock				"Clock:"
set ClockDetail			"minutes each, plus seconds increment per move"
set MoveTime			"Fixed time per move:"
set MilliSeconds		"ms"
set UseSuite			"Seed games from an opening suite (PGN or database):"
set SuiteBrowse			"Browse..."
set SuitePlies			"Opening plies:"
set Adjudication		"Adjudication:"
set UseTablebase		"tablebases when seven pieces or fewer remain"
set OnlineTb			"allow the online tablebase lookup"
set Target				"Save games to:"
set Start				"Start"
set Cancel				"Cancel"
set Pause				"Pause"
set Resume				"Resume"
set Stop				"Stop"
set NewMatch			"New Match"
set Close				"Close"
set Event				"Engine match"
set Running				"Game %d of %d: %s (white) - %s (black)"
set GameDone			"Game %d of %d finished: %s - %s %s (%s)"
set Paused				"Paused after %d of %d games."
set Finished			"Match finished: %d game(s) saved to %s."
set Stopped				"Match stopped after %d of %d games."
set Aborted				"Match aborted: %s"
set NeedEngines			"choose two engines (match), or the engine and at least one opponent (gauntlet)"
set UnknownMode			"unknown mode '%s'"
set NoSuchEngine		"no UCI engine named '%s'"
set NoBase				"the target database '%s' is not open or not writable"
set NoFreeGame			"no free game slot; close a game tab first"
set NoOpenings			"no openings found in %s"
set BadSuiteMove		"the opening suite holds the illegal move %s"
set EngineGone			"%s disappeared"
set EngineMissing		"the program of %s is missing: %s"
set IllegalMove			"%s played the illegal move %s"
set NoMove				"%s gave no move"
set Flag				"%s loses on time"
set FlagDraw			"%s ran out of time, but the material is not enough to mate"
set Checkmate			"checkmate"
set Stalemate			"stalemate"
set FiftyMoves			"fifty-move rule"
set Repetition			"threefold repetition"
set Material			"insufficient mating material"
set TbAdj				"tablebase adjudication"
set ResignAdj			"agreed heavy score (resign adjudication)"
set DrawAdj				"flat scores after move 40 (draw adjudication)"
set TblEngine			"Engine"
set TblGames			"Games"
set TblScore			"Score"
set TblPercent			"%"
set TblWon				"+"
set TblDrawn			"="
set TblLost				"-"
set EloLine				"Elo difference (%s vs %s): %s"
set EloNone				"Elo difference (%s vs %s): -"
set TheOthers			"the others"

} ;# namespace mc

# Persisted across sessions (WriteOptions below).
array set Options {
	mode			match
	engine1		""
	engine2		""
	gengine		""
	gopps		{}
	games		6
	minutes		5
	increment	2
	movetime	1000
	tc			clock
	suite		""
	suitePlies	10
	tb			1
	online		0
	base		""
}

variable StartFen		{rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
variable MoveTimeout	2000	;# grace added to a move's clock, ms
variable ResignCp		800		;# agree on a win from this |centipawns|
variable ResignPlies	5		;# ... over this many plies
variable DrawCp			10		;# a flat score stays below this |centipawns|
variable DrawPlies		10		;# ... for this many plies ...
variable DrawMinMove	40		;# ... and only past this move number
variable MateCap		10000	;# a mate score counts as this many centipawns
variable SuiteMax		1000	;# openings taken from a suite at most
variable SuitePos		45		;# scratch game slot for reading a suite base

array set Priv {
	dialog		{}
	running		0
	paused		0
	busy		0
	engines		{}
	mode		match
	games		2
	schedule	{}
	next		0
	openings	{}
	base		""
	noclock		0
	minutes		5
	increment	2
	movetime	1000
	tb			1
	online		0
	pos			-1
	token		0
	phase		idle
	white		""
	black		""
	side		w
	history		{}
	eval:w		{}
	eval:b		{}
	tbLatch		0
	clock:w		0
	clock:b		0
	pending:w	0
	pending:b	0
	pipe:w		{}
	pipe:b		{}
	pipeState:w	off
	pipeState:b	off
	watchdog	{}
	scores		{}
	saved		0
	subscribed	0
}

} ;# namespace enginematch


# ======================================================================
# The dialog
# ======================================================================

proc ::enginematch::open {parent} {
	variable Priv
	variable Options
	variable mc

	set dlg $parent.enginematch
	if {[winfo exists $dlg]} {
		raise $dlg
		return $dlg
	}
	set Priv(dialog) $dlg

	toplevel $dlg -class Scidb
	wm title $dlg $mc::Title
	wm transient $dlg [winfo toplevel $parent]
	wm withdraw $dlg
	wm protocol $dlg WM_DELETE_WINDOW [namespace code Close]
	bind $dlg <Escape> [namespace code Close]

	set top [ttk::frame $dlg.top]
	pack $top -fill both -expand yes -padx $::theme::padx -pady $::theme::pady

	### setup ##############################################################
	set f [ttk::frame $top.setup]

	set mf [ttk::frame $f.mode]
	ttk::label $mf.label -text $mc::Mode
	ttk::radiobutton $mf.match -text $mc::MatchMode -value match \
		-variable [namespace current]::Priv(dlg:mode) -command [namespace code ModeChanged]
	ttk::radiobutton $mf.gauntlet -text $mc::GauntletMode -value gauntlet \
		-variable [namespace current]::Priv(dlg:mode) -command [namespace code ModeChanged]
	# Stacked rows keep the dialog narrow enough for a strip beside the
	# board, so no control is squeezed below its requested size (VAL-DLG-016).
	grid $mf.label $mf.match -sticky w
	grid x $mf.gauntlet -sticky w
	grid $mf.match $mf.gauntlet -padx [list $::theme::padx 0]
	pack $mf -anchor w -pady [list 0 $::theme::pady]

	# the engine pickers, rebuilt by ModeChanged
	ttk::frame $f.picker
	pack $f.picker -fill x -pady [list 0 $::theme::pady]
	set Priv(widget:picker) $f.picker

	set gf [ttk::frame $f.games]
	ttk::label $gf.label -text $mc::Games
	ttk::spinbox $gf.count -from 2 -to 1000 -width 5 \
		-textvariable [namespace current]::Priv(dlg:games)
	ttk::label $gf.detail -text $mc::GamesDetail
	grid $gf.label $gf.count -sticky w
	grid $gf.count -padx [list $::theme::padx 0]
	grid $gf.detail -columnspan 3 -sticky w
	grid columnconfigure $gf 2 -weight 1
	pack $gf -anchor w -pady [list 0 $::theme::pady]

	set tf [ttk::frame $f.time]
	ttk::label $tf.label -text $mc::TimeControl
	ttk::radiobutton $tf.clock -text $mc::Clock -value clock \
		-variable [namespace current]::Priv(dlg:tc)
	ttk::spinbox $tf.minutes -from 1 -to 180 -width 3 \
		-textvariable [namespace current]::Priv(dlg:minutes)
	ttk::label $tf.plus -text "+"
	ttk::spinbox $tf.increment -from 0 -to 60 -width 2 \
		-textvariable [namespace current]::Priv(dlg:increment)
	ttk::label $tf.s -text "s"
	ttk::label $tf.detail -text $mc::ClockDetail
	set ncf [ttk::frame $f.movetime]
	ttk::radiobutton $ncf.choice -text $mc::MoveTime -value movetime \
		-variable [namespace current]::Priv(dlg:tc)
	ttk::spinbox $ncf.mt -from 10 -to 60000 -increment 100 -width 6 \
		-textvariable [namespace current]::Priv(dlg:movetime)
	ttk::label $ncf.ms -text $mc::MilliSeconds
	grid $tf.label $tf.clock $tf.minutes $tf.plus $tf.increment $tf.s -sticky w
	grid $tf.clock $tf.minutes $tf.plus $tf.increment $tf.s \
		-padx [list $::theme::padx 0]
	grid $tf.detail -columnspan 7 -sticky w
	grid columnconfigure $tf 6 -weight 1
	pack $ncf.choice $ncf.mt -side left
	pack $ncf.ms -side left -padx [list $::theme::padx 0]
	pack $tf -anchor w
	pack $ncf -anchor w -pady [list 0 $::theme::pady]

	set sf [ttk::frame $f.suite]
	ttk::checkbutton $sf.use -text $mc::UseSuite \
		-variable [namespace current]::Priv(dlg:usesuite)
	pack $sf.use -anchor w
	set srow [ttk::frame $sf.row]
	ttk::entry $srow.file -width 30 -textvariable [namespace current]::Priv(dlg:suite)
	ttk::button $srow.browse -text $mc::SuiteBrowse -command [namespace code BrowseSuite]
	ttk::label $srow.plieslabel -text $mc::SuitePlies
	ttk::spinbox $srow.plies -from 1 -to 40 -width 3 \
		-textvariable [namespace current]::Priv(dlg:suitelies)
	pack $srow.file -side left -fill x -expand yes
	pack $srow.browse -side left -padx [list $::theme::padx 0]
	pack $srow.plieslabel -side left -padx [list $::theme::padx 0]
	pack $srow.plies -side left
	pack $srow -fill x
	pack $sf -fill x -pady [list 0 $::theme::pady]

	set af [ttk::frame $f.adj]
	ttk::label $af.label -text $mc::Adjudication
	ttk::checkbutton $af.tb -text $mc::UseTablebase \
		-variable [namespace current]::Priv(dlg:tb)
	ttk::checkbutton $af.online -text $mc::OnlineTb \
		-variable [namespace current]::Priv(dlg:online)
	grid $af.label $af.tb -sticky w
	grid x $af.online -sticky w
	grid $af.tb $af.online -padx [list $::theme::padx 0]
	pack $af -anchor w -pady [list 0 $::theme::pady]

	set bf [ttk::frame $f.base]
	ttk::label $bf.label -text $mc::Target
	ttk::combobox $bf.base -state readonly -width 28 \
		-textvariable [namespace current]::Priv(dlg:base)
	pack $bf.label -side left
	pack $bf.base -side left -padx [list $::theme::padx 0]
	pack $bf -anchor w
	set Priv(widget:basebox) $bf.base

	pack $f -fill x

	### the run panel ########################################################
	set p [ttk::frame $top.run]

	ttk::label $p.status -wraplength 340 -justify left
	pack $p.status -fill x -pady [list 0 $::theme::pady]
	set Priv(widget:status) $p.status

	set tbl [ttk::frame $p.tbl]
	set tree [ttk::treeview $tbl.tree -height 7 -selectmode browse \
		-columns {engine games score pct w d l} -show headings]
	$tree heading engine -text $mc::TblEngine -anchor w
	$tree heading games -text $mc::TblGames -anchor e
	$tree heading score -text $mc::TblScore -anchor e
	$tree heading pct -text $mc::TblPercent -anchor e
	$tree heading w -text $mc::TblWon -anchor e
	$tree heading d -text $mc::TblDrawn -anchor e
	$tree heading l -text $mc::TblLost -anchor e
	$tree column engine -width 160 -anchor w
	foreach col {games score pct w d l} width {56 56 50 40 40 40} {
		$tree column $col -width $width -stretch no -anchor e
	}
	ttk::scrollbar $tbl.vs -orient vertical -command [list $tree yview]
	$tree configure -yscrollcommand [list $tbl.vs set]
	pack $tree -side left -fill both -expand yes
	pack $tbl.vs -side right -fill y
	pack $tbl -fill both -expand yes
	set Priv(widget:table) $tree

	ttk::label $p.elo -justify left
	pack $p.elo -anchor w -pady [list $::theme::pady 0]
	set Priv(widget:elo) $p.elo

	::widget::dialogButtons $dlg {ok cancel}
	$dlg.ok configure -text $mc::Start -command [namespace code Start]
	$dlg.cancel configure -text $mc::Cancel -command [namespace code Close]
	set Priv(widget:ok) $dlg.ok
	set Priv(widget:cancel) $dlg.cancel

	# persisted defaults
	set names [EngineNames]
	set Priv(dlg:mode) $Options(mode)
	set Priv(dlg:engine1) [FirstOf $Options(engine1) $names 0]
	set Priv(dlg:engine2) [FirstOf $Options(engine2) $names 1]
	set Priv(dlg:gengine) [FirstOf $Options(gengine) $names 0]
	set Priv(dlg:games) $Options(games)
	set Priv(dlg:tc) $Options(tc)
	set Priv(dlg:minutes) [expr {max(1, $Options(minutes))}]
	set Priv(dlg:increment) $Options(increment)
	set Priv(dlg:movetime) $Options(movetime)
	set Priv(dlg:usesuite) [expr {$Options(suite) ne ""}]
	set Priv(dlg:suite) $Options(suite)
	set Priv(dlg:suitelies) $Options(suitePlies)
	set Priv(dlg:tb) $Options(tb)
	set Priv(dlg:online) $Options(online)
	set bases [BaseList]
	$bf.base configure -values $bases
	if {$Options(base) in $bases} {
		set Priv(dlg:base) $Options(base)
	} else {
		set Priv(dlg:base) $::scidb::clipbaseName
	}
	ModeChanged

	::util::place::besideBoard $dlg $parent
	wm deiconify $dlg
	return $dlg
}


# <name> when it is in <names>, else the <dflt>th entry, else "".
proc ::enginematch::FirstOf {name names dflt} {
	if {$name in $names} { return $name }
	if {[llength $names] > $dflt} { return [lindex $names $dflt] }
	return ""
}


# The engine pickers follow the mode: two comboboxes for a match, one
# combobox and a multi-select list of the opponents for a gauntlet.
proc ::enginematch::ModeChanged {} {
	variable Priv
	variable Options
	variable mc

	set f $Priv(widget:picker)
	foreach child [winfo children $f] { destroy $child }
	set names [EngineNames]

	if {$Priv(dlg:mode) eq "match"} {
		foreach side {1 2} {
			set row [ttk::frame $f.e$side]
			ttk::label $row.l -text "[set mc::Engine$side]"
			ttk::combobox $row.engine -state readonly -width 24 -values $names \
				-textvariable [namespace current]::Priv(dlg:engine$side)
			pack $row.l -side left
			pack $row.engine -side left -padx [list $::theme::padx 0]
			pack $row -anchor w
		}
		return
	}

	set row [ttk::frame $f.ge]
	ttk::label $row.l -text $mc::GauntletEngine
	ttk::combobox $row.engine -state readonly -width 24 -values $names \
		-textvariable [namespace current]::Priv(dlg:gengine)
	bind $row.engine <<ComboboxSelected>> [namespace code ModeChanged]
	pack $row.l -side left
	pack $row.engine -side left -padx [list $::theme::padx 0]
	pack $row -anchor w

	set lf [ttk::frame $f.opps]
	ttk::label $lf.label -text $mc::Opponents -wraplength 340 -justify left
	listbox $lf.list -selectmode multiple -height 5 -exportselection 0 -width 28
	ttk::scrollbar $lf.vs -orient vertical -command [list $lf.list yview]
	$lf.list configure -yscrollcommand [list $lf.vs set]
	pack $lf.label -anchor w
	pack $lf.list -side left -fill both -expand yes
	pack $lf.vs -side right -fill y
	pack $lf -fill both -expand yes
	set Priv(widget:opps) $lf.list

	set champ $Priv(dlg:gengine)
	$lf.list delete 0 end
	foreach name $names {
		if {$name eq $champ} { continue }
		$lf.list insert end $name
		if {$Options(gopps) eq "" || $name in $Options(gopps)} {
			$lf.list selection set end
		}
	}
}


# File chooser for the opening suite.
proc ::enginematch::BrowseSuite {} {
	variable Priv

	set file [tk_getOpenFile -parent $Priv(dialog) \
		-filetypes [list \
			[list PGN {.pgn}] \
			[list Scidb {.sci .si3 .si4}] \
			[list * .*] \
		] \
	]
	if {$file eq ""} { return }
	set Priv(dlg:suite) $file
	set Priv(dlg:usesuite) 1
}


# The target database choices: the open, writable bases of the switcher.
proc ::enginematch::BaseList {} {
	set bases {}
	set switcher [::application::database::switcherWidget]
	if {$switcher ne ""} {
		foreach base [$switcher bases] {
			if {![catch { ::scidb::db::get writable? $base } w] && $w} { lappend bases $base }
		}
	}
	if {$::scidb::clipbaseName ni $bases} { lappend bases $::scidb::clipbaseName }
	return $bases
}


# The Start button: gather the spec, keep the choices, start.
proc ::enginematch::Start {} {
	variable Priv
	variable Options

	if {$Priv(dlg:mode) eq "match"} {
		set engines [list $Priv(dlg:engine1) $Priv(dlg:engine2)]
	} else {
		set engines [list $Priv(dlg:gengine)]
		if {[info exists Priv(widget:opps)] && [winfo exists $Priv(widget:opps)]} {
			foreach i [$Priv(widget:opps) curselection] {
				lappend engines [$Priv(widget:opps) get $i]
			}
		}
	}
	set spec [list -mode $Priv(dlg:mode) -base $Priv(dlg:base) -engines $engines]
	lappend spec -games $Priv(dlg:games)
	if {$Priv(dlg:tc) eq "clock"} {
		lappend spec -minutes $Priv(dlg:minutes) -increment $Priv(dlg:increment)
	} else {
		lappend spec -minutes 0 -movetime $Priv(dlg:movetime)
	}
	if {$Priv(dlg:usesuite) && [string trim $Priv(dlg:suite)] ne ""} {
		lappend spec -suite $Priv(dlg:suite) -suitePlies $Priv(dlg:suitelies)
	}
	lappend spec -tb $Priv(dlg:tb) -online $Priv(dlg:online)

	# keep the working choices for next time
	set Options(mode) $Priv(dlg:mode)
	set Options(games) $Priv(dlg:games)
	set Options(tc) $Priv(dlg:tc)
	set Options(minutes) $Priv(dlg:minutes)
	set Options(increment) $Priv(dlg:increment)
	set Options(movetime) $Priv(dlg:movetime)
	set Options(suite) [expr {$Priv(dlg:usesuite) ? $Priv(dlg:suite) : ""}]
	set Options(suitePlies) $Priv(dlg:suitelies)
	set Options(tb) $Priv(dlg:tb)
	set Options(online) $Priv(dlg:online)
	set Options(base) $Priv(dlg:base)
	if {$Priv(dlg:mode) eq "match"} {
		set Options(engine1) $Priv(dlg:engine1)
		set Options(engine2) $Priv(dlg:engine2)
	} else {
		set Options(gengine) $Priv(dlg:gengine)
		set Options(gopps) [lrange $engines 1 end]
	}

	StartMatch $spec
}


# Close: a running match is stopped first, the saved games stay saved.
proc ::enginematch::Close {} {
	variable Priv

	Finish
	if {[winfo exists $Priv(dialog)]} { destroy $Priv(dialog) }
	set Priv(dialog) {}
}


# ======================================================================
# Running a match
# ======================================================================

# Starts a match from <spec> (see the header comment). Returns 1 when
# the match got going; bad specs show in the dialog's status line, or
# raise an error on the programmatic path.
proc ::enginematch::StartMatch {spec} {
	variable Priv
	variable Options
	variable mc

	array set opts [list \
		-mode		match \
		-engines	{} \
		-games		2 \
		-minutes	5 \
		-increment	2 \
		-movetime	1000 \
		-suite		"" \
		-suitePlies	10 \
		-base		$::scidb::clipbaseName \
		-tb			1 \
		-online		0 \
	]
	array set opts $spec

	if {$Priv(running)} { error "an engine match is already running" }

	set mode $opts(-mode)
	set engines {}
	foreach name $opts(-engines) {
		set name [string trim $name]
		if {$name eq ""} { continue }
		# the same engine may play itself: later entries get a " #2" label
		set label $name
		for {set n 2} {$label in $engines} {incr n} { set label "$name #$n" }
		lappend engines $label
	}
	if {$mode eq "match"} { set engines [lrange $engines 0 1] }
	if {($mode eq "match" && [llength $engines] != 2)
	 || ($mode eq "gauntlet" && [llength $engines] < 2)} {
		Fail $mc::NeedEngines
		return 0
	}
	if {$mode ni {match gauntlet}} {
		Fail [format $mc::UnknownMode $mode]
		return 0
	}
	set known [EngineNames]
	foreach name $engines {
		if {[EngineBase $name] ni $known} {
			Fail [format $mc::NoSuchEngine $name]
			return 0
		}
	}
	set games [Normalize $opts(-games) 2 1000 2]
	set base $opts(-base)
	if {$base eq "" || [catch { ::scidb::db::get writable? $base } writable] || !$writable} {
		Fail [format $mc::NoBase $base]
		return 0
	}

	# the opening suite, if one was named
	set openings {}
	if {[string trim $opts(-suite)] ne ""} {
		set plies [Normalize $opts(-suitePlies) 1 40 10]
		if {[catch { LoadOpenings $opts(-suite) $plies } openings]} {
			Fail $openings
			return 0
		}
		if {![llength $openings]} {
			Fail [format $mc::NoOpenings $opts(-suite)]
			return 0
		}
	}

	Finish

	# claim a game slot: the games can be watched on the board, and the
	# position-less game commands act on the slot of the match
	set pos [ClaimSlot]
	if {$pos < 0} {
		Fail $mc::NoFreeGame
		return 0
	}
	set Priv(pos) $pos
	set Priv(engines) $engines
	set Priv(mode) $mode
	set Priv(games) $games
	set Priv(schedule) [schedule $mode $engines $games [llength $openings]]
	set Priv(next) 0
	set Priv(openings) $openings
	set Priv(base) $base
	set Priv(noclock) [expr {$opts(-minutes) <= 0}]
	set Priv(minutes) [expr {max(0, $opts(-minutes))}]
	set Priv(increment) [expr {max(0, $opts(-increment))}]
	set Priv(movetime) [expr {max(1, $opts(-movetime))}]
	set Priv(tb) $opts(-tb)
	set Priv(online) $opts(-online)
	set Priv(scores) [dict create]
	foreach name $engines { dict set Priv(scores) $name {0 0 0} }
	set Priv(saved) 0
	set Priv(paused) 0
	set Priv(running) 1

	::scidb::game::subscribe board $pos [namespace current]::Update
	::scidb::db::subscribe gameClose [namespace current]::GameClosed
	::scidb::db::subscribe gameSwitch [namespace current]::GameSwitched
	set Priv(subscribed) 1
	BoardInput off

	ShowRun
	NextGame
	return 1
}


# A visible game slot for the match: the resting slot of a previous
# match when it is still open, else a fresh one from the game bar.
proc ::enginematch::ClaimSlot {} {
	variable Priv

	if {$Priv(pos) >= 0
	 && ![catch { ::scidb::game::query $Priv(pos) open? } open]
	 && $open} {
		catch { ::scidb::game::switch $Priv(pos) }
		return $Priv(pos)
	}
	set before [::scidb::game::current]
	if {[catch { ::menu::gameNew .application }]} { return -1 }
	set pos [::scidb::game::current]
	if {$pos == $before || [::scidb::game::query length] > 0} {
		# no free slot: never take over a game the user has open
		return -1
	}
	return $pos
}


# Clamp an integer between <low> and <high>; junk becomes <dflt>.
proc ::enginematch::Normalize {v low high dflt} {
	if {![string is integer -strict $v]} { return $dflt }
	return [expr {max($low, min($high, $v))}]
}


# A spec problem: into the dialog's status line when there is one, an
# error otherwise (the programmatic path, the tests).
# The configured engine behind a match label ("Stockfish #2" -> "Stockfish").
proc ::enginematch::EngineBase {label} {
	regsub { #[0-9]+$} $label {} base
	return $base
}


proc ::enginematch::Fail {why} {
	if {[DialogExists]} {
		Status $why
		return
	}
	error $why
}


# Ends the session (whatever was on): subscriptions, timers, pipes, the
# board input. Saved games and the table survive.
proc ::enginematch::Finish {} {
	variable Priv

	if {$Priv(subscribed) && $Priv(pos) >= 0} {
		catch { ::scidb::game::unsubscribe board $Priv(pos) [namespace current]::Update }
		catch { ::scidb::db::unsubscribe gameClose [namespace current]::GameClosed }
		catch { ::scidb::db::unsubscribe gameSwitch [namespace current]::GameSwitched }
	}
	set Priv(subscribed) 0
	after cancel $Priv(watchdog)
	set Priv(watchdog) {}
	set Priv(running) 0
	set Priv(paused) 0
	set Priv(phase) idle
	ShutdownPipes
	BoardInput on
}


# The match slot closed or the user switched to another game tab: the
# board work is over, wrap up.
proc ::enginematch::GameClosed {position} {
	variable Priv
	variable mc

	if {$Priv(running) && $position == $Priv(pos)} {
		AbortMatch [format $mc::Aborted "the game was closed"]
	}
}


proc ::enginematch::GameSwitched {oldPos newPos} {
	variable Priv
	variable mc

	if {$Priv(running) && $Priv(pos) >= 0 && $newPos != $Priv(pos)} {
		AbortMatch [format $mc::Aborted "another game was selected"]
	}
}


# An out-of-band move on the match slot (keyboard, menu command; board
# input is off): roll it back, the engines play their own game.
proc ::enginematch::Update {position cmd data promoted} {
	variable Priv

	if {!$Priv(running) || $Priv(busy) || $position != $Priv(pos)} { return }
	if {$cmd ne "move"} { return }
	if {[llength $data] && ![lindex $data end]} { return } ;# backward navigation

	set Priv(busy) 1
	::scidb::game::go -1
	::scidb::game::strip truncate
	set Priv(busy) 0
}


proc ::enginematch::AbortMatch {why} {
	variable Priv

	Finish
	Status $why
	SetupButtons
	return $why
}


# All games done: report the final state; the dialog stays on the table.
proc ::enginematch::MatchDone {} {
	variable Priv
	variable mc

	set saved $Priv(saved)
	set base $Priv(base)
	Finish
	Status [format $mc::Finished $saved $base]
	SetupButtons
}


# The Stop button: the current game is discarded, finished games stay.
proc ::enginematch::Stop {} {
	variable Priv
	variable mc

	if {!$Priv(running)} { return }
	set done $Priv(next)
	set total [llength $Priv(schedule)]
	Finish
	Status [format $mc::Stopped $done $total]
	SetupButtons
}


# The Pause/Resume button: the break happens between games, engines are
# never left thinking with stopped clocks.
proc ::enginematch::Pause {} {
	variable Priv
	variable mc

	if {!$Priv(running)} { return }
	set Priv(paused) [expr {!$Priv(paused)}]
	if {!$Priv(paused)} { NextGame }
	SetupButtons
}


# ----------------------------------------------------------------------
# One game
# ----------------------------------------------------------------------

# Pops the next pairing off the schedule and starts its game; the end of
# the schedule (or a pause) ends (or suspends) the match here.
proc ::enginematch::NextGame {} {
	variable Priv
	variable mc

	if {!$Priv(running)} { return }
	set total [llength $Priv(schedule)]
	if {$Priv(paused)} {
		Status [format $mc::Paused $Priv(next) $total]
		return
	}
	if {$Priv(next) >= $total} {
		MatchDone
		return
	}
	lassign [lindex $Priv(schedule) $Priv(next)] white black opening
	SetupGame $white $black $opening
	Status [format $mc::Running [expr {$Priv(next) + 1}] $total $white $black]
}


# Sets up game <white> vs <black> on the match slot: the board is reset
# to the start (plus the opening suite's plies), clocks and adjudication
# state are fresh, then the side to move is asked for its move.
proc ::enginematch::SetupGame {white black opening} {
	variable Priv
	variable mc
	variable StartFen

	set Priv(white) $white
	set Priv(black) $black
	set Priv(side) w
	set Priv(history) {}
	set Priv(eval:w) {}
	set Priv(eval:b) {}
	set Priv(tbLatch) 0
	set Priv(clock:w) [expr {$Priv(minutes) * 60 * 1000}]
	set Priv(clock:b) [expr {$Priv(minutes) * 60 * 1000}]
	unset -nocomplain Priv(seg:w) Priv(seg:b)
	set Priv(pending:w) 0
	set Priv(pending:b) 0
	incr Priv(token)

	# the suite's moves go in under the busy flag: the board
	# subscription rolls back any move it sees otherwise
	set Priv(busy) 1
	set failed [catch {
		::scidb::game::clear $StartFen
		if {$opening >= 0} {
			set bad ""
			foreach san [lindex $Priv(openings) $opening] {
				set before [::scidb::game::query length]
				if {[catch { ::scidb::game::move $san }]
				 || [::scidb::game::query length] == $before} {
					set bad $san
					break
				}
				::scidb::game::go 1
			}
			if {$bad ne ""} { error [format $mc::BadSuiteMove $bad] }
		}
		::scidb::game::go end
	} err]
	set Priv(busy) 0
	if {$failed} {
		AbortMatch $err
		return
	}

	set Priv(phase) play
	StartTurn [::scidb::pos::stm]
}


# Hands the turn to <side> (the side to move): the move request itself
# is the stub seam of the tests.
proc ::enginematch::StartTurn {side} {
	variable Priv

	if {!$Priv(running) || $Priv(phase) ne "play"} { return }
	set Priv(side) $side
	set Priv(eval:$side) {}
	RequestMove $side
	# Note: a synchronous stub may have ended the game already.
}


# The seam the tests stub: asked once per engine turn, on the position
# the board shows after the other side's move. The default
# implementation talks UCI over the engine pipes; a stub calls
# [namespace code GotMove] with a uci move itself.
proc ::enginematch::RequestMove {side} {
	DriveMove $side
}


# Drives one move of <side>'s engine over its pipe: starts the engine on
# first use, remembers the pending move while the handshake runs, then
# sends the position and the go line and arms the watchdog.
proc ::enginematch::DriveMove {side} {
	variable Priv
	variable MoveTimeout

	if {[Connect $side]} {
		set Priv(pending:$side) 1
		return
	}
	if {$Priv(pipeState:$side) ne "ready"} { return }

	set fen [::scidb::pos::fen]
	StartSegment $side [clock milliseconds]
	if {$Priv(noclock)} {
		set go "go movetime $Priv(movetime)"
		set wait [expr {$Priv(movetime) + $MoveTimeout}]
	} else {
		set inc [expr {$Priv(increment) * 1000}]
		set go "go wtime $Priv(clock:w) btime $Priv(clock:b) winc $inc binc $inc"
		set wait [expr {$Priv(clock:$side) + $MoveTimeout}]
	}
	set Priv(pipeState:$side) busy
	Send $side "position fen $fen"
	Send $side $go
	set token $Priv(token)
	set Priv(watchdog) [after $wait [namespace code [list OnTimeout $side $token]]]
}


# The pipe handshake of <side>'s engine; returns 1 while the engine is
# still starting (the move goes out when "readyok" arrives), 0 when the
# engine is already up.
proc ::enginematch::Connect {side} {
	variable Priv
	variable mc

	if {$Priv(pipe:$side) ne ""} { return 0 }
	if {$Priv(pipeState:$side) eq "starting"} { return 1 }

	set name [EngineName $side]
	set index [::engine::FindIndex [EngineBase $name]]
	set e [dict merge $::engine::EmptyEngine [lindex $::engine::Engines $index]]
	set cmd [::engine::Command [dict get $e Command] [dict get $e Parameters]]
	if {$cmd eq "" || $cmd eq "no-wine"} {
		EngineDied $side [format $mc::EngineMissing $name [dict get $e Command]]
		return 1
	}
	if {[catch { set pipe [::open "|[list {*}$cmd]" r+] } err]} {
		EngineDied $side $err
		return 1
	}
	fconfigure $pipe -blocking 0 -buffering line
	set Priv(pipe:$side) $pipe
	set Priv(pipeState:$side) starting
	fileevent $pipe readable [namespace code [list OnReadable $side]]
	Send $side uci
	return 1
}


proc ::enginematch::Send {side line} {
	variable Priv
	if {[catch { puts $Priv(pipe:$side) $line; flush $Priv(pipe:$side) }]} {
		EngineDied $side ""
	}
}


proc ::enginematch::OnReadable {side} {
	variable Priv

	if {[catch {
		while {[gets $Priv(pipe:$side) line] >= 0} {
			if {$line ne ""} { OnEngineLine $side $line }
		}
	}]} { EngineDied $side ""; return }
	if {[catch { eof $Priv(pipe:$side) } eof] || $eof} { EngineDied $side "" }
}


proc ::enginematch::OnEngineLine {side line} {
	variable Priv

	switch -glob -- $line {
		uciok {
			Send $side "ucinewgame"
			Send $side "isready"
		}
		readyok {
			if {$Priv(pipeState:$side) eq "starting"} {
				set Priv(pipeState:$side) ready
				if {$Priv(pending:$side) && $Priv(phase) eq "play" && $Priv(side) eq $side} {
					set Priv(pending:$side) 0
					DriveMove $side
				}
			}
		}
		info* {
			lassign [::playengine::infoScore $line] kind value
			if {$kind ne ""} { set Priv(eval:$side) [list $kind $value] }
		}
		bestmove* {
			set move [lindex $line 1]
			set Priv(pipeState:$side) ready
			GotMove $side $move
		}
	}
}


# The move a side chose (uci string; also the entry the test stub
# calls). The turn is settled: clock, eval for the adjudication history,
# the move on the board, then the end checks and the next turn.
proc ::enginematch::GotMove {side uci} {
	variable Priv
	variable mc

	after cancel $Priv(watchdog)
	set Priv(watchdog) {}
	set Priv(pipeState:$side) ready
	if {!$Priv(running) || $Priv(phase) ne "play" || $Priv(side) ne $side} {
		return ;# a stale answer (flag fell, the game is over, ...)
	}
	if {[::scidb::game::current] != $Priv(pos)} { return }

	# a move that arrives after its clock ran out loses on time anyway
	if {!$Priv(noclock) && [SettleClock $side [clock milliseconds]] <= 0} {
		FlagFall $side
		return
	}

	# the engine's latest score, in white's perspective, feeds the rules
	lappend Priv(history) [NormScore $side $Priv(eval:$side)]

	# no legal move reported: the board decides mate/stalemate, anything
	# else is a forfeit
	if {$uci eq "" || $uci eq "(none)"} {
		set end [NaturalEnd]
		if {[llength $end]} {
			EndGame {*}$end
		} else {
			EndGame [expr {$side eq "w" ? "0-1" : "1-0"}] rulesinfraction \
				[format $mc::NoMove [EngineName $side]]
		}
		return
	}

	set san [::playengine::uciToSan $uci]
	if {$san eq ""} {
		EndGame [expr {$side eq "w" ? "0-1" : "1-0"}] rulesinfraction \
			[format $mc::IllegalMove [EngineName $side] $uci]
		return
	}
	set Priv(busy) 1
	catch { ::scidb::game::move $san; ::scidb::game::go 1 }
	set Priv(busy) 0

	set end [NaturalEnd]
	if {[llength $end]} { EndGame {*}$end; return }
	if {[TryAdjudicate]} { return }

	StartTurn [expr {$side eq "w" ? "b" : "w"}]
}


# {result terminationKey reason} when the position itself ends the game,
# {} otherwise (mate, stalemate, fifty moves, repetition, bare material).
proc ::enginematch::NaturalEnd {} {
	variable mc

	if {[catch { ::scidb::game::query over? } over] || !$over} {
		set fen [::scidb::pos::fen]
		if {![string length $fen]} { return {} }
		if {[::playengine::fiftyMoves $fen]} { return [list 1/2-1/2 normal $mc::FiftyMoves] }
		if {[::playengine::repetition]} { return [list 1/2-1/2 normal $mc::Repetition] }
		if {[::playengine::insufficientMaterial $fen]} { return [list 1/2-1/2 normal $mc::Material] }
		return {}
	}
	if {[::playengine::inCheck [::scidb::pos::fen]]} {
		# side to move has no move and is in check: the other side mates
		set result [expr {[::scidb::pos::stm] eq "w" ? "0-1" : "1-0"}]
		return [list $result normal $mc::Checkmate]
	}
	return [list 1/2-1/2 normal $mc::Stalemate]
}


# The adjudication stack, checked after every move: tablebases first
# (they are exact), then the agreed-score rules. Answers 1 when the game
# is over or the flow pauses for an online answer (which then resumes
# it).
proc ::enginematch::TryAdjudicate {} {
	variable Priv
	variable mc

	set fen [::scidb::pos::fen]
	set plies [::scidb::game::query length]

	if {$Priv(tb) && [::tablebase::pieceCount $fen] <= 7} {
		set verdict [TbLocal $fen]
		if {$verdict ne ""} {
			EndGame $verdict adjudication $mc::TbAdj
			return 1
		}
		# an inconclusive online answer is asked only once per game, the
		# engines may yet mate, flag or fall under the score rules
		if {$Priv(online) && !$Priv(tbLatch)} {
			set token $Priv(token)
			set Priv(phase) tbwait
			::application::download::Get [::tablebase::url $fen] \
				[namespace code [list TbAnswer $fen $token]]
			return 1
		}
	}

	set resign [resignRule $Priv(history)]
	if {$resign ne ""} {
		EndGame $resign adjudication $mc::ResignAdj
		return 1
	}
	if {[drawRule $plies $Priv(history)]} {
		EndGame 1/2-1/2 adjudication $mc::DrawAdj
		return 1
	}
	return 0
}


# The online tablebase answered (or failed): adjudicate when the verdict
# is decisive, otherwise play on. Stale answers (a new game started) are
# dropped by the token.
proc ::enginematch::TbAnswer {fen token result} {
	variable Priv
	variable mc

	if {!$Priv(running) || $Priv(phase) ne "tbwait" || $token != $Priv(token)} { return }
	set Priv(phase) play
	set Priv(tbLatch) 1
	if {[::scidb::game::current] != $Priv(pos)} { return }

	set category unknown
	if {[dict get $result ok]} {
		if {![catch { package require json; ::json::json2dict [dict get $result data] } answer]
		 && [dict exists $answer category]} {
			set category [dict get $answer category]
		}
	}
	set verdict [tbVerdict $category [lindex $fen 1]]
	if {$verdict ne ""} {
		EndGame $verdict adjudication $mc::TbAdj
		return
	}
	# no verdict: the score rules still apply to what has been played
	set resign [resignRule $Priv(history)]
	if {$resign ne ""} {
		EndGame $resign adjudication $mc::ResignAdj
		return
	}
	if {[drawRule [::scidb::game::query length] $Priv(history)]} {
		EndGame 1/2-1/2 adjudication $mc::DrawAdj
		return
	}
	StartTurn [::scidb::pos::stm]
}


# ----------------------------------------------------------------------
# The end of a game
# ----------------------------------------------------------------------

# The game is decided: it is saved with its headers, engines and pipes
# are freed, the table and scores are updated, and the conveyor moves on
# to the next game.
proc ::enginematch::EndGame {result termKey reason} {
	variable Priv
	variable mc

	if {!$Priv(running) || $Priv(phase) eq "over"} { return }
	set Priv(phase) over

	after cancel $Priv(watchdog)
	set Priv(watchdog) {}
	ShutdownPipes

	set white $Priv(white)
	set black $Priv(black)
	set round [expr {$Priv(next) + 1}]
	catch { SaveGame $result $termKey }
	UpdateScores $result

	incr Priv(next)
	set total [llength $Priv(schedule)]
	Status [format $mc::GameDone $round $total $white $black $result $reason]
	UpdateTable
	after idle [namespace code NextGame]
}


# Saves the slot's game into the target database with the match headers
# (the Termination tag only takes the fixed PGN values, so the dialog's
# verbal reason stays in the status line).
proc ::enginematch::SaveGame {result termKey} {
	variable Priv
	variable mc

	set tags [list \
		Event $mc::Event \
		Site ? \
		Date [clock format [clock seconds] -format {%Y.%m.%d}] \
		Round [expr {$Priv(next) + 1}] \
		White $Priv(white) \
		Black $Priv(black) \
		Result $result \
		TimeControl [timeControlText $Priv(noclock) $Priv(minutes) $Priv(increment) $Priv(movetime)] \
		Termination [termTag $termKey] \
	]
	set ok [::scidb::game::save $Priv(base) Normal $tags {} {} [namespace current]::LogSink {}]
	if {$ok} {
		incr Priv(saved)
		catch { ::application::database::refreshBase $Priv(base) }
	}
	return $ok
}


proc ::enginematch::LogSink {args} { return }


# +/-/= for both engines of the finished game.
proc ::enginematch::UpdateScores {result} {
	variable Priv

	set white $Priv(white)
	set black $Priv(black)
	set scores $Priv(scores)
	foreach name [list $white $black] {
		if {![dict exists $scores $name]} { dict set scores $name {0 0 0} }
	}
	lassign [dict get $scores $white] ww wd wl
	lassign [dict get $scores $black] bw bd bl
	switch -- $result {
		1-0 { incr ww; incr bl }
		0-1 { incr wl; incr bw }
		default { incr wd; incr bd }
	}
	dict set scores $white [list $ww $wd $wl]
	dict set scores $black [list $bw $bd $bl]
	set Priv(scores) $scores
}


# ----------------------------------------------------------------------
# Clocks: the wall-clock ledger of tcl/play-engine.tcl, per side
# ----------------------------------------------------------------------

# <side> starts thinking now.
proc ::enginematch::StartSegment {side now} {
	variable Priv
	set Priv(seg:$side) $now
}


# <side> has just moved; charge the elapsed wall time and grant the
# increment. Returns the remaining time (ms); a non-positive value means
# the flag fell on the move. No clock always stays positive.
proc ::enginematch::SettleClock {side now} {
	variable Priv

	if {$Priv(noclock) || ![info exists Priv(seg:$side)]} { return 1 }
	set left [expr {$Priv(clock:$side) - ($now - $Priv(seg:$side)) + $Priv(increment) * 1000}]
	set Priv(clock:$side) $left
	unset Priv(seg:$side)
	return $left
}


# Remaining ms for <side> at <now>, a running segment charged against it.
proc ::enginematch::Remaining {side now} {
	variable Priv

	set ms $Priv(clock:$side)
	if {[info exists Priv(seg:$side)]} {
		set ms [expr {$ms - ($now - $Priv(seg:$side))}]
	}
	return $ms
}


# Time ran out for <side>: it loses, unless the other side cannot mate.
proc ::enginematch::FlagFall {side} {
	variable Priv
	variable mc

	set name [EngineName $side]
	if {[::playengine::insufficientMaterial [::scidb::pos::fen]]} {
		EndGame 1/2-1/2 time [format $mc::FlagDraw $name]
		return
	}
	EndGame [expr {$side eq "w" ? "0-1" : "1-0"}] time [format $mc::Flag $name]
}


# The engine spent longer than its clock plus the grace: with a clock it
# is a flag fall, thinking forever with a fixed movetime counts as a
# crash.
proc ::enginematch::OnTimeout {side token} {
	variable Priv

	set Priv(watchdog) {}
	if {!$Priv(running) || $token != $Priv(token) || $Priv(phase) ne "play"} { return }
	if {$Priv(side) ne $side} { return }
	if {$Priv(noclock)} {
		EngineDied $side ""
	} else {
		FlagFall $side
	}
}


# The pipe broke or would not start: the engine forfeits the game it was
# playing; before the first move there is no game to forfeit and the
# match is aborted.
proc ::enginematch::EngineDied {side {why ""}} {
	variable Priv
	variable mc

	if {!$Priv(running) || $Priv(phase) ni {play tbwait}} { return }
	set name [EngineName $side]
	set why [expr {$why eq "" ? [format $mc::EngineGone $name] : $why}]
	EndGame [expr {$side eq "w" ? "0-1" : "1-0"}] abandoned $why
}


proc ::enginematch::EngineName {side} {
	variable Priv
	return [expr {$side eq "w" ? $Priv(white) : $Priv(black)}]
}


proc ::enginematch::ShutdownPipes {} {
	variable Priv

	foreach side {w b} {
		if {$Priv(pipe:$side) ne ""} {
			catch { fileevent $Priv(pipe:$side) readable {} }
			catch { puts $Priv(pipe:$side) "quit"; flush $Priv(pipe:$side) }
			catch { close $Priv(pipe:$side) }
			set Priv(pipe:$side) {}
		}
		set Priv(pipeState:$side) off
		set Priv(pending:$side) 0
	}
}


# ======================================================================
# The run panel
# ======================================================================

proc ::enginematch::ShowRun {} {
	variable Priv

	if {![DialogExists]} { return }
	set top $Priv(dialog).top
	pack forget $top.setup
	pack $top.run -fill both -expand yes
	SetupButtons
	UpdateTable
}


# The dialog buttons follow the phase: Start/Cancel up front,
# Pause/Stop while running, New Match/Close when done.
proc ::enginematch::SetupButtons {} {
	variable Priv
	variable mc

	if {![DialogExists]} { return }
	if {$Priv(running)} {
		$Priv(widget:ok) configure \
			-text [expr {$Priv(paused) ? $mc::Resume : $mc::Pause}] \
			-command [namespace code Pause] -state normal
		$Priv(widget:cancel) configure -text $mc::Stop -command [namespace code Stop]
	} else {
		$Priv(widget:ok) configure -text $mc::NewMatch \
			-command [namespace code ShowSetup] -state normal
		$Priv(widget:cancel) configure -text $mc::Close -command [namespace code Close]
	}
}


# "New Match": back to the setup view.
proc ::enginematch::ShowSetup {} {
	variable Priv
	variable mc

	Finish
	if {![DialogExists]} { return }
	set top $Priv(dialog).top
	pack forget $top.run
	pack $top.setup -fill x
	$Priv(widget:ok) configure -text $mc::Start -command [namespace code Start]
	$Priv(widget:cancel) configure -text $mc::Cancel -command [namespace code Close]
	$Priv(widget:basebox) configure -values [BaseList]
}


proc ::enginematch::Status {text} {
	variable Priv
	if {[DialogExists]} {
		$Priv(widget:status) configure -text $text
	}
}


# The table and the Elo line are rebuilt from the scores after each
# game; match mode pairs the two engines, gauntlet mode pits the first
# engine against the combined others.
proc ::enginematch::UpdateTable {} {
	variable Priv
	variable mc

	if {![DialogExists]} { return }
	set t $Priv(widget:table)
	foreach row [$t children {}] { $t delete $row }
	foreach name $Priv(engines) {
		lassign [ScoreOf $name] w d l
		set games [expr {$w + $d + $l}]
		set score [expr {$w + $d / 2.0}]
		set pct [expr {$games ? [format %.1f [expr {100.0 * $score / $games}]] : ""}]
		$t insert {} end -values [list $name $games [format %g $score] $pct $w $d $l]
	}

	set a [lindex $Priv(engines) 0]
	if {$a eq ""} { return }
	set b [expr {$Priv(mode) eq "match" ? [lindex $Priv(engines) 1] : $mc::TheOthers}]
	lassign [ScoreOf $a] w d l
	set elo [eloText $w $d $l]
	if {$elo eq ""} {
		$Priv(widget:elo) configure -text [format $mc::EloNone $a $b]
	} else {
		$Priv(widget:elo) configure -text [format $mc::EloLine $a $b $elo]
	}
}


# The {W D L} of an engine of the running or the last match.
proc ::enginematch::ScoreOf {name} {
	variable Priv
	if {![dict exists $Priv(scores) $name]} { return {0 0 0} }
	return [dict get $Priv(scores) $name]
}


proc ::enginematch::DialogExists {} {
	variable Priv
	return [expr {[string length $Priv(dialog)] && [winfo exists $Priv(dialog)]}]
}


proc ::enginematch::BoardInput {on} {
	if {$on eq "on"} { ::move::enable } else { ::move::disable }
}


proc ::enginematch::WriteOptions {chan} {
	::options::writeItem $chan [namespace current]::Options
}

::options::hookWriter ::enginematch::WriteOptions


# ======================================================================
# Pure helpers (covered by tests/test_app_engine_match.tcl)
# ======================================================================

# The UCI engines configured for the app (shared with the training
# game).
proc ::enginematch::EngineNames {} {
	return [::playengine::EngineNames]
}


# The game list of a match: every entry is {white black opening}, the
# pairing's <gamesPerPairing> games alternating colours, each opening
# played with both colours before the next one starts. A match is one
# pairing; a gauntlet plays round-robin over the champion's opponents.
proc ::enginematch::schedule {mode engines gamesPerPairing nOpenings} {
	set out {}
	if {$mode eq "match"} {
		set a [lindex $engines 0]
		set b [lindex $engines 1]
		for {set g 0} {$g < $gamesPerPairing} {incr g} {
			lappend out [gameEntry $a $b $g $nOpenings]
		}
		return $out
	}
	set champ [lindex $engines 0]
	set opps [lrange $engines 1 end]
	# round-robin: round <r> holds one game against each opponent, so the
	# table fills for all opponents early; colours alternate per pairing
	for {set r 0} {$r < $gamesPerPairing} {incr r} {
		foreach opp $opps {
			lappend out [gameEntry $champ $opp $r $nOpenings]
		}
	}
	return $out
}


# One schedule entry: game <g> of the pairing (<first> is white on even
# games), opening index -1 without a suite.
proc ::enginematch::gameEntry {first second g nOpenings} {
	set white [expr {$g % 2 == 0 ? $first : $second}]
	set black [expr {$g % 2 == 0 ? $second : $first}]
	set opening [expr {$nOpenings > 0 ? ($g / 2) % $nOpenings : -1}]
	return [list $white $black $opening]
}


# An engine's latest UCI score (from its own perspective, the side to
# move) as centipawns in white's perspective, mate scores folded onto
# +-[MateCap]. No score yet counts as 0.
proc ::enginematch::NormScore {side eval} {
	variable MateCap

	set sign [expr {$side eq "w" ? 1 : -1}]
	if {$eval eq ""} { return 0 }
	lassign $eval kind value
	if {$kind eq "mate"} {
		return [expr {$sign * $MateCap * ($value >= 0 ? 1 : -1)}]
	}
	return [expr {$sign * $value}]
}


# The resign rule: the last <ResignPlies> scores all agree on a win
# beyond <ResignCp> centipawns (both engines see it, as the plies
# alternate). Answers "1-0", "0-1" or "".
proc ::enginematch::resignRule {evals} {
	variable ResignCp
	variable ResignPlies

	if {[llength $evals] < $ResignPlies} { return "" }
	set white 1
	set black 1
	foreach e [lrange $evals end-[expr {$ResignPlies - 1}] end] {
		if {$e < $ResignCp} { set white 0 }
		if {$e > -$ResignCp} { set black 0 }
	}
	if {$white} { return 1-0 }
	if {$black} { return 0-1 }
	return ""
}


# The draw rule: past move <DrawMinMove>, <DrawPlies> plies without a
# score reaching |<DrawCp>| centipawns. <plies> is the mainline length.
proc ::enginematch::drawRule {plies evals} {
	variable DrawCp
	variable DrawPlies
	variable DrawMinMove

	if {$plies < 2 * $DrawMinMove} { return 0 }
	if {[llength $evals] < $DrawPlies} { return 0 }
	foreach e [lrange $evals end-[expr {$DrawPlies - 1}] end] {
		if {abs($e) >= $DrawCp} { return 0 }
	}
	return 1
}


# A tablebase category as a game result for the side to move <stm>
# (w/b): cursed wins and blessed losses stay draws under the 50-move
# rule, maybe-* categories are no verdict at all.
proc ::enginematch::tbVerdict {category stm} {
	switch -- $category {
		win { return [expr {$stm eq "w" ? "1-0" : "0-1"}] }
		loss { return [expr {$stm eq "w" ? "0-1" : "1-0"}] }
		draw - cursed-win - blessed-loss { return 1/2-1/2 }
	}
	return ""
}


# The local Syzygy verdict of <fen> as a result string, "" when the
# tables do not cover the position (no folder set, more pieces than the
# tables hold, ...).
proc ::enginematch::TbLocal {fen} {
	if {![info exists ::tablebase::Options(local)]} { return "" }
	set answer [::tablebase::LocalAnswer $fen]
	if {$answer eq "" || ![dict exists $answer category]} { return "" }
	return [tbVerdict [dict get $answer category] [lindex $fen 1]]
}


# The Elo difference of a {W D L} record, "" without games, +-inf for a
# perfect or pointless record.
proc ::enginematch::eloDiff {w d l} {
	set n [expr {double($w + $d + $l)}]
	if {$n == 0} { return "" }
	set p [expr {($w + $d / 2.0) / $n}]
	if {$p <= 0.0} { return -inf }
	if {$p >= 1.0} { return inf }
	return [expr {400.0 * log10($p / (1.0 - $p))}]
}


# The error bar of the Elo difference: the standard formula -- the
# spread of the per-game score (win 1, draw 1/2, loss 0) carried through
# the 400*log10(p/(1-p)) scale as half the interval over one standard
# deviation. The scale is singular at 0% and 100%, so the bar is clipped
# a whisker short of the edge; a perfect record has no bar at all.
proc ::enginematch::eloError {w d l} {
	set n [expr {double($w + $d + $l)}]
	if {$n == 0} { return "" }
	set p [expr {($w + $d / 2.0) / $n}]
	if {$p <= 0.0 || $p >= 1.0} { return "" }
	set sum [expr {$w * (1.0 - $p) * (1.0 - $p) \
		+ $d * (0.5 - $p) * (0.5 - $p) + $l * $p * $p}]
	set sd [expr {sqrt($sum / ($n * $n))}]
	set lo [expr {max(0.001, $p - $sd)}]
	set hi [expr {min(0.999, $p + $sd)}]
	return [expr {abs(400.0 * log10($hi / (1.0 - $hi)) \
		- 400.0 * log10($lo / (1.0 - $lo))) / 2.0}]
}


# The Elo line for the table, "+123 +/- 45", "" without games.
proc ::enginematch::eloText {w d l} {
	set diff [eloDiff $w $d $l]
	if {$diff eq ""} { return "" }
	if {$diff eq "inf" || $diff eq "-inf"} { return $diff }
	set err [eloError $w $d $l]
	if {$err eq ""} { return [format "%+d" [expr {round($diff)}]] }
	return [format "%+d \u00B1 %d" [expr {round($diff)}] [expr {round($err)}]]
}


# The TimeControl tag value: "<seconds>+<inc>" with a clock, a verbal
# form for fixed movetime games.
proc ::enginematch::timeControlText {noclock minutes increment movetime} {
	if {$noclock} { return "movetime $movetime" }
	return "[expr {$minutes * 60}]+$increment"
}


# The PGN Termination tag value of an internal key (only these strings
# are legal PGN).
proc ::enginematch::termTag {key} {
	switch -- $key {
		time { return TimeForfeit }
		adjudication { return Adjudication }
		abandoned { return Abandoned }
		rulesinfraction { return RulesInfraction }
	}
	return Normal
}


# The openings of a suite: <source> is a PGN file, a Scidb database
# file, or the name of an open database; the first <plies> plies of each
# game form one opening (as SANs), duplicates skipped.
proc ::enginematch::LoadOpenings {source plies} {
	variable SuitePos
	variable SuiteMax

	if {[file extension $source] in {.pgn .PGN}} {
		set chan [::open $source r]
		fconfigure $chan -encoding utf-8
		set text [read $chan]
		close $chan
		set openings [parsePgnOpenings $text $plies]
		return [lrange $openings 0 [expr {$SuiteMax - 1}]]
	}

	set imported ""
	if {[catch { ::scidb::db::count games $source Normal } n]} {
		# not an open base: a database file is imported into a scratch
		# in-memory base first (the same trick as the merge dialog)
		set imported "EngineMatchSuite"
		catch { ::scidb::db::close $imported }
		if {[catch {
			::scidb::db::new $imported Undetermined [::application::database::lookupType Clipbase]
			::scidb::db::import $imported $source [namespace current]::LogSink {} \
				[namespace current]::LogSink {} -encoding utf-8
		} err]} {
			catch { ::scidb::db::close $imported }
			error $err
		}
		set source $imported
		if {[catch { ::scidb::db::count games $source Normal } n]} {
			catch { ::scidb::db::close $imported }
			error $n
		}
	}

	set openings {}
	set made [catch { ::scidb::game::new $SuitePos }]
	set rc [catch {
		for {set i 0} {$i < $n && [llength $openings] < $SuiteMax} {incr i} {
			if {[catch { ::scidb::game::load $SuitePos $source Normal $i }]} { continue }
			set moves {}
			foreach ply [::scidb::game::query $SuitePos mainline] {
				if {[llength $moves] >= $plies} { break }
				lappend moves [lindex $ply 1]
			}
			if {[llength $moves]} {
				set key [join $moves " "]
				if {![info exists seen($key)]} {
					set seen($key) 1
					lappend openings $moves
				}
			}
		}
	} err opts]
	if {!$made} { catch { ::scidb::game::release $SuitePos } }
	if {$imported ne ""} { catch { ::scidb::db::close $imported } }
	if {$rc} { return -options $opts $err }
	return $openings
}


# The openings of a PGN text: the first <plies> SAN moves of each game,
# comments, variations, NAGs and move numbers out; games without moves
# and duplicate openings are skipped.
proc ::enginematch::parsePgnOpenings {text plies} {
	set out {}

	# a tag pair after movetext starts the next game
	set movetext ""
	set seenMoves 0
	set games {}
	foreach line [split $text "\n"] {
		if {[string match {\[*} [string trim $line]]} {
			if {$seenMoves} {
				lappend games $movetext
				set movetext ""
				set seenMoves 0
			}
			continue
		}
		if {[string trim $line] ne ""} { set seenMoves 1 }
		append movetext $line "\n"
	}
	if {[string trim $movetext] ne ""} { lappend games $movetext }

	foreach game $games {
		set moves [parsePgnMoves $game $plies]
		if {![llength $moves]} { continue }
		set key [join $moves " "]
		if {![info exists seen($key)]} {
			set seen($key) 1
			lappend out $moves
		}
	}
	return $out
}


# The first <n> SAN moves of a PGN movetext: comments first (they may
# hold live parentheses), then variations, NAGs and move numbers, and
# the terminator ends the line.
proc ::enginematch::parsePgnMoves {text n} {
	regsub -all -- {\{[^\}]*\}} $text " " text
	regsub -all -- {;[^\n]*} $text " " text
	set text [stripVariations $text]

	set moves {}
	foreach tok [split $text " \t\r\n"] {
		if {$tok eq ""} { continue }
		if {[regexp {^\d+\.(\.\.)?$} $tok]} { continue } ;# move numbers
		if {[regexp {^\$\d+$} $tok]} { continue } ;# NAGs
		if {$tok in {1-0 0-1 1/2-1/2 *}} { break }
		# annotation glyphs stick to the SAN in many files
		lappend moves [string trimright $tok "!?"]
		if {[llength $moves] >= $n} { break }
	}
	return $moves
}


# ( .. ) and ( .. ( .. ) .. ) out of a movetext, comments already gone.
proc ::enginematch::stripVariations {text} {
	set out ""
	set depth 0
	foreach ch [split $text ""] {
		if {$ch eq "("} { incr depth; continue }
		if {$ch eq ")"} { if {$depth > 0} { incr depth -1 }; continue }
		if {$depth == 0} { append out $ch }
	}
	return $out
}

# vi:set ts=3 sw=3:
