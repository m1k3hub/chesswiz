# =======================================================================
# Author : $Author$
# Version: $Revision: 1529 $
# Date   : $Date: 2018-11-22 05:48:49 -0500 (Thu, 22 Nov 2018) $
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
# Copyright: (C) 2010-2018 Gregor Cramer
# Modified for Chesswiz, 2026; see docs/UPSTREAM.md
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

::util::source analysis-pane

namespace eval application {
namespace eval analysis {
namespace eval mc {

set Control						"Control"
set Information				"Information"
set SetupEngine				"Setup engine"
set StartEngine				"Start engine"
set Pause						"Pause"
set Resume						"Resume"
set LockEngine					"Lock engine to current position"
set CloseEngine				"Power down motor"
set MultipleVariations		"Multiple variations"
set HashFullness				"Hash fullness"
set NodesPerSecond			"Nodes per second"
set TablebaseHits				"Tablebase hits"
set Hash							"Hash"
set Lines						"Lines"
set MateIn						"%color mate in %n"
set BestScore					"Best score (of current lines)"
set CurrentMove				"Currently searching this move"
set TimeSearched				"Time searched"
set SearchDepth				"Search depth in plies (Selective search depth)"
set IllegalPosition			"Illegal position - Cannot analyze"
set IllegalMoves				"Illegal moves in game - Cannot analyze"
set DidNotReceivePong		"Engine is not responding to \"ping\" command - Engine aborted"
set SearchMateNotSupported	"This engine is not supporting search for mate."
set EngineIsPausing			"This engine is currently pausing."
set PressEngineButton		"Use the locomotive for starting a motor."
set Stopped						"stopped"
set StopSearch					"Stop the search"
set StopSearchTip				"Stop the search (the engine keeps running)"
set StopTimedOut				"The engine did not stop within %s seconds and was powered down."
set NumberOfLines				"Number of lines the engine shows"
set OpponentsView				"Opponents view"
set InsertMoveAsComment		"Insert move as comment"
set SetupEvalEdges			"Setup evaluation edges"
set InvalidEdgeValues		"Invalid edge values."
set MustBeAscending			"The values must be strictly ascending as in the examples."
set StartMotor					"Start motor"
set StartOfMotorFailed		"Start of motor failed"
set WineIsNotInstalled		"'Wine' is not (properly) installed"
set AnalyzeThisPosition		"Analyze this position"
set PinToRepertoire			"Pin best line to repertoire"
set ExplainLine				"Explain this line"
set EngineComparison			"Engine Comparison"
set SelectEngines				"Engines to compare:"
set Seconds						"Seconds:"
set Engine						"Engine"
set Depth						"Depth"
set Eval							"Score"
set BestMove					"Best move"
set Nodes						"Nodes"
set Nps							"Nodes/s"
set StartComparison			"Start"
set StopComparison			"Stop"
set NeedTwoEngines			"Select at least two engines that can analyse."
set SecondsLeft				"%d seconds left"
set NoLinesYet					"No engine has a line yet."
set AgreeOn						"%d of %d engines choose %s."
set PrefersOther				"%s: %s."
set ScoreSpread				"Scores from %s to %s (spread %s)."
set DeepestSearch				"Deepest search: %s (depth %d)."
set NoveltyFound				"Novelty: move not in database"
set AnalyzeFromReport		"Analyze this position"
set OpponentDossierTitle			"Opponent Dossier: %s"
set DossierWhiteRepertoire		"White Repertoire"
set DossierBlackRepertoire		"Black Repertoire"
set DossierRecentGames			"Recent Games"
set DossierSummary					"Summary"
set DossierScore						"Score"
set DossierDate						"Date"
set DossierEvent						"Event"
set DossierOpponent					"Opponent"
set DossierResult						"Result"
set DossierRating						"Rating"
set DossierNoRecentGames			"No recent games"
set HighlightNovelties				"Highlight novelties"
set OpponentDossier					"Opponent Dossier"

set LinesPerVariation		"Lines per variation"
set BestFirstOrder			"Use \"best first\" order"
set Engine						"Engine"

set Ply							"ply"
set Seconds						"sec"
set Minutes						"min"

set Show(more)					"Show more"
set Show(less)					"Show less"

set Status(checkmate)		"%s is checkmate"
set Status(stalemate)		"%s is stalemate"
set Status(threechecks)		"%s got three checks"
set Status(losing)			"%s lost all pieces"
set Status(check)				"%s is in check"

set NotSupported(standard)	"This engine does not support standard chess."
set NotSupported(chess960)	"This engine does not support chess 960."
set NotSupported(variant)	"This engine does not support variant '%s'."
set NotSupported(analyze)	"This engine does not have an analysis mode."

set Signal(stopped)			"Engine stopped by signal."
set Signal(resumed)			"Engine resumed by signal."
set Signal(killed)			"Engine crashed or killed by signal."
set Signal(crashed)			"Engine crashed."
set Signal(closed)			"Engine has closed connection."
set Signal(terminated)		"Engine terminated with exit code %s."

set Add(move)					"Append move"
set Add(seq)					"Append variation"
set Add(var)					"Add move as new variation"
set Add(line)					"Add variation"
set Add(all)					"Add all variations"
set Add(merge)					"Merge variation"
set Add(incl)					"Merge all variations"

} ;# namespace mc

namespace import ::tcl::mathfunc::abs

array set Defaults {
	engine:bestFirst	1
	engine:nlines		1
	engine:multiPV		4
	engine:singlePV	0
	toolbar:info		less
}

array set GlobalOptions {
	background			analysis,background
	info:background	analysis,info:background
	info:foreground	analysis,info:foreground
	best:foreground	analysis,best:foreground
	error:foreground	analysis,error:foreground
	active:background	analysis,active:background
	engine:delay		250
	engine:stopTimeout	10000
	eval:edges			{ 45 75 175 400 }
	engine:font			TkTextFont
}
# Edge values:
# Scidb:		45	 75	175	400
# Scid:		50	150	300	550
# CB:			35	70		160

array set NumberToTree {}
set FreeNumbers {}

# from Scid
# array set Informant { !? 0.5 ? 1.5 ?? 3.0 ?! 0.5 }


proc build {parent number patternNumber} {
	variable ScoreEdgeValues
	variable GlobalOptions
	variable Defaults
	variable NumberToTree
	variable FreeNumbers

	namespace eval ${number} {}
	variable ${number}::Options

	set ScoreEdgeValues {}
	foreach score $GlobalOptions(eval:edges) nag {10 14 16 18} { lappend ScoreEdgeValues $score $nag }

	set mw $parent.mw
	set main $mw.main
	set mesg $mw.mesg
	set tree $main.tree

	namespace eval $tree {}
	variable ${tree}::Vars

	array set Vars {
		after:id				{}
		after:stop			{}
		best:0				black
		best:1				black
		current:item		0
		current:message	{}
		engine:locked		0
		engine:opponent	0
		engine:pause		0
		engine:state		normal
		engine:stopped		0
		info:height			0
		keep:active			0
		moves:max			0
		multiPV			1
		state:paused		0
		toolbar:childs		{}
		toolbar:height		0
		state:suspended	0
	}

	array set Options [array get ${patternNumber}::Options]
	foreach name [array names Defaults] {
		if {![info exists Options($name)]} { set Options($name) $Defaults($name) }
	}

	set bg [::colors::lookup $GlobalOptions(info:background)]
	set fg [::colors::lookup $GlobalOptions(info:foreground)]
	set mw [tk::multiwindow $mw -borderwidth 0 -background $bg -takefocus 0]

	if {!$Options(engine:bestFirst) && !$Options(engine:singlePV)} {
		set Vars(best:1) $GlobalOptions(best:foreground)
	}
	set Vars(linespace) [font metrics $GlobalOptions(engine:font) -linespace]
	set Vars(number) $number
	set Vars(widget:main) $main
	set Vars(widget:mesg) $mesg
	set Vars(widget:mw) $mw
	set menuCmd [namespace code [list PopupMenu $tree $number]]

	set charwidth [font measure $GlobalOptions(engine:font) "0"]
	set minsize [expr {12*$charwidth}]

	set main [tk::frame $main -takefocus 0 -borderwidth 0 -background $bg]
	bind $main <Destroy> [list ::toolbar::removeFromLayout board analysis:$number]
	set mesg [tk::label $mw.mesg \
		-takefocus 0 \
		-borderwidth 0 \
		-background [::colors::lookup $GlobalOptions(background)] \
	]
	bind $main <<LanguageChanged>> [namespace code LanguageChanged]
	bind $mesg <ButtonPress-3> $menuCmd

	$mw add $main -sticky nsew
	$mw add $mesg

	set info [tk::frame $main.info \
		-background [::colors::lookup $GlobalOptions(background)] \
		-borderwidth 0 \
		-takefocus 0 \
	]
	bind $info <ButtonPress-3> $menuCmd

	set score [tk::frame $info.score -background $bg -borderwidth 1 -relief raised -takefocus 0]
	set tscore [tk::text $info.score.t \
		-font $::font::text(text:normal) \
		-background $bg \
		-foreground $fg \
		-borderwidth 0 \
		-state disabled \
		-width 0 \
		-height 1 \
		-cursor {} \
		-takefocus 0 \
	]
	catch { $tscore configure -state readonly }
	$tscore tag configure center -justify center
	$tscore tag configure symbol -font $::font::symbol(text:normal)
	pack $tscore -padx 2 -pady 2
	set Vars(widget:info) $main.info

	set move [tk::frame $info.move -background $bg -borderwidth 1 -relief raised -takefocus 0]
	set tmove [tk::text $info.move.t \
		-font $::font::text(text:normal) \
		-background $bg \
		-foreground $fg \
		-borderwidth 0 \
		-state disabled \
		-width 0 \
		-height 1 \
		-cursor {} \
		-takefocus 0 \
	]
	catch { $tmove configure -state readonly }
	$tmove tag configure figurine -font $::font::figurine(text:normal)
	$tmove tag configure center -justify center
	$tmove tag configure stopped -foreground darkred
	pack $tmove -padx 2 -pady 2

	set time [tk::frame $info.time -background $bg -borderwidth 1 -relief raised -takefocus 0]
	set ttime [tk::label $info.time.t \
		-font $::font::text(text:normal) \
		-background $bg \
		-foreground $fg \
		-borderwidth 0 \
		-width 0 \
		-takefocus 0 \
	]
	pack $ttime -padx 2 -pady 2

	set depth [tk::frame $info.depth -background $bg -borderwidth 1 -relief raised -takefocus 0]
	set tdepth [tk::label $info.depth.t \
		-font $::font::text(text:normal) \
		-background $bg \
		-foreground $fg \
		-borderwidth 0 \
		-takefocus 0 \
		-width 0 \
	]
	pack $tdepth -padx 2 -pady 2

	bind $info <ButtonPress-3> [namespace code [list PopupMenu $tree $number]]

	set col 1
	foreach type {score move time depth} {
		grid [set $type] -column $col -row 0 -sticky ew -pady 2
		grid columnconfigure [set $type] 0 -weight 1
		grid [set t$type] -column 0 -row 1 -padx 2 -sticky ew
		incr col 2
		bind [set  $type] <ButtonPress-3> $menuCmd
		bind [set t$type] <ButtonPress-3> $menuCmd
	}

	::tooltip::tooltip $score  [namespace current]::mc::BestScore
	::tooltip::tooltip $tscore [namespace current]::mc::BestScore
	::tooltip::tooltip $move   [namespace current]::mc::CurrentMove
	::tooltip::tooltip $tmove  [namespace current]::mc::CurrentMove
	::tooltip::tooltip $time   [namespace current]::mc::TimeSearched
	::tooltip::tooltip $ttime  [namespace current]::mc::TimeSearched
	::tooltip::tooltip $depth  [namespace current]::mc::SearchDepth
	::tooltip::tooltip $tdepth [namespace current]::mc::SearchDepth

	grid columnconfigure $score 0 -minsize $minsize
	grid columnconfigure $move  0 -minsize $minsize
	grid columnconfigure $time  0 -minsize $minsize
	grid columnconfigure $depth 0 -minsize $minsize

	treectrl $tree \
		-takefocus 0 \
		-borderwidth 1 \
		-relief sunken \
		-showheader no \
		-selectmode single \
		-showroot no \
		-showlines no \
		-showrootlines no \
		-background [::colors::lookup $GlobalOptions(background)] \
		-font $GlobalOptions(engine:font) \
		;
	bind $tree <ButtonPress-3> [namespace code [list PopupMenu $tree $number %x %y]]
	bind $tree <ButtonPress-1> [namespace code [list AddMove $tree %x %y %s]]

	$tree notify install <Item-enter>
	$tree notify install <Item-leave>
	$tree notify bind Table <Item-enter> [namespace code [list VisitItem $tree enter %C %I %x %y]]
	$tree notify bind Table <Item-leave> [namespace code [list VisitItem $tree leave %C %I]]

	$tree element create elemRect rect \
		-open nw \
		-outline gray \
		-outlinewidth 1 \
		-fill [list [::colors::lookup $GlobalOptions(active:background)] active] \
		;
	$tree element create elemTextFig text \
		-lines $Options(engine:nlines) \
		-wrap word \
		-fill [::colors::lookup black] \
		-specialfont [list [list $::font::figurine(text:normal) 9812 9823]] \
		;
	$tree element create elemTextSym text \
		-lines $Options(engine:nlines) \
		-wrap word \
		-fill [::colors::lookup black] \
		-font $::font::symbol(text:normal) \
		;
	bind $tree <<ThemeChanged>> [namespace code [list ThemeChanged $tree]]

	$tree style create styleFig
	$tree style elements styleFig {elemRect elemTextFig}
	$tree style layout styleFig elemRect -detach yes -iexpand xy
	$tree style layout styleFig elemTextFig -padx {4 4} -pady {2 2} -squeeze x -sticky ne

	$tree style create styleSym
	$tree style elements styleSym {elemRect elemTextSym}
	$tree style layout styleSym elemRect -detach yes -iexpand xy
	$tree style layout styleSym elemTextSym -padx {4 4} -pady {2 2} -squeeze x -sticky ne

	$tree column create -steady yes -tags Eval  -width [expr {6*$charwidth}] -itemjustify center
	$tree column create -steady yes -tags Value -width [expr {8*$charwidth}] -itemjustify right
	$tree column create -steady yes -tags Moves -expand yes -squeeze yes -weight 1 -itemjustify left

	foreach i {0 1 2 3 4 5 6 7} {
		set item [$tree item create]
		$tree item lastchild root $item
		$tree item configure $item -tag Line$i
		$tree item style set $item Eval  styleSym
		$tree item style set $item Value styleFig
		$tree item style set $item Moves styleFig
	}

	grid $info -column 0 -row 0 -sticky ew
	grid $tree -column 0 -row 1 -sticky ewns

	grid columnconfigure $info {1 3 5 7} -weight 1
	grid columnconfigure $info {2 4 6} -minsize 2

	grid columnconfigure $main 0 -weight 1
	grid rowconfigure $main 1 -weight 1

	pack $mw -fill both -expand yes

	set Vars(widget:score) $info.score.t
	set Vars(widget:move) $info.move.t
	set Vars(widget:time) $info.time.t
	set Vars(widget:depth) $info.depth.t

	::toolbar::setup $parent -id analysis:$number -layout board
	set tbControl [::toolbar::toolbar $parent \
		-id analysis-control \
		-hide 0 \
		-side top \
		-alignment left \
		-allow {top bottom} \
		-tooltipvar [namespace current]::mc::Control \
		-avoidconfigurehack 1 \
	]
	set Vars(widget:button:pause) [::toolbar::add $tbControl button \
		-image $::icon::toolbarPause \
		-state disabled \
		-tooltipvar [namespace current]::mc::Pause \
		-command [namespace code [list Pause $tree]] \
	]
	trace add variable [namespace current]::${tree}::Vars(engine:pause) write \
		[namespace code [list ConfigurePause $tree]]
	lappend Vars(widget:toolbar:childs) $Vars(widget:button:pause)
	set Vars(widget:button:lock) [::toolbar::add $tbControl checkbutton \
		-image $::icon::toolbarLock \
		-variable [namespace current]::${tree}::Vars(engine:locked) \
		-state disabled \
		-tooltipvar [namespace current]::mc::LockEngine \
		-command [namespace code [list EngineLock $tree]] \
	]
	lappend Vars(widget:toolbar:childs) $Vars(widget:button:lock)
	set Vars(widget:button:opponent) [::toolbar::add $tbControl checkbutton \
		-image $::icon::toolbarRotateBoard \
		-variable [namespace current]::${tree}::Vars(engine:opponent) \
		-command [namespace code [list restartAnalysis $Vars(number)]] \
		-state disabled \
		-tooltipvar [namespace current]::mc::OpponentsView \
	]
	lappend Vars(widget:toolbar:childs) $Vars(widget:button:opponent)
	::toolbar::add $tbControl button \
		-image $::icon::toolbarEngine \
		-command [namespace code [list StartMotor $tree $number]] \
		-tooltipvar [namespace current]::mc::StartEngine \
		;
	# The square (stop) button stops the search, it does not power the engine
	# down: "stop" is sent and the engine answers with its last lines and
	# "bestmove". Powering down is the separate "close" of the context menu.
	set Vars(widget:button:stop) [::toolbar::add $tbControl button \
		-image $::icon::toolbarStop \
		-tooltipvar [namespace current]::mc::StopSearchTip \
		-command [namespace code [list Stop $tree]] \
		-state disabled \
	]
	lappend Vars(widget:toolbar:childs) $Vars(widget:button:stop)
	set Vars(widget:button:close) [::toolbar::add $tbControl button \
		-image $::icon::16x16::close \
		-tooltipvar [namespace current]::mc::CloseEngine \
		-command [namespace code [list CloseEngine $tree]] \
		-state disabled \
	]
	::toolbar::addSeparator $tbControl
	set Vars(widget:button:pin) [::toolbar::add $tbControl button \
		-image $icon::16x16::insert \
		-tooltipvar [namespace current]::mc::PinToRepertoire \
		-command [namespace code [list PinToRepertoire $tree]] \
		-state disabled \
	]
	lappend Vars(widget:toolbar:childs) $Vars(widget:button:pin)
	set tbw [::toolbar::add $tbControl checkbutton \
		-image $::icon::toolbarLines \
		-variable [namespace current]::${number}::Options(engine:singlePV) \
		-onvalue 0 \
		-offvalue 1 \
		-tooltipvar [namespace current]::mc::MultipleVariations \
		-command [namespace code [list SetMultiPV $tree]] \
	]
	#lappend Vars(widget:toolbar:childs) $tbw
	set Vars(widget:ordering) [::toolbar::add $tbControl checkbutton \
		-image $::icon::toolbarSort(descending) \
		-variable [namespace current]::${number}::Options(engine:bestFirst) \
		-tooltipvar [namespace current]::mc::BestFirstOrder \
		-command [namespace code [list SetOrdering $tree]] \
	]
	#lappend Vars(widget:toolbar:childs) $Vars(widget:ordering)
	::toolbar::addSeparator $tbControl
	# The Lines spinner shows the number of lines the engine is asked for
	# (MultiPV), which is what the pane renders; changing it changes MultiPV.
	# "Lines per variation" (how many plies of each line are wrapped) stays in
	# the context menu.
	::toolbar::add $tbControl label -textvar [namespace current]::mc::Lines
	set Vars(multiPV) [expr {$Options(engine:singlePV) ? 1 : $Options(engine:multiPV)}]
	set lpv [::toolbar::add $tbControl ::ttk::spinbox \
		-tooltipvar [namespace current]::mc::NumberOfLines \
		-from 1 \
		-to 8 \
		-width 2 \
		-justify right \
		-state readonly \
		-cursor {} \
		-takefocus 0 \
		-textvar [namespace current]::${tree}::Vars(multiPV) \
		-exportselection no \
		-command [namespace code [list SetLines $tree]] \
	]
	::theme::configureSpinbox $lpv
	set Vars(widget:linesPerPV) $lpv
	::toolbar::add $tbControl frame -width 3
	set Vars(widget:toolbar:control) $tbControl
	bind $tbControl <Configure> [list set [namespace current]::${tree}::Vars(toolbar:height) %h]

	set tbInfo [::toolbar::toolbar $parent \
		-id analysis-info \
		-hide 0 \
		-side top \
		-alignment left \
		-allow {top bottom} \
		-tooltipvar [namespace current]::mc::Information \
	]
	set infoLabelBg [expr {[::theme::isDark] ? "#1b1f27" : "#e0e0e0"}]
	set infoLabelFg [expr {[::theme::isDark] ? "#e6edf3" : "#000000"}]
	::toolbar::add $tbInfo label -textvar [namespace current]::mc::Hash
	set Vars(widget:hashfullness) [::toolbar::add $tbInfo label \
		-width 5 \
		-justify center \
		-background $infoLabelBg \
		-foreground $infoLabelFg \
		-relief raised \
		-borderwidth 1 \
		-tooltipvar [namespace current]::mc::HashFullness \
	]
	set Vars(widget:show) \
		[::toolbar::add $tbInfo button -command [namespace code [list ToggleInfo $tree]]]
	set Vars(widget:nps:label) [::toolbar::add $tbInfo label -text "NPS"]
	set Vars(widget:nps) [::toolbar::add $tbInfo label \
		-width 9 \
		-justify center \
		-background $infoLabelBg \
		-foreground $infoLabelFg \
		-relief raised \
		-borderwidth 1 \
		-tooltipvar [namespace current]::mc::NodesPerSecond \
	]
	set Vars(widget:tbhits:label) [::toolbar::add $tbInfo label -text "TB hits"]
	set Vars(widget:tbhits) [::toolbar::add $tbInfo label \
		-width 5 \
		-justify center \
		-background $infoLabelBg \
		-foreground $infoLabelFg \
		-relief raised \
		-borderwidth 1 \
		-tooltipvar [namespace current]::mc::TablebaseHits \
	]

	set NumberToTree($number) $tree
	# Explicit-number callers can reopen a closed pane without newNumber.
	# Its number is occupied again, including any repeated free-list entries.
	set FreeNumbers [lsearch -all -inline -not -exact $FreeNumbers $number]
	ConfigureInfo $tree
	SetState $tree disabled
	Layout $tree
	DisplayPressEngineButton $tree
}


proc exists? {number} {
	variable NumberToTree
	return [info exists NumberToTree($number)]
}


proc active? {number} {
	if {![exists? $number]} { return false }
	variable NumberToTree
	set tree $NumberToTree($number)
	return [::engine::active? [set ${tree}::Vars(number)]]
}


proc newNumber {} {
	variable NumberToTree
	variable FreeNumbers
	
	if {[llength $FreeNumbers]} {
		set n [lindex $FreeNumbers 0]
		set FreeNumbers [lrange $FreeNumbers 1 end]
		return $n
	}

	if {[array size NumberToTree] == 0} { return 1 }
	return [expr {[lindex [lsort -integer -decreasing [array names NumberToTree]] 0] + 1}]
}


proc update {args} {
	variable GlobalOptions
	variable NumberToTree

	foreach number [array names NumberToTree] {
		variable [set [namespace current]::NumberToTree($number)]::Vars

		if {[info exists Vars(after:id)]} {
			after cancel $Vars(after:id)
		}
		# a stopped pane does not follow the board with a new search
		if {[::engine::active? $number] && !$Vars(engine:locked) && !$Vars(engine:stopped)} {
			set Vars(after:id) [after $GlobalOptions(engine:delay) [list ::engine::startAnalysis $number]]
		}
	}
}


proc startAnalysis {number} {
	variable NumberToTree

	if {![exists? $number]} {
		::application::newAnalysisPane $number
	}
	set tree [set NumberToTree($number)]
	variable ${tree}::Vars
	variable ${Vars(number)}::Options

	set Vars(current:message) {}
	$Vars(widget:mesg) configure -text ""
	::engine::kill $number
	after cancel $Vars(after:id)
	after cancel $Vars(after:stop)
	set Vars(after:stop) {}
	set Vars(engine:stopped) 0

	set isReadyCmd [namespace current]::IsReady
	set signalCmd [namespace current]::Signal
	set updateCmd [namespace current]::UpdateInfo

	Display(start) $tree $number
	set rc [::engine::startEngine $number $isReadyCmd $signalCmd $updateCmd $tree]

	if {![string is integer -strict $rc] || $rc == -2} {
		DisplayStartOfMotorFailed $tree $rc
		set rc -1
	}

	# TODO: in case that the user is starting more than one Stockfish engine
	# we have to show the more detailed name.
	::application::updateAnalysisTitle $number [::engine::engineName $number]
	set Vars(engine:pause) [expr {![engine::active? $number]}]

	if {!$Vars(engine:pause)} {
		if {$Options(engine:bestFirst)} { set order bestFirst } else { set order unordered }
		::scidb::engine::ordering [::engine::id $number] $order
		set multiPV [MultiPV $number]
		set Vars(multiPV) $multiPV
		::engine::activateEngine $number [list multiPV $multiPV]
	}
}


# The lines engine of pane <number> shows now, best first when so ordered:
# one {score mate depth seldepth time nodes nps tbhits pv} per row, the
# score in centipawns from White's side.
proc lines {number} {
	variable NumberToTree

	if {![exists? $number]} { return {} }
	variable $NumberToTree($number)::Vars
	variable ${number}::Options

	if {$Options(engine:singlePV)} { set n 1 } else { set n $Options(engine:multiPV) }
	set most [MaxMultiPV $number]
	if {$n > $most} { set n $most }
	set result {}
	for {set row 0} {$row < $n} {incr row} {
		if {[info exists Vars(lines:$row)]} { lappend result $Vars(lines:$row) }
	}
	return $result
}


proc setLines {number n} {
	variable NumberToTree
	SetMultiPV $NumberToTree($number) $n
}


proc stopEngine {number} {
	variable NumberToTree
	if {[exists? $number]} { CloseEngine $NumberToTree($number) }
}


proc restartAnalysis {number} {
	if {![::engine::active? $number]} { return }
	variable NumberToTree
	set tree [set NumberToTree($number)]
	variable ${tree}::Vars
	variable ${Vars(number)}::Options

	after cancel $Vars(after:id)
	# the opponent view is asked for by the user: it searches again
	after cancel $Vars(after:stop)
	set Vars(after:stop) {}
	if {$Vars(engine:stopped)} {
		set Vars(engine:stopped) 0
		set Vars(engine:pause) 0
	}
	::engine::restartAnalysis $number $Vars(engine:opponent) [list multiPV [MultiPV $number]]
	::application::updateAnalysisTitle $number [::engine::engineName $number]
}


proc activate {w flag} {
	::toolbar::activate $w $flag
}


proc closed {w} {
	variable NumberToTree
	variable FreeNumbers

	set tree ${w}.mw.main.tree
	variable ${tree}::Vars

	after cancel $Vars(after:id)
	after cancel $Vars(after:stop)
	array unset NumberToTree $Vars(number)
	lappend FreeNumbers $Vars(number)
	::engine::forget $Vars(number)

	if {[winfo exists $Vars(widget:button:close)]} {
		::toolbar::childconfigure $Vars(widget:button:close) -state disabled
	}
	if {[winfo exists $Vars(widget:button:stop)]} {
		::toolbar::childconfigure $Vars(widget:button:stop) -state disabled
	}
}


proc clearHash {number} {
	Display(hash) [set [namespace current]::NumberToTree($number)] 0
}


# Stops the search of the pane's engine but keeps the engine: "stop" goes to
# the engine, which answers with its last lines and "bestmove". Nothing here
# waits for that answer -- waiting would block the Tk event loop, and an
# engine which does not answer at all would freeze the application (F-11).
# The timeout powers the engine down instead.
proc Stop {tree} {
	variable GlobalOptions
	variable ${tree}::Vars

	if {![::engine::active? $Vars(number)]} { return }
	if {$Vars(engine:stopped)} { return }

	after cancel $Vars(after:id)
	set Vars(engine:stopped) 1
	set Vars(engine:pause) 1
	ShowMessage $tree info $mc::Stopped
	UpdatePinState $tree
	StopSearch $tree
}


# Sends "stop" and arms the timeout of the pane's stopped search. The engine
# may be between two searches (an "isready" of a restart is still in flight),
# in which case there is nothing to stop now and nothing to wait for.
proc StopSearch {tree} {
	variable GlobalOptions
	variable ${tree}::Vars

	if {[string length $Vars(after:stop)]} {
		after cancel $Vars(after:stop)
		set Vars(after:stop) {}
	}
	if {![::engine::stopAnalysis $Vars(number)]} { return }
	# Only UCI sends "bestmove" in answer to "stop"; WinBoard engines send "exit"
	# (and handle their own ping/pong timeout in C++).
	if {[info exists ::engine::$Vars(number)::Vars(current:protocol)]
		&& [set ::engine::$Vars(number)::Vars(current:protocol)] ne "UCI"} {
		return
	}

	set Vars(after:stop) [after $GlobalOptions(engine:stopTimeout) \
		[namespace code [list StopTimedOut $tree [::engine::id $Vars(number)]]]]
}


# A search started although the user stopped it: an "isready" of a restart was
# still in flight, or the board was changed. The stop wins, so stop it again.
proc StopAgain {tree} {
	variable ${tree}::Vars

	if {![winfo exists $tree]} { return }
	if {!$Vars(engine:stopped) || ![::engine::active? $Vars(number)]} { return }
	StopSearch $tree
}


# The Lines spinner: what it shows is the number of lines (MultiPV) the engine
# is asked for, so a change of it changes the MultiPV of the engine.
proc SetLines {tree} {
	variable ${tree}::Vars

	set n $Vars(multiPV)
	if {![string is integer -strict $n] || $n < 1} {
		# the spinner is readonly, but a script may have put nonsense in it
		Layout $tree
		return
	}
	SetMultiPV $tree $n
}


# Called when the engine answered "stop" with its last best move.
proc StopFinished {tree} {
	variable ${tree}::Vars

	set Vars(after:stop) {}
	if {$Vars(engine:stopped)} { ShowMessage $tree info $mc::Stopped }
}


# The engine did not answer "stop": it is gone, or it is hung. Power it
# down, exactly as "close" does, instead of waiting for it for ever.
proc StopTimedOut {tree engineId} {
	variable GlobalOptions
	variable ${tree}::Vars

	set Vars(after:stop) {}
	if {![winfo exists $tree]} { return }
	if {[::engine::id $Vars(number)] != $engineId} { return }

	set seconds [expr {$GlobalOptions(engine:stopTimeout)/1000}]
	set msg [format $mc::StopTimedOut $seconds]
	set Vars(current:message) [list [namespace current]::ShowMessage $tree error $msg]
	CloseEngine $tree
	# close asks for the engine button in an idle callback: the reason why the
	# engine went away has to be what the user sees
	after idle [namespace code [list ShowMessage $tree error $msg]]
}


proc CloseEngine {tree} {
	variable ${tree}::Vars

	# a pending stop timer refers to an engine which is about to go away
	after cancel $Vars(after:stop)
	set Vars(after:stop) {}
	set Vars(engine:stopped) 0

	::engine::kill $Vars(number)
	::toolbar::childconfigure $Vars(widget:button:close) -state disabled
	::toolbar::childconfigure $Vars(widget:button:stop) -state disabled
	UpdatePinState $tree
	::application::updateAnalysisTitle $Vars(number)
	after idle [namespace code [list DisplayPressEngineButton $tree]]
	# The pane is content-empty again: let the dynamic layout collapse it
	# (VAL-PANE-010), exactly as it does for a fresh pane.
	catch { ::application::reflow::onPaneStateChange }
}


proc Pause {tree} {
	variable ${tree}::Vars
	if {![::engine::active? $Vars(number)]} { return }

	set Vars(engine:pause) [expr {!$Vars(engine:pause)}]

	if {$Vars(engine:pause)} {
		after cancel $Vars(after:id)
		::engine::pause $Vars(number)
	} elseif {$Vars(engine:stopped)} {
		# the search was stopped, not paused: start it again
		set Vars(engine:stopped) 0
		::engine::startAnalysis $Vars(number)
		ConfigurePause $tree
	} else {
		::engine::resume $Vars(number)
	}
}


proc ConfigurePause {tree args} {
	if {![winfo exists $tree]} { return }
	variable ${tree}::Vars

	if {$Vars(engine:pause)} {
		set icon $::icon::toolbarStart
		if {$Vars(engine:stopped)} {
			set tip [namespace current]::mc::StartMotor
		} else {
			set tip [namespace current]::mc::Resume
		}
	} else {
		set icon $::icon::toolbarPause
		set tip [namespace current]::mc::Pause
	}
	::toolbar::childconfigure $Vars(widget:button:pause) -image $icon -tooltipvar $tip
}


proc StartMotor {tree number} {
	# A fresh pane has no engine process to resume or restart. Load its
	# selected engine first; without a selection, use the usual default.
	if {![::engine::active? $number]} {
		::engine::initVars $number
		namespace upvar ::engine::$number Vars engine
		set name $engine(current:name)
		if {![CanAnalyse $name]} { set name [defaultEngine] }
		if {$name ne ""} {
			startEngine $name $number
			return
		}
	}
	Setup $tree $number
}


proc Setup {tree number} {
	::engine::openSetup [winfo toplevel $tree] $number
}


proc ToggleInfo {tree} {
	variable ${tree}::Vars
	variable ${Vars(number)}::Options

	if {$Options(toolbar:info) eq "more"} {
		set Options(toolbar:info) less
	} else {
		set Options(toolbar:info) more
	}

	ConfigureInfo $tree
}


proc ConfigureInfo {tree} {
	variable ${tree}::Vars
	variable ${Vars(number)}::Options

	switch $Options(toolbar:info) {
		more {
			set arrow $icon::11x14::arrowLeft
			set ttv [namespace current]::mc::Show(less)
			set visible yes
		}
		less {
			set arrow $icon::11x14::arrowRight
			set ttv [namespace current]::mc::Show(more)
			set visible no
		}
	}

	::toolbar::childconfigure $Vars(widget:show) -image $arrow -tooltipvar $ttv
	::toolbar::childconfigure $Vars(widget:nps:label) -visible $visible
	::toolbar::childconfigure $Vars(widget:nps) -visible $visible
	::toolbar::childconfigure $Vars(widget:tbhits:label) -visible $visible
	::toolbar::childconfigure $Vars(widget:tbhits) -visible $visible
}


proc SetOrdering {tree} {
	variable ${tree}::Vars
	variable ${Vars(number)}::Options
	variable GlobalOptions

	if {$Options(engine:bestFirst) || $Options(engine:singlePV)} {
		set Vars(best:1) black
	} else {
		set Vars(best:1) [::colors::lookup $GlobalOptions(best:foreground)]
	}

	if {$Options(engine:bestFirst)} {
		set order bestFirst
	} else {
		set order unordered
	}

	if {[::engine::active? $Vars(number)]} {
		::scidb::engine::ordering [::engine::id $Vars(number)] $order
	}

	if {$Options(engine:bestFirst)} {
		set fg [::colors::lookup black]
		foreach i {0 1 2 3 4 5 6 7} {
			$tree item element configure Line$i Eval  elemTextSym -fill $fg
			$tree item element configure Line$i Value elemTextFig -fill $fg
		}
	}
}


proc ThemeChanged {tree} {
	if {![winfo exists $tree]} { return }
	variable GlobalOptions
	variable ${tree}::Vars

	set bg [::colors::lookup $GlobalOptions(background)]
	set infobg [::colors::lookup $GlobalOptions(info:background)]
	set infofg [::colors::lookup $GlobalOptions(info:foreground)]
	set fg [::colors::lookup black]

	catch { $tree configure -background $bg }
	catch {
		$tree element configure elemRect \
			-fill [list [::colors::lookup $GlobalOptions(active:background)] active]
		$tree element configure elemTextFig -fill $fg
		$tree element configure elemTextSym -fill $fg
	}
	foreach i {0 1 2 3 4 5 6 7} {
		catch { $tree item element configure Line$i Eval  elemTextSym -fill $fg }
		catch { $tree item element configure Line$i Value elemTextFig -fill $fg }
		catch { $tree item element configure Line$i Moves elemTextFig -fill $fg }
	}
	catch { $Vars(widget:mw) configure -background $infobg }
	catch { $Vars(widget:main) configure -background $infobg }
	catch { $Vars(widget:mesg) configure -background $bg -foreground $infofg }
	catch { $Vars(widget:info) configure -background $bg }
	foreach type {score move time depth} {
		catch { $Vars(widget:info).$type configure -background $infobg }
		catch { $Vars(widget:info).$type.t configure -background $infobg -foreground $infofg }
	}
	set infoLabelBg [expr {[::theme::isDark] ? "#1b1f27" : "#e0e0e0"}]
	set infoLabelFg [expr {[::theme::isDark] ? "#e6edf3" : "#000000"}]
	foreach wkey {widget:hashfullness widget:nps widget:tbhits} {
		if {[info exists Vars($wkey)] && [winfo exists $Vars($wkey)]} {
			catch { $Vars($wkey) configure -background $infoLabelBg -foreground $infoLabelFg }
		}
	}
}


proc EngineLock {tree} {
	variable ${tree}::Vars

	if {[::engine::active? $Vars(number)] && !$Vars(engine:locked)} {
		after cancel $Vars(after:id)
		after idle [list ::engine::startAnalysis $Vars(number)]
	}
}




proc ClearLines {tree args} {
	set fg [::colors::lookup black]
	foreach i $args {
		$tree item element configure Line$i Eval  elemTextSym -text "" -fill $fg
		$tree item element configure Line$i Value elemTextFig -text "" -fill $fg
		$tree item element configure Line$i Moves elemTextFig -text "" -fill $fg
	}
}


# The number of lines the engine of pane <number> can be asked for: the pane
# has rows for eight lines, and the engine may support fewer.
proc MaxMultiPV {number} {
	set most 8

	if {![namespace exists ::engine::$number]} { return $most }
	variable ::engine::${number}::Vars
	if {![info exists Vars(current:name)] || ![info exists Vars(current:protocol)]} {
		return $most
	}

	set index [::engine::FindIndex $Vars(current:name)]
	if {$index < 0} { return $most }
	# the protocol the pane's engine is running with (probed features differ)
	set protocol $Vars(current:protocol)
	if {$protocol ne "UCI" && $protocol ne "WinBoard"} { return $most }

	set engine [lindex $::engine::Engines $index]
	if {![dict exists $engine Features:$protocol]} { return $most }
	set features [dict get $engine Features:$protocol]
	if {[dict exists $features multiPV]} {
		set value [dict get $features multiPV]
		if {[string is integer -strict $value] && $value > 0} {
			set most [expr {min($most, $value)}]
		}
	}
	return $most
}


# The number of lines the engine of pane <number> is asked for right now, i.e.
# the MultiPV it runs with (one line while "multiple variations" is off).
proc MultiPV {number} {
	variable NumberToTree

	if {![exists? $number]} { return 1 }
	variable ${number}::Options

	# an engine may support fewer lines than the pane has rows
	set most [MaxMultiPV $number]
	if {$Options(engine:multiPV) > $most} { set Options(engine:multiPV) $most }
	if {$Options(engine:multiPV) < 1} { set Options(engine:multiPV) 1 }

	return [expr {$Options(engine:singlePV) ? 1 : $Options(engine:multiPV)}]
}


proc SetMultiPV {tree {number 0}} {
	variable GlobalOptions
	variable ${tree}::Vars
	variable ${Vars(number)}::Options

	if {$number} {
		if {$number == 1} {
			set Options(engine:singlePV) 1
		} else {
			set Options(engine:singlePV) 0
			set Options(engine:multiPV) $number
		}
	}

	# the engine may support fewer lines than the pane has rows (MultiPV
	# clamps the request, and the spinner shows the value which resulted)
	set multiPV [MultiPV $Vars(number)]
	if {[::engine::active? $Vars(number)]} {
		::scidb::engine::multiPV [::engine::id $Vars(number)] $multiPV
	}
	if {$Options(engine:bestFirst) || $Options(engine:singlePV)} {
		set Vars(best:1) black
	} else {
		set Vars(best:1) [::colors::lookup $GlobalOptions(best:foreground)]
	}
	Layout $tree
}


proc SetLinesPerPV {tree} {
	variable ${tree}::Vars

	# the radio buttons of the context menu write Options(engine:nlines)
	Layout $tree
}


proc Layout {tree} {
	variable ${tree}::Vars
	variable ${Vars(number)}::Options

	if {$Options(engine:singlePV)} {
		set pvcount 1
		set nlines 4
		set state disabled
	} else {
		set pvcount $Options(engine:multiPV)
		set nlines $Options(engine:nlines)
		set state readonly
	}

	# the spinner always shows the MultiPV the engine runs with
	set Vars(multiPV) $pvcount

	if {$nlines == 1} {
		set lines 0
		set wrap none
	} else {
		set lines $nlines
		set wrap word
	}

	for {set i 0} {$i < $pvcount} {incr i} {
		$tree item configure Line$i -visible 1
		$tree item element configure Line$i Moves elemTextFig -lines $lines -wrap $wrap
	}

	for {} {$i < 8} {incr i} {
		$tree item configure Line$i -visible 0
		$tree item element configure Line$i Moves elemTextFig -lines $lines -wrap $wrap
		ClearLines $tree $i
	}

	set theight [expr {$nlines*$pvcount*$Vars(linespace) + $pvcount*4}]
	set lheight [expr {$nlines*$Vars(linespace)}]
	$tree configure -height $theight
#	$tree style layout styleFig elemText -padx {4 4} -pady {2 2} -squeeze x -sticky ne -minheight $lheight
	$tree style layout styleFig elemTextFig -minheight $lheight
	$tree style layout styleSym elemTextSym -minheight $lheight
	::toolbar::childconfigure $Vars(widget:linesPerPV) -state $state
	set most [MaxMultiPV $Vars(number)]
	if {$most < $Vars(multiPV)} { set most $Vars(multiPV) }
	catch { [::toolbar::lookupChild $Vars(widget:linesPerPV)] configure -to $most }
#	::toolbar::childconfigure $Vars(widget:ordering) -state $state
	after idle [namespace code [list ResizePane $tree $theight]]
}


proc ResizePane {tree height} {
	variable ${tree}::Vars

	# an idle callback may still run when the pane has been closed
	if {![winfo exists $tree] || ![winfo exists $Vars(widget:info)]} { return }
	if {$height <= 1 || $Vars(toolbar:height) <= 1} { return }
	incr height $Vars(toolbar:height)
	incr height [winfo height $Vars(widget:info)]
	incr height 5 ;# borders
	[namespace parent]::resizePaneHeight $Vars(number) $height
}


proc SetState {tree state} {
	variable ${tree}::Vars

	set Vars(state:paused) 0
	$Vars(widget:mw) raise $Vars(widget:main)

	if {![winfo exists $tree]} { return }
	if {$Vars(engine:state) eq $state} { return }

	set Vars(engine:state) $state

	foreach child $Vars(widget:toolbar:childs) {
		::toolbar::childconfigure $child -state $state
	}
}


proc EvalText {score mate} {
	variable ScoreEdgeValues

	if {$mate} {
		if {$mate > 0} { set nag 20 } else { set nag 21 }
	} else {
		set value [abs $score]
		set nag 20

		foreach {barrier nagv} $ScoreEdgeValues {
			if {$value < $barrier} {
				set nag $nagv
				break
			}
		}

		if {$score < 0 && $nag != 10} { incr nag }
	}

	return $nag
}


proc ScoreText {score mate} {
	if {$mate == 0} { return [FormatScore $score] }
	if {$mate < 0} { set sign "\u2212" } else { set sign "+" }
	return "$sign#[abs $mate]"
}


proc FormatScore {score} {
	set p [expr {abs($score)/100}]
	set cp [expr {abs($score) % 100}]
	if {$score < 0} {
		set sign "\u2212"
	} elseif {$score > 0} {
		set sign "+"
	} else {
		set sign ""
	}
	return [format "$sign%d.%02d" $p $cp]
}


proc ShowMessage {tree type txt} {
	variable ${tree}::Vars
	variable GlobalOptions

	# an idle callback may still run when the pane has been closed
	if {![winfo exists $tree] || ![winfo exists $Vars(widget:mw)]} { return }

	set width [expr {[winfo width $Vars(widget:mw)] - 50}]
	$Vars(widget:mesg) configure \
		-text $txt \
		-wraplength $width \
		-foreground [::colors::lookup $GlobalOptions($type:foreground)] \
		;
	$Vars(widget:mw) raise $Vars(widget:mesg)
}


proc DisplayPressEngineButton {tree} {
	variable ${tree}::Vars

	set Vars(current:message) [list [namespace current]::DisplayPressEngineButton $tree]
	ShowMessage $tree info $mc::PressEngineButton
}


proc DisplayStartOfMotorFailed {tree rc} {
	variable ${tree}::Vars

	set msg $mc::StartOfMotorFailed
	append msg ": "
	if {![string is integer -strict $rc]} {
		append msg "\"" $rc "\""
	} else {
		append msg $mc::WineIsNotInstalled
	}
	append msg "."
	set Vars(current:message) [list [namespace current]::DisplayStartOfMotorFailed $tree $rc]
	ShowMessage $tree error $msg
}


proc Display(state) {tree state} {
	variable ${tree}::Vars

	switch $state {
		stop	{
			if {$Vars(engine:stopped)} {
				# a stop by the user: the engine keeps running and the lines it
				# found stay on screen; the start button restarts the search
				SetState $tree disabled
				::toolbar::childconfigure $Vars(widget:button:close) -state normal
				set Vars(engine:pause) 1
				::toolbar::childconfigure $Vars(widget:button:pause) -state normal
				ShowMessage $tree info $mc::Stopped
			} else {
				SetState $tree disabled
				::toolbar::childconfigure $Vars(widget:button:close) -state disabled
				Display(clear) $tree
			}
		}

		start	{
			SetState $tree normal
			::toolbar::childconfigure $Vars(widget:button:close) -state normal
			if {$Vars(engine:stopped)} {
				# the stop wins over a search which was already on its way
				::toolbar::childconfigure $Vars(widget:button:stop) -state disabled
				after idle [namespace code [list StopAgain $tree]]
			} else {
				::toolbar::childconfigure $Vars(widget:button:stop) -state normal
			}
		}

		pause {
			if {!$Vars(state:paused)} {
				$Vars(widget:move) delete begin end
				if {[$Vars(widget:mw) raise] eq $Vars(widget:mesg)} {
					ShowMessage $tree info $mc::EngineIsPausing
				} else {
					$Vars(widget:move) insert end $mc::Stopped {stopped center}
				}
				set Vars(state:paused) 1
			}
		}

		resume {
			$Vars(widget:move) delete begin end
			SetState $tree normal
			set Vars(engine:pause) 0
			$Vars(widget:button:close) configure -state normal
		}
	}
}


proc Display(clear) {tree} {
	variable ${tree}::Vars

	set Vars(current:message) {}
	$Vars(widget:mesg) configure -text ""
	$Vars(widget:mw) raise $Vars(widget:main)

	$Vars(widget:score) delete begin end
	$Vars(widget:move) delete begin end
	$Vars(widget:depth) configure -text ""
	$Vars(widget:time) configure -text ""

	[::toolbar::lookupChild $Vars(widget:hashfullness)] configure -text ""
	[::toolbar::lookupChild $Vars(widget:nps)] configure -text ""
	[::toolbar::lookupChild $Vars(widget:tbhits)] configure -text ""
	set Vars(moves:max) 0

	ClearLines $tree 0 1 2 3 4 5 6 7
	$tree activate 0
}


proc Display(pv) {tree score mate depth seldepth time nodes nps tbhits line pv} {
	variable ${tree}::Vars
	variable ${Vars(number)}::Options

	set Vars(pv:$line) $pv

	if {$Vars(state:suspended)} {
		set args [list $score $mate $depth $seldepth $time $nodes $nps $tbhits $line $pv]
		set Vars(suspended,[lindex $args 9]) $args
	} else {
		Display(time) $tree $time $depth $seldepth $nodes $nps $tbhits

		set evalTxt [::font::mapNagToSymbol [EvalText $score $mate]]
		set scoreTxt [ScoreText $score $mate]

		$tree item element configure Line$line Eval  elemTextSym -text $evalTxt
		$tree item element configure Line$line Value elemTextFig -text $scoreTxt
		$tree item element configure Line$line Moves elemTextFig -text [::font::translate $pv]

		if {$line + 1 == $Vars(current:item)} {
			$tree activate $Vars(current:item)
		}
	}
}


proc Display(bestscore) {tree score mate bestLines} {
	variable ${tree}::Vars

	$Vars(widget:score) delete begin end
	if {$mate} {
		if {$mate < 0} { set stm White } else { set stm Black }
		set color [string index [set ::mc::$stm] 0]
		set scoreTxt [string map [list %color $color %n [abs $mate]] $mc::MateIn]
	} else {
		set scoreTxt "  "
		append scoreTxt [FormatScore $score]
		lassign [::font::splitAnnotation [EvalText $score $mate]] value sym tags
		lappend tags center
		$Vars(widget:score) insert end $sym $tags
	}
	$Vars(widget:score) insert end $scoreTxt center

	set line 0
	foreach best $bestLines {
		set color [::colors::lookup $Vars(best:$best)]
		$tree item element configure Line$line Eval  elemTextSym -fill $color
		$tree item element configure Line$line Value elemTextFig -fill $color
		if {$best} {
			set evalTxt [::font::mapNagToSymbol [EvalText $score $mate]]
			set scoreTxt [ScoreText $score $mate]
			$tree item element configure Line$line Eval  elemTextSym -text $evalTxt
			$tree item element configure Line$line Value elemTextFig -text $scoreTxt
		}
		incr line
	}
}


proc Display(start) {tree number} {
	variable ${tree}::Vars

	append msg "$mc::StartMotor \""
	append msg [join [::engine::startCommand $number] " "]
	append msg "\" ..."
	ShowMessage $tree info $msg
}


proc Display(over) {tree state color} {
	variable ${tree}::Vars

	set Vars(current:message) [list [namespace current]::Display(over) $tree $state $color]
	ShowMessage $tree info [format $mc::Status($state) [set ::mc::[string toupper $color 0 0]]]
}


proc Display(move) {tree number count move} {
	variable ${tree}::Vars

	if {$count > 0} {
		set Vars(moves:max) $count
	} elseif {$Vars(moves:max) < $number} {
		set Vars(moves:max) $number
	}

	$Vars(widget:move) delete begin end
	$Vars(widget:move) insert end [::font::translate $move] {figurine center}
	if {$number > 0} {
		$Vars(widget:move) insert end " ($number/$Vars(moves:max))"
	}
}


proc Display(time) {tree time depth seldepth nodes nps tbhits} {
	variable ${tree}::Vars

	if {$depth} {
		set txt $depth
		if {$seldepth} { append txt " (" $seldepth ")" }
		append txt " " $mc::Ply
		$Vars(widget:depth) configure -text $txt
	}

	if {$time > 0.0} {
		set txt ""
		set seconds [lindex [split $time .] 0]
		set minutes [expr {$seconds/60}]
		if {$minutes} {
			set seconds [expr {$seconds % 60}]
			append txt $minutes ":"
			if {[string length $seconds] == 1} { append txt "0" }
			append txt $seconds " " $mc::Minutes
		} elseif {$seconds} {
			append txt $seconds " " $mc::Seconds
		}
		$Vars(widget:time) configure -text $txt
	}

	if {$nps} {
		[::toolbar::lookupChild $Vars(widget:nps)] configure -text [::locale::formatNumber $nps]
	}

	if {$tbhits} {
		[::toolbar::lookupChild $Vars(widget:tbhits)] configure -text [::locale::formatNumber $tbhits]
	}
}


proc Display(bestmove) {tree move} {
	variable ${tree}::Vars

	# the engine answered "stop" (see Stop): no need to power it down
	if {[string length $Vars(after:stop)]} {
		after cancel $Vars(after:stop)
		StopFinished $tree
	}
}


proc Display(hash) {tree fullness} {
	variable ${tree}::Vars

	set w [::toolbar::lookupChild $Vars(widget:hashfullness)]
	$w configure -text "[expr {int($fullness/10.0 + 0.5)}]%"
}


proc Display(cpuload) {tree load} {
#	TODO
#	variable ${tree}::Vars
#	[::toolbar::lookupChild $Vars(widget:cpuload)] configure -text "[expr {int($load/10.0 + 0.5)}]%"
}


proc Display(error) {tree code} {
	variable ${tree}::Vars

	switch $code {
		registration - copyprotection	{ set msg $::engine::mc::ProbeError($code) }
		standard - chess960 - analyze	{ set msg $mc::NotSupported($code) }
		position								{ set msg $mc::IllegalPosition }
		moves									{ set msg $mc::IllegalMoves }
		pong									{ set msg $mc::DidNotReceivePong }
		searchMate							{ set msg $mc::SearchMateNotSupported }

		variant {
			set variant [::scidb::engine::variant [::engine::id $Vars(number)]]
			set msg [format $mc::NotSupported($code) $::mc::VariantName($variant)]
		}
	}

	set Vars(current:message) [list [namespace current]::Display(error) $tree $code]
	ShowMessage $tree error $msg
}


proc UpdateInfo {tree id type info} {
	variable ${tree}::Vars

	# the latest line of each row, for lines
	switch $type {
		pv			{ set Vars(lines:[lindex $info 8]) [lreplace $info 8 8] }
		bestscore	{ set Vars(lines:best) [lindex $info 2] }
		clear		{ array unset Vars lines:* }
	}

	if {[winfo exists $tree]} {
		Display($type) $tree {*}$info
		if {$type in {pv clear}} { UpdatePinState $tree }
	}
}


proc IsReady {tree id} {
	if {![winfo exists $tree]} { return }
	variable ${tree}::Vars

	# a stop must not be undone by the answer to an earlier "isready"
	if {$Vars(engine:stopped)} { return }

	after idle [list ::engine::startAnalysis $Vars(number)]
}


proc Signal {tree id code} {
	if {![winfo exists $tree]} { return }
	variable ${tree}::Vars

	after cancel $Vars(after:id)
	after cancel $Vars(after:stop)
	set Vars(after:stop) {}
	set Vars(engine:stopped) 0
	set parent [winfo toplevel $tree]
	SetState $tree disabled

	if {[string is integer $code]} {
		set msg [format $mc::Signal(terminated) $code]
	} else {
		set msg $mc::Signal($code)
	}

	switch $code {
		stopped - resumed {
			after idle [list ::dialog::info -parent $parent -message $msg]
		}
		default {
			if {[string is integer $code]} {
				set msg [format $mc::Signal(terminated) $code]
			} else {
				set msg $mc::Signal($code)
			}
			after idle [list ::dialog::error -parent $parent -message $msg]
			after idle [list ::engine::kill $Vars(number)]
		}
	}
}


proc VisitItem {tree mode column item {x {}} {y {}}} {
	variable ${tree}::Vars

	if {$Vars(keep:active)} { return }
	if {[string length $column] == 0} { return }
	if {![::engine::active? $Vars(number)]} { return }

	if {$mode eq "leave"} {
		$tree activate root
		set Vars(current:item) 0
	} else {
		if {$item <= [::scidb::engine::countLines [::engine::id $Vars(number)]]} {
			$tree activate $item
		}
		set Vars(current:item) $item
	}
}


proc AddMove {tree x y state} {
	variable ${tree}::Vars
	variable ${Vars(number)}::Options

	if {$Vars(engine:opponent)} { return }
	if {[::scidb::game::query expansion?]} { return }
	set engineID [::engine::id $Vars(number)]
	if {$engineID == -1} { return }
	if {![::scidb::engine::bound? $engineID]} { return }
	set id [$tree identify $x $y]
	if {[lindex $id 0] ne "item"} { return }
	set id [$tree identify $x $y]
	set line [$tree item order [lindex $id 1] -visible]
	if {[::scidb::engine::empty? $engineID $line]} { return }
	::scidb::engine::snapshot $engineID
	set san [::scidb::engine::snapshot $engineID san $line]
	if  {[::scidb::game::valid? $san]} {
		set force [::util::shiftIsHeldDown? $state]
		::move::addMove menu $san -force $force
	}
	::scidb::engine::snapshot $engineID clear
}


proc InsertMoves {tree what line} {
	variable ${tree}::Vars

	set id [::engine::id $Vars(number)]

	if {[application::pgn::ensureScratchGame]} {
		::scidb::engine::bind $id
	}

	# Append requires a line end. In the middle, insert the sequence as a
	# variation instead, preserving the existing continuation.
	set where [::scidb::engine::snapshot $id]
	if {$what eq "seq" && $where ne "atend"} { set what line }
	if {$what in {all incl}} {
		::scidb::engine::snapshot $id $what
	} else {
		::scidb::engine::snapshot $id $what $line
	}
}


proc InsertComment {tree line} {
	variable ${tree}::Vars

	set id [::engine::id $Vars(number)]
	::scidb::engine::snapshot $id
	set san [::scidb::engine::snapshot $id comment $line]

	if {[string length $san]} {
		set move {}
		if {$Vars(engine:opponent)} {
			lappend move {nag 140}
			lappend move {str " "}
		}
		if {[string index $san 0] in {K Q R B N P}} {
			lappend move [list sym [string index $san 0]]
			set san [string range $san 1 end]
		}
		lappend move [list str $san]
		set comment [::scidb::misc::xml fromList [list [list {} $move]]]
		::scidb::game::update addcomment [::scidb::game::query current] [::scidb::game::current] $comment
	}
}


proc LanguageChanged {} {
	variable NumberToTree

	foreach number [array names NumberToTree] {
		variable [set [namespace current]::NumberToTree($number)]::Vars
		if {[llength $Vars(current:message)]} { {*}$Vars(current:message) }
	}
}


proc PopupMenu {tree number args} {
	variable ${tree}::Vars
	variable ${Vars(number)}::Options

	set menu $tree.__menu__
	catch { destroy $menu }
	menu $menu -tearoff no
	catch { wm attributes $menu -type popup_menu }

	# C6: the one engine-line context menu.
	if {[llength [info commands ::context::Build]]} {
		set engineID -1
		catch { set engineID [::engine::id $Vars(number)] }
		set lineId ""
		set pv ""
		if {[llength $args]} {
			set ident [$tree identify {*}$args]
			if {[lindex $ident 0] eq "item"} {
				set lineId [$tree item order [lindex $ident 1] -visible]
				if {[info exists Vars(pv:$lineId)]} { set pv $Vars(pv:$lineId) }
			}
		}
		set object [dict create tree $tree number $Vars(number) engine $engineID \
			lineId $lineId pv $pv]
		if {[::context::Build C6 $menu $object]} {
			tk_popup $menu {*}[winfo pointerxy $tree]
			return
		}
		destroy $menu
		return
	}

	if {[llength $args] && [::engine::id $Vars(number)] >= 0} {
		set id [$tree identify {*}$args]

		if {[lindex $id 0] eq "item"} {
			set line [$tree item order [lindex $id 1] -visible]
			set id [::engine::id $Vars(number)]
			if {	![::scidb::engine::empty? $id $line]
				&& ![::scidb::game::query expansion?]
				&& [::scidb::engine::bound? $id]} {
				$tree activate [set Vars(current:item) [expr {$line + 1}]]
				if {[set atLineEnd [::scidb::engine::snapshot $id]] eq "atend"} {
					set action move
					set icon $icon::16x16::append
				} else {
					set action var
					set icon $::icon::16x16::plus
				}
				$menu add command \
					-label " $mc::Add($action)" \
					-image $icon \
					-compound left \
					-command [namespace code [list InsertMoves $tree $action $line]] \
					;
				if {$atLineEnd eq "atend"} {
					$menu add command \
						-label " $mc::Add(seq)" \
						-image $icon::16x16::append \
						-compound left \
						-command [namespace code [list InsertMoves $tree seq $line]] \
						;
				}
				if {[::scidb::game::current] != 9} {
					$menu add command \
						-label " $mc::Add(line)" \
						-image $::icon::16x16::plus \
						-compound left \
						-command [namespace code [list InsertMoves $tree line $line]] \
						;
					if {!$Options(engine:singlePV)} {
						$menu add command \
							-label " $mc::Add(all)" \
							-image $::icon::16x16::plus \
							-compound left \
							-command [namespace code [list InsertMoves $tree all $line]] \
							;
					}
					if {!$Vars(engine:opponent)} {
						$menu add command \
							-label " $mc::Add(merge)" \
							-image $::icon::16x16::merge \
							-compound left \
							-command [namespace code [list InsertMoves $tree merge $line]] \
							;
						if {!$Options(engine:singlePV)} {
							$menu add command \
								-label " $mc::Add(incl)" \
								-image $::icon::16x16::merge \
								-compound left \
								-command [namespace code [list InsertMoves $tree incl $line]] \
								;
						}
					}
					$menu add command \
						-label " $mc::InsertMoveAsComment" \
						-image $icon::16x16::insert \
						-compound left \
						-command [namespace code [list InsertComment $tree $line]] \
						;
				}
				# C3: explain the engine's line.
				if {[llength [info commands ::application::ai::explainLine]]
				 && [info exists Vars(pv:$line)] && [string length $Vars(pv:$line)]} {
					$menu add command \
						-label " $mc::ExplainLine" \
						-image $::icon::16x16::none \
						-compound left \
						-command [namespace code [list ::application::ai::explainLine \
							[winfo toplevel $tree] $Vars(pv:$line) [::scidb::pos::fen]]] \
						;
				}
				$menu add separator
			}
		}
	}

	$menu add command \
		-label " $mc::SetupEngine..." \
		-image $::icon::16x16::setup \
		-compound left \
		-command [namespace code [list Setup $tree $number]] \
		;
	$menu add command \
		-label " $mc::SetupEvalEdges..." \
		-image $::icon::16x16::none \
		-compound left \
		-command [namespace code [list SetupEvalEdges $tree]]
		;

	if {[::engine::id $Vars(number)] >= 0} {
		if {!$Vars(engine:stopped)} {
			$menu add command \
				-label " $mc::StopSearch" \
				-image $::icon::16x16::stop \
				-compound left \
				-command [namespace code [list Stop $tree]] \
				;
		}
		if {$Vars(engine:pause)} {
			set txt $mc::Resume
			set img $::icon::16x16::start
		} else {
			set txt $mc::Pause
			set img $::icon::16x16::pause
		}
		$menu add command \
			-label " $txt" \
			-image $img \
			-compound left \
			-command [namespace code [list Pause $tree]] \
			;
		if {$Vars(number) >= 0} {
			# powering down is a separate action, it does not stop the search
			$menu add command \
				-label " $mc::CloseEngine" \
				-image $::icon::16x16::close \
				-compound left \
				-command [namespace code [list CloseEngine $tree]] \
				;
		}
		$menu add separator
		$menu add checkbutton \
			-label " $mc::LockEngine" \
			-image $::icon::16x16::lock \
			-compound left \
			-command [namespace code [list EngineLock $tree]] \
			-variable [namespace current]::${tree}::Vars(engine:locked) \
			;
		::theme::configureCheckEntry $menu
		$menu add checkbutton \
			-label " $mc::OpponentsView" \
			-image $::icon::16x16::rotateBoard \
			-compound left \
			-command [namespace code [list restartAnalysis $Vars(number)]] \
			-variable [namespace current]::${tree}::Vars(engine:opponent) \
			;
		::theme::configureCheckEntry $menu
		$menu add checkbutton \
			-label " $mc::BestFirstOrder" \
			-image $::icon::16x16::sort(descending) \
			-compound left \
			-command [namespace code [list SetOrdering $tree]] \
			-variable [namespace current]::${number}::Options(engine:bestFirst) \
			;
		::theme::configureCheckEntry $menu
		$menu add separator
		set sub [menu $menu.multiPV -tearoff 0]
		$menu add cascade \
			-menu $sub \
			-label " $mc::MultipleVariations"  \
			-image $::icon::16x16::lines \
			-compound left \
			;
		foreach n {1 2 3 4 5 6 7 8} {
			$sub add radiobutton \
				-label $n \
				-value $n \
				-variable [namespace current]::${number}::Options(engine:multiPV) \
				-command [namespace code [list SetMultiPV $tree $n]] \
				;
			::theme::configureRadioEntry $sub
		}
		if {!$Options(engine:singlePV)} {
			set sub [menu $menu.lines -tearoff 0]
			$menu add cascade \
				-menu $sub \
				-label " $mc::LinesPerVariation" \
				-image $::icon::16x16::none \
				-compound left \
				;
			foreach i {1 2 3 4} {
				$sub add radiobutton \
					-label $i \
					-value $i \
					-variable [namespace current]::${number}::Options(engine:nlines) \
					-command [namespace code [list SetLinesPerPV $tree]] \
					;
				::theme::configureRadioEntry $sub
			}
		}

		set Vars(keep:active) 1
		set Vars(state:suspended) 1
		::bind $menu <<MenuUnpost>> [namespace code [list RevertDisplay $tree]]
	}

	tk_popup $menu {*}[winfo pointerxy $tree]
}


proc RevertDisplay {tree} {
	variable ${tree}::Vars

	set Vars(state:suspended) 0

	foreach line [array names Vars suspended,*] {
		Display(pv) $tree {*}$Vars($line)
	}

	array unset Vars suspended,*
	set Vars(keep:active) 0
	after idle [namespace code [list ActivateCurrent $tree]]
}


proc ActivateCurrent {tree} {
	variable ${tree}::Vars

	if {![winfo exists $tree]} { return }
	lassign [winfo pointerxy $tree] x y
	set x [expr {$x - [winfo rootx $tree]}]
	set y [expr {$y - [winfo rooty $tree]}]
	set id [$tree identify $x $y]
	if {[lindex $id 0] eq "item"} { set item [lindex $id 1] } else { set item 0 }
	$tree activate $item
	set Vars(current:item) $item
}


proc SetupEvalEdges {tree} {
	variable GlobalOptions
	variable Score_

	set dlg [tk::toplevel $tree.setupEvalRanges -class Dialog]
	wm withdraw $dlg
	set top [ttk::frame $dlg.top]
	pack $top -fill both -expand yes
#	ttk::label $top.logo -style icon.TButton -image $::icon::48x48::logo -borderwidth 0
	ttk::label $top.logo -style icon.TButton -image $::icon::32x32::engine -borderwidth 0
	grid $top.logo -row 1 -column 1 -rowspan 3

	foreach nag {14 16 18 20} score $GlobalOptions(eval:edges) {
		set Score_($nag) [::locale::formatSpinboxDouble [expr {$score/100.0}]]
	}

	set col 1
	foreach nag {14 16 18 20} {
		ttk::label $top.lbl$nag \
			-font $::font::symbol(text:normal) \
			-anchor center \
			-text [::font::mapNagToSymbol $nag] \
			;
		grid $top.lbl$nag -row 1 -column [incr col 2] -sticky ew
		::tooltip::tooltip $top.lbl$nag ::annotation::mc::Nag($nag)
	}

	set col 1
	foreach nag {14 16 18 20} {
		ttk::spinbox $top.spb$nag \
			-from 0.0 \
			-to 999.0 \
			-width 5 \
			-increment 0.01 \
			-justify right \
			-takefocus 1 \
			-textvar [namespace current]::Score_($nag) \
			-exportselection no \
			;
		::theme::configureSpinbox $top.spb$nag
		::validate::spinboxDouble $top.spb$nag
		grid $top.spb$nag -row 3 -column [incr col 2] -sticky ew
	}

	set values {0.45 0.75 1.75 4.00}
	set btn [ttk::button $top.scidb \
		-style aligned.TButton \
		-text "Chesswiz" \
		-command [namespace code [list SetEdgeValues $top $values]] \
	]
	grid $btn -row 5 -column 1 -sticky w
	set col 1
	foreach nag {14 16 18 20} score $values {
		set score [::locale::formatDouble $score]
		grid [ttk::label $top.scidb$nag -text "$score  " -anchor e] -row 5 -column [incr col 2] -sticky ew
	}

	set values {0.50 1.50 3.00 5.50}
	set btn [ttk::button $top.scid \
		-style aligned.TButton \
		-text "Scid" \
		-command [namespace code [list SetEdgeValues $top $values]] \
	]
	grid $btn -row 7 -column 1 -sticky w
	set col 1
	foreach nag {14 16 18 20} score $values {
		set score [::locale::formatDouble $score]
		grid [ttk::label $top.scid$nag -text "$score  " -anchor e] -row 7 -column [incr col 2] -sticky ew
	}

	set values {0.35 0.70 1.60 \u2014}
	set btn [ttk::button $top.cb \
		-style aligned.TButton \
		-text "ChessBase" \
		-command [namespace code [list SetEdgeValues $top $values]] \
	]
	grid $btn -row 9 -column 1 -sticky w
	set col 1
	foreach nag {14 16 18 20} score $values {
		if {[string is double $score]} { set score [::locale::formatDouble $score] }
		grid [ttk::label $top.cb$nag -text "$score  " -anchor e] -row 9 -column [incr col 2] -sticky ew
	}

	grid columnconfigure $top {2 4 6 8} -minsize $::theme::padx
	grid columnconfigure $top {0 10} -minsize $::theme::padY
	grid rowconfigure $top {2 6 8} -minsize $::theme::pady
	grid rowconfigure $top {4} -minsize [expr {3*$::theme::pady}]
	grid rowconfigure $top {0 10} -minsize $::theme::padX

	::widget::dialogButtons $dlg {save cancel} -default save
	$dlg.save   configure -command [namespace code [list SaveEvalRanges $dlg]]
	$dlg.cancel configure -command [list destroy $dlg]

	wm protocol $dlg WM_DELETE_WINDOW [$dlg.cancel cget -command]
	wm resizable $dlg false false
	wm transient $dlg .application
	wm title $dlg $mc::SetupEvalEdges
	::util::place $dlg -parent [winfo parent [winfo parent $tree]] -position above-or-below
	focus $top.spb14
	$top.spb14 selection range 0 end
	wm deiconify $dlg
}


proc SetEdgeValues {w values} {
	variable Score_

	foreach score $values nag {14 16 18 20} {
		if {[string is double $score]} { set Score_($nag) [::locale::formatSpinboxDouble $score] }
	}
}


proc SaveEvalRanges {dlg} {
	variable ScoreEdgeValues
	variable GlobalOptions
	variable Score_

	set score -1.0
	foreach nag {14 16 18 20} {
		if {[::locale::toDouble $Score_($nag)] <= $score} {
			return [::dialog::error \
				-parent $dlg \
				-message $mc::InvalidEdgeValues \
				-detail $mc::MustBeAscending \
			]
		}
	}

	set GlobalOptions(eval:edges) {}
	set ScoreEdgeValues {}

	foreach nag1 {14 16 18 20} nag2 {10 14 16 18} {
		set score [expr {int([::locale::toDouble $Score_($nag1)]*100)}]
		lappend GlobalOptions(eval:edges) $score
		lappend ScoreEdgeValues $score $nag2
	}

	destroy $dlg
}


proc WriteOptions {chan} {
	foreach ns [namespace children [namespace current]] {
		if {[string match {*[0-9]} $ns]} {
			if {[set number [[namespace parent]::mapToTerminalNumber $ns]] >= 0} {
				namespace eval ${number} {}
				array set ${number}::Options_ [array get ${ns}::Options]
			}
		}
	}
	foreach ns [namespace children [namespace current]] {
		if {[array exists ${ns}::Options_]} {
			array set ${ns}::Options [array get ${ns}::Options_]
		}
	}
	foreach ns [namespace children [namespace current]] {
		if {[string match {*[0-9]} $ns]} {
			::options::writeEvalNS $chan $ns
			::options::writeItem $chan ${ns}::Options
		}
	}
	::options::writeItem $chan [namespace current]::GlobalOptions
}
::options::hookWriter [namespace current]::WriteOptions


namespace eval icon {
namespace eval 16x16 {

set append [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
	ZXIgSWNvbnMgdjMuMzEuMDogaHR0cHM6Ly9jb2RlbG9hZC5naXRodWIuY29tL3RhYmxlci90YWJs
	ZXItaWNvbnMvdGFyLmd6L3JlZnMvdGFncy92My4zMS4wClNIQTI1NjogNmNhZTU3YzFjMTdmNjIz
	MjY3OTQ1ZmM0ODFjODExYzNkODg3ZjMzYTU1MWE2MmI2ZjBlYTdhNDFiNWEzZWYxZgoKTUlUIExp
	Y2Vuc2UKCkNvcHlyaWdodCAoYykgMjAyMC0yMDI0IFBhd2XFgiBLdW5hCgpQZXJtaXNzaW9uIGlz
	IGhlcmVieSBncmFudGVkLCBmcmVlIG9mIGNoYXJnZSwgdG8gYW55IHBlcnNvbiBvYnRhaW5pbmcg
	YSBjb3B5Cm9mIHRoaXMgc29mdHdhcmUgYW5kIGFzc29jaWF0ZWQgZG9jdW1lbnRhdGlvbiBmaWxl
	cyAodGhlICJTb2Z0d2FyZSIpLCB0byBkZWFsCmluIHRoZSBTb2Z0d2FyZSB3aXRob3V0IHJlc3Ry
	aWN0aW9uLCBpbmNsdWRpbmcgd2l0aG91dCBsaW1pdGF0aW9uIHRoZSByaWdodHMKdG8gdXNlLCBj
	b3B5LCBtb2RpZnksIG1lcmdlLCBwdWJsaXNoLCBkaXN0cmlidXRlLCBzdWJsaWNlbnNlLCBhbmQv
	b3Igc2VsbApjb3BpZXMgb2YgdGhlIFNvZnR3YXJlLCBhbmQgdG8gcGVybWl0IHBlcnNvbnMgdG8g
	d2hvbSB0aGUgU29mdHdhcmUgaXMKZnVybmlzaGVkIHRvIGRvIHNvLCBzdWJqZWN0IHRvIHRoZSBm
	b2xsb3dpbmcgY29uZGl0aW9uczoKClRoZSBhYm92ZSBjb3B5cmlnaHQgbm90aWNlIGFuZCB0aGlz
	IHBlcm1pc3Npb24gbm90aWNlIHNoYWxsIGJlIGluY2x1ZGVkIGluIGFsbApjb3BpZXMgb3Igc3Vi
	c3RhbnRpYWwgcG9ydGlvbnMgb2YgdGhlIFNvZnR3YXJlLgoKVEhFIFNPRlRXQVJFIElTIFBST1ZJ
	REVEICJBUyBJUyIsIFdJVEhPVVQgV0FSUkFOVFkgT0YgQU5ZIEtJTkQsIEVYUFJFU1MgT1IKSU1Q
	TElFRCwgSU5DTFVESU5HIEJVVCBOT1QgTElNSVRFRCBUTyBUSEUgV0FSUkFOVElFUyBPRiBNRVJD
	SEFOVEFCSUxJVFksCkZJVE5FU1MgRk9SIEEgUEFSVElDVUxBUiBQVVJQT1NFIEFORCBOT05JTkZS
	SU5HRU1FTlQuIElOIE5PIEVWRU5UIFNIQUxMIFRIRQpBVVRIT1JTIE9SIENPUFlSSUdIVCBIT0xE
	RVJTIEJFIExJQUJMRSBGT1IgQU5ZIENMQUlNLCBEQU1BR0VTIE9SIE9USEVSCkxJQUJJTElUWSwg
	V0hFVEhFUiBJTiBBTiBBQ1RJT04gT0YgQ09OVFJBQ1QsIFRPUlQgT1IgT1RIRVJXSVNFLCBBUklT
	SU5HIEZST00sCk9VVCBPRiBPUiBJTiBDT05ORUNUSU9OIFdJVEggVEhFIFNPRlRXQVJFIE9SIFRI
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABcUlEQVR4nKWT
	v0pjURDGf3NyYzSNplm3EBsbO99AFBtZSLkgbGG1W/gAVsK9pfgItmKxjZ2wzeLuawg2YSXin7sR
	DLnJ3nM+iyRwNSYq+zVzmG+YmW9mDvwn7LlDkpmZJM10c9YBKhFnZtYZchMzSnIDu1mP79J6fJdK
	2ixyRUTPHUnSt+eXfv7iitrwXeRGEkgywAYBLo4F3muqFAIAHsWxHOAkAehVKY1mvrWycxNWdm5C
	o5lvjYsbdjANrJ1f+nnnCJHD32da1WDI912tNa5za3eoLC+WroBfZpZJMgPIMn36vP/36KKpWrkU
	JGGAdXr9KjNTYBD+BWdLHy092attl8t2KsmNTPW9sHESHjKtfjlofQM43p07nK3a75ckRABmlgE/
	ipn/XOfewVeAWtXOFj5E30eqm+nFNQKh1e5Ve74vsdX21eEak4TApDU+ucQkva0n6e2kS5z8F7ps
	AFQq/HzzX3gvRjoodlLgx2p+BPJm1PQHvqmeAAAAAElFTkSuQmCC
}]

set insert [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
	ZXIgSWNvbnMgdjMuMzEuMDogaHR0cHM6Ly9jb2RlbG9hZC5naXRodWIuY29tL3RhYmxlci90YWJs
	ZXItaWNvbnMvdGFyLmd6L3JlZnMvdGFncy92My4zMS4wClNIQTI1NjogNmNhZTU3YzFjMTdmNjIz
	MjY3OTQ1ZmM0ODFjODExYzNkODg3ZjMzYTU1MWE2MmI2ZjBlYTdhNDFiNWEzZWYxZgoKTUlUIExp
	Y2Vuc2UKCkNvcHlyaWdodCAoYykgMjAyMC0yMDI0IFBhd2XFgiBLdW5hCgpQZXJtaXNzaW9uIGlz
	IGhlcmVieSBncmFudGVkLCBmcmVlIG9mIGNoYXJnZSwgdG8gYW55IHBlcnNvbiBvYnRhaW5pbmcg
	YSBjb3B5Cm9mIHRoaXMgc29mdHdhcmUgYW5kIGFzc29jaWF0ZWQgZG9jdW1lbnRhdGlvbiBmaWxl
	cyAodGhlICJTb2Z0d2FyZSIpLCB0byBkZWFsCmluIHRoZSBTb2Z0d2FyZSB3aXRob3V0IHJlc3Ry
	aWN0aW9uLCBpbmNsdWRpbmcgd2l0aG91dCBsaW1pdGF0aW9uIHRoZSByaWdodHMKdG8gdXNlLCBj
	b3B5LCBtb2RpZnksIG1lcmdlLCBwdWJsaXNoLCBkaXN0cmlidXRlLCBzdWJsaWNlbnNlLCBhbmQv
	b3Igc2VsbApjb3BpZXMgb2YgdGhlIFNvZnR3YXJlLCBhbmQgdG8gcGVybWl0IHBlcnNvbnMgdG8g
	d2hvbSB0aGUgU29mdHdhcmUgaXMKZnVybmlzaGVkIHRvIGRvIHNvLCBzdWJqZWN0IHRvIHRoZSBm
	b2xsb3dpbmcgY29uZGl0aW9uczoKClRoZSBhYm92ZSBjb3B5cmlnaHQgbm90aWNlIGFuZCB0aGlz
	IHBlcm1pc3Npb24gbm90aWNlIHNoYWxsIGJlIGluY2x1ZGVkIGluIGFsbApjb3BpZXMgb3Igc3Vi
	c3RhbnRpYWwgcG9ydGlvbnMgb2YgdGhlIFNvZnR3YXJlLgoKVEhFIFNPRlRXQVJFIElTIFBST1ZJ
	REVEICJBUyBJUyIsIFdJVEhPVVQgV0FSUkFOVFkgT0YgQU5ZIEtJTkQsIEVYUFJFU1MgT1IKSU1Q
	TElFRCwgSU5DTFVESU5HIEJVVCBOT1QgTElNSVRFRCBUTyBUSEUgV0FSUkFOVElFUyBPRiBNRVJD
	SEFOVEFCSUxJVFksCkZJVE5FU1MgRk9SIEEgUEFSVElDVUxBUiBQVVJQT1NFIEFORCBOT05JTkZS
	SU5HRU1FTlQuIElOIE5PIEVWRU5UIFNIQUxMIFRIRQpBVVRIT1JTIE9SIENPUFlSSUdIVCBIT0xE
	RVJTIEJFIExJQUJMRSBGT1IgQU5ZIENMQUlNLCBEQU1BR0VTIE9SIE9USEVSCkxJQUJJTElUWSwg
	V0hFVEhFUiBJTiBBTiBBQ1RJT04gT0YgQ09OVFJBQ1QsIFRPUlQgT1IgT1RIRVJXSVNFLCBBUklT
	SU5HIEZST00sCk9VVCBPRiBPUiBJTiBDT05ORUNUSU9OIFdJVEggVEhFIFNPRlRXQVJFIE9SIFRI
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACOklEQVR4nK2T
	sWsUURDGv3nv7W72kjUGPU9joaSMYG1UQkDsJRLBIpY2NqY0zWFjIYKFnVhEsTJBtAwiUcEE/4GU
	YlA0eOrFu8ve7e5777PwEi/BNOIHU0wx880MvwFJwT9oq066SSVt2jPNmilBO+q/FDgAyCGlMtNk
	v1kWkXWSYkgOv55L77xbcJN5x0UE93QVCII+lZ2aCp+RvC4i66rdwvjyfH6h/oWRsy4nyL3CWZfX
	PzNaedK+mDYxBgCm9dUN2IwmSoriyt19t5Kyem9TaOo/o4iDmBJcs+ZH5mYaszbTYbPm+gHAIIAH
	SRPosHwsWE0OyPxeKzS/c8oEKiA9dQD/u0EBBRGxhStqa8Vo7aOdtim00qDrnSCCq60VI7bwRWB0
	6AooADADh3TLRLBpPYgfzTRmlZFQRIEEAN9dQwng4S3zrGHCeNjbpMxNAFDxAN6cvhQ/HToiHWVU
	4D1c3vFtgm1n4Z2F9853vINTRgVDw9IZm4oXSolZ6eXgcLphz7bqJg4jF+lQTuYtnHh8ozEGily9
	nyxmKZ+3W3CDFW6WEvN2iwMhKSKyfXGS5+5N/5z79oEV55zxhZGjo6hde9h/WSR42UuiiFCJCEnK
	0hJNtUqVpSgpjX6lJNAGXrQnBGGWolStUnGJZrfpDrZJxiTPf1p1D6rjP3hzosGN9eI2yZCg7P4d
	sw1Lt6OItAG8IOkPHleTAnKwYhZFJCepRMTvxHuXug4CoM9mmAAAE+EVgHav0X/TL0w4U3ikxETq
	AAAAAElFTkSuQmCC
}]

} ;# namespace 16x16
namespace eval 11x14 {

set arrowLeft [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAAsAAAAOCAYAAAD5YeaVAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
	ZXIgSWNvbnMgdjMuMzEuMDogaHR0cHM6Ly9jb2RlbG9hZC5naXRodWIuY29tL3RhYmxlci90YWJs
	ZXItaWNvbnMvdGFyLmd6L3JlZnMvdGFncy92My4zMS4wClNIQTI1NjogNmNhZTU3YzFjMTdmNjIz
	MjY3OTQ1ZmM0ODFjODExYzNkODg3ZjMzYTU1MWE2MmI2ZjBlYTdhNDFiNWEzZWYxZgoKTUlUIExp
	Y2Vuc2UKCkNvcHlyaWdodCAoYykgMjAyMC0yMDI0IFBhd2XFgiBLdW5hCgpQZXJtaXNzaW9uIGlz
	IGhlcmVieSBncmFudGVkLCBmcmVlIG9mIGNoYXJnZSwgdG8gYW55IHBlcnNvbiBvYnRhaW5pbmcg
	YSBjb3B5Cm9mIHRoaXMgc29mdHdhcmUgYW5kIGFzc29jaWF0ZWQgZG9jdW1lbnRhdGlvbiBmaWxl
	cyAodGhlICJTb2Z0d2FyZSIpLCB0byBkZWFsCmluIHRoZSBTb2Z0d2FyZSB3aXRob3V0IHJlc3Ry
	aWN0aW9uLCBpbmNsdWRpbmcgd2l0aG91dCBsaW1pdGF0aW9uIHRoZSByaWdodHMKdG8gdXNlLCBj
	b3B5LCBtb2RpZnksIG1lcmdlLCBwdWJsaXNoLCBkaXN0cmlidXRlLCBzdWJsaWNlbnNlLCBhbmQv
	b3Igc2VsbApjb3BpZXMgb2YgdGhlIFNvZnR3YXJlLCBhbmQgdG8gcGVybWl0IHBlcnNvbnMgdG8g
	d2hvbSB0aGUgU29mdHdhcmUgaXMKZnVybmlzaGVkIHRvIGRvIHNvLCBzdWJqZWN0IHRvIHRoZSBm
	b2xsb3dpbmcgY29uZGl0aW9uczoKClRoZSBhYm92ZSBjb3B5cmlnaHQgbm90aWNlIGFuZCB0aGlz
	IHBlcm1pc3Npb24gbm90aWNlIHNoYWxsIGJlIGluY2x1ZGVkIGluIGFsbApjb3BpZXMgb3Igc3Vi
	c3RhbnRpYWwgcG9ydGlvbnMgb2YgdGhlIFNvZnR3YXJlLgoKVEhFIFNPRlRXQVJFIElTIFBST1ZJ
	REVEICJBUyBJUyIsIFdJVEhPVVQgV0FSUkFOVFkgT0YgQU5ZIEtJTkQsIEVYUFJFU1MgT1IKSU1Q
	TElFRCwgSU5DTFVESU5HIEJVVCBOT1QgTElNSVRFRCBUTyBUSEUgV0FSUkFOVElFUyBPRiBNRVJD
	SEFOVEFCSUxJVFksCkZJVE5FU1MgRk9SIEEgUEFSVElDVUxBUiBQVVJQT1NFIEFORCBOT05JTkZS
	SU5HRU1FTlQuIElOIE5PIEVWRU5UIFNIQUxMIFRIRQpBVVRIT1JTIE9SIENPUFlSSUdIVCBIT0xE
	RVJTIEJFIExJQUJMRSBGT1IgQU5ZIENMQUlNLCBEQU1BR0VTIE9SIE9USEVSCkxJQUJJTElUWSwg
	V0hFVEhFUiBJTiBBTiBBQ1RJT04gT0YgQ09OVFJBQ1QsIFRPUlQgT1IgT1RIRVJXSVNFLCBBUklT
	SU5HIEZST00sCk9VVCBPRiBPUiBJTiBDT05ORUNUSU9OIFdJVEggVEhFIFNPRlRXQVJFIE9SIFRI
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAA80lEQVR4nJWS
	sUoDURBF77ysVSAI+gEWgjGmsBcs7LQRxcbSKoWd2C0SsPIH9BOsbEQQCzUiFuIP+AVWNmFfQNB9
	79isuKxGkymHc4c7d0aqFGCAVfs/qgyZ/cF/gUACTPzGJAVQM7MATJ9f3qaZH9SBA0mvkkxSNDME
	uEIweXHVO24vbbCzmz4DM8MstK7vH88WlzdDZ+/wBdgHmsAcMA80JMmAqd7D01336KTtvY8Lzdn+
	R55neYiuZibnnNveWjtdX11JXbE5/0ZVtnEzgo2xFkzMLBbR9YFuCPE984O6pLdi0Hd04xyl6n20
	c5cFwx7pExSVt8CM/7U2AAAAAElFTkSuQmCC
}]

set arrowRight [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAAsAAAAOCAYAAAD5YeaVAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
	ZXIgSWNvbnMgdjMuMzEuMDogaHR0cHM6Ly9jb2RlbG9hZC5naXRodWIuY29tL3RhYmxlci90YWJs
	ZXItaWNvbnMvdGFyLmd6L3JlZnMvdGFncy92My4zMS4wClNIQTI1NjogNmNhZTU3YzFjMTdmNjIz
	MjY3OTQ1ZmM0ODFjODExYzNkODg3ZjMzYTU1MWE2MmI2ZjBlYTdhNDFiNWEzZWYxZgoKTUlUIExp
	Y2Vuc2UKCkNvcHlyaWdodCAoYykgMjAyMC0yMDI0IFBhd2XFgiBLdW5hCgpQZXJtaXNzaW9uIGlz
	IGhlcmVieSBncmFudGVkLCBmcmVlIG9mIGNoYXJnZSwgdG8gYW55IHBlcnNvbiBvYnRhaW5pbmcg
	YSBjb3B5Cm9mIHRoaXMgc29mdHdhcmUgYW5kIGFzc29jaWF0ZWQgZG9jdW1lbnRhdGlvbiBmaWxl
	cyAodGhlICJTb2Z0d2FyZSIpLCB0byBkZWFsCmluIHRoZSBTb2Z0d2FyZSB3aXRob3V0IHJlc3Ry
	aWN0aW9uLCBpbmNsdWRpbmcgd2l0aG91dCBsaW1pdGF0aW9uIHRoZSByaWdodHMKdG8gdXNlLCBj
	b3B5LCBtb2RpZnksIG1lcmdlLCBwdWJsaXNoLCBkaXN0cmlidXRlLCBzdWJsaWNlbnNlLCBhbmQv
	b3Igc2VsbApjb3BpZXMgb2YgdGhlIFNvZnR3YXJlLCBhbmQgdG8gcGVybWl0IHBlcnNvbnMgdG8g
	d2hvbSB0aGUgU29mdHdhcmUgaXMKZnVybmlzaGVkIHRvIGRvIHNvLCBzdWJqZWN0IHRvIHRoZSBm
	b2xsb3dpbmcgY29uZGl0aW9uczoKClRoZSBhYm92ZSBjb3B5cmlnaHQgbm90aWNlIGFuZCB0aGlz
	IHBlcm1pc3Npb24gbm90aWNlIHNoYWxsIGJlIGluY2x1ZGVkIGluIGFsbApjb3BpZXMgb3Igc3Vi
	c3RhbnRpYWwgcG9ydGlvbnMgb2YgdGhlIFNvZnR3YXJlLgoKVEhFIFNPRlRXQVJFIElTIFBST1ZJ
	REVEICJBUyBJUyIsIFdJVEhPVVQgV0FSUkFOVFkgT0YgQU5ZIEtJTkQsIEVYUFJFU1MgT1IKSU1Q
	TElFRCwgSU5DTFVESU5HIEJVVCBOT1QgTElNSVRFRCBUTyBUSEUgV0FSUkFOVElFUyBPRiBNRVJD
	SEFOVEFCSUxJVFksCkZJVE5FU1MgRk9SIEEgUEFSVElDVUxBUiBQVVJQT1NFIEFORCBOT05JTkZS
	SU5HRU1FTlQuIElOIE5PIEVWRU5UIFNIQUxMIFRIRQpBVVRIT1JTIE9SIENPUFlSSUdIVCBIT0xE
	RVJTIEJFIExJQUJMRSBGT1IgQU5ZIENMQUlNLCBEQU1BR0VTIE9SIE9USEVSCkxJQUJJTElUWSwg
	V0hFVEhFUiBJTiBBTiBBQ1RJT04gT0YgQ09OVFJBQ1QsIFRPUlQgT1IgT1RIRVJXSVNFLCBBUklT
	SU5HIEZST00sCk9VVCBPRiBPUiBJTiBDT05ORUNUSU9OIFdJVEggVEhFIFNPRlRXQVJFIE9SIFRI
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAA/klEQVR4nJ2S
	u0pDURBFZ86cBIIkIIjYpolRBD9AFPwEtbRKGSxjpRYSsLFJJYKlIihaiFchhZKAjWJjZX7AUrCy
	vGfZXF/JAR+73DN7XntEIgAU0FjsG1Q/c34lAHKA7xd8JZyIICKjB8dJs1QcegW2VPUZMFVNfdYa
	EUkzYaFzczd7//BYNXN5YENVXwD33rYETADjQBVo1BvNp+m5xfSqe3sKTIqIeMAn7e7a4cnFcggh
	pAQxs5DP+YKKyub27pKZqwDz7sdt+68SHWN1cIxYlXJtZb03NbNA0u7sAMMZ/7GgAgY4YGz/6Hzv
	7PK6BYxkcfuzKQP4j93RR3oDGpu5aSXSCHIAAAAASUVORK5CYII=
}]

} ;# namespace 11x14
} ;# namespace icon
# ======================================================================
# Engines started without the setup dialog: "Analyze this position" of
# the tree, the engine comparison and the assistant.
# ======================================================================

# Starts engine <name> on the board position in analysis pane <number>
# (the internal analysis number; "" = the first pane without a running
# engine, else a new one). <settings> may give lines, threads and hash
# (MB), checked against what the engine supports. Returns the pane's
# analysis number; raises an error with a plain reason.
proc startEngine {name {number ""} {settings {}}} {
	set index [::engine::FindIndex $name]
	if {$index == -1} { error "no engine named '$name'" }
	set e [dict merge $::engine::EmptyEngine [lindex $::engine::Engines $index]]
	set protocol [dict get $e Protocol]
	set protocol [expr {"UCI" in $protocol ? "UCI" : [lindex $protocol 0]}]
	set features [dict get $e Features:$protocol]
	if {![dict exists $features analyze]} { error "$name cannot analyse" }
	if {![file executable [dict get $e Command]]} {
		error "the program of $name is missing: [dict get $e Command]"
	}

	set lines [expr {[dict exists $settings lines] ? [dict get $settings lines] : ""}]
	if {$lines ne ""} {
		# the pane has rows for eight lines
		set most 8
		if {[dict exists $features multiPV]} { set most [expr {min($most, [dict get $features multiPV])}] }
		if {$lines > $most} { error "$name shows at most $most lines here" }
	}
	foreach {key features:keys label} {threads {threads smp} threads hash {hashSize} "hash size"} {
		set value [expr {[dict exists $settings $key] ? [dict get $settings $key] : ""}]
		set $key $value
		if {$value eq ""} { continue }
		set range {}
		foreach k ${features:keys} { if {[dict exists $features $k]} { set range [dict get $features $k] } }
		if {[llength $range] != 2} { error "$name does not take a $label" }
		lassign $range min max
		if {$value < $min || ($max > 0 && $value > $max)} { error "$label must be from $min to $max for $name" }
	}

	# the engine already analysing in a pane is reused, not started again:
	# asking twice must not leave two copies running side by side
	if {$number eq "" && $threads eq "" && $hash eq ""} {
		foreach n [Running] {
			if {[catch { set running [set ::engine::${n}::Vars(current:name)] }]} continue
			if {$running eq $name} {
				if {$lines ne ""} { setLines $n $lines }
				catch { ::application::openPane analysis:[::application::mapToTerminalNumber $n] false }
				return $n
			}
		}
	}
	if {$number eq ""} { set number [FreeNumber] }
	::engine::initVars $number
	namespace upvar ::engine::$number Vars Vars
	set profiles [lmap {p _} [dict get $e Profiles:$protocol] { set p }]
	set Vars(current:name) $name
	set Vars(current:protocol) $protocol
	if {$Vars(current:profile) ni $profiles} {
		set Vars(current:profile) [expr {"Default" in $profiles ? "Default" : [lindex $profiles 0]}]
	}
	if {$threads ne ""} { set Vars(current:cores) $threads }
	if {$hash ne ""} { set Vars(current:memory) $hash }

	if {![exists? $number]} {
		::application::newAnalysisPane $number
		update idletasks
	}
	if {$lines ne ""} { setLines $number $lines }
	startAnalysis $number
	catch { ::application::openPane analysis:[::application::mapToTerminalNumber $number] false }
	if {![::engine::active? $number]} { error "$name did not start; the analysis pane says why" }
	return $number
}


# The engine to use when the user has not chosen one: the one last chosen
# in the setup dialog, else the first that can analyse. "" when none can.
proc defaultEngine {} {
	set names [lmap e $::engine::Engines { dict get $e Name }]
	set last $::engine::Options(engine)
	if {$last in $names} { set names [linsert [lsearch -all -inline -not -exact $names $last] 0 $last] }
	foreach name $names {
		if {[CanAnalyse $name]} { return $name }
	}
	return ""
}


proc CanAnalyse {name} {
	set index [::engine::FindIndex $name]
	if {$index == -1} { return 0 }
	set e [dict merge $::engine::EmptyEngine [lindex $::engine::Engines $index]]
	if {![file executable [dict get $e Command]]} { return 0 }
	foreach protocol [dict get $e Protocol] {
		if {[dict exists [dict get $e Features:$protocol] analyze]} { return 1 }
	}
	return 0
}


proc FreeNumber {} {
	variable NumberToTree

	foreach number [lsort -integer [array names NumberToTree]] {
		if {![::engine::active? $number]} { return $number }
	}
	return [newNumber]
}


proc Running {} {
	variable NumberToTree
	return [lmap n [lsort -integer [array names NumberToTree]] { if {![::engine::active? $n]} continue; set n }]
}


# ======================================================================
# "Analyze this position" of the tree's context menu: play the row's move
# as a click on the row does, and have an engine analyse the result. A
# running engine follows the board by itself; else the default one starts.
# ======================================================================

proc AnalyzePosition {table row} {
	set move [::scidb::tree::move $row]
	if {$move eq "" || ![::scidb::game::valid? $move]} { return }
	::move::addMove menu $move
	AnalyzeCurrentPosition
}


# Explicit analysis actions follow the board even if the pane was stopped or locked.
proc AnalyzeCurrentPosition {} {
	variable NumberToTree
	set running [Running]
	if {[llength $running]} {
		set number [lindex $running 0]
		set tree $NumberToTree($number)
		variable ${tree}::Vars
		set Vars(engine:locked) 0
		set Vars(engine:opponent) 0
		if {$Vars(engine:pause) && !$Vars(engine:stopped)} { ::engine::resume $number }
		set Vars(engine:pause) 0
		restartAnalysis $number
		::application::openPane analysis:[::application::mapToTerminalNumber $number] false
		return
	}

	set name [defaultEngine]
	if {$name eq ""} { return [::engine::openSetup .application] }
	if {[catch { startEngine $name } err]} {
		::dialog::error -parent .application -message $err
	}
}


# ======================================================================
# Pin the engine's best line to a repertoire database: the game up to the
# board position, then the candidate PV with its score as comment.
# ======================================================================

# The best line of the pane: {row line} (see lines), or {} while there is none.
proc BestLine {tree} {
	variable ${tree}::Vars

	if {![::engine::active? $Vars(number)]} { return {} }
	set row 0
	if {[info exists Vars(lines:best)]} {
		set i [lsearch -exact $Vars(lines:best) 1]
		if {$i >= 0} { set row $i }
	}
	if {![info exists Vars(lines:$row)]} { return {} }
	return [list $row $Vars(lines:$row)]
}


proc UpdatePinState {tree} {
	variable ${tree}::Vars

	if {![info exists Vars(widget:button:pin)]} { return }
	set state [expr {[llength [BestLine $tree]] ? "normal" : "disabled"}]
	::toolbar::childconfigure $Vars(widget:button:pin) -state $state
}


# "1.e4 e5 2.Nf3" -> e4, "12...Qxd5+ 13.Nc3" -> Qxd5+
# The first move of a line, in letter SAN: lines hold figurines (shown as
# letters or figurines by the notation setting), and ::scidb::game::move
# takes letters only ("Pin best line" failed with figurine notation).
proc FirstMove {pv} {
	set move [lindex [split [string trim $pv]] 0]
	regsub {^\d+\.+} $move "" move
	if {$move eq ""} { set move [lindex [split [string trim $pv]] 1] }
	return [string map {\u2654 K \u2655 Q \u2656 R \u2657 B \u2658 N \u265a K \u265b Q \u265c R \u265d B \u265e N} $move]
}


proc PinToRepertoire {tree {row ""}} {
	variable ${tree}::Vars

	set id [::engine::id $Vars(number)]
	if {$id < 0 || $Vars(engine:opponent) || ![::scidb::engine::bound? $id]} { return }
	if {$row eq ""} {
		set best [BestLine $tree]
	} elseif {[info exists Vars(lines:$row)]} {
		set best [list $row $Vars(lines:$row)]
	} else {
		return
	}
	if {![llength $best]} { return }
	lassign [lindex $best 1] score mate depth
	set move [LineMoves [lindex $best 1 8]]
	if {![llength $move]} { return }
	set comment "[::engine::engineName $Vars(number)]: [ScoreText $score $mate] (depth $depth)"
	set parent [winfo toplevel $tree]

	set bases [::application::database::repertoireBases 0 [::scidb::game::query Variant?]]
	if {[llength $bases] == 0} {
		return [::application::database::showNoRepertoireBases $parent]
	}
	if {[llength $bases] == 1} {
		return [SaveBestLine $parent [lindex $bases 0] $move $comment]
	}

	set menu $parent.pinRepertoireMenu
	catch { destroy $menu }
	menu $menu -tearoff false
	foreach base $bases {
		$menu add command \
			-label [::util::databaseName $base] \
			-command [namespace code [list SaveBestLine $parent $base $move $comment]] \
			;
	}
	tk_popup $menu [winfo pointerx $tree] [winfo pointery $tree]
}


proc SaveBestLine {parent base move comment} {
	set extend [namespace code [list AppendMove $move $comment]]
	if {[catch { ::application::database::saveCurrentLineToRepertoire $parent $base $extend } err]} {
		::dialog::error -parent $parent -message $err
	}
}


# Convert a displayed PV to letter SAN for the repertoire copy.
proc LineMoves {pv} {
	set pv [string map {♔ K ♕ Q ♖ R ♗ B ♘ N ♚ K ♛ Q ♜ R ♝ B ♞ N} $pv]
	regsub -all {\d+\.+} $pv " " pv
	return [regexp -all -inline {\S+} $pv]
}


# Append the candidate to the temporary repertoire game, with its evaluation.
proc AppendMove {moves comment} {
	foreach move $moves {
		if {![::scidb::game::valid? $move]} { error "Invalid analysis move: $move" }
		::scidb::game::move $move
		::scidb::game::go 1
	}
	set xml [::scidb::misc::xml fromList [list [list {} [list [list str $comment]]]]]
	::scidb::game::update addcomment [::scidb::game::query current] [::scidb::game::current] $xml
}


# ======================================================================
# Engine comparison: several engines analyse the board position, each in
# its own analysis pane, for some seconds; then their best moves, scores
# and depths are set side by side.
# ======================================================================

namespace eval compare {
	variable Seconds 10
	array set Vars { dlg {} engines {} after {} remaining 0 startup 0 }
}


proc openComparison {parent} {
	variable compare::Vars

	set dlg .compareEngines
	if {[winfo exists $dlg]} { return [::widget::dialogRaise $dlg] }

	set names [lmap e $::engine::Engines { set n [dict get $e Name]; if {![CanAnalyse $n]} continue; set n }]
	if {[llength $names] < 2} {
		return [::dialog::info -parent $parent -message $mc::NeedTwoEngines]
	}

	tk::toplevel $dlg -class Scidb
	wm withdraw $dlg
	set top [ttk::frame $dlg.top -takefocus 0]
	pack $top -fill both -expand yes
	set Vars(dlg) $dlg

	ttk::label $top.lengines -text $mc::SelectEngines
	set lb [tk::listbox $top.engines -selectmode multiple -exportselection 0 -height [expr {min(8, [llength $names])}]]
	$lb insert end {*}$names
	ttk::label $top.lseconds -text $mc::Seconds
	ttk::spinbox $top.seconds -from 2 -to 600 -width 5 -textvariable [namespace current]::compare::Seconds
	::validate::spinboxInt $top.seconds

	set tv [ttk::treeview $top.results -show headings -height 6 \
		-columns {engine depth eval move nodes nps}]
	foreach {col head width anchor} [list \
			engine $mc::Engine 160 w  depth $mc::Depth 60 e  eval $mc::Eval 70 e \
			move $mc::BestMove 80 w  nodes $mc::Nodes 100 e  nps $mc::Nps 90 e] {
		$tv heading $col -text $head
		$tv column $col -width $width -anchor $anchor -stretch [expr {$col eq "engine"}]
	}
	set txt [tk::text $top.summary -height 5 -width 60 -wrap word -state disabled -borderwidth 1 -relief sunken]
	ttk::label $top.status

	grid $top.lengines	-row 1 -column 1 -columnspan 3 -sticky w
	grid $top.engines		-row 2 -column 1 -columnspan 3 -sticky ew
	grid $top.lseconds	-row 3 -column 1 -sticky w
	grid $top.seconds		-row 3 -column 2 -sticky w
	grid $top.results		-row 5 -column 1 -columnspan 3 -sticky nsew
	grid $top.summary		-row 7 -column 1 -columnspan 3 -sticky nsew
	grid $top.status		-row 8 -column 1 -columnspan 3 -sticky w
	grid rowconfigure $top {0 4 6 9} -minsize $::theme::pady
	grid rowconfigure $top {5 7} -weight 1
	grid columnconfigure $top {0 4} -minsize $::theme::padx
	grid columnconfigure $top {3} -weight 1

	::widget::dialogButtons $dlg {close}
	::widget::dialogButtonAdd $dlg start [namespace current]::mc::StartComparison {}
	::widget::dialogButtonAdd $dlg stop [namespace current]::mc::StopComparison {}
	$dlg.start configure -command [namespace code [list StartComparison $lb]]
	$dlg.stop configure -command [namespace code FinishComparison] -state disabled
	$dlg.close configure -command [namespace code CloseComparison]

	wm protocol $dlg WM_DELETE_WINDOW [namespace code CloseComparison]
	wm title $dlg $mc::EngineComparison
	wm transient $dlg [winfo toplevel $parent]
	::util::place $dlg -parent [winfo toplevel $parent] -position center
	wm deiconify $dlg
}


proc StartComparison {lb} {
	variable compare::Vars
	variable compare::Seconds

	set dlg $Vars(dlg)
	set names [lmap i [$lb curselection] { $lb get $i }]
    if {[llength $names] < 2} { return [::dialog::info -parent $dlg -message $mc::NeedTwoEngines] }
    StartNamedComparison $names $Seconds
}

# Execution core shared by selection widgets and registry arguments.
proc StartNamedComparison {names seconds} {
    variable compare::Vars
    variable compare::Seconds
    set dlg $Vars(dlg)
    set Seconds $seconds
	if {[llength $names] < 2} {
		error $mc::NeedTwoEngines
	}
	if {![string is integer -strict $Seconds] || $Seconds < 1} { set Seconds 10 }

	StopComparisonEngines
	if {[winfo exists $dlg]} { $dlg.top.results delete [$dlg.top.results children {}] }
	SetSummary ""
	set Vars(engines) {}
	set failed {}
	foreach name $names {
		if {[catch { startEngine $name "" {lines 1} } number]} {
			lappend failed "$name: $number"
		} else {
			lappend Vars(engines) [list $name $number]
			if {[winfo exists $dlg]} { $dlg.top.results insert {} end -id $number -values [list $name "" "" "" "" "" ] }
		}
	}
    if {[llength $failed]} {
        SetSummary [join $failed \n]
        if {![winfo exists $dlg]} {
            CloseComparison
            error [join $failed "; "]
        }
    }
	if {[llength $Vars(engines)] < 2} { return [FinishComparison] }

	set Vars(remaining) $Seconds
	set Vars(startup) 0
	if {[winfo exists $dlg]} {
		$dlg.start configure -state disabled
		$dlg.stop configure -state normal
	}
	TickComparison
}


proc TickComparison {} {
	variable compare::Vars

	if {![llength $Vars(engines)]} { return }
	RefreshComparison
	# The time counts from when every engine has a line: a big network can
	# take seconds to load on a slow machine (4 s on the macOS VM), and that
	# must not eat the comparison. A dead engine holds it at most 30 s.
	set waiting [llength [lsearch -all -exact -index 2 [ComparisonLines] {}]]
	if {$waiting && [incr Vars(startup)] <= 30} {
		set Vars(after) [after 1000 [namespace code TickComparison]]
		return
	}
	if {[incr Vars(remaining) -1] < 0} { return [FinishComparison] }
	if {[winfo exists $Vars(dlg)]} { $Vars(dlg).top.status configure -text [format $mc::SecondsLeft [expr {$Vars(remaining) + 1}]] }
	set Vars(after) [after 1000 [namespace code TickComparison]]
}


# The best line of each compared engine: {name number line}, line {} if none yet.
proc ComparisonLines {} {
	variable compare::Vars
	variable NumberToTree

	set result {}
	foreach entry $Vars(engines) {
		lassign $entry name number
		set line {}
		if {[info exists NumberToTree($number)]} {
			set best [BestLine $NumberToTree($number)]
			if {[llength $best]} { set line [lindex $best 1] }
		}
		lappend result [list $name $number $line]
	}
	return $result
}


proc RefreshComparison {} {
	variable compare::Vars

	set tv $Vars(dlg).top.results
	if {![winfo exists $tv]} { return }
	foreach entry [ComparisonLines] {
		lassign $entry name number line
		if {![$tv exists $number] || ![llength $line]} { continue }
		lassign $line score mate depth seldepth time nodes nps tbhits pv
		$tv item $number -values [list $name $depth [ScoreText $score $mate] \
			[::font::translate [FirstMove $pv]] [::locale::formatNumber $nodes] [::locale::formatNumber $nps]]
	}
}


proc FinishComparison {} {
	variable compare::Vars

	after cancel $Vars(after)
	set Vars(after) {}
	if {![winfo exists $Vars(dlg)]} { StopComparisonEngines; return }
	RefreshComparison
	SetSummary [ComparisonSummary [ComparisonLines]]
	StopComparisonEngines
	$Vars(dlg).top.status configure -text ""
	$Vars(dlg).start configure -state normal
	$Vars(dlg).stop configure -state disabled
}


# What the engines agree on: the most chosen best move, who chose another,
# and the spread of their scores (in pawns, from White's side).
proc ComparisonSummary {entries} {
	set moves {}
	set scores {}
	set deepest {}
	foreach entry $entries {
		lassign $entry name number line
		if {![llength $line]} { continue }
		lassign $line score mate depth
		set move [FirstMove [lindex $line 8]]
		dict lappend moves $move $name
		if {!$mate} { lappend scores $score }
		if {![llength $deepest] || $depth > [lindex $deepest 1]} { set deepest [list $name $depth] }
	}
	if {![dict size $moves]} { return $mc::NoLinesYet }

	set total [llength [concat {*}[dict values $moves]]]
	set top ""
	dict for {move names} $moves {
		if {$top eq "" || [llength $names] > [llength [dict get $moves $top]]} { set top $move }
	}
	set out [list [format $mc::AgreeOn [llength [dict get $moves $top]] $total [::font::translate $top]]]
	dict for {move names} $moves {
		if {$move ne $top} { lappend out [format $mc::PrefersOther [join $names ", "] [::font::translate $move]] }
	}
	if {[llength $scores] > 1} {
		set scores [lsort -integer $scores]
		lappend out [format $mc::ScoreSpread [FormatScore [lindex $scores 0]] \
			[FormatScore [lindex $scores end]] [FormatScore [expr {[lindex $scores end] - [lindex $scores 0]}]]]
	}
	lappend out [format $mc::DeepestSearch {*}$deepest]
	return [join $out \n]
}


proc SetSummary {text} {
	variable compare::Vars

	set w $Vars(dlg).top.summary
	if {![winfo exists $w]} { return }
	$w configure -state normal
	$w delete 1.0 end
	$w insert end $text
	$w configure -state disabled
}


proc StopComparisonEngines {} {
	variable compare::Vars

	foreach entry $Vars(engines) {
		lassign $entry name number
		if {[::engine::active? $number] && [::engine::engineName $number] eq $name} {
			stopEngine $number
		}
	}
}


proc CloseComparison {} {
	variable compare::Vars

	after cancel $Vars(after)
	StopComparisonEngines
	set Vars(engines) {}
	if {[winfo exists $Vars(dlg)]} { destroy $Vars(dlg) }
	set Vars(dlg) {}
	set Vars(after) {}
}


} ;# namespace analysis
} ;# namespace application
