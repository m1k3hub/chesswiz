# ======================================================================
# Online game screen (docs/features/ONLINE_CLIENT_SPEC.md §4.1).
# While a Lichess or FICS game runs, the board pane fills the window and a
# panel in a strip beside the board shows both players, large clocks,
# material, the live move list, game actions, chat and the result.
#
# Back ends (tcl/lichess.tcl, tcl/ics.tcl) keep the protocol and the game
# on the main board; they drive the panel through this interface:
#
#   ::online::panel::open backend userSide   backend is a command prefix,
#                                            called {*}$backend action ?arg?
#   ::online::panel::players white black      dicts: name title rating
#   ::online::panel::clocks wms bms stm ticking
#   ::online::panel::refresh                  moves + material from the board
#   ::online::panel::actions dict             action -> 0/1 (enabled)
#   ::online::panel::status text
#   ::online::panel::chat who text
#   ::online::panel::result text              banner + after-game buttons
#   ::online::panel::close
#
# Actions sent to the back end: resign draw accept decline takeback abort
# claim chat <text> lobby analyse.
# ======================================================================

::util::source online-panel

namespace eval ::online {}
namespace eval ::online::panel {
namespace eval mc {

set Resign				"Resign"
set ResignConfirm		"Resign this game?"
set OfferDraw			"Offer draw"
set AcceptDraw			"Accept draw"
set DeclineDraw			"Decline"
set Takeback			"Takeback"
set Abort				"Abort"
set ClaimVictory		"Claim victory"
set Flip				"Flip board"
set Live				"Back to the live position"
set Chat				"Chat"
set Send				"Send"
set BackToLobby			"Back to lobby"
set Analyse				"Analyse"
set You					"You"

}

array set Options {
	width		320
	lowTime		20
}

variable Priv
array set Priv {
	open		0
	backend		{}
	user		w
	clock:w		0
	clock:b		0
	stm			w
	ticking		0
	clockAt		0
	tick		{}
	zoomed		{}
	result		{}
	panel		{}
}
variable TickInterval 100
variable Glyph
array set Glyph {P ♙ N ♘ B ♗ R ♖ Q ♕ p ♟ n ♞ b ♝ r ♜ q ♛}
variable Value
array set Value {p 1 n 3 b 3 r 5 q 9}


proc exists {} {
	variable Priv
	return [expr {$Priv(open) && [winfo exists $Priv(panel)]}]
}


proc open {backend userSide} {
	variable Priv
	variable Options

	if {[exists]} { close }
	set pane [Pane]
	if {$pane eq ""} { return "" }
	set Priv(backend) $backend
	set Priv(user) [expr {$userSide eq "b" ? "b" : "w"}]
	set Priv(result) {}
	set Priv(ticking) 0
	set Priv(open) 1
	Fonts

	set w [ttk::frame $pane.online -padding 6]
	set Priv(panel) $w
	Build $w

	# The game is the whole screen: zoom the board pane, then reserve a
	# strip beside the board for the panel.
	if {![catch { ::application::twm } twm]} {
		set Priv(zoomed) [$twm zoomed]
		if {"board" in [$twm leaves]} {
			catch { $twm zoom [$twm leaf board] }
		}
	}
	::application::board::afterRebuild [namespace current]::Place
	::application::board::setReserve right [Width]
	Place
	after idle [namespace current]::Place
	return $w
}


proc close {} {
	variable Priv
	if {!$Priv(open)} { return }
	set Priv(open) 0
	after cancel $Priv(tick)
	::application::board::afterRebuild [namespace current]::Place true
	catch { ::application::board::setReserve {} 0 }
	if {[winfo exists $Priv(panel)]} { destroy $Priv(panel) }
	if {![catch { ::application::twm } twm]} {
		catch { $twm zoom $Priv(zoomed) }
	}
	set Priv(zoomed) {}
}


proc Pane {} {
	if {[catch { set canv $::application::board::Vars(widget:frame) }] || ![winfo exists $canv]} {
		return ""
	}
	return [winfo parent $canv]
}


# The panel spans the board canvas's height at its right edge, below the
# pane's header buttons, and never past the window. Its width follows the
# screen scaling (Options(width) is in points at 96 dpi).
proc Width {} {
	variable Options
	return [expr {int(round($Options(width) * [tk scaling] / 1.3333))}]
}


proc Place {} {
	variable Priv
	if {![exists]} { return }
	set w $Priv(panel)
	set pane [winfo parent $w]
	upvar #0 ::application::board::Vars vars
	set canv $vars(widget:frame)
	set y [winfo y $canv]
	set h [expr {min([winfo height $canv], [winfo height $pane] - $y)}]
	if {$h < 50} { set h [expr {[winfo height $pane] - $y}] }
	place $w -in $pane -relx 1 -rely 0 -x 0 -y $y -anchor ne -width [Width] -height $h
	raise $w
}


proc Fonts {} {
	if {"OnlineClock" in [font names]} { return }
	set base [font actual TkDefaultFont]
	set size [expr {abs([dict get $base -size])}]
	font create OnlineClock -family [dict get [font actual TkFixedFont] -family] \
		-size [expr {$size * 2 + 6}] -weight bold
	font create OnlineName -family [dict get $base -family] -size [expr {$size + 2}] -weight bold
	font create OnlineMaterial -family [dict get $base -family] -size [expr {$size + 3}]
	font create OnlineBanner -family [dict get $base -family] -size [expr {$size + 3}] -weight bold
}


proc Build {w} {
	variable Priv
	variable mc

	# Opponent at the top, the user at the bottom, as on the board.
	foreach {where row} {top 0 bottom 6} {
		set c [ttk::frame $w.$where]
		ttk::label $c.name -font OnlineName -anchor w
		ttk::label $c.material -font OnlineMaterial -anchor w
		label $c.clock -font OnlineClock -anchor e -padx 8 -relief flat -borderwidth 0
		grid $c.name -row 0 -column 0 -sticky w
		grid $c.material -row 1 -column 0 -sticky w
		grid $c.clock -row 0 -column 1 -rowspan 2 -sticky e
		grid columnconfigure $c 0 -weight 1
		grid $c -row $row -column 0 -sticky ew
		set Priv(widget:$where) $c
	}

	set m [ttk::frame $w.moves]
	text $m.text -width 24 -height 8 -wrap word -cursor arrow -borderwidth 1 -relief solid \
		-yscrollcommand [list $m.sb set] -state disabled -spacing1 2
	ttk::scrollbar $m.sb -command [list $m.text yview]
	$m.text tag configure current -background #ffe680
	$m.text tag configure number -foreground #777777
	pack $m.sb -side right -fill y
	pack $m.text -side left -fill both -expand yes
	grid $m -row 1 -column 0 -sticky nsew -pady 4
	set Priv(widget:moves) $m.text
	ttk::button $w.live -text $mc::Live -command [namespace current]::Live
	grid $w.live -row 2 -column 0 -sticky ew
	set Priv(widget:live) $w.live

	set b [ttk::frame $w.actions]
	set i 0
	foreach {key label} {resign Resign draw OfferDraw takeback Takeback abort Abort \
		accept AcceptDraw decline DeclineDraw claim ClaimVictory flip Flip} {
		ttk::button $b.$key -text [set mc::$label] -command [list [namespace current]::Action $key]
		grid $b.$key -row [expr {$i / 2}] -column [expr {$i % 2}] -sticky ew -padx 1 -pady 1
		set Priv(widget:$key) $b.$key
		incr i
	}
	grid columnconfigure $b {0 1} -weight 1 -uniform a
	grid $b -row 3 -column 0 -sticky ew -pady 4

	set banner [ttk::frame $w.banner]
	ttk::label $banner.text -font OnlineBanner -anchor center -justify center -wraplength [expr {[Width] - 40}]
	ttk::button $banner.analyse -text $mc::Analyse -command [list [namespace current]::Action analyse]
	ttk::button $banner.lobby -text $mc::BackToLobby -command [list [namespace current]::Action lobby]
	grid $banner.text -row 0 -column 0 -columnspan 2 -sticky ew -pady 4
	grid $banner.analyse -row 1 -column 0 -sticky ew -padx 1
	grid $banner.lobby -row 1 -column 1 -sticky ew -padx 1
	grid columnconfigure $banner {0 1} -weight 1 -uniform a
	set Priv(widget:banner) $banner

	set c [ttk::labelframe $w.chat -text $mc::Chat]
	text $c.text -width 24 -height 5 -wrap word -borderwidth 1 -relief solid -state disabled
	$c.text tag configure who -font OnlineName
	ttk::entry $c.entry -textvariable [namespace current]::Priv(chat)
	ttk::button $c.send -text $mc::Send -command [namespace current]::SendChat
	bind $c.entry <Return> [namespace current]::SendChat
	grid $c.text -row 0 -column 0 -columnspan 2 -sticky nsew
	grid $c.entry -row 1 -column 0 -sticky ew -pady [list 2 0]
	grid $c.send -row 1 -column 1 -padx [list 2 0] -pady [list 2 0]
	grid columnconfigure $c 0 -weight 1
	grid rowconfigure $c 0 -weight 1
	grid $c -row 5 -column 0 -sticky nsew
	set Priv(widget:chat) $c.text
	set Priv(chat) {}

	ttk::label $w.status -anchor w -justify left -wraplength [expr {[Width] - 30}]
	grid $w.status -row 7 -column 0 -sticky ew -pady [list 4 0]
	set Priv(widget:status) $w.status

	grid columnconfigure $w 0 -weight 1
	grid rowconfigure $w 1 -weight 3
	grid rowconfigure $w 5 -weight 2
}


proc Action {key} {
	variable Priv
	variable mc
	if {$key eq "flip"} {
		catch { ::application::board::Rotate $::application::board::Vars(widget:frame) }
		set Priv(user) [expr {$Priv(user) eq "w" ? "b" : "w"}]
		DrawPlayers
		DrawClocks
		return
	}
	if {$key eq "resign"} {
		set reply [::dialog::question -parent $Priv(panel) -message $mc::ResignConfirm]
		if {$reply ne "yes"} { return }
	}
	if {[llength $Priv(backend)]} { {*}$Priv(backend) $key }
}


proc SendChat {} {
	variable Priv
	set text [string trim $Priv(chat)]
	if {$text eq "" || ![llength $Priv(backend)]} { return }
	set Priv(chat) {}
	{*}$Priv(backend) chat $text
}


proc Live {} {
	catch { ::scidb::game::go end }
	refresh
}


# ======================================================================
# Players, clocks, material
# ======================================================================

proc players {white black} {
	variable Priv
	set Priv(player:w) $white
	set Priv(player:b) $black
	DrawPlayers
}


proc DrawPlayers {} {
	variable Priv
	if {![exists]} { return }
	foreach colour {w b} {
		set where [expr {$colour eq $Priv(user) ? "bottom" : "top"}]
		set player [expr {[info exists Priv(player:$colour)] ? $Priv(player:$colour) : {}}]
		set text ""
		if {[dict exists $player title] && [dict get $player title] ni {"" null}} {
			append text "[dict get $player title] "
		}
		append text [expr {[dict exists $player name] ? [dict get $player name] : "?"}]
		if {[dict exists $player rating] && [dict get $player rating] ni {"" null}} {
			append text " ([dict get $player rating])"
		}
		$Priv(widget:$where).name configure -text [expr {$colour eq "w" ? "○ " : "● "}]$text
	}
}


proc clocks {wms bms stm ticking} {
	variable Priv
	variable TickInterval
	set Priv(clock:w) $wms
	set Priv(clock:b) $bms
	set Priv(stm) $stm
	set Priv(ticking) $ticking
	set Priv(clockAt) [clock milliseconds]
	DrawClocks
	after cancel $Priv(tick)
	if {$ticking} { set Priv(tick) [after $TickInterval [namespace current]::Tick] }
}


proc Tick {} {
	variable Priv
	variable TickInterval
	set Priv(tick) {}
	if {![exists] || !$Priv(ticking)} { return }
	DrawClocks
	set Priv(tick) [after $TickInterval [namespace current]::Tick]
}


proc Remaining {colour} {
	variable Priv
	set ms $Priv(clock:$colour)
	if {$Priv(ticking) && $Priv(stm) eq $colour} {
		set ms [expr {$ms - ([clock milliseconds] - $Priv(clockAt))}]
	}
	return [expr {max(0, $ms)}]
}


proc DrawClocks {} {
	variable Priv
	variable Options
	if {![exists]} { return }
	foreach colour {w b} {
		set where [expr {$colour eq $Priv(user) ? "bottom" : "top"}]
		set ms [Remaining $colour]
		set active [expr {$Priv(ticking) && $Priv(stm) eq $colour}]
		if {$active && $ms < $Options(lowTime) * 1000} {
			set bg #c62828; set fg white
		} elseif {$active} {
			set bg #2e7d32; set fg white
		} else {
			set bg #e0e0e0; set fg #555555
		}
		$Priv(widget:$where).clock configure -text [FormatClock $ms] -background $bg -foreground $fg
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


# Captured pieces per side from a FEN placement: each side shows the
# opponent's pieces it has taken and, for the side ahead, the difference.
proc material {fen} {
	variable Value
	array set count {}
	foreach p {p n b r q P N B R Q} { set count($p) 0 }
	foreach ch [split [lindex $fen 0] {}] {
		if {[info exists count($ch)]} { incr count($ch) }
	}
	array set start {p 8 n 2 b 2 r 2 q 1}
	set score(w) 0
	set score(b) 0
	set taken(w) {}
	set taken(b) {}
	foreach p {q r b n p} {
		set P [string toupper $p]
		# White took black's missing pieces, and vice versa.
		set missingBlack [expr {max(0, $start($p) - $count($p))}]
		set missingWhite [expr {max(0, $start($p) - $count($P))}]
		for {set i 0} {$i < $missingBlack} {incr i} { lappend taken(w) $p }
		for {set i 0} {$i < $missingWhite} {incr i} { lappend taken(b) $P }
		incr score(w) [expr {$Value($p) * $count($P)}]
		incr score(b) [expr {$Value($p) * $count($p)}]
	}
	return [list $taken(w) $taken(b) [expr {$score(w) - $score(b)}]]
}


proc DrawMaterial {fen} {
	variable Priv
	variable Glyph
	lassign [material $fen] takenW takenB diff
	foreach colour {w b} taken [list $takenW $takenB] {
		set where [expr {$colour eq $Priv(user) ? "bottom" : "top"}]
		set text ""
		foreach p $taken { append text $Glyph($p) }
		if {($colour eq "w" && $diff > 0) || ($colour eq "b" && $diff < 0)} {
			append text " +[expr {abs($diff)}]"
		}
		$Priv(widget:$where).material configure -text $text
	}
}


# ======================================================================
# Move list
# ======================================================================

proc refresh {} {
	variable Priv
	if {![exists]} { return }
	set t $Priv(widget:moves)
	if {[catch { ::scidb::game::query mainline } plies]} { set plies {} }
	set current ""
	catch { set current [::scidb::game::position key] }
	$t configure -state normal
	$t delete 1.0 end
	set n 0
	foreach ply $plies {
		lassign $ply key san fen
		set stm [lindex $fen 1]
		set number [lindex $fen 5]
		if {$stm eq "w"} {
			$t insert end "$number. " number
		} elseif {$n == 0} {
			$t insert end "$number... " number
		}
		set tag k[incr n]
		$t insert end $san [list move $tag] " "
		$t tag bind $tag <Button-1> [list [namespace current]::Goto $key]
		if {$key eq $current} { $t tag add current $tag.first $tag.last }
	}
	$t configure -state disabled
	$t see end
	set atEnd 1
	catch { set atEnd [::scidb::game::position atEnd?] }
	if {$atEnd} { grid remove $Priv(widget:live) } else { grid $Priv(widget:live) }
	if {![catch { ::scidb::pos::fen } fen]} { DrawMaterial $fen }
}


proc Goto {key} {
	catch { ::scidb::game::moveto $key }
	refresh
}


# ======================================================================
# Actions, status, chat, result
# ======================================================================

proc actions {enabled} {
	variable Priv
	if {![exists]} { return }
	foreach key {resign draw takeback abort accept decline claim} {
		set on [expr {[dict exists $enabled $key] && [dict get $enabled $key]}]
		$Priv(widget:$key) state [expr {$on ? "!disabled" : "disabled"}]
	}
}


proc status {text} {
	variable Priv
	if {[exists]} { $Priv(widget:status) configure -text $text }
}


proc chat {who text} {
	variable Priv
	if {![exists]} { return }
	set t $Priv(widget:chat)
	$t configure -state normal
	$t insert end "$who: " who "$text\n"
	$t configure -state disabled
	$t see end
}


proc result {text} {
	variable Priv
	if {![exists]} { return }
	set Priv(result) $text
	set Priv(ticking) 0
	after cancel $Priv(tick)
	DrawClocks
	actions {}
	$Priv(widget:banner).text configure -text $text
	grid $Priv(widget:banner) -row 4 -column 0 -sticky ew -pady 4
	status $text
}

} ;# namespace ::online::panel

# vi:set ts=3 sw=3:
