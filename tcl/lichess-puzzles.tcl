# ======================================================================
# Lichess Puzzles tab (::lichess::puzzles).
# Tab "Lichess puzzles" in the Chesswiz Online window:
# - Fetch daily puzzle (::lichess::api::puzzleDaily), next puzzle with
#   theme angle and difficulty (::lichess::api::puzzleNext), or by ID
#   (::lichess::api::puzzle).
# - Interactive solving on the board (play moves against puzzle.solution,
#   auto-play opponent reply, report result via
#   ::lichess::api::puzzleBatchSolved).
# - Dashboard summary (::lichess::api::puzzleDashboard) and recent
#   activity list (::lichess::api::puzzleActivity).
# - Local 3-minute Storm run (timed run of puzzleNext fetches, counting
#   solved puzzles locally).
# - Puzzle Racer button (::lichess::api::puzzleRace -> open racer URL in
#   the web browser via ::lichess::api::OpenBrowser).
# ======================================================================

::util::source lichess-puzzles

package require Tcl 8.5
package require Tk 8.5

namespace eval ::lichess::puzzles {
namespace eval mc {
set NoDashboard "No puzzles played yet."
set DashboardSummary "Last %s days: %s puzzles, %s first-try wins, performance %s"
set NoActivity "No puzzle activity yet."
set PuzzlePrompt "Choose Daily puzzle, Next puzzle or Load ID to start solving."
set StatsPrompt "Refresh dashboard & activity to load your puzzle statistics."

set TabTitle				"Lichess puzzles"
set FetchGroup				"Fetch puzzle"
set DailyPuzzle			"Daily puzzle"
set NextPuzzle				"Next puzzle"
set AngleLabel				"Theme:"
set DifficultyLabel		"Difficulty:"
set RatedPuzzle			"Rated"
set PuzzleIdLabel			"Puzzle ID:"
set LoadById				"Load ID"
set SolveGroup				"Solve"
set MoveEntryLabel		"Move (SAN/UCI):"
set PlayMove				"Play move"
set RetryPuzzle			"Retry"
set ShowSolution			"Show solution"
set StormGroup				"Puzzle Storm (local 3-minute run)"
set StartStorm				"Start 3-min Storm"
set StopStorm				"Stop Storm"
set RacerButton			"Create Puzzle Racer (opens in browser)"
set StatsGroup				"Dashboard & recent activity"
set RefreshStats			"Refresh dashboard & activity"
set LoadingPuzzle			"Loading puzzle…"
set YourTurnToFind		"%s to move — find the best line (puzzle %s, rating %s)."
set CorrectKeepGoing		"Correct move! Keep going…"
set PuzzleSolved			"Solved puzzle %s!"
set WrongMove				"Wrong move (%s). Try again or view the solution."
set SolutionShown			"Solution: %s"
set StormRunning			"Storm: %d solved — %d:%02d remaining"
set StormBest "Best Storm: %d"
set StormStopped "Storm stopped. Score: %d (not counted)."
set StormFinished			"Storm finished! Score: %d solved in 3 minutes."
set RacerOpened			"Opened Puzzle Racer %s in web browser."
set EnterPuzzleId			"Enter a puzzle ID first."

} ;# namespace mc

variable Angles {
	mix mateIn1 mateIn2 mateIn3 fork pin skewer discoveredAttack
	deflection attraction sacrifice hangingPiece backRankMate endgame
	opening middlegame
}

variable Difficulties {
	easiest easier normal harder hardest
}

# Test-only override; production remains three minutes. Never an option/UI control.
variable StormDuration 180

array set Priv {
	tab				{}
	view				{}
	statusText		{}
	angle				mix
	difficulty		normal
	rated				1
	lookupId			{}
	puzzleId			{}
	puzzleRating	{}
	themes			{}
	initialPly		0
	startFen			{}
	currentFen		{}
	solution			{}
	remaining		{}
	state				idle
	failedOnce		0
	reported			0
	moveInput		{}
	infoText			{}
	dashboardText	{}
	dashboard		{}
	activity			{}
	stormActive		0
	stormScore		0
	stormRemaining	0
	stormEndAt		0
	stormTimer		{}
	racerUrl			{}
}

} ;# namespace ::lichess::puzzles


proc ::lichess::puzzles::open {{parent .application}} {
	variable Priv
	variable Angles
	variable Difficulties
	variable mc

	set tab [::online::window::tab lichess-puzzles $mc::TabTitle]
	::online::window::select lichess-puzzles
	if {[info exists Priv(widget:top)] && [winfo exists $Priv(widget:top)]} {
		return $tab
	}
	set Priv(tab) $tab
	set Priv(infoText) $mc::PuzzlePrompt
	set Priv(dashboardText) $mc::StatsPrompt

	set top [ttk::frame $tab.top]
	pack $top -fill both -expand yes
	set Priv(widget:top) $top

	set left [ttk::frame $top.left]
	set right [ttk::frame $top.right]
	grid $left -row 0 -column 0 -sticky nsew -padx {0 8}
	grid $right -row 0 -column 1 -sticky nsew
	grid columnconfigure $top 0 -weight 2
	grid columnconfigure $top 1 -weight 3
	grid rowconfigure $top 0 -weight 1

	# 1. Fetch puzzle controls
	set ff [ttk::labelframe $left.fetch -text $mc::FetchGroup -padding 6]
	ttk::button $ff.daily -text $mc::DailyPuzzle -command [namespace code FetchDaily]
	ttk::button $ff.next -text $mc::NextPuzzle -command [namespace code FetchNext]
	ttk::checkbutton $ff.rated -text $mc::RatedPuzzle \
		-variable [namespace current]::Priv(rated)
	ttk::label $ff.angL -text $mc::AngleLabel
	ttk::combobox $ff.ang -state readonly -width 16 -values $Angles \
		-textvariable [namespace current]::Priv(angle)
	ttk::label $ff.difL -text $mc::DifficultyLabel
	ttk::combobox $ff.dif -state readonly -width 10 -values $Difficulties \
		-textvariable [namespace current]::Priv(difficulty)
	ttk::label $ff.idL -text $mc::PuzzleIdLabel
	ttk::entry $ff.idE -width 12 -textvariable [namespace current]::Priv(lookupId)
	ttk::button $ff.idBtn -text $mc::LoadById -command [namespace code FetchById]
	bind $ff.idE <Return> [namespace code FetchById]
	grid $ff.daily -row 0 -column 0 -sticky w -padx {0 4}
	grid $ff.next -row 0 -column 1 -sticky w -padx {0 4}
	grid $ff.rated -row 0 -column 2 -sticky w
	grid $ff.angL -row 1 -column 0 -sticky w -pady {4 0}
	grid $ff.ang -row 1 -column 1 -columnspan 2 -sticky ew -pady {4 0}
	grid $ff.difL -row 2 -column 0 -sticky w -pady {4 0}
	grid $ff.dif -row 2 -column 1 -columnspan 2 -sticky w -pady {4 0}
	grid $ff.idL -row 3 -column 0 -sticky w -pady {4 0}
	grid $ff.idE -row 3 -column 1 -sticky ew -pady {4 0}
	grid $ff.idBtn -row 3 -column 2 -sticky e -padx {4 0} -pady {4 0}
	grid columnconfigure $ff 1 -weight 1
	pack $ff -fill x -pady {0 6}

	# 2. Solve controls
	set sf [ttk::labelframe $left.solve -text $mc::SolveGroup -padding 6]
	ttk::label $sf.info -anchor w -justify left -wraplength 360 \
		-textvariable [namespace current]::Priv(infoText)
	ttk::label $sf.mL -text $mc::MoveEntryLabel
	ttk::entry $sf.mE -width 12 -textvariable [namespace current]::Priv(moveInput)
	ttk::button $sf.play -text $mc::PlayMove -command [namespace code SubmitMoveEntry]
	bind $sf.mE <Return> [namespace code SubmitMoveEntry]
	ttk::button $sf.retry -text $mc::RetryPuzzle -command [namespace code Retry]
	ttk::button $sf.sol -text $mc::ShowSolution -command [namespace code ShowSolution]
	grid $sf.info -row 0 -column 0 -columnspan 4 -sticky ew -pady {0 4}
	grid $sf.mL -row 1 -column 0 -sticky w
	grid $sf.mE -row 1 -column 1 -sticky ew -padx 4
	grid $sf.play -row 1 -column 2 -sticky w
	grid $sf.retry -row 2 -column 0 -sticky w -pady {4 0}
	grid $sf.sol -row 2 -column 1 -columnspan 2 -sticky w -padx 4 -pady {4 0}
	grid columnconfigure $sf 1 -weight 1
	pack $sf -fill x -pady {0 6}

	# 3. Storm & Racer controls
	UpdateStormBest
	set tf [ttk::labelframe $left.storm -text $mc::StormGroup -padding 6]
	ttk::button $tf.start -text $mc::StartStorm -command [namespace code StartStorm]
	ttk::button $tf.stop -text $mc::StopStorm -command [namespace code StopStorm]
	ttk::label $tf.best -anchor w -textvariable [namespace current]::Priv(stormBestText)
	grid $tf.best -row 3 -column 0 -columnspan 2 -sticky ew -pady {4 0}
	ttk::label $tf.status -anchor w -textvariable [namespace current]::Priv(stormText)
	ttk::button $tf.racer -text $mc::RacerButton -command [namespace code StartRacer]
	grid $tf.start -row 0 -column 0 -sticky w -padx {0 4}
	grid $tf.stop -row 0 -column 1 -sticky w
	grid $tf.status -row 1 -column 0 -columnspan 2 -sticky ew -pady {4 0}
	grid $tf.racer -row 2 -column 0 -columnspan 2 -sticky ew -pady {4 0}
	grid columnconfigure $tf 1 -weight 1
	pack $tf -fill x -pady {0 6}

	# 4. Dashboard & Activity
	set df [ttk::labelframe $left.stats -text $mc::StatsGroup -padding 6]
	ttk::button $df.refresh -text $mc::RefreshStats -command [namespace code RefreshStats]
	ttk::label $df.summary -anchor w -justify left -wraplength 360 \
		-textvariable [namespace current]::Priv(dashboardText)
	set atree [ttk::treeview $df.tree -height 5 -selectmode browse \
		-columns {id rating win} -show headings]
	$atree heading id -text "Puzzle"
	$atree heading rating -text "Rating"
	$atree heading win -text "Result"
	$atree column id -width 90 -anchor w
	$atree column rating -width 70 -anchor e
	$atree column win -width 80 -stretch 1 -anchor center
	bind $atree <<TreeviewSelect>> [namespace code OnSelectActivity]
	pack $df.refresh -anchor w -pady {0 4}
	pack $df.summary -fill x -pady {0 4}
	pack $atree -fill both -expand yes
	pack $df -fill both -expand yes
	set Priv(widget:activity) $atree
	::lichess::ListMessage $atree $mc::StatsPrompt

	# Right column: interactive board view
	set viewPath $right.view
	::online::view::create $viewPath [namespace code ViewAction] w
	::online::view::trainer $viewPath
	pack $viewPath -fill both -expand yes
	set Priv(view) $viewPath

	ttk::label $tab.status -anchor w -justify left -wraplength 700 \
		-textvariable [namespace current]::Priv(statusText)
	pack $tab.status -side bottom -fill x -pady {6 0}
	# a storm run ends with its tab
	bind $viewPath <Destroy> +[namespace code { if {"%W" eq $Priv(view) && $Priv(stormActive)} { StopStorm } }]

	return $tab
}


proc ::lichess::puzzles::Status {text} {
	variable Priv
	set Priv(statusText) $text
	if {$Priv(view) ne "" && [::online::view::exists $Priv(view)]} {
		::online::view::status $Priv(view) $text
	}
	::online::window::status $text
}


# ======================================================================
# Fetching puzzles (daily, next, by ID) and setting up the board
# ======================================================================

proc ::lichess::puzzles::FetchDaily {} {
	variable mc
	Status $mc::LoadingPuzzle
	::lichess::api::puzzleDaily [namespace code OnPuzzleLoaded]
	return 1
}


proc ::lichess::puzzles::FetchNext {{angle ""} {difficulty ""}} {
	variable Priv
	variable mc
	if {$angle ne ""} { set Priv(angle) $angle }
	if {$difficulty ne ""} { set Priv(difficulty) $difficulty }
	Status $mc::LoadingPuzzle
	::lichess::api::puzzleNext $Priv(angle) $Priv(difficulty) [namespace code OnPuzzleLoaded]
	return 1
}


proc ::lichess::puzzles::FetchById {{id ""}} {
	variable Priv
	variable mc
	if {$id ne ""} { set Priv(lookupId) $id }
	set pid [string trim $Priv(lookupId)]
	if {$pid eq ""} {
		Status $mc::EnterPuzzleId
		return 0
	}
	Status $mc::LoadingPuzzle
	::lichess::api::puzzle $pid [namespace code OnPuzzleLoaded]
	return 1
}


proc ::lichess::puzzles::OnPuzzleLoaded {reply} {
	variable Priv
	variable mc
	if {![dict exists $reply ok] || ![dict get $reply ok]} {
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Could not load puzzle."}]
		return
	}
	set data [expr {[dict exists $reply data] ? [dict get $reply data] : $reply}]
	SetupPuzzle $data
}


proc ::lichess::puzzles::SetupPuzzle {data} {
	variable Priv
	variable mc
	set game [expr {[dict exists $data game] ? [dict get $data game] : {}}]
	set puz [expr {[dict exists $data puzzle] ? [dict get $data puzzle] : $data}]

	set Priv(puzzleId) [expr {[dict exists $puz id] ? [dict get $puz id] : ""}]
	set Priv(puzzleRating) [expr {[dict exists $puz rating] ? [dict get $puz rating] : "?"}]
	set Priv(themes) [expr {[dict exists $puz themes] ? [dict get $puz themes] : {}}]
	set Priv(initialPly) [expr {[dict exists $puz initialPly] ? [dict get $puz initialPly] : 0}]
	set Priv(solution) [expr {[dict exists $puz solution] ? [dict get $puz solution] : {}}]
	set Priv(remaining) $Priv(solution)
	set Priv(failedOnce) 0
	set Priv(reported) 0
	set Priv(state) solving

	set pgn [expr {[dict exists $game pgn] ? [dict get $game pgn] : ""}]
	set allMoves [ParsePgnMoves $pgn]
	# Lichess initialPly is 0-indexed ply in game.pgn (or number of moves before puzzle).
	# Play up to initialPly + 1 plies if allMoves has at least initialPly + 1 and the
	# first solution move is legal in that position; otherwise check initialPly.
	set startFen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
	set prefixUcis [ResolveInitialPrefix $startFen $allMoves $Priv(initialPly) [lindex $Priv(solution) 0]]

	set curFen $startFen
	foreach uci $prefixUcis {
		set facts [::online::view::Facts $uci $curFen]
		if {$facts eq ""} { break }
		set curFen [dict get $facts fenAfter]
	}
	set Priv(startFen) $curFen
	set Priv(currentFen) $curFen

	set stm [lindex $curFen 1]
	if {$stm ni {w b}} { set stm w }
	set sideWord [expr {$stm eq "w" ? "White" : "Black"}]
	set Priv(infoText) "Puzzle $Priv(puzzleId) (rating $Priv(puzzleRating)) — themes: [join $Priv(themes) {, }]"

	if {$Priv(view) ne "" && [::online::view::exists $Priv(view)]} {
		set w $Priv(view)
		set wantFlip [expr {$stm eq "b"}]
		set ::online::view::${w}::V(side) $stm
		if {[set ::online::view::${w}::V(flip)] != $wantFlip} {
			set ::online::view::${w}::V(flip) $wantFlip
			::board::diagram::rotate [set ::online::view::${w}::V(board)]
		}
		::online::view::setGame $w [dict create name "White"] [dict create name "Black"] \
			$startFen $prefixUcis
	}
	Status [format $mc::YourTurnToFind $sideWord $Priv(puzzleId) $Priv(puzzleRating)]
}


proc ::lichess::puzzles::ParsePgnMoves {pgn} {
	regsub -all {\{[^\}]*\}} $pgn { } pgn
	while {[regsub -all {\([^()]*\)} $pgn { } pgn]} {}
	regsub -all {\[[^\]]*\]} $pgn { } pgn
	regsub -all {\$[0-9]+|[0-9]+\.(\.\.)?} $pgn { } pgn
	set moves {}
	foreach tok [regexp -all -inline {\S+} $pgn] {
		if {$tok in {* 1-0 0-1 1/2-1/2}} { break }
		lappend moves $tok
	}
	return $moves
}


proc ::lichess::puzzles::ResolveInitialPrefix {startFen tokens initialPly firstSolutionMove} {
	set ucis {}
	set curFen $startFen
	set fens [list $startFen]
	foreach tok $tokens {
		set facts [::online::view::Facts $tok $curFen]
		if {$facts eq ""} {
			set clean [string trimright $tok !?+#]
			set facts [::online::view::Facts $clean $curFen]
		}
		if {$facts eq ""} { break }
		lappend ucis [dict get $facts uci]
		set curFen [dict get $facts fenAfter]
		lappend fens $curFen
	}
	set total [llength $ucis]
	# Candidate counts: initialPly + 1, initialPly, total
	foreach count [list [expr {$initialPly + 1}] $initialPly $total] {
		if {$count < 0 || $count > $total} { continue }
		set fenAt [lindex $fens $count]
		if {$firstSolutionMove eq "" || [::online::view::Facts $firstSolutionMove $fenAt] ne ""} {
			return [lrange $ucis 0 [expr {$count - 1}]]
		}
	}
	return $ucis
}


# ======================================================================
# Interactive move checking & reporting (puzzleBatchSolved)
# ======================================================================

proc ::lichess::puzzles::ViewAction {action args} {
	switch -- $action {
		move {
			lassign $args uci san
			CheckUserMove $uci 1
		}
	}
}


proc ::lichess::puzzles::SubmitMoveEntry {} {
	variable Priv
	set mv [string trim $Priv(moveInput)]
	if {$mv eq ""} { return 0 }
	set Priv(moveInput) {}
	return [PlayMove $mv]
}


proc ::lichess::puzzles::PlayMove {move} {
	variable Priv
	if {$Priv(state) ne "solving" || ![llength $Priv(remaining)]} { return 0 }
	set facts [::online::view::Facts $move $Priv(currentFen)]
	if {$facts eq ""} {
		return [CheckUserMove $move 0]
	}
	set uci [dict get $facts uci]
	if {$Priv(view) ne "" && [::online::view::exists $Priv(view)]} {
		::online::view::addMove $Priv(view) $uci
	}
	return [CheckUserMove $uci 1]
}


proc ::lichess::puzzles::CheckUserMove {uci fromBoard} {
	variable Priv
	variable mc
	if {$Priv(state) ne "solving" || ![llength $Priv(remaining)]} { return 0 }
	set expected [lindex $Priv(remaining) 0]
	# as on Lichess, any move that mates solves the puzzle
	if {$uci ne $expected} {
		set facts [::online::view::Facts $uci $Priv(currentFen)]
		if {$facts ne "" && [dict get $facts mate]} {
			set Priv(remaining) [list $uci]
			set expected $uci
		}
	}
	if {$uci ne $expected} {
		set Priv(failedOnce) 1
		set Priv(state) wrong
		if {$fromBoard && $Priv(view) ne "" && [::online::view::exists $Priv(view)]} {
			::online::view::rejectMove $Priv(view) [format $mc::WrongMove $uci]
		}
		Status [format $mc::WrongMove $uci]
		ReportSolved 0
		# a storm run moves on; it must not wait on a failed puzzle
		if {$Priv(stormActive)} { FetchNext }
		return 0
	}

	# Move is correct! Advance currentFen.
	set facts [::online::view::Facts $uci $Priv(currentFen)]
	if {$facts ne ""} {
		set Priv(currentFen) [dict get $facts fenAfter]
	}
	if {$fromBoard && $Priv(view) ne "" && [::online::view::exists $Priv(view)]} {
		# Clear pending marker by echoing the move
		::online::view::addMove $Priv(view) $uci
	}
	set Priv(remaining) [lrange $Priv(remaining) 1 end]

	# Auto-play opponent's reply if one remains
	if {[llength $Priv(remaining)]} {
		set replyUci [lindex $Priv(remaining) 0]
		set rfacts [::online::view::Facts $replyUci $Priv(currentFen)]
		if {$rfacts ne ""} {
			set Priv(currentFen) [dict get $rfacts fenAfter]
		}
		if {$Priv(view) ne "" && [::online::view::exists $Priv(view)]} {
			::online::view::addMove $Priv(view) $replyUci
		}
		set Priv(remaining) [lrange $Priv(remaining) 1 end]
	}

	if {![llength $Priv(remaining)]} {
		set Priv(state) solved
		Status [format $mc::PuzzleSolved $Priv(puzzleId)]
		ReportSolved [expr {!$Priv(failedOnce)}]
		if {$Priv(stormActive)} {
			incr Priv(stormScore)
			UpdateStormStatus
			FetchNext
		}
		return 1
	}

	Status $mc::CorrectKeepGoing
	return 1
}


proc ::lichess::puzzles::ReportSolved {win} {
	variable Priv
	if {$Priv(reported) || $Priv(puzzleId) eq ""} { return }
	set Priv(reported) 1
	if {![llength [info commands ::lichess::api::puzzleBatchSolved]]} { return }
	set sol [list [dict create \
		id $Priv(puzzleId) \
		win [expr {$win ? 1 : 0}] \
		rated [expr {$Priv(rated) ? 1 : 0}]]]
	::lichess::api::puzzleBatchSolved $Priv(angle) $sol [namespace code OnBatchReported]
}


proc ::lichess::puzzles::OnBatchReported {reply} {
	# Result reported; nothing further required unless an error is returned.
}


proc ::lichess::puzzles::Retry {} {
	variable Priv
	variable mc
	if {$Priv(puzzleId) eq ""} { return 0 }
	set Priv(remaining) $Priv(solution)
	set Priv(currentFen) $Priv(startFen)
	set Priv(state) solving
	set stm [lindex $Priv(startFen) 1]
	if {$stm ni {w b}} { set stm w }
	if {$Priv(view) ne "" && [::online::view::exists $Priv(view)]} {
		set w $Priv(view)
		set ::online::view::${w}::V(side) $stm
		::online::view::setGame $w [dict create name "White"] [dict create name "Black"] \
			$Priv(startFen) {}
	}
	Status [format $mc::YourTurnToFind [expr {$stm eq "w" ? "White" : "Black"}] \
		$Priv(puzzleId) $Priv(puzzleRating)]
	return 1
}


proc ::lichess::puzzles::ShowSolution {} {
	variable Priv
	variable mc
	if {![llength $Priv(solution)]} { return 0 }
	set Priv(failedOnce) 1
	set Priv(state) solved
	ReportSolved 0
	Status [format $mc::SolutionShown [join $Priv(solution) " "]]
	return 1
}


# ======================================================================
# Dashboard & Activity
# ======================================================================

proc ::lichess::puzzles::RefreshStats {{days 30} {max 20}} {
	if {[llength [info commands ::lichess::api::puzzleDashboard]]} {
		::lichess::api::puzzleDashboard $days [namespace code OnDashboard]
	}
	if {[llength [info commands ::lichess::api::puzzleActivity]]} {
		::lichess::api::puzzleActivity $max [namespace code OnActivity]
	}
	return 1
}


proc ::lichess::puzzles::OnDashboard {reply} {
	variable Priv
	variable mc
	if {![dict exists $reply ok] || ![dict get $reply ok]} {
		set Priv(dashboardText) [::lichess::ReplyError $reply]
		return
	}
	set d [expr {[dict exists $reply data] ? [dict get $reply data] : $reply}]
	set Priv(dashboard) $d
	set days [expr {[dict exists $d days] ? [dict get $d days] : 30}]
	set g [expr {[dict exists $d global] ? [dict get $d global] : $d}]
	set nb [expr {[dict exists $g nb] ? [dict get $g nb] : 0}]
	set firstWins [expr {[dict exists $g firstWins] ? [dict get $g firstWins] : 0}]
	set perf [expr {[dict exists $g performance] ? [dict get $g performance] : "?"}]
	set Priv(dashboardText) [expr {$nb == 0 ? $mc::NoDashboard : [format $mc::DashboardSummary $days $nb $firstWins $perf]}]
}


proc ::lichess::puzzles::OnActivity {reply} {
	variable mc
	variable Priv
	if {![dict exists $reply ok] || ![dict get $reply ok]} {
		if {[info exists Priv(widget:activity)]} {
			::lichess::ListMessage $Priv(widget:activity) [::lichess::ReplyError $reply] 1
		}
		return
	}
	set items [expr {[dict exists $reply data] ? [dict get $reply data] : {}}]
	set Priv(activity) $items
	if {![info exists Priv(widget:activity)] || ![winfo exists $Priv(widget:activity)]} { return }
	set tree $Priv(widget:activity)
	$tree delete [$tree children {}]
	foreach item $items {
		if {[catch {dict size $item}]} { continue }
		set id [expr {[dict exists $item puzzle id] ? [dict get $item puzzle id] : \
			[dict exists $item id] ? [dict get $item id] : ""}]
		if {$id eq ""} { continue }
		set rating [expr {[dict exists $item puzzle rating] ? [dict get $item puzzle rating] : \
			[dict exists $item puzzleRating] ? [dict get $item puzzleRating] : ""}]
		set win [expr {[dict exists $item win] && [dict get $item win] ? "Solved" : "Failed"}]
		if {![$tree exists $id]} {
			$tree insert {} end -id $id -values [list $id $rating $win]
		}
	}
	::lichess::ListResult $tree $mc::NoActivity
}


proc ::lichess::puzzles::OnSelectActivity {} {
	variable Priv
	if {![info exists Priv(widget:activity)] || ![winfo exists $Priv(widget:activity)]} { return }
	set sel [$Priv(widget:activity) selection]
	if {[llength $sel]} {
		set Priv(lookupId) [lindex $sel 0]
	}
}


# ======================================================================
# Local 3-minute Storm & Puzzle Racer
# ======================================================================

proc ::lichess::puzzles::StartStorm {} {
	variable Priv
	variable StormDuration
	after cancel $Priv(stormTimer)
	set Priv(stormActive) 1
	set Priv(stormScore) 0
	set Priv(stormRemaining) $StormDuration
	set Priv(stormEndAt) [expr {[clock seconds] + $StormDuration}]
	UpdateStormStatus
	set Priv(stormTimer) [after 1000 [namespace code TickStorm]]
	FetchNext
	return 1
}


proc ::lichess::puzzles::TickStorm {} {
	variable Priv
	set Priv(stormTimer) {}
	if {!$Priv(stormActive)} { return }
	set rem [expr {$Priv(stormEndAt) - [clock seconds]}]
	if {$rem <= 0} {
		StopStorm 1
		return
	}
	set Priv(stormRemaining) $rem
	UpdateStormStatus
	set Priv(stormTimer) [after 1000 [namespace code TickStorm]]
}


proc ::lichess::puzzles::UpdateStormStatus {} {
	variable Priv
	variable mc
	set m [expr {$Priv(stormRemaining) / 60}]
	set s [expr {$Priv(stormRemaining) % 60}]
	set text [format $mc::StormRunning $Priv(stormScore) $m $s]
	set Priv(stormText) $text
	Status $text
}


proc ::lichess::puzzles::UpdateStormBest {} {
	variable Priv
	variable mc
	if {![string is integer -strict $::lichess::Options(stormBest)]
		|| $::lichess::Options(stormBest) < 0} {
		set ::lichess::Options(stormBest) 0
	}
	set Priv(stormBestText) [format $mc::StormBest $::lichess::Options(stormBest)]
}


proc ::lichess::puzzles::StopStorm {{completed 0}} {
	variable Priv
	variable mc
	after cancel $Priv(stormTimer)
	set Priv(stormTimer) {}
	# Only timer expiry of an active run may update the record.
	set completed [expr {$completed && $Priv(stormActive)
		&& [clock seconds] >= $Priv(stormEndAt)}]
	UpdateStormBest
	if {$completed && $Priv(stormScore) > $::lichess::Options(stormBest)} {
		set ::lichess::Options(stormBest) $Priv(stormScore)
		UpdateStormBest
	}
	set Priv(stormActive) 0
	set Priv(stormRemaining) 0
	set text [format [expr {$completed ? $mc::StormFinished : $mc::StormStopped}] $Priv(stormScore)]
	set Priv(stormText) $text
	Status $text
	return $Priv(stormScore)
}


proc ::lichess::puzzles::StartRacer {} {
	::lichess::api::puzzleRace [namespace code OnRacerCreated]
	return 1
}


proc ::lichess::puzzles::OnRacerCreated {reply} {
	variable Priv
	variable mc
	if {![dict exists $reply ok] || ![dict get $reply ok]} {
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Could not create Puzzle Racer."}]
		return
	}
	set d [expr {[dict exists $reply data] ? [dict get $reply data] : $reply}]
	set id [expr {[dict exists $d id] ? [dict get $d id] : ""}]
	set base [expr {[info exists ::lichess::api::Base] ? [string trimright $::lichess::api::Base /] : "https://lichess.org"}]
	# only a Lichess address is handed to the browser
	set url "$base/racer/[::lichess::api::Segment $id]"
	if {[dict exists $d url] && [string match "$base/*" [dict get $d url]]} { set url [dict get $d url] }
	set Priv(racerUrl) $url
	catch { ::lichess::api::OpenBrowser $url }
	Status [format $mc::RacerOpened $id]
}

# vi:set ts=3 sw=3:
