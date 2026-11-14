# ======================================================================
# One online game in a tab of the Chesswiz Online window
# (docs/features/ONLINE_CLIENT_SPEC.md §4.1). The view owns its own board
# and its own move list; it never touches the main window's game. Moves
# are checked and applied with ::scidb::ai::moveFacts, which takes SAN or
# UCI against any FEN.
#
#   ::online::view::create w backend side   side w, b, or {} (watching)
#   ::online::view::setGame w white black startFen ucis
#   ::online::view::addMove w uci            server move (or echo of ours)
#   ::online::view::clocks w wms bms stm ticking
#   ::online::view::actions w dict           resign draw takeback abort
#                                            accept decline claim -> 0/1
#   ::online::view::status w text
#   ::online::view::chat w who text
#   ::online::view::result w text
#
# The view calls {*}$backend move uci, and the action names above, plus
# chat text, analyse and close.
# ======================================================================

::util::source online-view

namespace eval ::online {}
namespace eval ::online::view {
namespace eval mc {

set Resign				"Resign"
set ResignConfirm		"Resign this game?"
set OfferDraw			"Offer draw"
set AcceptDraw			"Accept"
set DeclineDraw			"Decline"
set Takeback			"Takeback"
set Abort				"Abort"
set ClaimVictory		"Claim victory"
set Flip				"Flip"
set Live				"Back to the live position"
set Chat				"Chat"
set Send				"Send"
set Analyse				"Analyse in Chesswiz"
set CloseTab			"Close tab"
set AutoQueen			"Always promote to a queen"
set Premove				"Premove: %s (right-click to cancel)"
set Illegal				"That move is not legal here."
set NotYourTurn		"Wait for your opponent's move."
set Promote				"Promote to"

}

array set Options {
	lowTime		20
	autoQueen	0
	premove		1
}

variable Glyph
array set Glyph {P ♙ N ♘ B ♗ R ♖ Q ♕ p ♟ n ♞ b ♝ r ♜ q ♛}
variable Value
array set Value {p 1 n 3 b 3 r 5 q 9}
variable Files {a b c d e f g h}
variable TickInterval 100
variable StartFen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"


proc create {w backend side} {
	namespace eval [namespace current]::${w} {}
	variable ${w}::V
	variable StartFen
	Fonts

	array set V [list backend $backend side $side flip [expr {$side eq "b"}] \
		start $StartFen fens [list $StartFen] sans {} ucis {} view -1 \
		select -1 premove {} pending {} over 0 clock:w 0 clock:b 0 stm w \
		ticking 0 clockAt 0 tick {} chat {} white {} black {} size 0]

	ttk::frame $w
	set b [ttk::frame $w.boardframe]
	::board::diagram::new $b.board 48 -bordersize 0 -rotate $V(flip)
	pack $b.board -expand yes
	set V(board) $b.board
	bind $b <Configure> [list [namespace current]::Resize $w]
	::board::diagram::bind $V(board) all <ButtonPress-1> [list [namespace current]::Press $w %q]
	::board::diagram::bind $V(board) all <ButtonRelease-1> [list [namespace current]::Release $w %X %Y]
	::board::diagram::bind $V(board) all <Button1-Motion> [list [namespace current]::Drag $w %X %Y]
	::board::diagram::bind $V(board) <ButtonPress-3> [list [namespace current]::CancelPremove $w]

	set side [ttk::frame $w.side -padding {8 0 0 0}]
	foreach {where row} {top 0 bottom 7} {
		set c [ttk::frame $side.$where]
		ttk::label $c.name -font OnlineName -anchor w
		ttk::label $c.material -font OnlineMaterial -anchor w
		label $c.clock -font OnlineClock -anchor e -padx 10 -borderwidth 0
		grid $c.name -row 0 -column 0 -sticky w
		grid $c.material -row 1 -column 0 -sticky w
		grid $c.clock -row 0 -column 1 -rowspan 2 -sticky e
		grid columnconfigure $c 0 -weight 1
		grid $c -row $row -column 0 -sticky ew -pady 2
		set V(card:$where) $c
	}

	set m [ttk::frame $side.moves]
	text $m.text -width 26 -height 8 -wrap word -cursor arrow -borderwidth 1 -relief solid \
		-yscrollcommand [list $m.sb set] -state disabled -spacing1 3 -padx 4 -pady 4 \
		-font OnlineMoves
	ttk::scrollbar $m.sb -command [list $m.text yview]
	$m.text tag configure current -background #ffe680
	$m.text tag configure number -foreground #777777
	pack $m.sb -side right -fill y
	pack $m.text -side left -fill both -expand yes
	grid $m -row 1 -column 0 -sticky nsew -pady 4
	set V(moves) $m.text
	ttk::button $side.live -text [set mc::Live] -command {::action::run toolbar.online.live}
	set V(live) $side.live

	set a [ttk::frame $side.actions]
	set i 0
	foreach {key label} {resign Resign draw OfferDraw takeback Takeback abort Abort \
		claim ClaimVictory flip Flip} {
		ttk::button $a.$key -text [set mc::$label] -command [list ::action::run toolbar.online.$key]
		grid $a.$key -row [expr {$i / 3}] -column [expr {$i % 3}] -sticky ew -padx 1 -pady 1
		set V(button:$key) $a.$key
		incr i
	}
	grid columnconfigure $a {0 1 2} -weight 1 -uniform a
	grid $a -row 3 -column 0 -sticky ew -pady 2

	# An offer from the opponent shows its own bar with accept/decline.
	set o [ttk::frame $side.offer]
	ttk::label $o.text -anchor w -wraplength 300 -font OnlineName
	ttk::button $o.accept -text [set mc::AcceptDraw] -command {::action::run toolbar.online.accept}
	ttk::button $o.decline -text [set mc::DeclineDraw] -command {::action::run toolbar.online.decline}
	grid $o.text -row 0 -column 0 -columnspan 2 -sticky ew
	grid $o.accept $o.decline -row 1 -sticky ew -padx 1
	grid columnconfigure $o {0 1} -weight 1 -uniform a
	set V(offer) $o

	set r [ttk::frame $side.result]
	ttk::label $r.text -font OnlineBanner -anchor center -justify center -wraplength 300
	ttk::button $r.analyse -text [set mc::Analyse] -command {::action::run toolbar.online.analyse}
	ttk::button $r.close -text [set mc::CloseTab] -command {::action::run toolbar.online.close}
	grid $r.text -row 0 -column 0 -columnspan 2 -sticky ew -pady 4
	grid $r.analyse $r.close -row 1 -sticky ew -padx 1
	grid columnconfigure $r {0 1} -weight 1 -uniform a
	set V(result) $r

	set c [ttk::labelframe $side.chat -text [set mc::Chat]]
	text $c.text -width 26 -height 5 -wrap word -borderwidth 1 -relief solid -state disabled \
		-padx 4 -pady 2
	$c.text tag configure who -font OnlineName
	ttk::entry $c.entry -textvariable [namespace current]::${w}::V(chat)
	ttk::button $c.send -text [set mc::Send] -command {::action::run toolbar.online.chat}
	bind $c.entry <Return> {::action::run toolbar.online.chat}
	grid $c.text -row 0 -column 0 -columnspan 2 -sticky nsew
	grid $c.entry -row 1 -column 0 -sticky ew -pady {2 0}
	grid $c.send -row 1 -column 1 -padx {2 0} -pady {2 0}
	grid columnconfigure $c 0 -weight 1
	grid rowconfigure $c 0 -weight 1
	grid $c -row 6 -column 0 -sticky nsew -pady 2
	set V(chatText) $c.text

	ttk::checkbutton $side.autoqueen -text [set mc::AutoQueen] \
		-variable [namespace current]::AutoQueenMark -command {::action::run toolbar.online.autoqueen}
	set ::online::view::AutoQueenMark $::online::view::Options(autoQueen)
	grid $side.autoqueen -row 8 -column 0 -sticky w
	ttk::label $side.status -anchor w -justify left -wraplength 300
	grid $side.status -row 9 -column 0 -sticky ew -pady {4 0}
	set V(status) $side.status

	grid columnconfigure $side 0 -weight 1 -minsize 300
	grid rowconfigure $side 1 -weight 3
	grid rowconfigure $side 6 -weight 2

	grid $b -row 0 -column 0 -sticky nsew
	grid $side -row 0 -column 1 -sticky ns
	grid columnconfigure $w 0 -weight 1
	grid rowconfigure $w 0 -weight 1
	bind $w <Destroy> [list [namespace current]::Destroyed $w %W]
	if {$V(side) eq ""} { actions $w {} }
	Draw $w
	return $w
}


# A board for solving (puzzles): no clocks, chat or game actions but Flip.
proc spectator {w} {
	HideGameControls $w
	grid remove $w.side.autoqueen
}


proc trainer {w} {
	variable ${w}::V
	HideGameControls $w
	foreach where {top bottom} { grid remove $V(card:$where).clock }
}


proc HideGameControls {w} {
	variable ${w}::V
	foreach key {resign draw takeback abort claim} { grid remove $V(button:$key) }
	grid remove [winfo parent $V(chatText)]
}


proc exists {w} {
	return [expr {[namespace exists [namespace current]::${w}] && [winfo exists $w]}]
}


proc Destroyed {w win} {
	if {$w ne $win} { return }
	variable ${w}::V
	catch { after cancel $V(tick) }
	namespace delete [namespace current]::${w}
}


proc Fonts {} {
	if {"OnlineClock" in [font names]} { return }
	set base [font actual TkDefaultFont]
	set size [expr {abs([dict get $base -size])}]
	set fixed [dict get [font actual TkFixedFont] -family]
	font create OnlineClock -family $fixed -size [expr {$size * 2 + 8}] -weight bold
	font create OnlineName -family [dict get $base -family] -size [expr {$size + 2}] -weight bold
	font create OnlineMaterial -family [dict get $base -family] -size [expr {$size + 6}]
	font create OnlineBanner -family [dict get $base -family] -size [expr {$size + 4}] -weight bold
	font create OnlineMoves -family [dict get $base -family] -size [expr {$size + 1}]
}


# The board takes the largest square size the frame allows.
proc Resize {w} {
	variable ${w}::V
	set f [winfo parent $V(board)]
	set size [expr {max(24, min([winfo width $f], [winfo height $f]) / 8)}]
	if {$size == $V(size)} { return }
	set V(size) $size
	::board::diagram::resize $V(board) $size
	Draw $w
}


# ======================================================================
# Game state: a start FEN and the moves played, as SAN, UCI and FENs
# ======================================================================

proc Facts {move fen} {
	if {[catch { ::scidb::ai::moveFacts $move $fen } json]} { return {} }
	set facts {}
	foreach key {san uci fenAfter} {
		if {[regexp "\"$key\":\"(\[^\"\]+)\"" $json -> value]} { dict set facts $key $value }
	}
	foreach key {check mate stalemate capture} {
		dict set facts $key [regexp "\"$key\":true" $json]
	}
	if {![dict exists $facts fenAfter]} { return {} }
	return $facts
}


proc setGame {w white black startFen ucis} {
	variable ${w}::V
	variable StartFen
	if {$startFen eq "" || $startFen eq "startpos"} { set startFen $StartFen }
	set V(white) $white
	set V(black) $black
	set V(start) $startFen
	set V(fens) [list $startFen]
	set V(sans) {}
	set V(ucis) {}
	set V(pending) {}
	foreach uci $ucis {
		if {![Apply $w $uci]} { break }
	}
	set V(view) -1
	Draw $w
	TryPremove $w
}


proc Apply {w move} {
	variable ${w}::V
	set facts [Facts $move [lindex $V(fens) end]]
	if {$facts eq ""} { return 0 }
	lappend V(sans) [dict get $facts san]
	lappend V(ucis) [dict get $facts uci]
	lappend V(fens) [dict get $facts fenAfter]
	return 1
}


# A server move: either the echo of our pending move, or a new one.
proc addMove {w move} {
	variable ${w}::V
	if {$V(pending) ne ""} {
		# Is this the echo of our move? Compare in the position before it.
		set facts [Facts $move [lindex $V(fens) end-1]]
		if {$facts ne "" && [dict get $facts uci] eq $V(pending)} {
			set V(pending) {}
			return 1
		}
		# Our optimistic move was not what the server played: drop it.
		set V(sans) [lrange $V(sans) 0 end-1]
		set V(ucis) [lrange $V(ucis) 0 end-1]
		set V(fens) [lrange $V(fens) 0 end-1]
		set V(pending) {}
	}
	if {![Apply $w $move]} { return 0 }
	Draw $w
	TryPremove $w
	return 1
}

# The backend refused our move: take it back.
proc rejectMove {w text} {
	variable ${w}::V
	if {$V(pending) ne ""} {
		set V(sans) [lrange $V(sans) 0 end-1]
		set V(ucis) [lrange $V(ucis) 0 end-1]
		set V(fens) [lrange $V(fens) 0 end-1]
		set V(pending) {}
	}
	status $w $text
	Draw $w
}


proc pending {w} {
	variable ${w}::V
	return $V(pending)
}


proc myTurn {w} { return [MyTurn $w] }


proc ucis {w} {
	variable ${w}::V
	return $V(ucis)
}


proc fen {w} {
	variable ${w}::V
	return [lindex $V(fens) end]
}


proc pgn {w tags result} {
	variable ${w}::V
	variable StartFen
	set text ""
	dict for {key value} $tags { append text "\[$key \"[string map {\\ \\\\ \" \\\"} $value]\"\]\n" }
	if {$V(start) ne $StartFen} {
		append text "\[SetUp \"1\"\]\n\[FEN \"$V(start)\"\]\n"
	}
	append text "\n"
	set fen $V(start)
	set i 0
	foreach san $V(sans) {
		set before [lindex $V(fens) $i]
		set number [lindex $before 5]
		if {[lindex $before 1] eq "w"} {
			append text "$number. "
		} elseif {$i == 0} {
			append text "$number... "
		}
		append text "$san "
		incr i
	}
	append text "$result\n"
	return $text
}


# ======================================================================
# Drawing
# ======================================================================

proc Draw {w} {
	variable ${w}::V
	set index [expr {$V(view) < 0 ? [llength $V(fens)] - 1 : $V(view)}]
	set fen [lindex $V(fens) $index]
	::board::diagram::update $V(board) [::scidb::board::fenToBoard $fen]
	foreach which {from to} { ::board::diagram::hilite $V(board) -1 $which }
	foreach which {suggested} { catch { ::board::diagram::hilite $V(board) -1 $which } }
	if {$index > 0} {
		set uci [lindex $V(ucis) [expr {$index - 1}]]
		::board::diagram::hilite $V(board) [::board::diagram::square [string range $uci 0 1]] from
		::board::diagram::hilite $V(board) [::board::diagram::square [string range $uci 2 3]] to
	}
	if {$V(premove) ne ""} {
		catch { ::board::diagram::hilite $V(board) \
			[::board::diagram::square [string range $V(premove) 0 1]] suggested }
	}
	DrawPlayers $w
	DrawMaterial $w $fen
	DrawMoves $w $index
	DrawClocks $w
	if {$V(view) < 0} { grid remove $V(live) } else { grid $V(live) -row 2 -column 0 -sticky ew }
}


proc Where {w colour} {
	variable ${w}::V
	set bottom [expr {$V(flip) ? "b" : "w"}]
	return [expr {$colour eq $bottom ? "bottom" : "top"}]
}


proc DrawPlayers {w} {
	variable ${w}::V
	foreach colour {w b} key {white black} {
		set player $V($key)
		set text [expr {$colour eq "w" ? "○ " : "● "}]
		if {[dict exists $player title] && [dict get $player title] ni {"" null}} {
			append text "[dict get $player title] "
		}
		append text [expr {[dict exists $player name] ? [dict get $player name] : "?"}]
		if {[dict exists $player rating] && [dict get $player rating] ni {"" null}} {
			append text "  [dict get $player rating]"
		}
		$V(card:[Where $w $colour]).name configure -text $text
	}
}


proc material {fen} {
	variable Value
	foreach p {p n b r q P N B R Q} { set count($p) 0 }
	foreach ch [split [lindex $fen 0] {}] {
		if {[info exists count($ch)]} { incr count($ch) }
	}
	array set start {p 8 n 2 b 2 r 2 q 1}
	set score(w) 0; set score(b) 0
	set taken(w) {}; set taken(b) {}
	foreach p {q r b n p} {
		set P [string toupper $p]
		for {set i $count($p)} {$i < $start($p)} {incr i} { lappend taken(w) $p }
		for {set i $count($P)} {$i < $start($p)} {incr i} { lappend taken(b) $P }
		incr score(w) [expr {$Value($p) * $count($P)}]
		incr score(b) [expr {$Value($p) * $count($p)}]
	}
	return [list $taken(w) $taken(b) [expr {$score(w) - $score(b)}]]
}


proc DrawMaterial {w fen} {
	variable ${w}::V
	variable Glyph
	lassign [material $fen] takenW takenB diff
	foreach colour {w b} taken [list $takenW $takenB] {
		set text ""
		foreach p $taken { append text $Glyph($p) }
		if {($colour eq "w" && $diff > 0) || ($colour eq "b" && $diff < 0)} {
			append text "  +[expr {abs($diff)}]"
		}
		$V(card:[Where $w $colour]).material configure -text $text
	}
}


proc DrawMoves {w index} {
	variable ${w}::V
	set t $V(moves)
	$t configure -state normal
	$t delete 1.0 end
	set i 0
	foreach san $V(sans) {
		set before [lindex $V(fens) $i]
		set number [lindex $before 5]
		if {[lindex $before 1] eq "w"} {
			$t insert end "$number. " number
		} elseif {$i == 0} {
			$t insert end "$number... " number
		}
		incr i
		$t insert end $san [list move m$i] "  "
		$t tag bind m$i <Button-1> [list [namespace current]::Show $w $i]
		if {$i == $index} { $t tag add current m$i.first m$i.last }
	}
	$t configure -state disabled
	if {$V(view) < 0} { $t see end } else { catch { $t see m$index.first } }
}


proc Show {w index} {
	variable ${w}::V
	if {$index >= [llength $V(fens)] - 1} { set index -1 }
	set V(view) $index
	set V(select) -1
	Draw $w
}


# ======================================================================
# Clocks
# ======================================================================

proc clocks {w wms bms stm ticking} {
	variable ${w}::V
	variable TickInterval
	if {![exists $w]} { return }
	set V(clock:w) $wms
	set V(clock:b) $bms
	set V(stm) $stm
	set V(ticking) $ticking
	set V(clockAt) [clock milliseconds]
	DrawClocks $w
	after cancel $V(tick)
	if {$ticking} { set V(tick) [after $TickInterval [list [namespace current]::Tick $w]] }
}


proc Tick {w} {
	variable TickInterval
	if {![exists $w]} { return }
	variable ${w}::V
	set V(tick) {}
	if {!$V(ticking)} { return }
	DrawClocks $w
	set V(tick) [after $TickInterval [list [namespace current]::Tick $w]]
}


proc Remaining {w colour} {
	variable ${w}::V
	set ms $V(clock:$colour)
	if {$V(ticking) && $V(stm) eq $colour} {
		set ms [expr {$ms - ([clock milliseconds] - $V(clockAt))}]
	}
	return [expr {max(0, $ms)}]
}


proc DrawClocks {w} {
	variable ${w}::V
	variable Options
	foreach colour {w b} {
		set ms [Remaining $w $colour]
		set active [expr {$V(ticking) && $V(stm) eq $colour}]
		if {$active && $ms < $Options(lowTime) * 1000} {
			set bg #c62828; set fg white
		} elseif {$active} {
			set bg #2e7d32; set fg white
		} else {
			set bg #e0e0e0; set fg #555555
		}
		$V(card:[Where $w $colour]).clock configure -text [FormatClock $ms] -background $bg -foreground $fg
	}
}


proc FormatClock {ms} {
	set tenths [expr {($ms % 1000) / 100}]
	set s [expr {$ms / 1000}]
	set h [expr {$s / 3600}]
	set m [expr {($s % 3600) / 60}]
	set s [expr {$s % 60}]
	if {$h} { return [format "%d:%02d:%02d" $h $m $s] }
	if {$ms < 10000} { return [format "%d:%02d.%d" $m $s $tenths] }
	return [format "%d:%02d" $m $s]
}


# ======================================================================
# Move input: click-click or drag; premove when it is not our turn
# ======================================================================

proc MyTurn {w} {
	variable ${w}::V
	return [expr {!$V(over) && $V(side) ne "" && [lindex [lindex $V(fens) end] 1] eq $V(side)}]
}


proc OwnPiece {w sq} {
	variable ${w}::V
	set p [string index [::scidb::board::fenToBoard [lindex $V(fens) end]] $sq]
	if {$p in {"" " " "."}} { return 0 }
	return [expr {($V(side) eq "w") == [string is upper $p]}]
}


proc Press {w sq} {
	variable ${w}::V
	if {$V(side) eq "" || $V(over)} { return }
	if {$V(view) >= 0} { Show $w -1; return }
	if {$V(select) >= 0 && $V(select) != $sq && ![OwnPiece $w $sq]} {
		set from $V(select)
		set V(select) -1
		::board::diagram::hilite $V(board) -1 from
		Move $w $from $sq
		return
	}
	if {![OwnPiece $w $sq]} { return }
	set V(select) $sq
	::board::diagram::hilite $V(board) $sq from
	::board::diagram::setDragSquare $V(board) $sq
}


proc Drag {w x y} {
	variable ${w}::V
	if {$V(select) < 0} { return }
	catch { ::board::diagram::dragPiece $V(board) $x $y }
}


proc Release {w x y} {
	variable ${w}::V
	if {$V(select) < 0} { return }
	set dragged [::board::diagram::isDragged? $V(board)]
	set to [::board::diagram::getSquare $V(board) $x $y]
	::board::diagram::finishDrag $V(board)
	::board::diagram::setDragSquare $V(board) -1
	if {$dragged && $to >= 0 && $to != $V(select)} {
		set from $V(select)
		set V(select) -1
		Move $w $from $to
	} elseif {$dragged} {
		Draw $w
	}
}


proc SquareName {sq} {
	variable Files
	return "[lindex $Files [expr {$sq % 8}]][expr {$sq / 8 + 1}]"
}


# Enter a move for the user as if made on the board (SAN or UCI); returns
# 1 when it was sent or queued as a premove.
proc play {w move} {
	variable ${w}::V
	if {$V(side) eq "" || $V(over)} { return 0 }
	set fen [lindex $V(fens) end]
	if {[MyTurn $w]} {
		set facts [Facts $move $fen]
		if {$facts eq ""} { return 0 }
		set uci [dict get $facts uci]
	} elseif {[regexp {^[a-h][1-8][a-h][1-8][qrbn]?$} $move]} {
		set uci $move
	} else {
		return 0
	}
	set n [llength $V(ucis)]
	Move $w [::board::diagram::square [string range $uci 0 1]] \
		[::board::diagram::square [string range $uci 2 3]] [string range $uci 4 end]
	return [expr {[llength $V(ucis)] > $n || $V(premove) ne ""}]
}


proc Move {w from to {promo ""}} {
	variable ${w}::V
	variable Options
	variable mc
	set uci "[SquareName $from][SquareName $to]"
	set board [::scidb::board::fenToBoard [lindex $V(fens) end]]
	set piece [string index $board $from]
	if {[string tolower $piece] eq "p" && [string index $uci 3] in {1 8}} {
		if {$promo eq ""} { set promo [expr {$Options(autoQueen) ? "q" : [AskPromotion $w]}] }
		if {$promo eq ""} { Draw $w; return }
		append uci $promo
	}
	if {![MyTurn $w]} {
		if {$Options(premove)} {
			set V(premove) $uci
			status $w [format $mc::Premove $uci]
		} else {
			status $w $mc::NotYourTurn
		}
		Draw $w
		return
	}
	if {$V(pending) ne ""} { Draw $w; return }
	if {![Apply $w $uci]} {
		status $w $mc::Illegal
		Draw $w
		return
	}
	set V(pending) [lindex $V(ucis) end]
	Draw $w
	{*}$V(backend) move $V(pending) [lindex $V(sans) end]
}


proc TryPremove {w} {
	variable ${w}::V
	if {$V(premove) eq "" || ![MyTurn $w]} { return }
	set uci $V(premove)
	set V(premove) {}
	if {[Facts $uci [lindex $V(fens) end]] eq ""} { Draw $w; return }
	Move $w [::board::diagram::square [string range $uci 0 1]] \
		[::board::diagram::square [string range $uci 2 3]] [string range $uci 4 end]
}


proc CancelPremove {w} {
	variable ${w}::V
	set V(premove) {}
	set V(select) -1
	Draw $w
}


proc AskPromotion {w} {
	variable ${w}::V
	variable Glyph
	variable mc
	set m $w.promo
	catch { destroy $m }
	menu $m -tearoff 0
	set V(promo) {}
	foreach p {q r b n} {
		set g $Glyph([expr {$V(side) eq "w" ? [string toupper $p] : $p}])
		$m add command -label "$g  [string toupper $p]" -font OnlineMaterial \
			-command [::action::html::Command online promotion $w $p]
	}
	tk_popup $m [winfo pointerx $w] [winfo pointery $w]
	# tk_popup returns at once on X11; wait for a choice or the menu closing.
	if {[winfo ismapped $m]} { tkwait variable [namespace current]::${w}::V(promo) }
	return $V(promo)
}


# ======================================================================
# Actions, status, chat, result
# ======================================================================

# Stable commands target the selected game tab. Lobby and game-tab names
# are session data; no action id contains a server game id or widget path.
proc Current {} {
	if {![winfo exists .online.tabs] || [wm state .online] eq "withdrawn"} { return "" }
	set w [.online.tabs select]
	if {$w eq "" || ![exists $w]} { return "" }
	return $w
}

proc Control {key} {
	set w [Current]
	if {$w eq ""} { return "" }
	switch -- $key {
		live { return $w.side.live }
		accept - decline { return $w.side.offer.$key }
		analyse - close { return $w.side.result.$key }
		chat { return $w.side.chat.send }
		autoqueen { return $w.side.autoqueen }
		default { return $w.side.actions.$key }
	}
}

proc Available {key} {
	set control [Control $key]
	if {$control eq "" || ![winfo exists $control]} { return 0 }
	# A withdrawn control group (spectating, training, no draw offer, ...)
	# must be unavailable to every caller, including the generic AI tool.
	for {set w $control} {$w ne [Current]} {set w [winfo parent $w]} {
		if {[winfo manager $w] eq ""} { return 0 }
	}
	return [expr {![$control instate disabled]}]
}

proc RunControl {key argsDict} {
	set w [Current]
	if {$w eq "" || ![Available $key]} { error "Select an available online game control first." }
	switch -- $key {
		live { Show $w -1 }
		chat { SendChat $w }
		autoqueen {
			variable Options
			set Options(autoQueen) [expr {!$Options(autoQueen)}]
			set ::online::view::AutoQueenMark $Options(autoQueen)
			return $Options(autoQueen)
		}
		default { Action $w $key }
	}
}

proc RegisterActions {} {
	foreach {key label purpose when} {
		resign Resign {Resign the selected online game.} {When you want to concede the game.}
		draw OfferDraw {Offer your opponent a draw.} {When you want to propose ending the game evenly.}
		takeback Takeback {Ask to take back the last move.} {When you want your opponent to allow a move to be undone.}
		abort Abort {Abort the selected online game.} {When the server allows ending a game without a result.}
		claim ClaimVictory {Claim victory in the selected online game.} {When the server allows you to claim the win.}
		flip Flip {Turn the online board around.} {When you want to see the game from the other side.}
		live Live {Return the online board to the latest position.} {When you have been replaying earlier moves and want to follow live play.}
		accept AcceptDraw {Accept your opponent's draw offer.} {When you agree to end the game as a draw.}
		decline DeclineDraw {Decline your opponent's draw offer.} {When you want to keep playing after an offer.}
		analyse Analyse {Open the completed online game for analysis in Chesswiz.} {When you want to review the moves after playing.}
		close CloseTab {Close the selected online game tab.} {When you have finished looking at the completed game.}
		chat Send {Send the message entered beside the online board.} {When you have written a message to your opponent.}
		autoqueen AutoQueen {Toggle automatic promotion to a queen in online games.} {When you want promotions to happen immediately or to choose a piece yourself.}
	} {
		set id toolbar.online.$key
		if {[dict exists $::action::Registry $id]} { continue }
		::action::register $id [dict create label [set ::online::view::mc::$label] \
			object {} what $purpose doc $purpose ai 0 operator 1 \
			handler [list ::online::view::RunControl $key] \
			visible [list ::online::view::Available $key] enabled [list ::online::view::Available $key] \
			purpose $purpose when $when examples [list $purpose "Please [string tolower $purpose]"]]
	}
}

proc Action {w key} {
	variable ${w}::V
	variable mc
	switch -- $key {
		flip {
			set V(flip) [expr {!$V(flip)}]
			::board::diagram::rotate $V(board)
			Draw $w
			return
		}
		resign {
			if {[::dialog::question -parent $w -message $mc::ResignConfirm] ne "yes"} { return }
		}
	}
	{*}$V(backend) $key
}


proc SendChat {w} {
	variable ${w}::V
	set text [string trim $V(chat)]
	if {$text eq ""} { return }
	set V(chat) {}
	{*}$V(backend) chat $text
}


proc actions {w enabled} {
	variable ${w}::V
	if {![exists $w]} { return }
	foreach key {resign draw takeback abort claim} {
		set on [expr {[dict exists $enabled $key] && [dict get $enabled $key]}]
		$V(button:$key) state [expr {$on ? "!disabled" : "disabled"}]
	}
}


proc offer {w text} {
	variable ${w}::V
	if {![exists $w]} { return }
	if {$text eq ""} {
		grid remove $V(offer)
	} else {
		$V(offer).text configure -text $text
		grid $V(offer) -row 4 -column 0 -sticky ew -pady 2
	}
}


proc status {w text} {
	variable ${w}::V
	if {[exists $w]} { $V(status) configure -text $text }
}


proc chat {w who text} {
	variable ${w}::V
	if {![exists $w]} { return }
	set t $V(chatText)
	$t configure -state normal
	$t insert end "$who: " who "$text\n"
	$t configure -state disabled
	$t see end
}


proc result {w text} {
	variable ${w}::V
	if {![exists $w]} { return }
	set V(over) 1
	set V(ticking) 0
	set V(premove) {}
	after cancel $V(tick)
	actions $w {}
	offer $w {}
	DrawClocks $w
	$V(result).text configure -text $text
	grid $V(result) -row 5 -column 0 -sticky ew -pady 4
	status $w $text
}

} ;# namespace ::online::view

# vi:set ts=3 sw=3:
